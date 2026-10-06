# Arcade curb handling — selected scale 0.25

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
there is no model teleport or wheel-position correction.

Minimum face opposition decreases from 0.30 to 0.12, admitting glancing travel
up to approximately 83 degrees from the face normal. Long rays are still gated
by perpendicular face distance within tire radius plus 0.18 stud. The climbing
lift no longer shrinks with the approach cosine: the tire/corner geometry
controls its vertical assistance even at a shallow approach.

ComputeStepForce now supports the load vertically while targeting 5.5 studs/s
along the climb tangent, with response 16, acceleration bounded to 100 studs/s²
and supported-mass fraction 0.85. The previous gravity projection could not carry
the chassis through the final part of a tall climb, even when its top was found.
Normal acceleration, ECO/SPORT speeds, steering and wheelie settings are retained.

A climb must start with ground contact. When a verified ledge briefly lifts both
tires off the lower road, assistance may continue for 1.25 seconds after the last
supported contact. Each frame still requires a valid contacted ledge. Releasing
input clears the grace immediately; airborne input alone cannot start a climb.
Dismount, wheelie and Fallen logic clear eligibility through the existing server
controller. No new client remotes or client-provided obstacle decisions are added.
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
never brakes horizontally, and recovers toward 90% of verified entry speed within
the server mode limit. See [rider fit and momentum](SCOOTER_RIDER_POSE.md) for
settings and native rolling-approach results.
