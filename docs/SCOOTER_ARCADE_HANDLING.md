# Arcade curb handling — selected scale 0.25

The [larger-wheel follow-up](SCOOTER_LARGE_WHEELS.md) retains this height limit and
horizontal momentum behavior, with gentler vertical support for small curbs
and a 1.95-stud tire diameter. The latest refinement adds one-degree entry,
shared tire support, underside recovery and spawn selection beside the player.

The user requested stronger arcade obstacle traversal, especially oblique curbs,
and selected scale 0.25. The installed `ServerStorage.ScooterModels.scooter` is
already 0.25; DevScooterBuildConfig now uses 0.25 for future builds. The earlier
0.20 template and accepted 0.30 review draft remain available. Studio comparison
displays are off by default to keep the spawn clear.

## Assistance and limits

The existing ScooterTerrain controller still applies one VectorForce per tire
through its normal WheelCenter attachment, hinges and suspension. Its maximum
ledge height is now 2.5 studs, also capped at 3.5 times the inset tire radius.
A 0.06-stud tolerance accounts for native solver penetration at the configured
limit. Assistance requires a contacted face, a walkable top and clear overhead;
there is no model teleport or wheel-position correction. During verified climbing,
PostSimulation caps excess upward rebound across connected assemblies together,
preserving relative spring motion. It also restores longitudinal entry speed
while a validated climb is active and briefly while the rear wheel clears it. Unsupported flight
and wheelie are excluded.

Minimum face opposition is sin(0.5 degrees), admitting one-degree approaches
measured from the curb edge. Short forward and both side rays remain gated by
perpendicular face distance within tire radius plus 0.18 stud. A supported top
is probed inward along the face normal. Rounded and uphill sloping faces are
also eligible; additional short inward samples find their walkable arc. Entry adds a bounded inward component,
which drive grip also follows while that verified contact lasts. Exactly parallel
or retreating travel does not trigger climbing.

ComputeStepForce now supports the load vertically while targeting 5.5 studs/s
along the climb tangent, with response 16, acceleration bounded to 100 studs/s²
and supported-mass fraction 0.85 for one assisted tire. Paired contact shares one
full gravity load across both tires, without doubling lift.
Smaller curbs use the gentler profile documented in SCOOTER_LARGE_WHEELS.md.
The previous gravity projection could not carry
the chassis through the final part of a tall climb, even when its top was found.
Catalog acceleration and ECO/SPORT speeds are retained. The restored steering
and over-pitched wheelie spark follow-up are described below.

A climb must start with ground contact. When a verified ledge briefly lifts both
tires off the lower road, assistance may continue for 1.25 seconds after the last
supported contact. Each frame still requires a valid contacted ledge. Releasing
input clears the grace immediately; airborne input alone cannot start a climb.
Dismount, wheelie and Fallen logic clear eligibility through the existing server
controller. A short complete-footprint underside Blockcast also recognizes deck
support when both tires hang above the road. Separate low deck friction lets
ordinary W/S drive slide off that support. Without physical support the normal
airborne-drive rejection remains active. No new client remotes or client-provided
obstacle decisions are added.
Tall-wall impact probes use the same climb-height bound, so ordinary supported
ledges are excluded while larger walls retain the existing crash behavior.

## Verification

Native Play at scale 0.25, with temporary geometry outside Workspace.Map:

- Started from rest and climbed a 2.5-stud ledge at 45 degrees, both wheels on top,
  rider mounted and not fallen; peak chassis vertical speed about 6 studs/s.
- Climbed a one-stud curb at 75 degrees; both wheels reached the top.
- Reversed onto a 2.4-stud ledge at 45 degrees, without ejecting the rider.
- A three-stud wall received zero step force and remained impassable from rest.

Fixtures were wide enough that the scooter could not drive around their ends.
Input was sent through the normal validated DriveInput remote. All fixtures and
automation were removed on stopping Play; production map geometry was unchanged.
761 CLI assertions pass, including glancing/parallel face handling, tall-step
limits, solver tolerance, airborne-grace expiry and input-release cleanup.
Native build/install fixtures, Luau compilation, Roblox-aware type analysis and
Rojo build also pass. Manual acceptance should assess the desired arcade feel on
successive curbs and other map geometry.

