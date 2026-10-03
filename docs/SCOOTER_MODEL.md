# Scooter model contract

Place production templates in `ServerStorage/ScooterModels`. A template name must match a key in `ScooterConfig.Models`, for example `KuKirin G2 Pro`. The server clones a matching template and uses the generated fallback only when no template exists.

## Required hierarchy

```text
KuKirin G2 Pro (Model, PrimaryPart = Root)
├── Root (BasePart)
│   └── ScooterDriveAttachment (Attachment, optional)
├── DriverSeat (VehicleSeat)
├── FrontSuspensionPoint (Attachment)
├── RearSuspensionPoint (Attachment)
├── RiderRootAttachment (Attachment)
├── LeftFootPlant (Attachment)
├── RightFootPlant (Attachment)
├── LeftHandGrip (Attachment)
├── RightHandGrip (Attachment)
├── FrontWheelMotor (Motor6D)
├── RearWheelMotor (Motor6D)
├── SteeringMotor (Motor6D)
└── BurnoutSmokeAttachment (Attachment)
    └── BurnoutSmoke (ParticleEmitter)
```

`Root`, `DriverSeat`, `BurnoutSmoke`, and the five rider attachments are required. Ground-probe attachments and visual motors are optional but strongly recommended. `Root` is the invisible assembly root and does not collide with the map. At spawn, the server creates two invisible low-friction spherical collision proxies centered on the wheel axles. Their radii match the resolved tire radius with a small clearance. The runtime reads a `WheelRadius` attribute from either wheel, then the template, when provided; otherwise it derives the tire radius from the smaller local Y/Z wheel dimension so a fender or swingarm does not enlarge it. Vertical raycasts report wheel contact but do not apply fake suspension forces because the production model has no articulated suspension. The server sanitizes every visual part to be unanchored, massless, non-collidable, non-touchable, and non-queryable. Only the two wheel proxies contact the map; `Root` supplies assembly mass.

`DriverSeat` is an invisible control and ownership mechanism, not a visible saddle. It must have `Transparency = 1`, `CanCollide = false`, and `CanTouch = false`; the server mounts the owner through the `E` proximity prompt. `RiderRootAttachment` defines the horizontal pelvis location, while runtime derives its height from the avatar's `HipHeight` and the two foot targets so scaled avatars stand instead of folding their legs. Put both foot targets at the sole contact points on the deck and both hand targets at the grip centers. R15 feet use transform IK with forward knee poles; a small centralized sole sink prevents a visible gap above the deck. During a wheelie, feet make only a small horizontal balance adjustment and stay near the deck.

The server publishes `RiderMounted`, `WheelieActive`, `Steering`, and `SpeedKmh` attributes on every spawned scooter. Rider posing and future authored animation blending must consume these replicated values instead of inferring authoritative trick state locally. R15 characters use four IK chains; R6 characters use a procedural standing pose so neither rig falls back to Roblox's seated animation.

Place `FrontSuspensionPoint` and `RearSuspensionPoint` at the wheel axle centers. At runtime, the server repositions existing attachment points from the `FrontWheel` and `RearWheel` part centers so stale template offsets cannot lower the contact proxies. The wheelbase fallback is used only when those wheel parts are absent.

## Blender separation

Export these visual assemblies separately:

- body/deck and fixed frame;
- front wheel;
- rear wheel;
- steering assembly, including the handlebar and front fork;
- rear swingarm if rear suspension travel should be visible;
- front suspension body if fork compression should be visible.

Small fixed details may stay joined to the body. Brake discs, calipers, fenders, and cables may stay joined to the wheel, steering assembly, or swingarm they move with. Wheel origins must be centered on their axles. The steering assembly origin must be on the steering axis.

## Visual joints

The client animates optional motors by name:

- `FrontWheelMotor` rotates the front wheel around local X;
- `RearWheelMotor` rotates the rear wheel around local X;
- `SteeringMotor` rotates the steering assembly around local Y.

Configure each motor's `Part0`, `Part1`, `C0`, and `C1` in Studio. The controller writes only `Motor6D.Transform`, preserving the authored offsets.

Front and rear wheel angles are tracked independently. Normal travel rotates both from authoritative assembly velocity; while `BurnoutActive` is true, the rear wheel uses `ScooterConfig.BurnoutWheelAngularSpeed` even when the scooter is stationary. Motor discovery is event-driven so missing optional visual motors do not cause repeated hierarchy scans every rendered frame.

A speedometer should read the replicated integer `SpeedKmh` attribute from the scooter model. The server derives it from horizontal movement along the scooter and forces it to zero inside the stopping deadzone, avoiding false speed caused by vertical movement.

## Physics behavior

