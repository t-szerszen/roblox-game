# Drivable scooter MVP

Current scope: throttle, coasting/braking/reverse, smooth steering, wheelie, burnout and cleanup. Garage, premium visuals, audio and local prediction are paused; the later sections describe parked work, not the active MVP.

## Studio setup

1. Run `rojo serve default.project.json` and connect/sync the Rojo plugin to this project.
2. Keep the existing template in `ServerStorage.ScooterModels.KuKirin G2 Pro`. It needs `PrimaryPart = Root`, a welded `DriverSeat` VehicleSeat, and `BurnoutSmoke` ParticleEmitter. Preserve authored rider attachments and wheel motors. With no template the server creates a basic test scooter automatically.
3. Set a numeric `WheelRadius` attribute on the template to the tire radius in studs (normally `0.7` for the assembler model). This takes precedence over visual mesh bounds, which may include fenders. All fixed visual parts must be welded or Motor6D-connected to Root. Runtime unanchors/sanitizes them and creates spherical collision proxies at both wheel axles.
4. Use a flat collidable road and an enabled SpawnLocation. Press **Play**, approach the automatically spawned scooter, and press **E**. The map is not rebuilt or overwritten.

| Input | Behavior |
| --- | --- |
| E | Mount nearby / dismount |
| W / up | Throttle |
| S / down | Brake, then low-speed reverse |
| A / D, left / right | Steering; no turning at rest; reverse travel follows the requested screen direction |
| Press Shift or C | Trigger wheelie once while moving forward; afterward W raises, S lowers, and neutral holds the angle |
| W + S at standstill | White burnout smoke visible to all players |
| Space / gamepad A | No action while mounted; default avatar jump is blocked |

`ScooterServer` uses `VectorForce` and native `AlignOrientation`, retaining server network ownership. The client sends input only; no duplicate scooter/avatar or camera prediction is created. Physics does not depend on DataStore access or premium ownership. Visual parts and seat are massless/noncolliding; the invisible Root supplies mass and two wheel proxies supply ground contact.

For acceptance, drive and coast on flat ground, verify left/right steering in both forward and reverse, then hold a wheelie and use `W`/`S` to cross the balance point or lower the front. Confirm that crossing the maximum wheelie angle ejects the rider. Hold/release burnout, then dismount and remount repeatedly; smoke and inputs must stop on exit. With two clients, verify the second sees burnout and cannot mount your scooter. CLI build/type checks do not replace this Studio test.

## Paused implementation reference

The following garage/premium APIs are retained for future work. The garage client exits while `GarageEnabled` is false, and ScooterServer returns `Unavailable` for garage requests without starting those services. Base model tuning is used for the MVP.

## Garage and persistence

Base speeds are G2 Pro 55, G2 Max 65, G2 Master 72, G3 Pro 80, and G4 90 km/h. Each model has three speed upgrades. Maximum speed is `base + tier * 1.5`, with acceleration scaled by the ratio of upgraded to base speed. All five GDD price schedules are centralized in `Shared/ScooterConfig`.

The garage panel selects an owned model, displays its current speed/tier and next price, and requests one upgrade at a time. The server supplies the price; the client sends only the model and the tier it last saw. Purchases update the existing profile and Coins value atomically without yielding, and immediately refresh a spawned scooter. The profile stores upgrades separately for each model, so switching models preserves their individual tiers. Old profiles migrate to tier zero and disabled premium visuals.

The existing profile store still uses its current autosave and shutdown workflow. These changes do not add cross-server session locking or guaranteed immediate durable writes. Failed initial reads are never saved over existing data; garage purchases and preference changes fail closed for that session.

## Premium visuals

Set real experience-owned game-pass IDs for `burnout_smoke` and `scooter_neons` in `Shared/Shop/ShopConfig`. Both currently have ID `0`, which deliberately denies the entitlement. Purchase prompts remain in the existing shop. Garage ownership checks run on the server with `MarketplaceService:UserOwnsGamePassAsync`; the server refreshes ownership after `PromptGamePassPurchaseFinished`. No client purchase-success flag grants an effect. See the [official MarketplaceService contract](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService).

Players with a verified pass can save RGB values and toggle each effect in the garage. The server validates finite channels in `[0, 1]`; the UI accepts `[0, 255]`. Ordinary burnout remains available with white smoke. Premium smoke colors, the neon strip, and underglow light are server-owned and visible to other clients. Each spawned model receives the owner's saved preferences; entitlement checks fail closed when unavailable.

Smoke is mounted on `RearWheelAttachment` at the rear axle. It activates only while the server sees a living authorized rider, fresh simultaneous throttle/brake intent, ground contact, and speed below the configured threshold. Acceleration, releasing controls, stale input, and dismount disable it. The client sends no smoke color through the trick event.

## Networking

All endpoints are under `ReplicatedStorage.Remotes.ScooterRemotes`:

| Endpoint | Arguments | Validation / result |
| --- | --- | --- |
| `RequestSpawn` event | `modelName` | Known owned model, living player, spawn cooldown |
| `DriveInput` event | `throttleHeld, brakeHeld, steering, wheelieHeld` | Exact boolean types; finite steering in `[-1, 1]`; the server converts the rising wheelie-button edge into one trigger; owner, seat, life/stun state, server rate limit |
| `TrickState` event | `"Burnout", active` or `"Dismount", true` | Authorized rider; burnout starts are rate limited and rechecked against server physics; releases are always accepted |
| `GarageRequest` function | `"GetState", nil, nil` | Rate-limited server snapshot |
| `GarageRequest` function | `"PurchaseSpeed", modelName, expectedCurrentTier` | Loaded persistent profile, ownership, exact current tier, tier cap, sufficient coins |
| `GarageRequest` function | `"SetVisual", nil, {kind = "Smoke" or "Neon", enabled = boolean, color = Color3}` | Exact fields, valid RGB, verified corresponding game pass |

Garage responses are `(success, reasonCode, state?)`. Clients must handle rate limiting, unavailable profiles, and stale tiers. `ScooterServer.Stop()` disconnects service callbacks, clears records, stops the garage service, and disables the function handler. Per-mount and per-model connections are explicitly disconnected.

## Verification

Run the automated checks and Studio scenarios in [tests/README.md](../tests/README.md). CLI tests execute production module code with service doubles; they do not simulate Roblox collision solving, actual Marketplace/DataStore services, avatar clothing, or multiplayer replication. A Rojo build and Roblox-aware type analysis check the synchronized source, but a Studio playtest is still needed to tune wheel contact and attitude against the authored scooter and road meshes.
