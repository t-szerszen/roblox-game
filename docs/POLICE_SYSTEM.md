# NPC police

## Inspected architecture (2026-10-08)

The repository was clean on `main` at `8bd9697`; implementation uses
`feature/npc-police-system`. The connected Studio is `gra roblox`, place
`127535941224851`, inspected directly in Edit mode. `Workspace.Map.Drogi`
contains the authored road surfaces. No map is rebuilt or serialized by police.
The existing approved Git road snapshot contains 216 nodes and 204 directed
Bezier curves (198 enabled). Its disconnected streets remain disconnected.

`TrafficManager` owns the shared fleet, Heartbeat, cached sensors and intersection
reservations. `VehicleController` is kinematic: acceleration and braking advance
distance on sampled road curves; anchored models move with `PivotTo`, with road
support, footprint overlap, predicted bodies and swept collision checks. Cars do
not use VehicleSeat throttle, constraints or Humanoid movement. Police must reuse
this controller and the same reservations and sensor bodies.

`ScooterServer` retains network ownership of articulated scooters and validates
all rider input. Its private records own seating, controls, contacts and wheelie.
`SpeedKmh` is a rounded presentation of physical motion using the established
arcade conversion `ScooterConfig.StudsPerKmH = 1.6`; police must use that conversion,
not introduce a different real-world scaling. Wheelie is server accepted and
requires rear contact; jumping and arbitrary pitch are not violations. Existing
dismount resets controls and removes only the owned seat's `SeatWeld`.

Both source cars are direct children of Workspace, anchored, without PrimaryPart,
constraints or an officer. Kia has 65 physical parts, A-Chassis/ELS scripts and
four wheel roots `Wheels.FL/FR/RL/RR`; its front points toward world +Z, opposite
its saved pivot. Fiat Ducato Policja has 99 physical parts, five passenger seats,
A-Chassis/ELS scripts and the same four wheel names; its front points toward -X.
Both contain blue/red PointLights and existing Wail/HiLow/Yelp sounds. Their
unscaled envelopes are approximately 14.3 x 11.7 x 31.2 and 14.8 x 14.0 x 28.0
studs. They cannot be passed directly to the existing strict traffic adapter.

## Scope decisions

The current request replaces the older GDD police triggers with a configurable
50 km/h limit and sustained wheelie, and authorizes temporary detention without
economy penalties. PvP, jumps, toll gates, fines, rewards and playable police
factions are outside this implementation. The documented spawn safe zone and
night reduction remain applicable. No gang membership changes police authority.

Integration uses per-car tuning and directed destination routing, preserving
civilian defaults. Police units participate in the same fleet and collision list.
An adapter sanitizes clones of the two actual cars, derives orientation from
axles, adds the traffic chassis contract, and leaves source models untouched.
Server-only scooter state/dismount APIs and a reversible mount lock support
detention. Officer navigation uses a standard R15 rig and bounded asynchronous
PathfindingService tasks. Violation rules, pursuit ownership, AI transitions and
detention validation are separate responsibilities.


## Runtime and authority

`TrafficInit` starts `TrafficManager`, which constructs one `PoliceService` for
that fleet. Police have no independent movement Heartbeat or competing road
network. The shared movement/sensing schedules remain 30/10 Hz. Police AI runs
at 5 Hz, with a hard budget of 16 candidate checks shared fairly among units;
the first scanning unit rotates when the fleet exceeds that budget. Visibility casts use
two target points after range/FOV filtering. Directed destination routing runs
at most once per second per pursuing unit. Civilians retain their original
speed, braking, routing, intersection priority and removal defaults. Their target
count remains six; police have a separate target of two and participate in the
same density checks, intersection reservations and obstacle body list.

An owned server-only `TrafficSystem.RuntimeStop` BindableEvent stops the previous
manager before a fresh require context publishes a replacement fleet. Its event
connection is cleaned up with the other infrastructure connections. Repeated
Start calls and development module reloads do not leave a second live Heartbeat.

Responsibilities:

