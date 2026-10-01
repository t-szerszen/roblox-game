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
├── FrontWheelMotor (Motor6D)
├── RearWheelMotor (Motor6D)
├── SteeringMotor (Motor6D)
└── BurnoutSmokeAttachment (Attachment)
    └── BurnoutSmoke (ParticleEmitter)
```

`Root`, `DriverSeat`, and `BurnoutSmoke` are required. Suspension attachments and visual motors are optional but strongly recommended. `Root` is an invisible safety collider whose bottom is aligned with the visual wheel bottoms; server raycast suspension maintains the dynamic ride height. The server makes all visual parts unanchored, non-collidable, and massless. Obstacle assistance and player ramming also use explicit server queries rather than wheel collisions.

Place `FrontSuspensionPoint` and `RearSuspensionPoint` at the wheel axle centers. If they are missing, the controller derives both positions from `ScooterConfig.WheelBase`.

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

A speedometer should read the replicated integer `SpeedKmh` attribute from the scooter model. The server derives it from horizontal movement along the scooter and forces it to zero inside the stopping deadzone, avoiding false speed caused by vertical suspension motion.

## Physics behavior

The authoritative server controller provides two-point raycast suspension, spring damping, ground-aligned propulsion, steering lean, acceleration pitch, low-step assistance, jumping, and progressive wheelies. The server disables touch seating and creates an owner-only `E` proximity prompt. Steering is ignored below the configured minimum speed. `Shift` or `C` triggers the initial wheelie kick only while moving forward; after that, `W` raises the front and `S` lowers it. Exceeding the wheelie balance angle releases the scooter stabilizer, removes the rider from the seat, applies a short eject impulse, and puts the humanoid into a two-second ragdoll stun before recovery. Wheel meshes are visual and do not collide with the world.

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

The assembler preserves the current mesh positions and derives forward from `RearWheel -> FrontWheel`, avoiding dependence on imported mesh axes. It creates `ServerStorage.ScooterModels.KuKirin G2 Pro` with an invisible physical `Root`, `DriverSeat`, suspension attachments, burnout smoke, fixed welds, and the three visual `Motor6D` joints expected by the client. It refuses to overwrite an existing production template.

The assembler uses `ScooterConfig.WheelRadius` (`0.7` studs) for ride height. Do not derive the radius from the complete wheel mesh bounds when that mesh also contains a fender or swingarm. If the actual tire radius differs, add a numeric `WheelRadius` attribute to the selected `FrontWheel` before assembly; the assembler copies that value to the final template.

The invisible `Root` is deliberately a short central safety foot rather than a full-length deck collider. This prevents a corner from penetrating the road during steep wheelies. The server publishes front and rear suspension compression attributes; the client combines those offsets with wheel spin and retries missing motor lookup while a fresh scooter clone is still replicating.

To recover the five visual parts from an incorrectly assembled template, run:

```lua
require(game.ServerScriptService.Scooter.DevScooterAssembler).DisassembleTemplateToWorkspace()
```

This removes generated joints and moves the five anchored visual parts back to `Workspace.kukurinNieruszac`, ready for repositioning and another assembly pass.

After assembly, temporarily set `Root.Transparency` and `DriverSeat.Transparency` to `0.5` to inspect their size and position. Adjust the root so it covers the deck without reaching the ground, and place the seat over the rear-middle portion of the deck. Return both transparencies to `1` before testing. If a wheel spins around the wrong axis, correct the mesh orientation before assembly; the runtime controller rotates wheel motors around local X.
