# ScooterFinal assembly and runtime integration

The larger-wheel remodel adds `newFrontWheel`, a matching larger rear tire,
level rest geometry, folded left kickstand and rear fender, preserving the
existing articulated controller. See [the 2026-10-09 workflow and verification](SCOOTER_LARGE_WHEELS.md).

## Active remodeled model — 2026-10-05

The user selected 0.25 after comparing sizes. It is the runtime and builder
default; comparison displays are disabled, with both templates retained. Arcade
curb assistance now supports 2.5-stud ledges and glancing approaches. See
[SCOOTER_ARCADE_HANDLING.md](SCOOTER_ARCADE_HANDLING.md).

The user accepted the remodeled mounts and requested the existing mechanics.
MountsVerified is true in the build configuration and accepted draft. The model
now has playable comparisons at scales 0.20 and 0.25. The default 0.25 is
`ServerStorage.ScooterModels.scooter`; 0.20 is `scooter_scale020`. Both retain seven
hinges, two calibrated central springs and all 21 imported MeshParts. The accepted
0.30 runtime is backed up; the 0.30 review draft remains in ScooterAuthoring.
See [scale comparisons and crosswalk repair](SCOOTER_SCALE_TESTS.md).
The approved source and yellow-marked draft are retained as
`ServerStorage.ScooterAuthoring.ScooterFinal` and `ScooterFinalRig`.
The previous runtime template remains in ScooterTemplateBackups. Previous raw
sources receive unique names instead of competing with the canonical source.

The remodeled deck surface was sampled read-only using an isolated query clone.
Its flat region runs from world X 293.75 to 310.5 and Z 4.114960 to 9.864960;
center surface height is 9.455956. The runtime deck helper uses body-local center
`(-2.715057, -2.812065, 0)` and unscaled size `(15.75, 0.95, 5.25)`, leaving margins
inside those edges. This places seat and foot targets on the new surface while
hand targets follow the actual grips. Accepted mechanical endpoints and mesh
poses/sizes are unchanged by installation. Editor review adornments are stripped
from the runtime copy.

No new gameplay controller was added. The model uses existing server-owned drive,
ECO/SPORT, reverse/braking, wheelie, burnout, curb traction, impact/recovery,
white headlight, stop light, physical dashboard and third-person speedometer.
The original mechanics integration left the production map untouched. The scale
comparison follow-up disables collisions only on decorative crosswalk stripes.
Garage, upgrades and coil-mesh animation remain
at their previously documented stages.

Native Play verified empty/mounted settling with both contacts, A/D Servo travel
at rest and centering, SPORT 55 km/h, ECO 25 km/h, reverse 18 km/h, wheelie with
rear-only contact and brake return, W+S burnout, white front light and reverse
stop-lamp without BRAKE. The HUD showed ECO, R, 18 km/h and correct brake/light
states, then cleaned up its GUI. Input automation used normal validated remotes;
keyboard focus/mobile delivery and longer manual handling remain user acceptance.
Temporary test floor geometry existed only in Play and was removed by stopping.
Studio is left in Edit with the model ready for a fresh user Play session.

## Draft construction after remodeling — 2026-10-05

`Workspace.ScooterFinal` now includes the remodeled deck, bar, brake levers, fork
and caliper. Six replacement/additional import Models were grouped into the
source without moving their meshes. The unnamed display was restored to Display,
and the duplicate front BackSpringStick was renamed FrontSpringStick. The source
has 25 components, 21 MeshParts and 44 physical parts. Its original poses, sizes
and appearances remain intact. The pre-grouping source/import copies are retained
in `ServerStorage.ScooterAuthoring.KukirinSourceBeforeReassembly_2026-10-05_<guid>`.

The user chose to steer the entire front assembly together. The new anchored,
noncolliding `Workspace.ScooterFinalRig` uses uniform scale 0.30, seven hinges
(one column Servo, four arm pivots, two wheel axles), two central springs and
18 attachments. FrontFork and both brake levers are rigidly linked to the steering
column/bar; the front arm pivots and spring upper endpoint belong to the column.
FrontSpringStick and FrontBrakeCaliper belong to the moving front axle; BrakeDisc
spins with the wheel. There is no separate FrontSteeringCarrier. The older
independent-front-wheel design is still supported with eight hinges.