The authoritative server controller provides two-point vertical ground probes, ground-aligned `VectorForce` propulsion, speed-dependent steering lean, adaptive low-step assistance, and progressive wheelies. Throttle and braking never add artificial chassis pitch; outside an active wheelie the scooter follows the filtered road normal. Step assistance measures the obstacle and scales its lift, so a raised road marking receives only a small correction while a valid curb receives more lift. Ground normals are exponentially filtered before reaching `AlignOrientation`, preventing road-tile seams from changing the target attitude abruptly. Releasing throttle applies gradual rolling drag, while reverse input first applies stronger braking and only engages low-speed reverse after the scooter stops. Reverse travel inverts chassis yaw while leaving handlebar animation aligned with player input. Exponential input smoothing and speed-sensitive steering retain low-speed maneuverability while limiting high-speed yaw. The server retains network ownership on spawn, mount, and dismount. The client sends input only; prediction clones and camera offsets are paused for the MVP. The server disables touch seating and creates an owner-only `E` proximity prompt. Steering is ignored only at near-zero speed. Press `Shift` or `C` once to trigger a wheelie while moving forward; afterward `W` raises the front and maintains momentum while `S` brakes and lowers it quickly. Neutral holds the angle only above the low-speed balance threshold; loss of momentum progressively drops the front, and a complete stop ends the wheelie rapidly. `Space` is intentionally inert while mounted, and `E` dismounts. Exceeding the wheelie balance angle releases the scooter stabilizer, removes the rider from the seat, applies a short eject impulse, and puts the humanoid into a two-second ragdoll stun before recovery. A fallen or unoccupied scooter near the ground receives linear and angular parking damping, preventing repeated bounces and long uncontrolled travel without weakening gravity while it is airborne. Wheel meshes are visual and do not collide with the world.

`BurnoutSmoke` is server-controlled and disabled outside an accepted stationary burnout. Runtime setup reparents it to `RearWheelAttachment` on the stable chassis at the rear axle, so wheel animation does not rotate its emission. Existing `BurnoutSmokeAttachment` templates remain compatible. Premium underglow is paused for the MVP; only white burnout smoke is active. Runtime setup forces zero light emission, a bounded rate, a short lifetime, and automatic shutdown as soon as movement exceeds the configured deadzone.

## Five-part Studio assembly

For a scooter imported as five separate `MeshPart` objects, first arrange the meshes into the final resting pose in Workspace. The scooter must face along its local negative Z axis, both wheel axle centers must line up, and every wheel must rotate correctly around its local X axis. Rename and select exactly these five parts:

```text
ScooterBody
FrontWheel
RearWheel
Fork
Handlebar
```

Select all five parts or select their single parent `Folder`/`Model`. Run this in Studio's Server Command Bar while not playing:

```lua
require(game.ServerScriptService.Scooter.DevScooterAssembler).AssembleFromSelection()
```

The assembler preserves the current mesh positions and derives forward from `RearWheel -> FrontWheel`, avoiding dependence on imported mesh axes. It creates `ServerStorage.ScooterModels.KuKirin G2 Pro` with an invisible physical `Root`, `DriverSeat`, rider and suspension attachments, burnout smoke, fixed welds, and the three visual `Motor6D` joints expected by the client. It refuses to overwrite an existing production template.

The assembler uses `ScooterConfig.WheelRadius` (`0.7` studs) for ride height. Do not derive the radius from the complete wheel mesh bounds when that mesh also contains a fender or swingarm. If the actual tire radius differs, add a numeric `WheelRadius` attribute to the selected `FrontWheel` before assembly; the assembler copies that value to the final template.

The invisible `Root` is deliberately non-colliding. Runtime setup caps its dimensions and creates spherical proxies at both wheel axles, so an older template cannot catch a low chassis corner on road markings. The two vertical ground probes exclude both the scooter and its rider. A directional low obstacle probe starts near the bottom of the leading wheel, measures the contacted ledge and assists over valid curbs from rest or at speed in both forward and reverse. Runtime code never changes `MeshPart.CollisionFidelity`, because Roblox restricts that property to Studio/plugin contexts; the assembler attempts to author `Box`, while spawned visual meshes are removed from collision entirely.

To recover the five visual parts from an incorrectly assembled template, run:

```lua
require(game.ServerScriptService.Scooter.DevScooterAssembler).DisassembleTemplateToWorkspace()
```

This removes generated joints and moves the five anchored visual parts back to `Workspace.kukurinNieruszac`, ready for repositioning and another assembly pass.

After assembly, temporarily set `Root.Transparency` and `DriverSeat.Transparency` to `0.5` and enable attachment visibility in Studio. Adjust the root so it covers the deck without reaching the ground, place the seat over the rear-middle portion of the deck, and fine-tune the five rider attachments against a representative R15 rig. Return both transparencies to `1` before testing. If a wheel spins around the wrong axis, correct the mesh orientation before assembly; the runtime controller rotates wheel motors around local X.

Garage speed tiers and premium effects are detailed in [SCOOTER_SYSTEMS.md](SCOOTER_SYSTEMS.md). The invisible wheel proxies use moderate contact friction while the controller supplies stronger lateral grip, preventing ice-like sliding without making propulsion depend entirely on native friction.
