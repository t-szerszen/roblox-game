# Rider fit and momentum at scale 0.25

The accepted balance leg is **left**. The right foot stays near the middle of the deck in every state. At idle the
left foot supports on the road, with natural right-knee flexion preferred over
a straight support leg. The scooter stays at 0.25. The user chose longer legs
also outside riding; the native R15 avatar is now about 9.8 studs tall.

`ScooterServer.alignRiderToDeck` fits the seat weld using the actual standing
height, a proportionate forward offset and a small crouch. The existing
AlignOrientation adds a smooth six-degree left lean only at a grounded,
occupied stop without throttle/brake, wheelie, burnout or fall.

`ScooterAnimator` retains the existing occupant binding, replicated state clips
and cleanup. It adds forward torso pitch and a steering twist. `ScooterLimbSolver`
solves the arms and procedural legs after the body layer in PreSimulation, using
either Motor6D or the newer R15 AnimationConstraint joints. A complete manually
solved chain disables its corresponding IKControl to avoid competing solvers;
partial rigs retain the original IK fallback. The rider solver uses **fixed** bone lengths and rotations around the actual
rest-bone axes. It clamps unreachable targets instead of translating or stretching
limbs. Mesh sizes and geometry remain unchanged, preserving their rectangular
segments. Elbow poles follow the torso, blend at 6/s, and lift by only 0.25 stud
while steering. Saved joint transforms are restored on exit.
See the official [AnimationConstraint reference](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint).

`ScooterRiderPose` supplies smoothed targets. During wheelie, the left leg sweeps
forward/back with a 1.6-stud amplitude and a smaller smooth upward arc. The right
foot remains on the deck. At idle, a collidable-ground ray outside the scooter and
character places the left sole on the road; probes run at most every 0.08 seconds.
Existing idle/riding hysteresis prevents flicker. Loaded authored leg clips still
take precedence while they have blend weight. The fallback needs no animation
asset IDs. R6 retains its simpler procedural pose.

`ScooterFirstPerson` makes only the local rider's existing arms/hands visible
after the default camera update. It neither clones a character nor changes the
camera. Dismount restores local visibility and removes the render binding. Other
clients use the existing ScooterRiderVisualizer occupant binding for poses.

## Climbing without artificial horizontal braking

Previously the tire force targeted a fixed speed **along** the climbing tangent.
At faster entry speeds this supplied a backward horizontal force, exaggerating
curb deceleration. The current force separates vertical support from forward
assistance: it bounds vertical climbing speed at 5.5 studs/s and never supplies
negative forward acceleration. On a verified contacted ledge, each tire remembers
its entry speed and can recover toward 90% of that speed, with an 8-stud/s minimum
for starts from rest. Acceleration is bounded and the target respects the server's
ECO/SPORT or reverse limit. The existing contacted-face, top/overhead, height and
airborne-grace checks remain required. Releasing input or reversing clears the
entry-speed memory. Collision can still remove momentum, especially on tall steps;
this assistance does not promise constant speed through all obstacles.

## Verification

828 CLI assertions pass, including modern/legacy joint reach and restoration,
left-leg swing, fixed right foot, sampled idle-ground height, first-person
visibility/cleanup, and no backward force at fast curb entry. Rojo build and Luau
analysis pass for the affected modules.

Native Studio Play verified the actual 0.25 scooter and R15 avatar:

- Both hands and feet reach their targets; settled full-lock steering in both
  directions keeps hand error below 0.004 stud without limb extension.
- Left idle sole reaches the road with the existing 0.08-stud visual sink.
- First person shows all six R15 arm/hand parts on the original avatar.
- Fixed-length controlled wheelie produced a 2.94-stud left-foot sweep, under
  0.005-stud right-foot target error and roughly 0.006-stud hand error, without falling.
- Both tires crossed a 2.4-stud ledge at 45 degrees from a blocked start.
- A rolling one-stud ledge at 60 degrees retained at least 37.67 studs/s from
  a 40-stud/s start (about 94%) while climbing, with both tires reaching the top.

Temporary physics fixtures were created outside Workspace.Map and removed by
stopping Play. Human acceptance should check the preferred posture and balance
rhythm, steering while moving, uneven roads and multiplayer observers. Other
avatar proportions may need adjustments in `ScooterConfig.RiderPose`.

## Permanent leg proportions

`Characters/CharacterInit.server.luau` applies `CharacterProportions` once after
player appearance loads, including respawns. `Shared/CharacterConfig` sets the
minimum leg rest-bone length to 82% of each segment's mesh height. This separates
overlapping segments without changing mesh sizes. In the tested avatar each leg
chain measures 3.838 studs; the added rest length is 1.460 studs. HipHeight receives
the same increment for standing and walking. Spawn/respawn produced the same
length once, and no further extension occurs on mounting, steering or wheelie.

Motor6D rigs use calibrated C0s. AnimationConstraint rigs use separate rest
attachments, retaining Roblox's original RigAttachment metadata for animation
retargeting. Corresponding fallback ball sockets share the calibrated origins.
The server subtracts the permanent added length when fitting the scooter seat,
so the walking height increase does not lift the rider away from the grips.
Appearance assets and rectangular mesh dimensions are retained. Configurable
proportions are game-wide, not tied to scooter occupancy. Different body packages
may require additional visual acceptance; tall packages will exceed the earlier
8-stud reference. Mid-session appearance/scale customization should explicitly
reapply a fresh rig calibration rather than expecting a mounted-only resize.