Mesh-local mounting coordinates from the approved earlier arm/shaft geometry
were normalized by mesh size and transferred to the new poses. Paired arm mounts
share a common lateral axis. The front body-local pivot is
`(10.599335, -3.635489, -0.028695)`, rear is
`(-11.522461, -3.402217, -0.120220)`, and steering is
`(13.481873, 4.332480, -0.044452)` in unscaled source studs. Springs use their coil
endpoints. The cloned body's imported PivotOffset is normalized for upright model
bounds without changing the source. Dashboard internal welds are regenerated when
absent; its previously accepted extra 1.48 display scale remains configured.

Native constraints are yellow. `_ScooterRigReview` contains 18 yellow endpoint
adornments and two spring lines, without adding physical parts. Repeated review
does not duplicate them; installation strips this folder from gameplay copies.
Preview offset `(0, 1.25, 20)` puts the model beside the source and above the
sidewalk for Edit inspection. PreviewNewModel retains earlier previews in backups.

At this construction stage, MountsVerified remained false pending visual review;
the previous gameplay template stayed active. Native builder tests cover both
steering designs, new import mapping,
regeneration of removed dashboard welds, preservation of source pivots/geometry,
marker cleanup and invalid links. A detached, temporarily approved copy passed
installer, calibration, clone and geometry-repair checks, preserving all 21 meshes
and mechanical endpoints without approving the actual draft.

This draft was subsequently accepted and installed as described above. Save the
place to persist the source, approved draft and installed Studio mesh assets.

## Source restoration before remodeling — 2026-10-05

The user requested a handlebar, front shock and front wheel remodel. The original
source was restored as `Workspace.ScooterFinal` in its original scale (1.0) and
world layout. All 39 physical parts are anchored and noncolliding. Its 17
MeshParts and appearances are preserved; 20 top-level component Models can be
arranged independently. StopLight and BackSpringStick now each have a Model
wrapper. No attachments, constraints or welds remain, including the 19 original
dashboard-internal welds. Decorative coil meshes remain available for editing.

The installed Kukirin template and approved draft were moved intact into
`ServerStorage.ScooterAuthoring.KukirinBeforeRemodel_2026-10-05_<guid>`.
The unchanged original source remains at `ServerStorage.ScooterAuthoring.ScooterFinal`.
The pre-Kukirin template from `ScooterTemplateBackups` was validated through
ScooterRig.Prepare and restored as the active `ScooterModels.scooter`, so the
existing gameplay systems retain their template. Workspace.Map was untouched.

`DevScooterBuildConfig.MountsVerified` is now false. The previous coordinates and
0.30 preview scale remain reference values; mounts must be remeasured and approved
after remodeling. No new preview or mechanical rig was generated. Save the place
to retain these Studio-authored changes. The following sections describe the
previous assembly and its development workflow.

The new authored source is `Workspace.ScooterFinal`. On 2026-10-04 it contains
17 MeshParts, 22 ordinary/wedge parts and 19 dashboard-internal WeldConstraints.
It has no mechanical attachments, hinges or springs. Its world bounds measure
33.502 by 30.800 by 18.890 studs. After inspecting the 0.20 preview, the user
approved its mounting placements and increased uniform scale to 0.25 for an
8-stud reference avatar: the copy measures about 8.376 by 7.700 by 4.723 studs.
The current test template uses scale **0.30**, as requested after the first ride.
The physical dashboard has an additional `DashboardScale = 1.48`, about 10% larger than the previous 1.35 setting.
Uniform scooter scale remains 0.30.
The accepted part-local mounting coordinates are preserved through scaling.
Scaling preserves the source's lowest bounding point and offsets the copy by
20 studs in world Z so it can be inspected separately.

After syncing Rojo, stop Play and run in the Studio Command Bar:

```lua
require(game.ServerScriptService.Scooter.ScooterWorkflow).PreviewNewModel()
```

This explicitly creates `Workspace.ScooterFinalRig`. Repeated calls rebuild from
the original and move the previous marked draft into
`ServerStorage.ScooterRigDraftBackups`; unrelated instances occupying the preview
name block the operation. The workflow reloads fresh builder/config modules and
destroys its temporary modules on success or failure. A previously cached older
ScooterWorkflow must itself be required through a fresh clone or after reopening
Studio to expose the newly added command.

The preview preserves the authored source and active template. It is anchored,
noncolliding and separate from gameplay. Its inspection elevation is deliberate:
it cannot settle on the road until converted into the runtime template.

After accepting mounts, run the explicit Edit-mode installation command:

```lua
require(game.ServerScriptService.Scooter.ScooterWorkflow).InstallNewModel()
```

