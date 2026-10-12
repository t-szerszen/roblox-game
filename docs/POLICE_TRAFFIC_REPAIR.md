# Police and traffic repair — 2026-10-12

Branch: `fix/police-traffic-lifecycle`. Existing scooter/UI changes were retained.
No commit, push, merge, map rebuild or Studio source replacement was performed.

## Causes and implementation

The server's private scooter owner/occupant checks were already correct.
However, active pursuit reused the patrol's limited field of view and remembered
the character position rather than the physical scooter root. Active visibility
now uses a 350-stud range without the patrol FOV restriction, while preserving
LOS, last-seen memory, safe zones and existing escape/search/pursuit deadlines.
Mounted targets use the scooter root for routing and intervention; dismount keeps
the claim and changes the reference to the living character root. Death, character
replacement and disconnection release claims. Player relevance/body collection
also accepts HumanoidRootPart without requiring character PrimaryPart.

There were no collision/blockage offence paths. All triggers now use the same
atomic `PoliceService.Begin` and existing exclusive ownership registry. Incidents
reuse available units; they never create extra units. Fleet and pursuit budgets
remain two, with existing night reduction and release/invulnerability protections.

Impact detection runs on the existing police observation schedule. Scooter
proxies disable touch/query flags, so the system uses an overlap query per car
with `RespectCanCollide`, restricted to scooters returned by the server riding
API. Physical colliders must reach the car envelope within 0.2 studs, with both
rider approach and relative closing speed at least 12 studs/s. A fresh previous
velocity sample retains evidence when impact slows the rider. Continuous contact
is deduplicated per car, with a three-second player incident cooldown. Tangential
scraping, low-speed contact and police hitting a stationary rider do not qualify.

Blockage requires an actual civilian obstacle attributed to the player/scooter,
car speed and target speed no greater than 0.5 studs/s, obstacle/emergency-brake
reason, actor within 24 studs and the same culprit for 12 seconds. Changed
culprits, sampling gaps, intersection waits and NPC queues clear evidence.
Dispatch uses a nearby available patrol with clear sight; proximity to a queue
does not make a player its culprit.

The officer's former negative mount offset placed the anchored rig inside the
car. A standard-proportion R15 rig now uses a uniform scale of 1, measured head
placement above the actual car envelope and a massless noncolliding chassis weld.
Exit anchors the root and removes the weld before interpolation. Collision and
mass settings are restored at a supported, clear standing point. Existing
procedural poses, pathfinding, detention and boarding remain in use.

| Tuning | Before | After |
| --- | --- | --- |
| Pursuit cap | 112 stud/s | 160 stud/s (100 catalog km/h) |
| Police acceleration/braking | 28 / 32 | 36 / 42 stud/s² |
| Route refresh | 1 second | 0.5 seconds |
| Police pursuit sensing horizon | 100 studs | 380 studs |
| Officer walk speed | 14 | 18 stud/s |
| Stop delay / exit interpolation | 0.4 / 0.6 | 0.2 / 0.3 seconds |
| Civilian cap / acceleration | 32 / 5 | 35 / 5.5 |
| Civilian lane multiplier / fallback scale | 1 / 1 | 1.1 / 1.1 |
| Civilian no-progress check | 60 seconds | 120 seconds |

The larger police horizon covers approximately 305 studs of maximum-speed braking
distance. Curvature/yaw limits, support checks, reservations and swept clearance
still constrain all vehicles; the new cap applies on suitable straight roads.
The current production offence threshold was already 25 km/h and is preserved.
The existing police CLI test incorrectly assumed 50; it now reads the config.

The existing civilian fallback scales uniformly to 6.6 × 4.4 × 13.2 studs. Wheels,
axle attachments and chassis scale together. Ground probes now use each prepared
vehicle's measured wheelbase, including existing Kia/Ducato models. Other prepared
traffic templates retain the established chassis/axle/bounds contract.

## Lifecycle and recovery

Previously, the common controller retired police at dead ends or recovery
timeouts, and police recovery deleted units after its attempt limit. Recovery
switches to unmanaged patrol routing, exposing an active pursuit to dead-end
retirement. Distance/intersection/night retirement also lacked a common policy.

`Traffic/VehicleLifecycle`, consulted by `VehicleController.Fail`, now protects
units with an active target or outside officer from those routine removals.
Structural failures still clean up safely. Manager shutdown still destroys owned
objects and releases claims. Active police recovery preserves the unit/target;
ordinary pursuit/search end conditions still apply. Failed officer return ends
a pending resumed pursuit before explicit cleanup.

