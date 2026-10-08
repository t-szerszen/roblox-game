# NPC road traffic

Implemented on `feat/npc-road-traffic`. Rojo automatically maps the new server
`Traffic` directory through the existing project paths. Production map authoring,
map rebuilding, scooter physics, ownership, economy, networking and input remain
unchanged. No traffic remotes or client authority were added.

## Movement and responsibilities

Cars use a server-authoritative **kinematic trajectory controller**. Speed is
integrated with acceleration/braking, then converted to distance along sampled
cubic Bezier lanes. Position and heading come from the continuous curve and its
derivative, rather than pointing at or jumping between nodes. Curvature limits
lateral acceleration and yaw rate; upcoming speed restrictions are approached
with a braking envelope. Ground probes align the chassis to road elevation and
reject unsupported footprints. Minor external displacement is corrected gradually
with swept clearance checks; a displacement beyond four studs is removed.

This avoids adding another suspension/constraint solver alongside the articulated
scooters. All car parts remain anchored and move together through `Model:PivotTo`.
There is no client network owner to assign. The invisible collidable chassis
provides physical contact, while explicit overlap, predicted vehicle footprints
and inflated swept blockcasts veto unsafe steps. Emergency contact stops can be
immediate; ordinary acceleration/braking remains gradual. Car impacts do not add
new damage or rewards.

