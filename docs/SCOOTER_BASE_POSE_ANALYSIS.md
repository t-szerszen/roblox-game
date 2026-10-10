# Normal riding pose: stage 1 analysis

Inspection date: 2026-10-10. Measurements are from the running Studio session
`gra roblox` (placeId 127535941224851), not inferred from the build configuration.
No avatar, scooter template, map, or running scripts were changed for this inspection.

## Observed cause

`ScooterServer.alignRiderToDeck` modifies the native `DriverSeat.SeatWeld.C0`
to put HumanoidRootPart at standing height: HipHeight plus half root height for
R15. The Humanoid remains Seated and default Animate still plays SitAnim
(`2506281703`). This combines a standing root position with folded sitting legs.
The lowest foot bounding-box corners are approximately 1.7 studs above the deck
in the inspected frame. Lowering the entire rider alone would not straighten
the knees or place hands at the grips.

The other playing track, `114302219876492`, comes from Animate.mood.Animation1
at Idle priority; it is not a scooter riding clip. The sitting track has Core
priority. No active scooter-specific IK or pose controller was found. The working
tree already deletes the old avatar scaling and scooter pose modules; those
user changes must be preserved.

## Geometry and proportions

| Measurement | Studs / value |
| --- | --- |
| Scooter live model bounding box, including support parts | 4.56 wide, 8.63 high, 10.36 long |
| FootRest mesh bounding box | 3.9375 long, 1.3125 wide, 0.2375 thick |
| Wheel mesh diameter | 1.95 |
| Actual axle separation, approximately | 7.90 |
| Grip height above deck surface | 5.66 |
| Grip spacing | 3.74 |
| Live R15 standing height, approximately | 8.00 |
| Each live foot bounding box | 0.8425 wide, 1.9356 long, 1.277 high |
| Live HipHeight | 3.1112 |
| Live HumanoidRootPart height | 3.1143 |
| Live HeightScale / DepthScale | 1.55716 / 1.55716 |
| Live WidthScale / HeadScale | 1.16787 / 1.49487 |
| Account description Height / Width / Depth / Head scale | 1 / 1 / 1 / 1 |
| Live and account BodyTypeScale / ProportionScale | 0 / 0 |

The FootRest local X axis is approximately the scooter's longitudinal axis.
These are mesh bounding-box measurements, not exact visible surface contours.
The live model identifies itself as CentralShockRig and LargeWheelRemodel,
with ScooterDraftScale 0.25 and ReferenceAvatarHeight 8. Build configuration
alone therefore cannot determine current template dimensions.

Two feet cannot fit side by side within a 1.31-stud-wide deck: their combined
width is approximately 1.68 studs. A staggered stance, nearly one behind the
other, is appropriate. Their combined lengths leave little longitudinal margin;
the real visible deck surface and mesh soles must be checked visually.

No remaining gameplay source applies HeightScale or ApplyDescription. The live
applied description differs from the account description. Avatar Settings is a
likely source of the difference, but this is not proven; running characters can
also retain earlier changes. Roblox documents that these settings are not
accessible through scripts. Confirm Body > Scale and Build in Studio before
choosing which avatar dimensions the pose must support. The user subsequently
confirmed that height 8 is intentional and authorized Studio integration.
The implementation preserves that scale.

Variant A preserves the intended avatar size and adapts root/limb placement. This
is the preferred first step for the measured approximately 8-stud rider. Variant B
would require a justified size policy: returning this character to its account's
approximately 5-stud size may put the 5.66-stud-high grips out of natural reach.
Scaling changes feet, arm reach, joint frames, hitboxes, ground movement and other
systems; changing every player's scale is not a pose-only fix.

## Relevant hierarchy and ownership

The installed template is `ServerStorage.ScooterModels.scooter`; the live clone
is `Workspace.Scooters.<player> Scooter`. Root is welded to ScooterBody and the
invisible DriverSeat. Native SeatWeld connects DriverSeat to HumanoidRootPart.
FootRest is rigid with the body. HandleBar is rigid with HandleBarStick; its
existing steering hinge moves both. Suspension and wheel hinges/springs remain
independent and must not be changed for this stage.