| Module | Owns |
| --- | --- |
| PoliceConfig | Fleet, detection, driving, intervention and timeout values |
| PoliceVehicleAdapter | Sanitized asset adaptation, axle orientation, bounded chassis, signals |
| PoliceSpawner | Supported road footprints, clearance, distance, separation, bounded spawn attempts |
| TrafficViolationDetector | Server riding state, eligibility, FOV/LOS and sustained evidence |
| PolicePursuitController | Exclusive target claims, global pursuit cap and last seen memory |
| PoliceStateMachine | Allowed AI transitions, state timestamps and cancellation generation |
| PoliceOfficerController | Cached R15 rig, measured standing height, exit sequence, navigation, fallback poses |
| ArrestService | Actor/target validation, owned dismount, reversible detention and cleanup |
| PoliceService | Unit orchestration and integration with the shared fleet |
| PoliceDebugService / PoliceClient | Server diagnostics and replicated stop/detention notices |

`RoadNetwork.Destination` searches enabled directed reachability and projects
onto reachable curve samples. It retains the current edge and its progress,
without moving the model. It never invents U-turns or connections through buildings.
Intersection edges are excluded as stopping goals. Existing reservations are
extended conservatively if a changed route lengthens their clearance distance.
Officers exit only outside a crossing and after reservations clear.

A suspect must be alive, on their own occupied scooter, outside the existing
CombatService spawn safe zone/protection and release grace. Server records supply
precise speed from the same heading velocity used by the dashboard; no rounded
client attribute is used for enforcement. Wheelie also requires the accepted
server state, rear support, absent front support and bounded vertical speed.
Short occlusion pauses evidence; it cannot confirm an unseen violation. Longer
occlusion discards it. A registry claim makes confirmation atomic across units.

Pursuit positions update only with actual sight. Officers can also observe a
nearby target after exiting. Hidden targets are searched around the remembered
location; search and total pursuit have hard timeouts. A car stays on supported
road curves and uses all ordinary collision sweeps. Being close to a moving
player never arrests them. A visible target must remain below the configured stop
speed, with a stopped car, before the exit/intervention sequence. Driving away
cancels the sequence, brings the officer back and resumes pursuit after boarding.
Blocked return or navigation times out and disposes the unit safely.

`ArrestService` revalidates the actual officer/car pair, active ARRESTING unit,
exclusive claim, same living character, eligible state, stopped motion, distance
and clear interaction ray. The server acquires a unique mount lock and calls the
shared scooter dismount. Only its own seat weld is removed. Character anchoring
waits for seat/assembly separation; failure to separate releases the lock within
one second. Movement/jump properties and anchoring are restored after ten seconds,
including removal, death, character replacement or server shutdown. No coins,
inventory, progression or gangs are changed. No police request/success remote is
introduced. Replicated attributes are presentation only.

The arrest validator is injected and used today for NPC authority; future police
players can supply a different server authorization policy. Violation rules and
exclusive claims are independent of the driver. Playable faction decisions,
permissions and network requests remain future work.

## Assets and Studio synchronization

`assets/police/Kia.rbxm` and `FiatDucatoPolicja.rbxm` are native engine snapshots of
the two inspected source models, with their executable chassis/UI/remotes removed
on unparented clones. Geometry, native unions, meshes, decals, wheels, seats and
existing light/sound resources are retained. They are mapped explicitly by Rojo
to `ServerStorage.PoliceVehicleModels`. These are reusable templates, not new
replacement car designs. Runtime copies are uniformly scaled to 0.45 and acquire
an invisible longitudinal collision chassis; the originals in Workspace are not
moved or edited. Prepared bounds are approximately 6.49 x 5.29 x 14.08 for Kia and
6.69 x 6.31 x 12.65 for Ducato. Driver placement and exit positions derive from
each envelope, rather than the source Kia seat's invalid location.

The actual Studio session was read and updated via Studio MCP. A temporary local
HTTP bridge transferred Git script contents and native model buffers; every
script was read back and compared, and model names/counts were verified. HTTP was
restored to its previous disabled setting after each transfer. Rojo builds and
sourcemaps validate the declared hierarchy. A live Rojo plugin connection was
not claimed or required for these MCP transfers. Normal ongoing development uses
`rojo serve default.project.json` plus the Studio Rojo plugin connection. Rojo does
not import the manually authored Workspace.Map into Git automatically.

## Running and debugging

Sync `default.project.json`, retain the authored city and its approved road data,
and start Play. Police start with traffic; no separate police startup script or
manual map regeneration is required. Missing/invalid road data stops traffic;
missing police templates or a failed R15 factory disable spawning with a bounded
warning while ordinary traffic can continue. Set PoliceConfig.Enabled=false to
disable police in a new session. Restart traffic after config changes; Studio
require caches mean a fresh Play session is the most reliable configuration test.