A blockcast does not detect initial overlap or sweep a changing orientation, so
it is paired with destination overlap checks, rotation padding and explicit body
checks. Queries use the existing Default collision group; no scooter collision
settings are changed. See the [Roblox WorldRoot query reference](https://create.roblox.com/docs/reference/engine/classes/WorldRoot).

`TrafficManager` owns one Heartbeat connection, the shared fleet, sensing and
spawning schedules, player relevance, cleanup and debugging. Movement runs at
30 Hz, sensing at 10 Hz, and diagnostics at 2 Hz. Server stalls are limited to a
small movement step instead of advancing a car across a large unchecked distance.
Road curves are cached. Look-ahead obstacle queries use the validated trajectory;
full ground probes run at movement and spawn time. Workspace is scanned at startup
or explicit authoring, never once per car per frame. With ten cars, a linear cached
body list is simpler than maintaining a spatial hash; an area/segment budget limits
local density. Profile the actual game before raising the fleet size.

## What was inspected in this city

The connected Studio session was `gra roblox`, place ID `127535941224851`, in Edit
mode. Its `Workspace.Map` contains the manually authored city and a `Drogi` folder.
The checked-in map-placement module contains an older mock layout and was not used
to invent production roads. `Workspace["Road Pack +"]` contained folders, not road
geometry. Road surfaces inspected in the city are predominantly named `Road`,
64 x 0.2 x 64 stud block parts, with sibling raised `RoadMarking` parts. Some tiles
overlap, some have been shortened, and some streets have gaps.

The committed `RoadNetworkData` is generated from those real surfaces: **216 nodes,
204 directed curves, 198 enabled curves, 188 candidate spawn nodes**, including
10 intersection movements across three reservation zones. Six unsupported or
blocked curves are disabled. There are 19 weak components (opposing lane streams
can also be separate components), two isolated tiles and two shortened/non-tile
pieces requiring road-region overlays. Nineteen candidate spawn nodes have only
one reachable edge and are rejected by the spawner's minimum two-edge route check.
The full review list is retained in the snapshot. Gaps and disconnected roads were
not bridged automatically. This is partial, conservatively verified road coverage,
not a claim that every unnamed surface in the city has been classified.

The city inspection and export used unparented fresh ModuleScripts. They did not
write to the original map, install a live network, change the active scooter or
start Play. The snapshot is enabled for its validated movements; runtime ground
and clearance checks still apply. After map edits or vehicle size changes,
regenerate/review the network. Runtime authoring data takes precedence only when
`Workspace.TrafficSystem.Network.Approved` is true; otherwise the Git snapshot is
used. An absent/unapproved/invalid network stops startup safely, with a warning.

## Data and generation

Nodes contain an ID, road/lane, position, direction, speed, optional intersection
and stop/yield behavior, and declared outgoing edge IDs. Edges contain directed
endpoint IDs, two Bezier control points, lane, road, speed, optional reservation
zone and availability. Disabled edges retain their references for review but are
excluded from routing. IDs use road coordinates, so moving a source road changes
its generated IDs. Schema version is 1.

Generation combines names or explicit tags/attributes with dimensions, shape,
orientation, elevation, reciprocal nearest-neighbor joins, sampled road support
and obstacle clearance. Color/material alone never selects a road. Close duplicate
tiles are merged for routing while their original surfaces remain usable for
support probes. Meshes/unions require an explicit road-region decision. Neighbor
ports produce right-hand lanes with a ten-stud center offset and smooth turn
handles. U-turns at unknown dead ends are not inferred. Intersections and corners
reserve the complete tile, including straight movements through that intersection.

Generation builds a separate `CandidateNetwork`, containing `RoadNodes` Parts and
`Connections` folders. Original map parts are never moved, replaced or destroyed.
Regeneration refuses to replace an existing draft unless `Generate(true)` is
explicitly used. Manual edits persist until that explicit replacement. Publishing
replaces only folders marked `TrafficGenerated`; unrelated folders are protected.

## Studio authoring commands

Connect Rojo with `rojo serve default.project.json`. In Studio **Edit mode**, use:

```lua
local traffic = require(game.ServerScriptService.Traffic.TrafficWorkflow)
local regions, review = traffic.Inspect()
print(#regions, table.concat(review, "\n"))
local draft = traffic.Generate()
print(#draft.nodes, #draft.edges, #draft.spawns)
print(table.concat(draft.review, "\n"))
```

Inspect `Workspace.TrafficSystem.CandidateNetwork`. Move/rotate node Parts to
correct lane positions and directions. Use their `Speed`, `Behavior` (`stop` or
`yield`), `Intersection`, `Road`, `Lane`, and `Spawn` attributes. Connection folders
have `From`, `To`, `Control1`, `Control2`, `Speed`, `Lane`, `Road`, `Intersection`,
and `Enabled`. After moving a node, adjust its curve controls to retain entry/exit
tangents. Disable an unsafe connection rather than deleting map geometry.

To add a movement between existing nodes without regenerating:

```lua
traffic.Connect("exact entry node ID", "exact exit node ID", "shared junction ID", 20)
traffic.Validate()
```

Every conflicting movement in an intersection must share its reservation-zone ID.
The generator does this automatically within each tile; manually joining different
junction regions requires checking the shared zone yourself. `Connect` validates
the schema; `Approve` additionally checks enabled curves against actual geometry.

For ambiguous meshes, gaps whose underlying pavement is real, or shortened pieces,
create **anchored, transparent, noncolliding, nonqueryable block Parts** in
`Workspace.TrafficSystem.RoadRegions`. Set `TrafficRoad = true` (or tag them
`TrafficRoad`). Size each region to the actual usable pavement, normally 40–100
studs in both horizontal directions. Use multiple contiguous regions for long
streets. Position their top surface at the pavement elevation. They are markers,
not collision replacement parts. Ground checks use the underlying map/terrain for
this workflow, and obstacle checks still reject buildings and sidewalks above the
pavement. `TrafficIgnore = true` excludes a wrongly detected source. Never mark
space merely to make the graph connect when there is no traversable pavement.
Then regenerate explicitly, accepting that this replaces draft edits:

```lua
traffic.Generate(true)
```

After correcting/reviewing the draft:

```lua
traffic.Validate()
traffic.Approve()
local source = traffic.Serialize()
```

For a large export, keep it in a temporary ModuleScript rather than copying a
possibly truncated Output entry. Run this directly in the Command Bar:

```lua
local source = require(game.ServerScriptService.Traffic.TrafficWorkflow).Serialize()
local export = Instance.new("ModuleScript")
export.Name = "RoadNetworkExport"
export.Source = source
export.Parent = game.ServerStorage
```

Open that export and copy the Luau into
`src/ServerScriptService/Traffic/RoadNetworkData.luau`, run validation and commit
that snapshot on a feature branch. Remove the temporary export after copying.
Save the Studio place to retain its explicit
`Network`. The wrapper reloads fresh dependencies each call; if the wrapper itself
changes, require a fresh wrapper copy or restart Studio.

For network drawing in Edit mode, after generation:

```lua
local modules = game.ServerScriptService.Traffic
local data = require(modules.DevTrafficTool).Read(workspace.TrafficSystem.CandidateNetwork)
local network = require(modules.RoadNetwork).Load(data)
local drawing = require(modules.TrafficDebug).new(workspace.TrafficSystem)
drawing:Network(network)
-- Remove this preview before Play or generation clearance checks:
drawing:Destroy()
```

Runtime debug can be enabled on the **server** without changing gameplay:

```lua
workspace.TrafficSystem:SetAttribute("Debug", true)
```

Green lines are enabled lanes, orange lines are intersection movements, red lines
are rejected movements and purple markers are spawn locations. Vehicle overlays
show target points, heading/trajectory, speed/state, following boundaries, obstacles
and held zones. Inspect `TrafficState`, `TrafficSpeed`, `TrafficRoute`,
`TrafficObstacle`, `TrafficReservations` and `TrafficRecoveryAttempts` on a car to
understand a stop. These compact attributes also exist when drawing is disabled.
Set `Debug` false to clear the drawing. Authoring nodes are hidden during Play.

## Fleet defaults and recovery

Defaults are target **6**, hard maximum **10**, one spawn attempt every **3 seconds**,
up to **3 vehicles within 100 studs**, and up to **3 on a road tile**. Spawns must
be 120–650 studs from the nearest player, at least 32 studs from another car,
have a clear expanded footprint and a usable route of at least two edges and
384 studs. Route planning samples up to 32 connected edges at a time and renews
the route while driving; this is a planning horizon, not a vehicle lifetime.
A 240-stud forward
cone based on character heading rejects nearby visible arrivals. This is a server
approximation of visibility, not access to the player's actual camera. The same
fleet serves all players. Cars beyond 850 studs of every player expire after
120 seconds; cars inside that boundary reset the timer. These conservative settings
match the large inspected city and cap the initial query/replication cost; they
have not yet been tuned with live performance measurements.

Vehicles brake behind cars, scooters, characters and static obstacles. Scooter
models are read from the existing configured `Workspace.Scooters` folder, with
current oriented bounds and assembly velocity. This explicitly handles scooter
meshes/proxies with `CanQuery = false` without changing their mechanics. Predicted
bounds account conservatively for a crossing scooter. Traffic stays in its lane;
there is no random obstacle steering or inferred overtaking lane.

Intersection reservations are exclusive per zone with FIFO requests. Entry
requires a clear exit and a completed stop dwell when requested. Reservations last
until the car's rear clears the movement. The movement step independently refuses
unreserved entry between sensing ticks. A holder making no progress for 120 seconds is removed
before its reservation is released; no timeout grants passage through a live car.
Actual movement renews the reservation timeout, so a long crossing does not expire
just because it was reserved earlier. This conservative policy can later be replaced with movement conflict tables or
signal scheduling behind the same manager interface.

Invalid references, unsupported ground, blocked/occupied spawns, malformed models,
removed vehicles, dead ends, displacement and below-map positions fail safely.
A blocked vehicle retries after 60 seconds, at most twice. Replanning happens only
at a valid route entry with a connected alternative and no held zone. Otherwise it
waits and is removed after the bounded attempts; a separate 300-second recovery
lifetime prevents indefinite retention. Cars never jump across obstacles during
recovery. A valid route ending within look-ahead does not delete a car at rest:
it brakes before the actual network boundary and retires 0.5 seconds after stopping.
Route-end waiting uses its own timer and is not shortened by stuck recovery. If a
valid continuation is restored during that grace period, the same car resumes.
Cars on connected loops continue renewing routes without an age-based lifetime
limit. Short terminal trips are rejected at spawn; missing road connections still
need review rather than unsafe invented movement.

Replacement uses normal validated spawns. This can visibly remove a
persistent blocker; tune recovery thresholds after gameplay acceptance.

Removal disposes the model, route, reservation queue entries and debug objects.
Manager stop disconnects its single Heartbeat connection and disposes every owned
car. Shutdown and script destruction both stop the manager. Failures log once per
removed car or spawn attempt, rather than every frame.

## Replacing the car

The procedural placeholder is created as
`ReplicatedStorage.TrafficAssets.TemporaryCar` when first needed. `TrafficAssets`
is a Rojo folder that preserves authored unknown children during sync. It contains
a body, cabin, four wheels, headlights/brake-light parts and a stable chassis.
Its lamps are decorative; wheel spinning and animated brake-light intensity are
not part of this first implementation.

Replace the template before Play, preserving this interface:

- A `Model` whose `PrimaryPart` is the configured `Chassis` BasePart.
- Root `PivotOffset = CFrame.identity`; root local **-Z is forward**, +X right, +Y up.
- `FrontAxle` and `RearAxle` Attachments under the chassis, positioned at the axles;
  front local Z is negative. An optional `DriverPosition` attachment is provided.
- Model attribute `TrafficBounds: Vector3`, centered on the chassis and containing
  **all part geometry**. The default is 6 x 4 x 12 studs. The adapter rejects a
  too-small envelope, nonfinite dimensions, missing roots and executable content.
- No scripts, suspension constraints or physics actuators. Decorative parts may
  be nested; the adapter anchors them and disables their collision/touch/query.
  Only the chassis envelope collides and participates in spatial queries.

Keep dimensions, wheelbase and clearance in `TrafficConfiguration.Vehicle` aligned
with the template and regenerate the network after changing its footprint. Export
the replacement to `assets/traffic/*.rbxmx` and add an explicit Rojo path to version
it in Git. Do not depend on a manually stored replacement being a Git artifact.

## Validation actually performed

On 2026-10-08:

- Rojo build and sourcemap generation passed using the unchanged project paths.
- Official `luau-compile --null` passed for every traffic module and native test.
- Roblox-aware `luau-lsp` analysis passed with no code diagnostics.
- **2,655 CLI assertions passed** against actual graph/configuration/trajectory/
  reservation modules and the city snapshot. The CLI uses vector/service doubles.
- **72 native Studio assertions passed** using real CFrames, Models, ModuleScripts
  and unparented fixtures: requireability, invalid data/models, bounded routes,
  tangent continuity, acceleration, obstacle stop/resume, curved movement, reserved
  entry, cleanup, query-disabled/predicted scooters, following, safe spawns, occupied
  spawns and shared caps. Retention regressions also verify 0.5 seconds of
  route-end waiting, resumption after a restored connection, rejection of short
  trips, moving intersection owners, and four simulated minutes of continuous
  driving on a connected loop with bounded route memory. Motion tests use
  controlled sensing doubles, not an
  integrated physics/replication simulation.
- The real city generator ran in Edit mode with Roblox road raycasts and footprint
  overlap checks. The saved geometry analysis excludes six failed movements.
- Existing scooter CLI regression suite passed **828 assertions**. Its files were
  unchanged.

Run the CLI checks with:

```sh
python3 tests/run_traffic_tests.py --luau /path/to/luau
python3 tests/run_scooter_tests.py --luau /path/to/luau
rojo build default.project.json --output /tmp/traffic-check.rbxlx
rojo sourcemap default.project.json --output /tmp/traffic-sourcemap.json
luau-compile --null src/ServerScriptService/Traffic/*.luau tests/traffic.studio.luau
luau-lsp analyze --platform=roblox --sourcemap=/tmp/traffic-sourcemap.json \
  --definitions=@roblox=/path/to/globalTypes.d.luau src/ServerScriptService/Traffic
```

Paste `tests/traffic.studio.luau` into the Studio Command Bar after Rojo sync to
repeat the native fixtures. They destroy their unparented test objects on success
or failure and preserve the city and scooter templates.

**Play-mode acceptance, real replication, scooter/car contact and two-client
performance have not been tested.** The connector requires confirmation of the
Studio target before edits or starting Play; that confirmation was requested and
not supplied during the initial implementation. The retention follow-up inspected
the already-running server read-only and observed `RouteEnd` on active vehicles,
then verified the changed behavior with fresh unparented fixtures. No game edits,
fleet restart or Play transition were performed through that connector.
After Rojo sync, stop and restart Play to reload cached modules with the new tuning.

## Manual Play acceptance checklist

1. Sync and save a test copy of the current city. Start Play near a covered street.
   On the server, inspect `TrafficSystem.ActiveVehicleCount` over 30 seconds: target
   six where safe spawning permits, never above ten. Verify distributed orientation
   and no close forward-cone materialization. Move away and check the extended despawn
   grace (now 120 seconds); return across the boundary and check that the fleet does not reset.
2. Enable server debug. Follow straight lanes and the three generated junction
   zones. Check smooth left/right turns, lane containment, grade contact, speed
   reduction and rear clearance before another car receives the zone. Manually
   assign a stop behavior in the draft and verify the one-second stop after review.
3. Ride the existing scooter into a lane, stop, cross it and leave. Cars must brake,
   hold position and resume without deliberate lane changes. Repeat with a second
   player and a stationary unoccupied scooter.
4. Add a collidable obstacle in Play on a covered lane. Observe smooth braking,
   bounded stopped recovery and resumption after removal. Hold a junction exit
   blocked with no progress for more than 120 seconds and verify owner removal precedes release.
5. Destroy one runtime car. Verify model/debug/queue cleanup and budget replacement.
   In Play only, move a car five studs sideways or below Y=-100: it must be removed,
   never teleported back through obstacles. Test a malformed template in a test
   copy: startup must warn and leave no half-prepared car.
6. Test dead ends and each reported component. Traffic must brake, wait for the 0.5-second route-end grace, and then retire
   without inventing cross-building connections. Correct missing regions in Edit mode,
   approve/export, and repeat; do not regenerate the production map.
7. Start a server with two clients, then configure a ten-car target and restart.
   Use 150–250 ms network emulation, inspect anchored ownership/contact, replication
   smoothness, MicroProfiler/query cost and memory after several spawn/removal
   cycles. No client can control traffic; no new remotes exist. Repeat normal
   scooter handling to catch physical contact regressions.

## File manifest

All server modules are in `src/ServerScriptService/Traffic/`:

| File | Purpose |
| --- | --- |
| `TrafficInit.server.luau` | Server lifecycle entry point |
| `TrafficManager.luau` | Fleet, schedules, relevance and cleanup |
| `TrafficConfiguration.luau` | Central tuning |
| `TrafficTypes.luau` | Typed graph/path schema |
| `RoadNetworkData.luau` | Actual city snapshot and review exclusions |
| `RoadNetwork.luau` | Validation, connectivity, bounded routing |
| `Trajectory.luau` | Cubic sampling, interpolation, braking math |
| `DevTrafficTool.luau` | Inspection, generation, correction and export |
| `TrafficWorkflow.luau` | Fresh Edit-mode developer entry points |
| `VehicleAdapter.luau` | Placeholder and replacement-model validation |
| `VehicleController.luau` | Continuous movement, sensing and recovery |
| `TrafficSensors.luau` | Road support, overlap, sweeps and scooter bodies |
| `TrafficSpawner.luau` | Shared density and safe spawning |
| `IntersectionManager.luau` | Exclusive FIFO zones and timeouts |
| `TrafficDebug.luau` | Network/vehicle drawing and diagnostics |

Also added `src/ReplicatedStorage/TrafficAssets/init.meta.json`,
`tests/run_traffic_tests.py`, `tests/traffic.spec.luau`,
`tests/traffic.studio.luau`, and this document. Updated `docs/ARCHITECTURE.md` and
`tests/README.md`. No existing gameplay source or map snapshot was changed.