The live Root already contains RiderRootAttachment, LeftFootPlant and
RightFootPlant. HandleBar contains LeftHandGrip and RightHandGrip at the actual
grip mesh centers. Their CFrame orientation follows the authored mesh and must
not be assumed to match the rider's forward orientation.

The live R15 character has 15 AnimationConstraints and no Motor6Ds. A pose
implementation must support Avatar Joint Upgrade rather than silently expecting
Motor6D joints. Existing physics joints must remain intact.

Files involved in a subsequent implementation:

- `src/ServerScriptService/Scooter/ScooterServer.luau`: native weld alignment,
  validated mount lifecycle, release and collision restoration.
- `src/ReplicatedStorage/Shared/ScooterConfig.luau`: centralized pose parameters.
- `src/ServerScriptService/Scooter/ScooterRig.luau`: generated support/targets;
  prepared templates preserve existing attachments, so changing generator values
  alone does not update an installed template.
- `src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau`: existing
  local mount lifecycle if local animation suppression or pose evaluation is needed.
- A small focused pose ModuleScript if required, without restoring the deleted
  multi-stage animation system or adding another rider weld.

## Proposed correction and acceptance

Preserve native SeatWeld and server mount validation. Express root alignment in
scooter-local coordinates, choose a slightly crouched standing height from actual
joint geometry, and apply a small forward torso lean. Position both foot soles
on FootRest with forward orientation and a staggered stance. Use existing grip
targets and procedural limb posing/IK with knee/elbow bend directions. Default
seated and mood animation must not compete with the mounted base pose; normal
Animate behavior must resume on dismount, death and respawn. Clean up every
temporary pose object and connection. Do not change acceleration, brakes,
collisions, steering physics, scale, or existing tricks.

A new uploaded animation is not yet justified. IKControl can pose limbs without
a new clip; its behavior with the actual upgraded rig must be verified in native
Play before claiming it solves this case. If a clip becomes necessary, author a
looping R15 base riding pose for the confirmed proportions and publish it under
the experience's permitted owner. A script cannot edit the keyframes of an
existing published animation merely by changing its ID or playback parameters.

## Initial implemented correction

Native IKControl was tested on the upgraded character but left target errors
and undesirable foot orientation. The initial implementation used a focused
two-bone joint-frame solver on existing AnimationConstraint/Motor6D joints.
It adds no physical joint and does not change limb lengths. Native SeatWeld
alignment lowers the root by 9% of HipHeight; its existing longitudinal target
is retained. Foot placement accounts for actual foot bounds; the waist leans
30 degrees to reach the relatively high/far grips, with upright head correction.
Both feet face forward. Measured knee bends are approximately 10/22 degrees;
elbows approximately 29/9 degrees. Animate remains enabled, with the base pose
applied after animation evaluation in PreSimulation on each observing client.

Build, bytecode compilation and Roblox-aware strict type analysis pass. Native
tests pass 77 assertions for actual foot/palm contact, slight knee/elbow bends,
and detached fixtures for both joint types, including joint restoration. Normal
gameplay-context lifecycle probes verify pose updates stop after the existing
dismount remote and after death. Remounting after respawn passes the same native
tests. Side/front inspection and target measurements were performed in Play.
No published clip is necessary.

A normal-throttle Play probe reached 11 km/h over approximately 28 studs.
The initial world-frame solve exposed a transient 0.66-stud palm error in motion.
Deriving the complete pose from native SeatWeld fixes mismatched character and
vehicle interpolation snapshots; the subsequent probe's maximum palm error was
0.034 studs, with negligible root/shoulder joint drift. A detached regression
fixture verifies that a delayed character snapshot cannot change joint targets.

The pre-existing CLI suite passes its first 229 assertions, then stops at an
undefined `make` helper in scooter_visuals.spec.luau. That unrelated failure was
not changed. Two actual clients and fit across different body/clothing variants
still require user verification. R6 has no custom base pose in this stage.

## Reference photo calibration

