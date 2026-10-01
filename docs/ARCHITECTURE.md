# Map authoring

The production map is authored manually in Roblox Studio under `Workspace.Map`. Studio is the active map-authoring environment between snapshots. Automatic runtime generation is disabled; `MapInit.server.luau` intentionally does not invoke the builder. The retained toolchain is used explicitly for snapshots, previews, and recovery:

```text
MapData -> AssetRegistry -> MapBuilder -> Workspace.Map
```

- `src/ServerScriptService/Map/MapData.luau` is the latest version-controlled snapshot. It contains placements with an asset ID, world position, Euler rotation in degrees, and uniform scale.
- `AssetRegistry.luau` creates anchored low-poly Roblox models for the mock asset IDs, including an explicit `Spawn` pad. This procedural registry proves the pipeline; production assets can replace its factories without changing the placement schema or builder.
- `MapBuilder.luau` validates each placement, creates and transforms its model, then publishes the completed folder as `Workspace.Map`. It stages the build so a failed generation does not replace the current map.
- `MapInit.server.luau` leaves the manually authored Studio map untouched when the server starts.

The MVP does not include a Studio GUI map editor. For Edit Mode placement, `DevMapTool.luau` exposes `DevBuildMap()` and `DevSerializeMap()`. Use `MapWorkflow.luau` from the Command Bar to reload fresh copies of the tool and its dependencies on every invocation:

```lua
require(game.ServerScriptService.Map.MapWorkflow).Build()
require(game.ServerScriptService.Map.MapWorkflow).Serialize()
```

The serializer recursively reads `Model` instances from `Workspace.Map`; logical `Folder` levels such as `Map/Roads` and `Map/Trees` are allowed. Each encountered model is serialized as one asset, so nested models inside an asset model are not serialized separately. Keeping a dedicated map root prevents characters, scooters, cameras, and unrelated Workspace content from entering `MapData`. Move, rotate, and uniformly scale each model as a whole; serialization reads each model's pivot and `GetScale()` value. `MapWorkflow` itself is required normally, so changes to that wrapper module require a fresh wrapper require (for example, a Studio restart or the earlier clone runner); edits to `DevMapTool`, `MapData`, and `AssetRegistry` are picked up by its internal reload on every call.

The normal map workflow is:

1. Build and adjust the map manually inside `Workspace.Map` in Studio.
2. Keep map models organized in logical folders under that root.
3. Periodically run `MapWorkflow.Serialize()` and update `src/ServerScriptService/Map/MapData.luau` with the generated placement data.
4. Commit the snapshot to Git together with any required asset or registry changes.
5. Use `MapWorkflow.Build()` only when an explicit preview or recovery rebuild is needed. It must not run automatically when a server starts.

Serialization records placement metadata, not model geometry. A rebuild therefore also requires matching model factories or imported templates registered by `AssetRegistry`.

`src/ServerScriptService/Environment/TowerBeacon.server.luau` controls warning lights on skyscraper roofs. For compatibility with the manually authored map, it recognizes `BasePart` instances named `czerwonabulba`; new lights should use the `TowerBeacon` CollectionService tag. Their parts and descendant `PointLight` instances blink briefly every 30 seconds. Runtime world effects live under `Environment`, separately from the map builder and serialization tools.

## Blender city mockup pipeline

Run `tools/blender/generate_warsaw_city.py` from Blender's Scripting workspace. It clears the Blender scene, generates a 3x3 layout of 500-stud districts with 22 objects in each of the eight urban districts, a Palace of Culture with four plaza tiles in the center, one continuous 1500-stud avenue, exactly two Kukirin workshops, and one railway crossing with a toll gate. It exports every unique low-poly asset individually as FBX to the repository's `assets/buildings/` directory and writes strict Luau placement data to the repository root as `MapData.luau`. Both paths are based on `PROJECT_ROOT` in the script, independent of Blender's current working directory. Generated IDs include `District_Ground`, `Road_Straight`, `Road_Intersection`, `Road_Avenue`, `Park_Trees`, `Park_Plaza`, `Shop_Small`, `Building_Residential`, `Building_Small`, `Building_Midrise`, `Building_Skyscraper`, `Palace_Of_Culture`, `Workshop_Kukirin`, `Railway_Crossing`, and `Toll_Gate`.

The generated root `MapData.luau` is kept separate from `src/ServerScriptService/Map/MapData.luau`: the current mock `AssetRegistry` does not load imported FBX assets or recognize all generated IDs. Generated FBX files may be imported as source assets and placed manually in the Studio map. Generated placement data is optional reference material and does not replace the manual production-map workflow. The script header lists Roblox Studio's FBX import settings for matching scale and axes, based on the [Roblox Blender and Studio guidance](https://create.roblox.com/docs/art/blender).

# Scooter MVP

The MVP scooter system is split between authoritative server ownership and a local arcade controller:

- `src/ServerScriptService/Scooter/ScooterServer.luau` creates scooter remotes, validates spawn and trick requests, owns scooter records, clones matching templates from `ServerStorage.ScooterModels` with a generated fallback, runs two-point raycast suspension and locomotion, and replicates authoritative trick state.
- `src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau` reads controls only for the local player's occupied scooter, sends rate-limited drive intent to the server, and animates optional wheel and steering motors for every replicated scooter.
- `src/ReplicatedStorage/Shared/Scooter/ScooterConfig.luau` contains shared model tuning and cooldown constants.

