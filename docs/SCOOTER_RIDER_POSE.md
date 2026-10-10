# Avatar behavior

Avatar Settings retains the intended 8-stud height. Gameplay does not scale
characters, change limb lengths, or add first-person body visibility.

Stage 1 adds only a base standing pose for mounted R15 riders. `ScooterServer`
retains the native SeatWeld and lowers its standing root offset by 4.5% of HipHeight
along the scooter's up axis. `ScooterBaseRidingPose.client.luau` observes occupied
seats for all visible scooters. A single PreSimulation pass runs
`Shared/Scooter/ScooterBasePose` after Animator evaluation, overriding the seated
and mood joint transforms while keeping Animate enabled. Each client computes
remote riders' appearance too; joint Transform changes themselves are not used
as a networking mechanism.

The focused two-bone solver reads actual Motor6D C0/C1 or upgraded
AnimationConstraint attachment frames, preserving joint lengths and attachment
connections. It places both feet forward on FootRest in a staggered stance, with an
8-degree toe lift on the front foot and heel lift on the rear foot. Projected
foot bounds determine deck contact and margins. Authored palm grip points meet
HandleBar.LeftHandGrip/RightHandGrip, with hands pointing down onto the bar.
Waist lean is 5 degrees; neck counter-rotation keeps the head upright. The arm
solver rotates each elbow only about its authored hinge axis, preserving the
mesh seam rather than independently twisting upper/lower arm segments. Palm orientation follows the actual moving bar;
elbow poles have been moved forward and slightly inward. Native
measurements give approximately 18/30-degree knee bends and 38/26-degree elbow
bends on the current avatar. Pose parameters
live in `ScooterConfig.BaseRidingPose`.

Pose evaluation derives the character frame from the existing SeatWeld so that
server-owned character/vehicle interpolation cannot introduce a false arm reach
error while moving. The final reference-fit normal-throttle probe is recorded in
`SCOOTER_BASE_POSE_ANALYSIS.md`.

The user subsequently authorized a complete model rebuild around this pose.
The current authoring recipe preserves the neutral grips, relocates the complete
front assembly with its real steering axis, and builds a coherent body around
that mount. See [the current remodel](SCOOTER_RIDER_REMODEL.md) for geometry,
installation, preservation guarantees and steering reach limitations.

Dismount, death, character/model destruction and script destruction release the
pose and its event connections. Default animation continues normally afterward.
R6 and incomplete R15 rigs receive no custom limb pose. Geometry outside the
confirmed fit cannot be guaranteed: unreachable goals retain joint lengths
rather than stretching limbs or scaling an avatar. No uploaded animation is
required. No start/stop, foot-support, wheelie or turning animation was added;
existing vehicle mechanics remain intact.

See [measurements and diagnosis](SCOOTER_BASE_POSE_ANALYSIS.md) and
[native verification](../tests/scooter_base_pose.studio.luau).

## Climbing without artificial horizontal braking

Previously the tire force targeted a fixed speed **along** the climbing tangent.
At faster entry speeds this supplied a backward horizontal force, exaggerating
curb deceleration. The current force separates vertical support from forward
assistance: it bounds vertical climbing speed at 5.5 studs/s and never supplies
negative forward acceleration. On a verified contacted ledge, each tire remembers
its entry speed and retains 100% of that speed, with an 8-stud/s minimum
for starts from rest. Acceleration is bounded and the target respects the server's
ECO/SPORT or reverse limit. The existing contacted-face, top/overhead, height and
airborne-grace checks remain required. Releasing input or reversing clears the
entry-speed memory. Verified climb momentum is restored after native collision solving, including
a short, expiring clearance interval while the rear tire finishes crossing.
Walls and unsupported flight remain outside that correction.