The user subsequently supplied three reference photos and explicitly authorized
adjusting the model to fit that pose. The original high/far grips require more
than one stud of additional reach with a nearly upright torso and downward
hands; changing avatar scale is unnecessary. The initial 30-degree lean was
therefore replaced by 5 degrees, and the upper steering visuals moved toward
the rider by 1.015 studs and down by 0.35 studs. Grip spacing remains 3.74 studs;
height above deck is now approximately 5.32 studs. Wheels, deck, lower fork,
steering axis, suspension attachment world frames and collision proxies remain
unchanged. The resized shaft retains its mass of 2 engine mass units through density
compensation; its visual shape naturally changes the inertia geometry.

Independent upper/lower arm orientation in the initial solver introduced elbow
twist, exposing the joint seam even when pivots coincided. Arms now use their
authored elbow hinge axis with zero elbow translation and no axial twist. Hands
point down onto the grips. Feet have opposing 8-degree pitches, their projected
bounds touching the deck. The root offset is lowered by 4.5% of HipHeight;
measured knee bends are approximately 18/30 degrees, elbows 38/26 degrees.

A replication-order issue was also fixed: observing clients now retain the pose
using the same VehicleSeat.Occupant signal that bound it, even if Humanoid.SeatPart
arrives later. Default Animate remains active outside the final pose pass.

The reference-fit native Play tests pass 85 assertions for contact, bends,
restoration, both joint types, interpolation and pure elbow hinge rotation.
The detached Edit-mode model-fit test passes 88 assertions. A final normal-throttle
probe traveled 28.97 studs, reached 33.82 studs/s, and had a maximum palm error
of 0.028 studs. The existing dismount remote released the pose updates and seat.
Final side and front screenshots were inspected in Studio. Matching every pixel
of the references is not claimed: the existing scooter mesh and viewpoint differ.
The 8-stud avatar scale and existing ride mechanics are retained. No new clip,
wheelie, transition or turning animation was added.

`DevScooterRiderFit.Build` reproduces the correction from the preserved installed
large-wheel template before `ReferenceRiderFit` was applied. It works only in
Studio Edit mode and rejects repeated fitting. Install its returned clone as
`ServerStorage.ScooterModels.scooter`, first archiving the previous template under
`ServerStorage.ScooterTemplateBackups`; never apply it to a live riding model.
The original authoring source and existing build/install pipeline are preserved.
The final component manifest is `assets/scooter/rider-fit-components.json`.
Run `tests/scooter_rider_fit.studio.luau`.Run(previousTemplate) in Edit mode to
verify the unchanged mounts, collision proxies, mass and rigid connections.

## References

- [Avatar Settings](https://create.roblox.com/docs/studio/avatar-settings)
- [AnimationConstraint](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint)
- [Inverse kinematics](https://create.roblox.com/docs/animation/inverse-kinematics)

## Straight shaft and steering diagnosis, follow-up

The user rejected the excessive shaft tilt and authorized lowering the bar while
keeping the shaft straight with its original angle. The recipe now preserves the
entire shaft rotation, fitting its lower endpoint into the existing front frame
rather than leaning the shaft toward the rider. Mount attachment world frames
still remain unchanged, and no collision proxy or ride parameter is changed.
The final straight-pose verification passes 91 native assertions, including
palm orientation. The model regression passes 90 assertions, including original
shaft tilt and roll. The updated component manifest records the straight shaft.

The user confirmed that the third problem screenshot was captured while turning
left. Hand orientation previously remained chassis-relative while grips rotated;
now it follows the actual bar. A detached steering sweep also revealed a reach
constraint: with a fixed torso, at 10 degrees one arm is already approximately
0.38 studs short and the opposite elbow bends approximately 77 degrees. At 20
degrees the shortfall reaches 0.80 studs. This cannot be corrected by the elbow
pole alone. Torso adaptation requires a scope decision before implementation.

## Complete rider-based remodel, current revision

The user subsequently authorized rebuilding the complete scooter around the
accepted rider. The current result and its validation are documented in
[SCOOTER_RIDER_REMODEL.md](SCOOTER_RIDER_REMODEL.md). Earlier model corrections
and their measurements above are historical; the current front module moves
with its actual bearing, and the obsolete original neck is hidden.
