# Map authoring

The production map is authored manually in Roblox Studio. Automatic runtime generation is disabled; `MapInit.server.luau` intentionally does not invoke the builder. The versioning toolchain remains available for explicit use:

```text
MapData -> AssetRegistry -> MapBuilder -> Workspace.Map
```

- `src/ServerScriptService/Map/MapData.luau` contains placements with an asset ID, world position, Euler rotation in degrees, and uniform scale.
- `AssetRegistry.luau` creates anchored low-poly Roblox models for the mock asset IDs, including an explicit `Spawn` pad. This procedural registry proves the pipeline; production assets can replace its factories without changing the placement schema or builder.
- `MapBuilder.luau` validates each placement, creates and transforms its model, then publishes the completed folder as `Workspace.Map`. It stages the build so a failed generation does not replace the current map.
- `MapInit.server.luau` leaves the manually authored Studio map untouched when the server starts.

The MVP does not include a Studio GUI map editor. For Edit Mode placement, `DevMapTool.luau` exposes `DevBuildMap()` and `DevSerializeMap()`. Use `MapWorkflow.luau` from the Command Bar to reload fresh copies of the tool and its dependencies on every invocation:

```lua
require(game.ServerScriptService.Map.MapWorkflow).Build()
require(game.ServerScriptService.Map.MapWorkflow).Serialize()
```

The serializer recursively reads `Model` instances from `Workspace.Map`; logical `Folder` levels such as `Map/Roads` and `Map/Trees` are allowed. Each encountered model is serialized as one asset, so nested models inside an asset model are not serialized separately. Keeping a dedicated map root prevents characters, scooters, cameras, and unrelated Workspace content from entering `MapData`. Move, rotate, and uniformly scale each model as a whole; serialization reads each model's pivot and `GetScale()` value. `MapWorkflow` itself is required normally, so changes to that wrapper module require a fresh wrapper require (for example, a Studio restart or the earlier clone runner); edits to `DevMapTool`, `MapData`, and `AssetRegistry` are picked up by its internal reload on every call.

`src/ServerScriptService/Environment/TowerBeacon.server.luau` controls warning lights on skyscraper roofs. For compatibility with the manually authored map, it recognizes `BasePart` instances named `czerwonabulba`; new lights should use the `TowerBeacon` CollectionService tag. Their parts and descendant `PointLight` instances blink briefly every 30 seconds. Runtime world effects live under `Environment`, separately from the map builder and serialization tools.

## Blender city mockup pipeline

Run `tools/blender/generate_warsaw_city.py` from Blender's Scripting workspace. It clears the Blender scene, generates a 3x3 layout of 500-stud districts with 22 objects in each of the eight urban districts, a Palace of Culture with four plaza tiles in the center, one continuous 1500-stud avenue, exactly two Kukirin workshops, and one railway crossing with a toll gate. It exports every unique low-poly asset individually as FBX to the repository's `assets/buildings/` directory and writes strict Luau placement data to the repository root as `MapData.luau`. Both paths are based on `PROJECT_ROOT` in the script, independent of Blender's current working directory. Generated IDs include `District_Ground`, `Road_Straight`, `Road_Intersection`, `Road_Avenue`, `Park_Trees`, `Park_Plaza`, `Shop_Small`, `Building_Residential`, `Building_Small`, `Building_Midrise`, `Building_Skyscraper`, `Palace_Of_Culture`, `Workshop_Kukirin`, `Railway_Crossing`, and `Toll_Gate`.

The generated root `MapData.luau` is kept separate from `src/ServerScriptService/Map/MapData.luau`: the current mock `AssetRegistry` does not load imported FBX assets or recognize all generated IDs. Import the FBX files into Roblox Studio, register those models in the runtime asset registry, and then move the generated placements into the runtime module as an integration step. The script header lists Roblox Studio's FBX import settings for matching scale and axes, based on the [Roblox Blender and Studio guidance](https://create.roblox.com/docs/art/blender).

# Scooter MVP

The MVP scooter system is split between authoritative server ownership and a local arcade controller:

- `src/ServerScriptService/Scooter/ScooterServer.luau` creates scooter remotes, validates spawn and trick requests, owns scooter records, spawns a temporary KuKirin-style fallback model beside the active `SpawnLocation`, and replicates burnout smoke state.
- `src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau` reads controls only for the local player's occupied scooter and sends rate-limited drive intent to the server.
- `src/ReplicatedStorage/Shared/Scooter/ScooterConfig.luau` contains shared model tuning and cooldown constants.

Clients may request a spawn and send drive or burnout intent, but the server owns the scooter assembly and applies locomotion. It rejects invalid model names, spawn spam, malformed or excessive drive input, unoccupied scooter input, tricks from non-owners, and burnout activation above the low-speed threshold. Visual burnout state is set on the server-owned particle emitter and echoed through `ScooterRemotes.TrickState` so every client sees the same smoke state.