Clients may request a spawn and send drive or burnout intent, but the server owns the scooter assembly and applies locomotion. It rejects invalid model names, spawn spam, malformed or excessive drive input, unoccupied scooter input, tricks from non-owners, and burnout activation above the low-speed threshold. Exceeding the wheelie balance angle ejects and stuns the rider on the server. Visual burnout state is set on the server-owned particle emitter and echoed through `ScooterRemotes.TrickState` so every client sees the same smoke state.

The production template hierarchy, Blender separation rules, suspension points, and visual `Motor6D` names are documented in `docs/SCOOTER_MODEL.md`.

# Shop MVP

The shop catalog lives in `ReplicatedStorage.Shared.Shop.ShopConfig` and drives two client tabs: Coin scooters and Robux extras. `ShopServer.server.luau` validates product IDs, request frequency, current ownership, and the server-owned `leaderstats.Coins` balance before deducting currency. Coin ownership currently uses player attributes as a session-level integration point; persistent profile storage must restore and save those attributes when the data system is added.

Robux products are visible with GDD prices but remain unavailable while their `productId` is `0`. After IDs owned by the experience are configured, the server validates the requested catalog entry before the client opens Roblox's native Game Pass purchase prompt. Permanent entitlement grants must be derived from MarketplaceService ownership or receipt processing, never from a client purchase-completed event.

# Phone MVP

The phone is the main player menu and intentionally contains no chat, map, or upgrade screen. `PhoneClient.client.luau` provides apps for owned scooters, current delivery status, gang status, daily mission progress, and passive protection. `PhoneServer.server.luau` builds all displayed state from server-owned player attributes and validates every action.

The activity and gang systems publish `DeliveryActive`, `DeliveryDestination`, `DeliveryDistance`, `GangName`, and the daily progress attributes declared by `PhoneConfig`; the phone renders these server-owned values and shows an empty state when no delivery or gang is active. Scooter summoning uses the authoritative ownership and cooldown checks in `ScooterServer.RequestSpawnForPlayer`. Passive mode is stored in `PassiveMode`; the combat system honors that server attribute, and the phone forcibly disables it for gang members.

# Gang MVP

`GangService.luau` is the server authority for gang creation, membership, invitations, leadership, capacity, and official colors. A gang has one leader and ordinary members only, no shared budget or base, and a maximum size of `floor(Players.MaxPlayers * 0.33)`. Invitations expire after 30 seconds. Leaders can invite and remove members; a member can leave, while a leader leaving disbands the gang. Membership disables `PassiveMode`, and server combat systems must call `GangService.CanDamage(attacker, target)` to enforce friendly-fire protection.

Gang state is currently server-session data. Persistent player and gang storage must restore membership and creation entitlement before `GangService.Start()` when the profile system is introduced. Creating a gang requires the server-owned `CanCreateGang` player attribute. The GDD does not yet define the Coin price for that permanent entitlement, so no purchase price is hardcoded; until that product decision is made, the entitlement can only be granted by an authoritative development or future economy system.

# Combat MVP

`CombatService.luau` owns player health, melee target resolution, damage, stuns, spawn protection, SafeZone checks, passive-mode checks, gang friendly-fire checks, and server-side scooter ram detection. Clients send only the action names `Melee` or `Pepper`; the server independently selects a target by range, facing direction, line of sight, and current PvP permissions. Other server systems must use `CombatService.CanDamage` or `CombatService.DamagePlayer` rather than changing another player's health directly.

Players have 100 HP. Melee deals 15 damage with a server-enforced 0.8-second cooldown. A qualifying scooter collision deals 25 damage and stuns both players for 2 seconds. Pepper spray deals no damage and stuns its target for 5 seconds; access requires the server-owned `OwnsPepperSpray` attribute. Respawn grants 3 seconds of invisible ForceField protection, and PvP is rejected within 100 studs horizontally of the enabled `SpawnLocation`. The combat client binds melee to `F`/gamepad R2 and pepper spray to `G`/gamepad L2, with corresponding touch controls.

# Work, activities, and rankings

`PlayerDataService.luau` owns persistent Coins, XP, deliveries, race wins, trick records, travel distance, daily progress, the seven-day login streak, and purchased entitlement attributes. It creates the server-owned `leaderstats.Coins` and `leaderstats.XP` values used by the shop and saves profiles to `PlayerProfiles_v1`. DataStore failures fall back to session data and are logged without preventing gameplay.

Delivery content is authored manually with CollectionService tags:

- Tag a `BasePart` or `Model` with `DeliveryPickup` to create a physical package pickup prompt.
- Tag destination buildings or their marker parts with `DeliveryDestination`.
- Optionally set the `DeliveryName` string attribute for the name shown in the phone.

`ActivityService.luau` selects a destination on the server, keeps the package assignment private to that player, validates prompt distance, preserves a delivery through character death, and awards `100 Coins + 50 XP + 15 Coins` per complete 100 studs of straight-line route distance. It also records movement, night movement, completed deliveries, and authoritative burnout/wheelie durations. Future race and police systems must call `ActivityService.RecordRaceWin(player)` and `ActivityService.RecordPoliceEscape(player)` respectively.

`LeaderboardService.luau` publishes monotonic records to four OrderedDataStores and creates four runtime boards beside the enabled `SpawnLocation`: race wins, longest burnout, longest wheelie, and deliveries. Repeated unchanged values are not written again. Studio testing of persistence and global rankings requires API Services access.

Daily login streaks and all five daily mission categories are tracked. The GDD does not define Coin/XP rewards for login days or completed daily missions, so `ActivityConfig.DailyLoginCoinRewards` is intentionally zeroed and no mission-completion payout is invented. Those values require an economy decision before release.
