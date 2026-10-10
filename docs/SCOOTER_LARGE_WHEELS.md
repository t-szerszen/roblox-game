# Larger wheels and reference-based assembly

The current rider-fit revision additionally rebuilds the visible body and moves
the complete front module. See [the current remodel](SCOOTER_RIDER_REMODEL.md).
The dimensions preserved below describe the earlier larger-wheel operation.

The 2026-10-09 remodel reuses the preserved `ScooterAuthoring.ScooterFinal`
component meshes and the user's `Workspace.newFrontWheel`. It does not use
`Workspace.Scooter_Reference_Rebuild`, which is a separate mesh-only authoring
model. The photograph guides the larger tires, level deck, folded left kickstand
and rear fender. Existing finishes are retained rather than replaced with the
photograph's paint scheme.

## Geometry and mechanics

Both playable tires have configurable diameter 1.95 studs: approximately 9% more
than the former front wheel and 8% more than the rear. This is 18% smaller than
the first 2.390002-stud remodel, which the user found oversized. The imported
front wheel is resized uniformly, retaining its width/diameter ratio. Its MeshPart retains
its color and normal maps. The rear keeps its original mesh, texture and width.
Deck, steering shaft, handlebar, grips, levers and seat dimensions stay unchanged.

The front linkage rotates down 21.138 degrees around its existing body-local
pivot so both tire centers share a level rest pose. Arm sizes and deck-side pivot
locations are retained. Arms, brake disc and caliper move laterally by half the
tire-width difference, and the small front shock crossbar extends to fit. The
front coil's lower endpoint follows the axle, with its upper mount retained;
its visual length and orientation follow the new endpoint geometry.

Existing DevScooterBuild, DevScooterInstall, ScooterRig, ScooterCollision and
ScooterSuspension create and calibrate seven hinges and two actual springs.
Contact spheres derive their 0.975-stud radii from the tires, including the
existing 0.03-stud collision inset. The original drive controller, authority,
remotes, speeds, tricks and rider systems continue to operate.

For an initially measured curb rise up to 1.25 studs, StepTraction uses a 3.5-stud/s lift
target, response 12 and acceleration cap 60. Added vertical support fades to zero
as the tire's upward speed reaches 6.5 studs/s, reducing energy fed into the
spring during a quick rise. Horizontal momentum support is retained. Taller
ledges use the existing 5.5/16/100 arcade settings throughout their climb. The
server remembers the initial rise from the existing face/top probes, avoiding a
weaker profile halfway through a tall climb; clients provide no geometry.
The 2.5-stud maximum obstacle height and existing impact rules remain configured.

The server probes local rays forward, to either side and diagonally, with face opposition
sin(0.5 degrees). This finds contacted curbs at a one-degree approach from their
edge with bounded rolling anticipation. The top probe enters along the
face normal, and FaceEntryBias 0.6 adds an inward entry component. Drive grip
follows that entry while the verified contact lasts, rather than resisting its
sideways motion. Chassis balance retains the rider's heading; assistance does not
automatically yaw the scooter into the face. Assisted tires share the carried mass to avoid
doubling vertical support. One assisted tire uses the existing 0.85 load fraction;
paired assistance carries one full gravity load because neither tire can rely on
the lower road. This avoids losing height before the grace interval ends.
Probe buffers are reused by the existing controller.
When a tire partially overlaps a step, low rays may start inside its geometry.
The controller retains that already verified face within one tire radius plus
contact padding, rechecking the same walkable top and overhead each frame.
Retreat, missing/changed top, cleared contact range, loss of eligibility or input
release clears it. Once the bottom reaches the top, only horizontal entry support
continues; no added vertical lift is supplied on the flat platform.
An already verified contact allows a 0.45-stud rebound margin and up to three
degrees of physical yaw perturbation. New climbs still require positive face
opposition. For glancing entries, normal-speed support targets 3 studs/s with
response 14 and acceleration bounded to 60 studs/s²; it fades out by face
opposition 0.5, leaving frontal/45-degree behavior unchanged. This component
remains useful when fast travel along the edge exceeds the forward-speed target.
Top rechecks span the bounded, briefly airborne corner transition, and additional
vertical lift stops above the platform. The existing 1.25-second eligibility
grace still expires, and unsupported air input cannot initiate assistance.

