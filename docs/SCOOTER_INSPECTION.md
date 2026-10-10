# Inspect a new scooter before assembly

Sync this repository with Rojo, stop Play, select exactly one complete scooter
Folder or Model in Explorer, and run in the Studio Command Bar:

```lua
require(game.ServerScriptService.Scooter.DevScooterInspect).InspectSelection()
```

The tool only reads the selected hierarchy. It accepts nested models and raw
MeshParts without requiring the current rig names or existing constraints. It
does not install a template, move parts, change selection, or modify Workspace.Map.
Output contains an indented tree, diagnostic warnings, and JSON entries on separate
lines to avoid truncating a single large Output message.

For programmatic access or a complete JSON report:

```lua
local inspector = require(game.ServerScriptService.Scooter.DevScooterInspect)
local report = inspector.Read(game:GetService("Selection"):Get()[1])
print(inspector.ToJSON(report))
```

`Read` also supports live Studio models for diagnostics. InspectSelection requires
Edit mode to capture the authored pose. ModuleScript results are cached by Studio;
after editing this module, require a fresh unparented clone and destroy it afterward,
or reopen Studio before using the command again.

Each entry has a report-local numeric ID, parent ID, depth, name, class, full path,
attributes and relevant mechanical properties. References use IDs, so repeated
names such as two Grip models remain distinguishable. Missing and external joint
endpoints, duplicate sibling names, anchored parts, and unreadable properties are
reported. Counts include the root. Empty raw folders are valid reports.

Part CFrames use the 12 values returned by GetComponents (world XYZ followed by
the rotation matrix); attachment CFrames are local and WorldCFrames are world
space. Vectors are XYZ arrays. The report includes part sizes, individual masses,
collision settings, mesh asset IDs, model pivots, weld references, hinge axes and
limits, and spring endpoints and tuning. Infinity/NaN become strings so the result
remains valid JSON. Other attribute types retain their type and string value when
no explicit numeric representation is provided. This is a mechanical inspection,
not a complete asset serializer or a reconstruction of mesh vertex geometry.

## Existing integration points and next steps

The current `ScooterRig.Inspect` requires direct named MeshParts and virtual axles,
seven hinges, four springs and the matching welds/attachments. A raw imported
hierarchy must first be mapped to those mechanical roles; do not run the existing
assembler on it until that contract is satisfied. `ScooterRigGeometry` validates
joint alignment; `ScooterSuspension` calibrates travel, preload and damping;
`ScooterCollision` provides wheel/deck contacts. Reuse these modules after mapping
the new model rather than replacing the driving controller.

`ScooterServer` and shared `ScooterPhysics` already implement authoritative drive,
braking/reverse, steering, wheelie, burnout, stabilization and ECO/SPORT modes.
Riders retain their Roblox default appearance and animations; no scooter pose client runs. Garage upgrades and premium appearance services are retained but
paused by `GarageEnabled = false`; enabling/redesigning them is a later product step.
See [current systems](SCOOTER_SYSTEMS.md) and [rig contract](SCOOTER_MODEL.md).

Studio inspection on 2026-10-04 found `Workspace.ScooterFinal` with nested component
Models, 15 MeshParts and 19 WeldConstraints, and no Attachments, HingeConstraints or
SpringConstraints. The user confirmed this is the new model and is still adding,
positioning and extracting MeshParts at that point. Authoring is now ready for
the [new draft assembly workflow](SCOOTER_FINAL_RIG.md).
`Workspace.scooter` and `ServerStorage.ScooterModels.scooter`
also exist. Never infer the intended root solely from its name or the currently
selected unrelated part.

Scripted placement can use the captured CFrames and explicit part-local mounting
coordinates. Mesh bounds alone do not identify bolt centers, steering axes or
shock endpoints reliably; visually verify these points and check suspension travel
in Studio. See the official [hinge](https://create.roblox.com/docs/reference/engine/classes/HingeConstraint),
[spring](https://create.roblox.com/docs/reference/engine/classes/SpringConstraint) and
[attachment](https://create.roblox.com/docs/reference/engine/classes/Attachment) APIs.
Validate a staged copy before installing the finished rig. Real solver behavior
requires a later Play test with the rider and the new geometry.