## Momentum follow-up

Tire assistance now separates bounded vertical climb speed from forward support,
never brakes horizontally, and retains 100% of verified entry speed within
the server mode limit. See [avatar behavior and climbing](SCOOTER_RIDER_POSE.md) for
the rider defaults and climbing behavior.

## Rounded obstacles, rebound and restored steering

The latest follow-up extends face detection to uphill normals below Y=0.98 and
searches up to two tire radii inward for a walkable arc on the same obstacle.
This lets W/S restart against a rounded speed hump as well as a curb. Rolling
approaches get 0.12 seconds of anticipation, capped at five studs; the same
2.5-stud height and overhead checks apply. Stationary detection stays local.

Suspension revision 3 uses damping ratio 1.4 and force headroom 1.1, down
from 4, limiting peak shock force while preserving passive visual travel. Contact proxies have
zero restitution with weight 100 to reduce bounce from map materials. A root
VectorForce damps excess upward speed during a verified climb and a brief,
road-probed settling interval. The existing server record also calls terrain
Stabilize in PostSimulation: excess chassis rise above 3.5 studs/s on small
steps, or 5.5 on taller ones, is removed equally from connected assemblies.
It changes no wheel positions. Supported road motion also receives rebound
damping after a climb: excess upward speed is limited to road rise plus
0.05 studs/s. Forward momentum recovery requires a verified local obstacle,
fresh direction and support/grace; the short clearance cache expires after
0.25 seconds without renewed assistance. Losing input, entering wheelie/fall
or dismounting clears climb and momentum assistance. Free airborne travel
keeps normal gravity.

Steering restores the previous full-axis AlignOrientation controller and
measured 48-degree Servo input. Maximum yaw rate is again 165 degrees/s,
heading lead starts at 12 degrees and scales with smoothed rider input. Holding
a direction for 0.18 seconds begins a 0.45-second ramp up to a 20-degree limit.
Release or changing direction resets that boost; unsupported travel, wheelie
and burnout do not build it. High-speed input fades to 0.55 between
25 and 80 km/h, and lateral slip correction is bounded to 100 studs/s².
A curvature boost of 1.2 improves low-speed maneuvering and fades to
1 over the same speed range. A separate rigid PrimaryAxisParallel constraint aligns only the chassis up
axis while riding on or immediately above sampled ground, preventing a collision from pitching the
rear into the air. Its target uses the same smoothed terrain pitch and steering
lean as the existing heading constraint; wheelie, falling and flight beyond
the ground probes disable it. There is no separate yaw actuator or additional cornering
acceleration. Terrain entry direction remains separate from balance
heading, preserving shallow-angle curb assistance without steering into a face.

ScooterScrape emits short orange/yellow particles near the rear scrape point
when server-measured pitch reaches 48 degrees, speed exceeds eight studs/s,
and a short downward ray verifies road within 0.65 stud. Pitch hysteresis stops
emission below 43 degrees. Reset, dismount, falling and scooter destruction
clear the effect. Particles start at 0.36 stud (three times the earlier size),
emit at 85/s and live for 0.2–0.4 seconds; size, lifetime and speed are configured
in WheelieSparks. It uses the existing server simulation and normal input
validation, with no additional remotes or client-selected effect state.

Earlier native obstacle verification: a rounded one-stud hump
passed forward and reverse from rest in approximately 1.5–1.7 seconds, with
chassis upward speed capped at 3.5 studs/s. Sparks appeared at 49.2 degrees of
actual pitch, stopped after overbalance/fall, and their attachment was removed
on replacement. These are controlled fixtures, not a guarantee about every
arbitrary collision mesh in the manually authored map.