In the Studio server Command Bar:

```lua
workspace.TrafficSystem:SetAttribute("PoliceDebug", true)
local manager = require(game.ServerScriptService.Traffic.TrafficManager)
local service = manager.GetPoliceService() -- Studio server only
-- manager.Stop(); manager.Start() performs an explicit fleet restart.
```

In Studio MCP, code executes in a separate require context. To inspect the active
service, run a temporary server Script, as the Play test fixtures do. Mandatory
PoliceState/PoliceReason attributes are always available on each `PoliceCar_*`.
Debug additionally publishes observed/target UserId, reason, measured speed,
wheelie, route, route target and recovery count. ArrestFailure explains denied
interactions. Traffic's existing attributes expose obstacle, speed and reservations.
No high-frequency Output spam is required. `PoliceStopRequested`, `PoliceState`
and `PoliceArrestUntil` on the player drive the client notice/countdown.

## Initial tuning

| Setting | Initial value |
| --- | --- |
| VehicleCount / MaxPursuits | 2 / 2 |
| SpeedLimitKmh | 50 |
| DetectionRange / FieldOfView | 220 studs / 140 degrees |
| SpeedConfirmation / WheelieConfirmation | 0.8 / 0.8 seconds |
| OcclusionTolerance / LostSightTolerance | 0.6 / 2 seconds |
| PatrolSpeed / MaxPursuitSpeed | 26 / 112 studs per second |
| Acceleration / Braking | 28 / 32 studs per second squared |
| RouteInterval / FollowDistance | 1 second / 20 studs |
| StopSpeedKmh / StopConfirmation | 2 km/h / 1 second |
| InterventionDistance / ArrestDistance | 26 / 6 studs |
| ArrestSequenceDuration / ArrestDuration | 1.5 / 10 seconds |
| SearchTimeout / PursuitTimeout | 15 / 120 seconds |
| StuckTimeout / RecoveryTimeout / MaxRecoveryAttempts | 8 / 15 seconds / 2 |
| SpawnInterval / RespawnCooldown | 5 / 20 seconds |
| SpawnMinDistance / SpawnMaxDistance | 120 / 650 studs |

Speeds retain the game's established arcade scale: 1.6 stud/s per catalog km/h.
The pursuit cap represents 70 catalog km/h; turns still obey shared curvature and
yaw limits. The 220-stud observation range and 0.8-second evidence window were
adjusted after real 55 km/h riding tests: shorter settings could lose sight before
confirmation, or during car acceleration. Tune these together with acceleration,
road coverage, traffic density and vehicle footprints. Night reduction floors
the 30% smaller integer budget: two daytime units become one at night, zero stays
zero. Fleet spawning is global, not multiplied by player count.

## Limits and remaining acceptance

The graph covers only the conservatively approved portion of this large city,
with 19 weak components and six disabled curves. Police cannot cross missing
connections or chase off-road through buildings. Dead ends retire vehicles using
the existing controller; stuck recovery keeps their physical position and is
bounded before cooldown/respawn. There is no lane-changing or magical U-turn.
Safe spawn attempts can fail when eligible roads are busy; they retry on the
configured interval rather than manufacturing a spawn.

Prepared patrols contain no A-Chassis executable code. The existing original
Workspace cars still run their old scripts in Play, generate unrelated warnings
and can block roads near spawn. They were deliberately preserved as user assets.
The experience currently lacks permission for several existing siren sounds,
including Kia's 5160858899 and Ducato's 893793527. Lights and notices work; audible
sirens require accessible experience-owned sound assets/permissions. There are no
invented animation IDs: exit/gesture/locomotion use the procedural R15 fallback.
Real door hinges and a cinematic handcuff animation are not implemented.

A single-player Studio session and native fixtures do not establish multiplayer
latency, mobile/gamepad acceptance, every street/turn, all blocking configurations,
or sustained server performance at maximum players. The CLI tests verify atomic
ownership/caps for multiple simulated targets; a true multi-client Play session
remains a separate acceptance check. See [POLICE_VALIDATION.md](POLICE_VALIDATION.md) for executed tests,
reproducible commands and the outstanding scenarios.