The installer validates and clones the approved draft, preserves its attachment
frames and meshes, normalizes imported names, creates rider/contact helpers and
calibrates the actual two-shock linkage. It installs the resulting model as
`ServerStorage.ScooterModels.scooter`. The previous template is moved intact into
`ServerStorage.ScooterTemplateBackups` under a unique name. The complete raw source
and anchored draft move into `ServerStorage.ScooterAuthoring`, outside the live
world; neither is destroyed. PreviewNewModel also finds the archived raw source.
The production map is untouched. Save the place to persist these Studio assets;
Rojo versions the installer/configuration, but does not export Studio mesh assets.

## Mechanical groups

| Group | Components |
| --- | --- |
| Chassis | ScooterBody, Footrest, StopLight, front and rear spring meshes |
| Steering column | HandleBarStick, Handbar, both Grips, Display, FrontLight, ScooterDashboard |
| Front steering | generated FrontSteeringCarrier |
| Front suspension | FrontLeftSuspension, FrontRightSuspension, generated VirtualFrontAxle |
| Rear suspension | BackLeftSuspension, BackRightSuspension, BackSpringStick, generated VirtualBackAxle |
| Front wheel | FrontWheel, BrakeDisc |
| Rear wheel | BackWheel |

There are eight HingeConstraints: separate column and front-wheel steering
Servos, two independent wheel rotation hinges and two coaxial pivots for each
suspension assembly. Each paired arm
assembly is welded to its virtual axle, without welding to the chassis or steering
shaft. Each end has one central SpringConstraint between the chassis and its moving
axle. Front swingarms stay attached to ScooterBody; FrontSteeringCarrier turns
the tire at the axle without yawing the swingarms outside the deck. The existing dashboard housing welds are retained and its screen
assembly is welded to Handbar. All 17 original MeshParts and their appearances
remain in the copy. The user accepted the visible mounting placements; this is
visual verification, not a measurement of mesh vertices or a physics solver test.

`DevScooterBuildConfig` centralizes scale, avatar height, preview offset, steering
settings and part-local mounting coordinates. Suspension pivots and the steering
pivot were placed using visible geometry and captured poses and accepted by the
user. `MountsVerified = true` preserves that decision on rebuilt copies.
Pivot coordinates use the original ScooterBody CFrame, in pre-scale studs; the
builder applies uniform scaling. Paired hinge axes run along the body's local Z.
Wheel pivots use the imported wheel centers. Spring endpoints use each coil's
local Y bounds. The rear lower endpoint remains on the moving axle assembly with BackSpringStick.

## Runtime contract and calibration

`CentralShockRig = true` selects the two-shock contract in the existing ScooterRig
and ScooterSuspension modules. Hinges, structural welds and wheel attachments use
the existing canonical names. ShockAbsorber_Front joins ScooterBody to
VirtualFrontAxle; ShockAbsorber_Back joins ScooterBody to VirtualBackAxle. Each
shock is calibrated from its own physical linkage leverage, with passive paired
hinge travel stops and spring length limits. The legacy four-shock rig remains
supported. Legacy automatic front-rest realignment is skipped for this model:
FrontRestPoseStatus is Authored, preserving user-approved mounts.

The imported Footrest is renamed RearFootRest; it is an inclined rear support.
An invisible FootRest helper describes the real riding deck inside ScooterBody.
Its top was checked by raycasting the authored body mesh at several points.
DeckCollider and standing attachments use this surface, while hand attachments
use the actual LeftGrip/RightGrip centers. Existing rider alignment derives
standing height from the live Humanoid instead of hardcoding avatar height.

RuntimePhysics in DevScooterBuildConfig targets chassis mass 12, steering mass 2,
each wheel mass 2, each suspension arm mass 0.5, front steering carrier mass 1
and reference rider mass 40
(Roblox mass units). These are model-specific starting values. The original
scaled import produced a total mass under 2 and unstable solver motion against
loaded springs; balancing the assemblies eliminated the observed jumping.
The tested Studio avatar contributed approximately 40 mass units. Imported
geometry, positions, scale and attachment frames are preserved; the runtime
clone receives physical densities. Safe travel and spring tuning continue to
use the existing shared suspension algorithm. Clones retain calibrated rest
limits instead of recalibrating their compressed pose.