The final native curb regression passed 14 cases: all 13 climbable approaches
crossed, including a frontal approach reaching 50 km/h and both sides at one
degree. A three-stud wall received no assistance. Small-curb chassis rise stayed
at or below 3.5 studs/s. A four-stud narrow underside support initially reported
both tires unsupported and DeckGrounded=true; W moved 4.6 studs clear, and S
moved 3.2 studs before its tire encountered the block beyond the climb limit.
The standalone Play runner passed; four additional one-degree entries
(rest, rolling, reverse rolling and opposite side) also crossed, with the rider
retained and no fall. The reproducible Play runner is `tests/scooter_arcade_followup.studio.luau`.
The CLI suite covers steering rollback, high-speed attenuation and spark lifecycle; Roblox-aware type analysis, bytecode
compilation and Rojo build also pass.

Rollback verification in native Play retained the rider through four turning
runs. At roughly 43–44 km/h, full steering measured a mean radius of 99.9 studs
versus 100.7 with the previous curvature. At 55 km/h, sustained 20 percent
left/right input turned about 31 degrees over three seconds; after release,
yaw speed settled below 0.042 rad/s. Tire penetration stayed within 0.036 stud
and maximum upward/downward chassis speed during these partial turns stayed
below one stud/s. The test floor spans 2,000 studs so gentle turns remain on road;
the runner rejects loss of road support or excessive suspension motion.
The same controller passed all 13 climbable curb cases, rejected a three-stud
wall and crossed the rounded hump in both directions. Larger sparks appeared
at 49.2 degrees of actual pitch, stopped after falling and were removed on
replacement. The final CLI run passed 911 assertions; type analysis, compilation
and Rojo build passed.

## Progressive held-turn refinement

The subsequent native steering-only regression passed six runs at 44–55 km/h.
Holding full steering reduced mean turn radius from 100.1 to 50.6 studs while
retaining the rider and road contact. At 55 km/h, 120 ms steering taps changed
heading by 4.2 degrees right and 7.7 degrees left, including the release tail.
Sustained 20 percent input produced about 49 degrees over three seconds.
All runs settled below 0.027 rad/s yaw after release; wheel penetration stayed
within 0.042 stud and vertical chassis speed below 1.85 studs/s. The spark
lifecycle also passed. The focused runner uses `STEERING_ONLY = true` after
the rider has loaded. The CLI suite passed 917 assertions; Roblox-aware type
analysis, bytecode compilation and Rojo build passed.

## Ground support across different heights

Ground probes also read lower surfaces within the 2.5-stud terrain budget.
Only actual tire proximity grants grounded drive; a distant or above-tire
surface can inform orientation but cannot authorize airborne propulsion.
Chassis pitch follows the sampled ground-height difference even when only one
wheel currently touches. This breaks the flat-frame deadlock at a curb edge,
letting the lower tire settle onto grass while the other remains on pavement.
All authoring meshes, attachments and suspension topology remain in place.

Revision 3 native physics verification passed all 13 climbable curb approaches,
including both sides at one degree; a three-stud wall received zero wheel-climb
force and remained blocked. Rounded humps passed forward and reverse from rest.
Four stationary fixtures with front/rear wheels on different one- and 2.5-stud
heights settled with both tires grounded; maximum contact penetration was
0.051 stud. Full-speed rolling approaches retained 99.996% and 99.632% of entry
speed across one- and 2.5-stud steps. The shocks still traveled 0.236–0.305 stud;
0.4 seconds after clearance, chassis vertical speed was downward at about
1.03–1.05 studs/s, rather than rebounding upward.

The same run passed six steering fixtures: held full steering reduced mean
radius from 103.1 to 54.6 studs, while 120 ms taps at 55 km/h changed heading by
4.5–8.2 degrees. Sparks started at 48.7 degrees of measured pitch, stopped after
falling and cleaned up on replacement. The wall force recheck measures only
WheelStepTraction, separating ordinary road rebound damping from climb support.
The CLI suite passed 930 assertions; Roblox-aware type analysis, Luau compilation
and Rojo build passed. All native geometry was temporary and outside Workspace.Map.
