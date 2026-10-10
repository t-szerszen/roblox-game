# Drivable scooter MVP

Current scope: throttle, coasting/braking/reverse, smooth steering, wheelie, burnout, calibrated suspension, cornering lean and cleanup. The articulated scooter rig is active; mounted R15 avatars use only the base riding pose, preserving their intended 8-stud Avatar Settings height. Garage, premium visuals, audio and local prediction are paused; the later sections describe parked work, not the active MVP.

## Studio setup

1. Run `rojo serve default.project.json` and connect/sync the Rojo plugin to this project.
2. Select the complete new `scooter` Folder in Edit mode and run `require(game.ServerScriptService.Scooter.ScooterWorkflow).Assemble()`. This installs `ServerStorage.ScooterModels.scooter` and replaces the old KuKirin template. The new rig is required; there is no generated fallback. See [SCOOTER_MODEL.md](SCOOTER_MODEL.md) for the authored hierarchy and generated support parts.
3. Verify tire contact radius in Studio. A positive `WheelRadius` attribute on each wheel or the template overrides the radius inferred from wheel mesh Size. Apply the suspension calibration from DevScooterSuspension.Apply and verify its travel and sag in Studio. Adjust generated foot targets and HandleBar grip attachments to the authored meshes. Prepared templates contain wheel contact proxies; the server preserves their collisions and uses their actual radii for ground probes and spawn clearance. It does not rigidly weld suspension to Root. For a collapsing rig use DevScooterRepair as described in [SCOOTER_MODEL.md](SCOOTER_MODEL.md#diagnose-or-repair-a-collapsing-scooter).
4. Use a flat collidable road and an enabled SpawnLocation. Press **Play**, approach the automatically spawned scooter, and press **E**. The map is not rebuilt or overwritten.

| Input | Behavior |
| --- | --- |
| E | Mount nearby / dismount |
| W / up | Throttle |
| S / down | Brake, then automatically engage reverse below 2 km/h; reverse up to 18 km/h |
| A / D, left / right | Steering; no turning at rest outside burnout; reverse travel follows the requested screen direction |
| Shift or C | Tap above 10 km/h to trigger wheelie; afterward W raises, releasing W lowers smoothly, S lowers faster |
| W + S at up to 5 km/h | Rear wheel motor spins the tire; A/D permit donuts, including at rest; white smoke is visible to all players |
| Space / gamepad A | No action while mounted; default avatar jump is blocked |

`ScooterServer` uses `VectorForce` and native `AlignOrientation`, retaining server network ownership. Stabilization accounts for articulated moving mass and initializes its target/torque before the first simulation update. The client sends input only; no duplicate scooter/avatar or camera prediction is created. Physics does not depend on DataStore access or premium ownership. Meshes and seat are noncolliding; moving suspension, steering and wheel assemblies retain mass. Two wheel proxies supply contact through the authored springs and virtual axles; a massless FootRest collider supports the deck if it tips or bottoms out, excluding its own tires. Legacy templates receive bounded front linkage rest alignment from the working rear during spawn, including actual part repositioning and front-only calibration. The physical Servo steers HandleBarStick. Player characters retain their Avatar Settings proportions and enabled Animate; the client applies the focused mounted R15 base pose after animation evaluation. See [rider fit](SCOOTER_RIDER_POSE.md).

World speed uses StudsPerKmH = 1.6 instead of the previous 1.0, increasing travel speed by 60% while retaining catalog km/h ratings and upgrade prices. Steering uses the measured Servo angle and actual axle spacing to determine curvature; yaw tends to zero at rest outside burnout. Active W+S burnout instead permits bounded A/D rotation from the measured Servo angle. The full steering target is now 30 degrees, subject to authored limits and speed fade. A speed-dependent heading lead prevents a blocked or crawling scooter from accumulating a large orientation error.

Reverse uses MaxReverseSpeedKmh = 18 and ReverseAcceleration = 75 studs/s² (formerly 12 and 50). Holding S first brakes forward motion at DirectionChangeBrakingDeceleration = 60 studs/s², then engages reverse below DirectionChangeSpeedKmh = 2 without a second press or a mandatory stationary frame. W uses the same transition when changing from reverse to forward. Forces remain bounded; velocity is never assigned by this transition. Hill assistance now also operates while braking into a direction change, so downhill gravity does not keep the scooter stuck in the braking stage. Releasing S retains normal coasting; W+S retains burnout behavior.

For acceptance, drive and coast on flat ground, verify left/right steering in both forward and reverse, then tap Shift/C above 10 km/h and release it. W must continue raising the front; release W to lower it, then add W again before landing to regain pitch without another trigger. S must lower it faster. Confirm that crossing the maximum wheelie angle ejects the rider. Hold/release burnout at rest and at 5 km/h; steer both ways and complete a donut before releasing S. Then dismount and remount repeatedly; smoke and inputs must stop on exit. With two clients, verify the second sees burnout and cannot mount your scooter. CLI build/type checks do not replace this Studio test.

Whole-fender brake visuals are disabled via BrakeLight.Enabled until a dedicated lamp is authored. Passive suspension uses geometry-safe pivot stops and leverage-aware spring tuning; green constraint debug coils are hidden. Cornering lean uses speed and the measured steering angle, caps roll at 16 degrees and eases back during wheelie or lost contact. Chassis yaw follows actual Servo movement, including authored angular limits. Settings and equations are documented in [SCOOTER_MODEL.md](SCOOTER_MODEL.md#scooter-brake-light-and-cornering-lean).

## Paused implementation reference

The following garage/premium APIs are retained for future work. The garage client exits while `GarageEnabled` is false, and ScooterServer returns `Unavailable` for garage requests without starting those services. Base model tuning is used for the MVP.

## Garage and persistence

Base speeds are G2 Pro 55, G2 Max 65, G2 Master 72, G3 Pro 80, and G4 90 km/h. Each model has three speed upgrades. Maximum speed is `base + tier * 1.5`, with acceleration scaled by the ratio of upgraded to base speed. All five GDD price schedules are centralized in `Shared/ScooterConfig`.

The garage panel selects an owned model, displays its current speed/tier and next price, and requests one upgrade at a time. The server supplies the price; the client sends only the model and the tier it last saw. Purchases update the existing profile and Coins value atomically without yielding, and immediately refresh a spawned scooter. The profile stores upgrades separately for each model, so switching models preserves their individual tiers. Old profiles migrate to tier zero and disabled premium visuals.

The existing profile store still uses its current autosave and shutdown workflow. These changes do not add cross-server session locking or guaranteed immediate durable writes. Failed initial reads are never saved over existing data; garage purchases and preference changes fail closed for that session.

## Premium visuals

Set real experience-owned game-pass IDs for `burnout_smoke` and `scooter_neons` in `Shared/Shop/ShopConfig`. Both currently have ID `0`, which deliberately denies the entitlement. Purchase prompts remain in the existing shop. Garage ownership checks run on the server with `MarketplaceService:UserOwnsGamePassAsync`; the server refreshes ownership after `PromptGamePassPurchaseFinished`. No client purchase-success flag grants an effect. See the [official MarketplaceService contract](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService).

Players with a verified pass can save RGB values and toggle each effect in the garage. The server validates finite channels in `[0, 1]`; the UI accepts `[0, 255]`. Ordinary burnout remains available with white smoke. Premium smoke colors, the neon strip, and underglow light are server-owned and visible to other clients. Each spawned model receives the owner's saved preferences; entitlement checks fail closed when unavailable.

Smoke is mounted on `VirtualBackAxle.RearWheelAttachment` at the rear axle. It activates only while the server sees a living authorized rider, fresh simultaneous throttle/brake intent, rear-wheel ground contact, and planar speed at most BurnoutMaxSpeedKmh (5 km/h). Releasing either key, exceeding the threshold, losing rear contact, stale input, and dismount disable the smoke and motor. Motor torque scales with supported mass, gravity and tire radius so the tire can overcome ground friction. The client sends no smoke color through the trick event.

## Networking

Drive modes belong to the authoritative scooter controller. New scooters start
in SPORT; `P` requests one ECO/SPORT toggle while the owner is mounted. ECO uses
a 25 km/h motor target, bounded by the model's own maximum; SPORT uses the full
existing tuning. Acceleration and the 18 km/h reverse limit are unchanged.
Mode changes retain velocity and use existing bounded drive forces to approach
the new forward target. Coasting, slope/gravity motion and external forces retain
their existing behavior; this is a motor limit, not a velocity teleport. The
chosen mode survives dismount/remount and resets with a new scooter. The popup
and touch shortcut are cleaned with the mounted controller. See
[dashboard setup](SCOOTER_DASHBOARD.md) for the static 67% battery and display.

All endpoints are under `ReplicatedStorage.Remotes.ScooterRemotes`:

| Endpoint | Arguments | Validation / result |
| --- | --- | --- |
| `RequestSpawn` event | `modelName` | Known owned model, living player, spawn cooldown |
| `DriveInput` event | `throttleHeld, brakeHeld, steering, wheelieHeld` | Exact boolean types; finite steering in `[-1, 1]`; the server converts the rising wheelie-button edge into one trigger; owner, seat, life/stun state, server rate limit |
| `ToggleDriveMode` event | No arguments | Rejects any arguments; current owner/rider, living and unstunned rider, nonfallen scooter, 0.4-second server cooldown; server toggles the record's mode and publishes `DriveMode` and effective `MaxSpeedKmh` |
| `TrickState` event | `"Burnout", active` or `"Dismount", true` | Authorized rider; rate-limited legacy burnout start hint, immediate release; actual burnout is derived each simulation step from validated DriveInput and server physics |
| `GarageRequest` function | `"GetState", nil, nil` | Rate-limited server snapshot |
| `GarageRequest` function | `"PurchaseSpeed", modelName, expectedCurrentTier` | Loaded persistent profile, ownership, exact current tier, tier cap, sufficient coins |
| `GarageRequest` function | `"SetVisual", nil, {kind = "Smoke" or "Neon", enabled = boolean, color = Color3}` | Exact fields, valid RGB, verified corresponding game pass |

Garage responses are `(success, reasonCode, state?)`. Clients must handle rate limiting, unavailable profiles, and stale tiers. `ScooterServer.Stop()` disconnects service callbacks, clears records, stops the garage service, and disables the function handler. Per-mount and per-model connections are explicitly disconnected.

## Verification

Run the automated checks and Studio scenarios in [tests/README.md](../tests/README.md). CLI tests execute production module code with service doubles; they do not simulate Roblox collision solving, actual Marketplace/DataStore services, avatar clothing, or multiplayer replication. A Rojo build and Roblox-aware type analysis check the synchronized source, but a Studio playtest is still needed to tune wheel contact and attitude against the authored scooter and road meshes.