Existing server-controlled driving, reverse/braking, physical steering,
wheelie, burnout, smoke, ECO/SPORT toggling, dashboard and rider presentation
are reused. Ownership and existing drive remote validation are preserved; the separate light
request is server-validated. Garage, upgrades
and economy remain parked. Imported coil meshes are still rigid decorations:
physical SpringConstraints work, but coil compression visuals and further
animation polish remain for the animation stage.

## Verification

The read-only inspection and draft fixture suites check source preservation,
scaling, internal links, rigid connectivity and rejection of invalid geometry.
`tests/scooter_install.studio.luau` uses the actual approved draft with native
Roblox Instances. It checks all imported mesh frames/sizes, unchanged hinge and
spring endpoints, canonical runtime links, deck/grip targets, mass, calibrated
travel, idempotent runtime cloning, decoration weld safety and rejection of
unapproved mounts. Tests do not install or mutate the source/active template.

On 2026-10-04 the complete CLI regression suite (747 assertions), Roblox type
analysis, Luau compilation and Rojo build passed. A real Play session verified:

- Empty and mounted rigs settle with both wheel probes grounded and remain upright.
- SPORT reaches 55 km/h and ECO reaches 25 km/h using existing validated DriveInput
  and ToggleDriveMode remotes. Keyboard injection loses focus during tool calls,
  so this automated test sent input through the normal remotes directly.
- Wheelie activates with rear contact and lifts the front wheel; braking returns it.
- Reverse, steering during burnout, rear smoke and BrakeActive respond to input.
- Dismount clears burnout/braking, restores character network ownership and retains
  server ownership of the scooter. The rig settles on both wheels afterward.

The 0.30 handling pass also verified the native steering Servo at rest, straight
acceleration, return to center and turning. Torque 50000, AngularSpeed 2 and
AngularResponsiveness 100 held the mounted neutral steering near zero; softer
trial settings drifted to the travel stop. Straight drive ignores residual
measured steering when accepted A/D input is neutral, preventing feedback into
chassis yaw. Steering travel is now 48 degrees and speed fade starts at 25 km/h.

The latest terrain pass replaced chassis launch impulses with wheel-local
VectorForce support along the tire/corner climbing tangent. A higher face ray
clears road penetration; a lower fallback retains contact through the final
centimeters. Actual springs remain passive and the chassis follows bounded axle
pitch. Supported step height is limited by both MaxStepHeight and tire radius.
Native Play tests, using temporary geometry outside Workspace.Map, verified:

- Forward launch from rest against vertical 0.65- and 0.90-stud curbs, with both
  wheels crossing and measurable suspension travel.
- Reverse launch from rest against a 0.65-stud curb, followed by the normal
  18 km/h reverse cap.
- Both steering directions and return to center; low-speed column deflection
  reached 48 degrees, while speed fade remained active. A tiny 0.1-mass carrier
  drifted under load; the installed 0.25-stud carrier has mass 1.
- A fast frontal wall impact causes Fallen, disables balance, tips the chassis
  and uses existing rider ejection/stun/recovery. A stationary/slow wall nudge
  stays mounted, adds no climbing force and does not trigger Fallen.

Temporary fixtures were removed by stopping Play. The current design and
remaining terrain cases are in [SCOOTER_TERRAIN.md](SCOOTER_TERRAIN.md).

Follow-up native Play tests also used the actual 1-stud map sidewalk without
modifying Workspace.Map. The old 95%-of-radius bound excluded that height for
the front collider. The bound is now 135% (also capped at 1.6 studs), with a
minimum forward tangent for contact compression and perpendicular face distance
checks for angled contact. Starting with either the front tire blocked or the
front tire already on top/rear tire blocked carried both tires over the curb;
a 45-degree approach passed as well. A/D at zero speed moved both steering
Servos to +48/-48 degrees and released to center while speed stayed 0 km/h.

The white front beam, rejected malformed/rate-limited light requests, forward
braking, reverse lamp without BRAKE, and braking reverse motion were checked
through the real running server. The analog HUD was inspected visually; a native client fixture also checked
47 km/h, ECO, reverse R without BRAKE, and GUI/connection cleanup. Keyboard
L delivery and mobile controls still need manual acceptance; remote-based
automation does not establish those behaviors.

Longer manual handling tests across map curbs/slopes, two-client light visibility
and final avatar ergonomics remain part of gameplay tuning. Rebuild the preview from the raw source and reinstall
explicitly if scale or mounting configuration changes; never scale only a live
prepared rig, whose densities, contact clearance and suspension tune are calibrated.
