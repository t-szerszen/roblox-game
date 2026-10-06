# Scooter curb handling, independent steering and impacts

Current settings use the accepted 0.25 model and stronger arcade assistance up
to 2.5 studs, including glancing approaches and brief loss of ground contact.
See [current arcade handling](SCOOTER_ARCADE_HANDLING.md). The following describes
the earlier handling passes and their validation.

The original handling pass used scale 0.30; current playable comparisons are
0.20 and 0.25, documented in [SCOOTER_SCALE_TESTS.md](SCOOTER_SCALE_TESTS.md). Forward acceleration and ECO/SPORT speeds
remain as previously accepted. This pass addresses starting against a curb, front
swingarms sweeping outside the deck, and high-speed wall collisions.

## Wheel contact and climbing

The existing server VectorForce still drives the chassis. ScooterTerrain creates
one additional VectorForce per physical tire, attached to WheelCenter and cleared
when drive eligibility ends. It measures a contacted vertical face, a supported
top, bounded rise and overhead clearance. The high face ray (0.14 stud above the
inset sphere bottom) avoids starting inside the road; the 0.02-stud fallback
retains support when the high ray has already cleared the corner.

The force follows the climbing tangent around the tire/corner contact. It accounts
for supported mass and gravity, targets 3.5 studs/s along that tangent and limits
added acceleration to 60 studs/s². SupportMassFraction is 0.6 to cover transient
load transfer; the controller reduces added support as climbing speed increases.
It acts on the tire assembly, transferring load through the existing passive
hinges and springs. No chassis teleport, constant upward kick, spring locking or
new client input endpoint is involved. Both tires receive support when eligible,
including the trailing tire and reverse travel. Reverse eligibility uses the
same 2 km/h direction-change band as the drive controller.

During the scale-comparison pass, maximum automatic rise was the smaller of
MaxStepHeight (1.6 studs) and 160% of
the inset tire radius. The scale-comparison follow-up raised the previous 135%
allowance because it rejected a one-stud curb for the 0.20 tire. The authored map sidewalks rise approximately 1 stud;
the previous 95% limit rejected them for the 1.041-stud front collider. Contact
compression can also put their corner just above the tire center. A bounded
minimum forward tangent keeps the tire advancing while support lifts it over
the corner. At angled approaches the extended travel ray finds the face, but
distance measured perpendicular to its normal must still be within the tire
radius plus 0.12 stud. This avoids lift before actual contact. Taller obstacles
require a deliberate trick; walls do not get climbing support. Normal chassis
balance follows measured axle pitch, capped at 20 degrees, while wheelie retains
its own pitch control. These are data-driven gameplay aids, not a complete tire
friction/contact simulation. Original wheel friction is retained after a higher
friction trial produced excessive drag.

## Front suspension and steering

This independent-wheel topology describes the earlier handling pass. The user
subsequently remodeled and approved the entire front assembly steering together;
the current rig uses IndependentFrontSteering=false. See SCOOTER_FINAL_RIG.md.

IndependentFrontSteering changes only the central-shock rig's linkage. Both front
swingarm hinges and the shock upper attachment belong to ScooterBody. The arms
are still welded to VirtualFrontAxle and freely compress within calibrated limits.
FrontSteeringCarrier has a vertical kingpin Servo at the wheel center and the
separate passive tire rotation hinge. The column Servo drives the handlebars and
hands; the wheel Servo receives the same steering target. Chassis curvature uses
the measured wheel Servo angle. This prevents steering from sweeping the arms
and spring outside the deck. Mesh rest poses and accepted mounting locations are
retained; only the fixed assembly and additional steering joint change.

The carrier is a hidden 0.25-stud part with mass 1. A lighter trial was unstable.
Both Servos retain torque 50000, speed 2 and responsiveness 100. Low-speed travel
is 48 degrees; the existing 25–80 km/h fade limits deflection at speed. This makes
low-speed turns tighter without adding stationary yaw. A/D also steers both
Servos at zero speed without throttle or burnout; normal chassis yaw still
requires travel. Legacy rigs still use
the original steering/suspension contract. Developer repair and calibration know
about the new carrier, and legacy rest realignment skips authored central rigs.

## Impacts, wheelie and screen

ScooterImpact probes in the actual direction of travel, above climbable curb
faces. A candidate must oppose travel, have a near-vertical normal, remain recent
(0.2 s), and be followed by an actual loss of approach speed. At least 24 km/h
of normal approach speed and a loss of 12 studs/s are required. Mere proximity,
slow nudges, ordinary braking, glancing contacts and ground landings do not crash.
A confirmed impact enters existing Fallen logic, disables balance, tips the
chassis, ejects/stuns the rider and uses existing recovery timers. No damage or
economy changes are added.

Natural wheelie drop increases from 45 to 58 degrees/s, with return smoothing
from 2.5 to 3.2/s; throttle still raises the front and S still lowers it faster.
DashboardScale increases from 1.35 to 1.48, approximately 10%, around its screen.
The whole scooter scale remains 0.30. Rebuild/install from preserved authoring
source to change these settings; save the place for Studio-authored assets.

## Verification

747 CLI assertions, native draft/install fixtures, type analysis and build verify
logic, structure and cleanup. Native Play using temporary parts outside
Workspace.Map verified forward starts against 0.65/0.90-stud curbs, reverse
against a 0.65-stud curb, suspension travel, both steering directions/centering,
fast wall ejection and harmless slow wall contact. Drive automation sent normal
validated remotes because tool focus interferes with keyboard injection. The
fixtures were removed on stopping Play.

The follow-up native Play tests used the actual 1-stud sidewalk in Workspace.Map,
without modifying it. They verified launch from rest with the front tire blocked,
and with the front tire already on the sidewalk while the rear tire was blocked,
including a 45-degree approach. Both tires crossed and the rider stayed mounted.
An additional 1-stud fixture reproduced the front-up/rear-blocked position.
At 0 km/h, A/D reached +48/-48 degrees and release returned the steering to
center. CLI regressions cover corners above the center, angled face contact,
rejection of distant faces and stationary server steering without chassis yaw.

Further manual map acceptance should cover successive steps, other approach angles,
uneven meshes, slopes, different avatar masses and multiple riders. Visual coil
compression remains part of the future animation work; actual SpringConstraints
already provide suspension.