When both tire probes miss, a short Blockcast covers the entire deck underside,
including narrow supports between the former point samples. It starts above
the underside to avoid initially intersecting shapes, as required by
[WorldRoot.Blockcast](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#Blockcast).
Walkable contact within 0.18 stud authorizes grounded drive and steering; it does
not authorize unsupported air propulsion. Deck friction is 0.02, separate from
the unchanged 0.15 tire-proxy friction, so the base scooter's normal acceleration
can slide off an underside support in either direction.

The existing client default-spawn request waits for HumanoidRootPart. The server
chooses the enabled SpawnLocation nearest that root, rather than the first one
in Workspace traversal. This fixes scooters appearing at the other enabled spawn
(the garage and main map spawn are far apart). No authored spawn or map is moved.

`Kickstand` has three primitive parts, folded along the left deck edge. It is
a visual accessory, without a deployment interaction. `BackFender` has eight
short arch sections and two supports, following the rear axle without spinning
with the tire. All thirteen added parts are massless, noncolliding, nonqueryable
and welded into their correct assemblies. Compound decorative Models are kept
intact by the builder and installer. No extra gameplay loops or asset uploads
are introduced.

## Explicit Studio workflow

After syncing Rojo, run in Edit:

```lua
require(game.ServerScriptService.Scooter.ScooterWorkflow).PreviewLargeWheels()
```

This preserves the original inputs and active template, and creates:

- `ServerStorage.ScooterAuthoring.ScooterLargeWheelSource`: unscaled editable
  component Models, preserving the original imported assets and materials.
- `ServerStorage.ScooterAuthoring.ScooterLargeWheelRig`: mechanical draft.
- `Workspace.ScooterLargeWheelPreview`: anchored assembled preview with contacts
  and seat, placed over the existing road through read-only raycasts.

Repeated calls archive only previous marked remodel artifacts under unique names.
The production map and unrelated authoring models are preserved. As with other
development workflows, require a fresh ScooterWorkflow clone if Studio cached
an older module. This workflow never runs automatically at server startup.

Install the prepared draft using the existing workflow:

```lua
require(game.ServerScriptService.Scooter.ScooterWorkflow).InstallNewModel(
    game.ServerStorage.ScooterAuthoring.ScooterLargeWheelRig
)
```

The installer preserves the previous active template in ScooterTemplateBackups.
Save the place to persist native meshes, materials, authoring sources and rig.
`assets/scooter/large-wheel-components.json` versions measured geometry and asset
references. Regenerate it with `scripts/snapshot_scooter_components.studio.luau`.
It is a component manifest, not a complete place/dashboard serializer.

## Verification

`tests/scooter_remodel.studio.luau` uses the actual imported source and wheel in
detached fixtures. It checks preserved inputs, materials, chassis dimensions,
level tire centers, calibrated articulation, three contact proxies, correct
decorative assembly welds, repeated runtime preparation and invalid input
rejection. The existing native builder tests, CLI regressions, strict analysis
and Rojo build also validate the integration. The follow-up CLI run passed 909
assertions, Roblox-aware type analysis and bytecode compilation passed, and Rojo
built the project successfully.

Fresh native Play against the installed template and final source verified:

| Approach | Height | Result |
| --- | --- | --- |
| Forward from rest | 1 stud | Both tires crossed, rider retained |
| Forward rolling | 1 stud | Both tires crossed, rider retained |
| Forward at 45 degrees from rest | 1 stud | Both tires crossed, rider retained |
| Reverse at 45 degrees from rest | 1 stud | Both tires crossed, rider retained |
| Forward at 1 degree from the edge, from rest | 1 stud | Both tires crossed, rider retained |
| Reverse at 1 degree from the edge, from rest | 1 stud | Both tires crossed, rider retained |
| Forward at 1 degree, opposite side / rolling | 1 stud | Both tires crossed in both cases |
| Forward at 1 degree from rest | 2.5 studs | Both tires crossed, rider retained |
| Reverse at 1 degree from rest | 2.4 studs | Both tires crossed, rider retained |
| Forward at 45 degrees from rest | 2.5 studs | Both tires crossed, rider retained |
| Reverse at 45 degrees from rest | 2.4 studs | Both tires crossed, rider retained |
| Forward wall contact from rest | 3 studs | No climb force, no crossing or ejection |

Stationary steering reached approximately -48/+48 degrees and returned within
0.03 degrees of center. W+S started burnout and releasing both inputs cleared
it; the rider remained mounted and the model did not fall.

Fresh Play without a manual spawn call produced one owned 1.95-stud-wheel scooter
within 12 studs of the character across repeated sessions. CLI integration additionally checks the nearest
of multiple enabled spawns, full-footprint deck support, W and S force with both
tires unsupported, immediate force clearing after loss of support, tire-friction
preservation, both-sided one-degree plane intersections and shared tire load.

The final native one-degree cases crossed in approximately 0.8–1.1 seconds,
with peak chassis upward speed 3.5–5.4 studs/s and final yaw change below 0.2
degree. The full 13-case curb suite kept
the rider mounted and the model upright; the three-stud wall remained blocked
with zero assistance. A narrow four-stud support verified DeckGrounded=true and
both tire contacts false before input. W moved the deck clear of the support;
S moved it 3.2 studs before the trailing tire met the tall block. This checks
underside drive eligibility, not permission to climb above the height limit.
On a narrow 2.5-stud block, the final diagonal probes let W and S both move more
than four studs off the support, with the rider retained and no fall. Diagonal
coverage matters where a round tire clips a finite face's corner while direct
forward and side rays miss it.

The [handling follow-up](SCOOTER_ARCADE_HANDLING.md#rounded-obstacles-rebound-and-restored-steering)
now caps small-curb chassis rebound at 3.5 studs/s, including a tested 50 km/h
frontal approach, and supports rounded humps from rest in both directions.
Actual suspension still follows changes in ground height. Manual acceptance should judge the camera/rider feel,
successive curbs and other speeds. Tests used ordinary validated DriveInput
remotes and temporary fixtures outside Workspace.Map. Stopping Play removed
the fixtures, automation and temporary runtime changes. No map edits or client
physics authority were introduced.

The installed template is `ServerStorage.ScooterModels.scooter`; the previous
0.25 template remains intact in ScooterTemplateBackups, and the older 0.20
variant remains available. The original source, new wheel and mesh-only
reference rebuild are retained. Studio is left in Edit with the finished preview
selected. Automated solver checks do not establish subjective visual acceptance
or multiplayer/mobile input behavior.