Civilian no-progress time uses verified advancement along sampled road curves,
not instantaneous speed or external model displacement. One stud of cumulative
route progress resets time and attempts. After 120 seconds the current blockage
is checked; stop signs, intersection waits, commanded holds, route ends and queues
behind NPCs are excluded. Unexpected blockage starts bounded recovery, with
15-second retry spacing. Rerouting is allowed only at the existing safe node
boundary without a held crossing. Failed recovery retires one vehicle through
the manager, releasing reservations/debug state and replenishing the same capped
fleet through safe spawning. No extra per-car loop is introduced. Cars/players
removed from the fleet/riding records discard incident evidence.

## Changed and added files

- `src/ServerScriptService/Police/`: `PoliceConfig`, `PoliceOfficerController`,
  `PoliceService`, `PoliceSpawner`, `PoliceStateMachine`, `TrafficViolationDetector`.
- `src/ServerScriptService/Traffic/`: `TrafficConfiguration`, `TrafficManager`,
  `TrafficSensors`, `TrafficSpawner`, `VehicleAdapter`, `VehicleController`;
  added `VehicleLifecycle`.
- `tests/`: updated `police.spec.luau`, `police.studio.luau`, `traffic.studio.luau`;
  added `police_traffic.spec.luau`, `run_police_traffic_tests.py`.
- Documentation: this report, `POLICE_SYSTEM.md`, `TRAFFIC_SYSTEM.md`, and an
  appended integration section in `tests/README.md`.

## Executed validation

- Police CLI: 809 production evidence, claim, transition and city-routing assertions.
- Traffic CLI: 2,655 road-geometry, connectivity and reservation assertions.
- Police/traffic integration CLI: 75 assertions using production orchestration,
  controller and lifecycle policy with explicit engine doubles. These cover
  impact attribution/deduplication/cooldown, persistent pedestrian blockage,
  legitimate queues, dismount/occlusion, physical scooter target positions,
  independent multiplayer claims, death/respawn/disconnect, claim release, 120-second recovery, failed
  recovery, progress reset and protected retirement.
- Rojo build, production/native-fixture Luau compilation and `git diff --check`.

No native gameplay, physics, visual or real multiplayer test was executed.
Studio listed an Edit session but execution returned
`Target is not reachable (createExecuteLuauBridge_loadCodeAsync, Edit)`.

## Native acceptance and known limits

Sync Rojo, run `tests/police.studio.luau` and `tests/traffic.studio.luau`, then run
fresh Play scenarios on the authored map. Updated native fixtures check scaled
civilian bounds/axles, officer mounting/visible head/stable turns, rear-target
pursuit sight and weld release on exit. Gameplay acceptance remains:

| Task test | Required native check |
| --- | --- |
| A: driving | Inspect both radiowoz models and the larger civilian; test narrow roads, turns, crossings, ground support and braking. |
| B: impact | Strike a radiowoz with an occupied scooter; verify PoliceImpact, one owner, cooldown, repeated-contact/side-scrape/low-speed negatives. |
| C: blockage | Block a civilian for 12 seconds; verify TrafficBlocking, evidence reset and no offence at stop signs or in NPC queues. |
| D: exit | Check faster exit, proper R15 proportions, clear side selection, detached mount, walking, arrest and boarding. |
| E: pursuit | Verify no ordinary removal at dead ends, recovery limits, distance/intersection timers or night transition; escape/disconnect then returns or cleans up. |
| F: recovery | Confirm recovery only after 120 seconds without route advancement, reset after movement and no removal in a normal queue lasting over 300 seconds. |
| G: multiplayer | Use two real clients with simultaneous incidents; verify independent targets, caps, death/respawn/disconnection cleanup and no orphaned units. |

Only the existing civilian fallback and Kia/Ducato templates were found in Git.
Additional models authored only in Studio could not be inspected or connected.
The graph still has 19 disconnected components; police do not invent lanes,
cross buildings or make unsupported U-turns. Siren permissions, original
Workspace A-Chassis scripts and procedural-animation limits remain as documented.

Contact detection samples physical proximity and authoritative motion. Brief
high-speed contacts, immediate fall/dismount and chassis corners require native
acceptance. CLI doubles do not establish native query behavior, appearance,
braking comfort, replication or maximum-player performance. The longer police
sensing horizon is bounded by the existing fleet and sensing schedule but still
needs native performance checks. No client impact/arrest authority was added.
