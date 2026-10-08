# NPC police validation — 2026-10-08–09

Implementation branch: `feature/npc-police-system`, based on `main` at `8bd9697`.
All commits are local; no push, merge or production publication was performed.
Architecture, configuration and known constraints are in [POLICE_SYSTEM.md](POLICE_SYSTEM.md).

## Executed checks

| Check | Result | Scope |
| --- | --- | --- |
| Police CLI | 809 assertions passed | Actual directed route search, legal/illegal transitions, exclusive claims/caps, last-seen memory, search/timeouts, sustained speed/wheelie and occlusion rules |
| Traffic CLI | 2,655 assertions passed | Existing road graph, curve geometry, routes, city data, reservations, spawn/recovery contracts |
| Scooter CLI | 841 assertions passed | Existing scooter suites plus precise server riding state, lock ownership and owned-seat dismount |
| Gang/combat/phone CLI | 138 assertions passed | Existing regression suite after exposing the existing safe-zone query |
| UI CLI | 133 assertions passed | Existing UI regression suite |
| Native police, Studio Edit | 305 assertions passed | Actual sanitized Kia/Ducato Instances, chassis envelopes, preserved sources, R15 standing height/exit, real raycast FOV/LOS, controller overrides, arrest validation/restoration and fair global scan budgets with 20 units |
| Native traffic, Studio Edit | 72 assertions passed | Existing native controller/sensor/reservation regression suite |
| Live speeding, Studio Play | Passed | Real owned scooter, client W/S controls, private physical speed, natural offence confirmation, road pursuit, officer approach, dismount, detention and release |
| Live wheelie/escape, Studio Play | Passed | Real C wheelie input/contact state, Wheelie claim, officer exit, fleeing cancellation and resumed pursuit with controls available |
| Live lifecycle, Studio Play | 52 checks passed | Authorized fixture interventions, officer/car deletion, real character respawn, mount unlock, repeated/fresh-context fleet start, preserved map/authoring content |
| Roblox-aware strict analysis | No diagnostics in changed production Luau | Luau Language Server with Roblox definitions and current Rojo sourcemap |
| Rojo build/sourcemap and diff checks | Passed | Native asset mapping, declared instance hierarchy, buildable project, whitespace review |

CLI service doubles do not simulate Roblox physics or multi-client replication.
Native arrest fixtures use real Instances and a controlled player double; live
Play tests use an actual connected player and the running server modules.
Lifecycle tests inject authorized intervention states to isolate cleanup; they
do not claim to detect a natural offence in those cases.

## Real Play evidence

Connected Studio: **gra roblox**, place **127535941224851**. Tests used its actual
authored city, approved directed road graph and installed scooter. The controlled
ride fixture used the 1,173-stud north/south route starting at
`R_43.4_0.2_-1918.4>R_43.4_0.2_-1982.4`. It paused civilian spawning and retired
existing civilian runtime cars for this isolated scenario, restored the spawn
function afterwards, and did not change Workspace.Map or saved source vehicles.

The final successful speeding run reached **55.02 km/h**, using the game's existing
1.6 stud/s per catalog km/h conversion. State times from fixture readiness:

| State | Approximate elapsed seconds | Reason |
| --- | --- | --- |
| OBSERVING | 6.29 | Visible candidate |
| PURSUIT | 7.14 | Sustained Speeding |
| APPROACHING | 15.46 | Stopped target |
| STOPPING | 16.56 | Confirmed stop |
| OFFICER_EXITING | 17.02 | Supported exit |
| ARRESTING | 18.12 | Officer navigation/intervention |
| RETURNING | 24.04 | Arrested |
| PATROL | 26.24 | Officer returned |
| Player released | 34.09 | Ten-second detention expired |

The server fixture confirmed no riding state during detention, an anchored
detained character, restored movement/anchoring afterwards, a released mount
lock and a released exclusive pursuit claim. Two earlier full speeding
runs also completed successfully. An initial longer drive escaped the observation
range and exercised bounded last-seen search/return instead of arrest; it is not
counted as a successful detention test.

A final input attempt with the Studio window unfocused recorded near-zero speed
and no claim. Focusing the game viewport restored actual W input; the attempt
was treated as a test-input failure and repeated, rather than counted as coverage.

The wheelie run confirmed server wheelie for approximately **2.45 seconds** and
claimed **Wheelie**, with speed below 50 km/h at confirmation. It entered PURSUIT
at 4.60 seconds and ARRESTING at 14.20. Driving away triggered RETURNING with
`TargetFleeing` at 19.55, then resumed PURSUIT at 21.71. No detention occurred;
the player retained scooter controls.

The final lifecycle report was:

```json
{"ok":true,"checks":52,"officerRemoval":true,"vehicleRemoval":true,"respawn":true,"restart":true,"freshContextRestart":true,"activeUnits":1,"activeVehicles":2}
```

The small final fleet count reflects safe spawn timing, not a requirement to
manufacture two police vehicles immediately. The test checks the configured
upper budgets, preserves unknown ActiveVehicles authoring children and compares
the authored map identity/descendant count across restarts.

## Reproduce

With Python 3 and the official Luau CLI:

```sh
python3 tests/run_police_tests.py --luau /path/to/luau
python3 tests/run_traffic_tests.py --luau /path/to/luau
python3 tests/run_scooter_tests.py --luau /path/to/luau
python3 tests/run_gang_tests.py --luau /path/to/luau
python3 tests/run_ui_tests.py --luau /path/to/luau
rojo build default.project.json -o /tmp/police-validation.rbxlx
rojo sourcemap default.project.json -o /tmp/police-sourcemap.json
git diff --check
```

Use Roblox-aware Luau analysis as described in [tests/README.md](../tests/README.md).
Analyze the changed Police, Traffic, ScooterServer, CombatService and PoliceClient
files against that sourcemap. The validation used official Luau 0.741 and the
existing local Luau Language Server/Roblox definitions.

For native verification, sync scripts and `ServerStorage.PoliceVehicleModels`,
then paste `tests/police.studio.luau` and `tests/traffic.studio.luau` into the Edit
Command Bar. Their temporary fixtures are disposed; neither starts the game or
rebuilds the city. Native police verification requires Roblox R15 generation.

For live verification, start a one-player **Play** session, wait for traffic and
a police unit, then run the chosen test source as a temporary normal server
Script under ServerScriptService. Set its Source before parenting/enabling it.
Keep Studio active and click the game viewport before sending driving inputs;
ScooterClient intentionally clears controls when the application loses focus.
Studio MCP execution has a separate require context; directly requiring the
manager there does not inspect the active server service. A normal server Script
shares the live module cache, as these tests require.

- **Speeding:** Use `tests/police.play.studio.luau`, default Scenario. Once
  `Workspace.TrafficSystem.PolicePlayStage` is `Ready`, focus the game, hold W for
  5.5 seconds, release W, hold S for 1.5 seconds and release. Wait for
  `PolicePlayReport`. A successful JSON report has `ok`, `claimed`, `officerExited`,
  `arrested`, `released`, `detentionStopsRide`, `mountLockReleased` and
  `pursuitReleased` true.
- **Wheelie/escape:** Set the Script's `Scenario` attribute to `WheelieEscape`
  before it starts. From Ready, hold W for 2.2 seconds, press C to engage the
  existing wheelie, continue W for 1.4 seconds, then release W and brake with S
  for 1.5 seconds. When PolicePlayStage reaches ARRESTING, accelerate with W for
  about four seconds. A successful report has `observedWheelie`,
  `escapedIntervention`, `controlsAvailable` and `resumed` true and `arrested` false.
- **Lifecycle:** Run `tests/police.edge.play.studio.luau` after the player and
  police service initialize. No driving inputs are needed. It repositions test
  actors, respawns the player and restarts the fleet. Read `PoliceEdgeReport`;
  safe respawn sampling may require up to 30 seconds per unit replacement.

Stop Play between scenarios and afterwards to discard temporary runtime actors,
scripts and attributes. Input timings depend on the selected scooter and server
load; inspect the reported states rather than assuming exact timestamps.

## Acceptance coverage and remaining checks

| Requested scenario | Executed evidence | Still manual |
| --- | --- | --- |
| A: ordinary traffic/patrol | Traffic CLI/native regression; shared fleet patrol and restart in Play | Extended ordinary civilian driving mixed with police through all covered city turns |
| B: no offence | Rule tests for below-limit/non-wheelie states and cancelled evidence | Long normal rides in varied traffic and latency |
| C: speeding | Real client ride at 54.99 km/h, one claim, complete arrest/release | Other scooter tiers and routes |
| D: wheelie | Real C-input wheelie confirmation; rule eligibility/grounding tests | Representative natural jumps, collisions and rough surfaces in Play |
| E: visibility | Real raycasts against obstruction, FOV/range checks; occlusion evidence tests | Full authored-building layouts and rapidly changing occluders |
| F: pursuit/escape | Directed route tests, live road pursuit, last-seen return and fleeing resume | Turning through every connected street, dead-end/off-road pursuits under mixed traffic |
| G/H: officer/arrest/release | Natural real speeding intervention plus native validation cases | Mobile/gamepad UX and visual review of all doorway placements |
| I: flee during intervention | Real W-input escape; officer returns and resumes without locking controls | Escape during each individual transition and with simultaneous blockers |
| J: lifecycle/multiple players | Real officer/car removal and respawn; 52 lifecycle checks; native missing-root/actor guards; simulated multi-target/cap rules | Actual disconnect/death during detention, two or more real clients, simultaneous offences and sustained maximum-player profiling |

No true multi-client session, disconnect experiment or mobile/gamepad session
was executed. Simulated ownership/cap tests do not establish multiplayer latency
or performance. Existing source A-Chassis cars produce unrelated startup warnings
and may obstruct roads near spawn. Existing siren SoundIds lack experience
permissions; visible signals/notices work, audio needs authorized assets. These
source cars were preserved. R15 locomotion/intervention uses a procedural fallback,
without unavailable animation IDs or physical hinged-door animation.

The city graph contains 19 weak components and six disabled curves; pursuit cannot
invent missing connections. Review/approve additional roads with TrafficWorkflow
before expanding coverage. Tune PoliceConfig detection/FOV, evidence times,
acceleration, patrol/pursuit speed, stop distances, spawn spacing, fleet budgets
and recovery/search timeouts against that coverage and real server profiling.

## Changed file manifest

New production modules:

- `src/ServerScriptService/Police/PoliceConfig.luau`
- `src/ServerScriptService/Police/PoliceVehicleAdapter.luau`
- `src/ServerScriptService/Police/PoliceSpawner.luau`
- `src/ServerScriptService/Police/TrafficViolationDetector.luau`
- `src/ServerScriptService/Police/PoliceStateMachine.luau`
- `src/ServerScriptService/Police/PolicePursuitController.luau`
- `src/ServerScriptService/Police/PoliceOfficerController.luau`
- `src/ServerScriptService/Police/ArrestService.luau`
- `src/ServerScriptService/Police/PoliceService.luau`
- `src/ServerScriptService/Police/PoliceDebugService.luau`
- `src/StarterPlayer/StarterPlayerScripts/PoliceClient.client.luau`

Modified production/configuration files:

- `src/ServerScriptService/Traffic/RoadNetwork.luau`
- `src/ServerScriptService/Traffic/VehicleController.luau`
- `src/ServerScriptService/Traffic/TrafficManager.luau`
- `src/ServerScriptService/Traffic/TrafficSpawner.luau`
- `src/ServerScriptService/Scooter/ScooterServer.luau`
- `src/ServerScriptService/Combat/CombatService.luau`
- `default.project.json`

New native assets and tests:

- `assets/police/Kia.rbxm`
- `assets/police/FiatDucatoPolicja.rbxm`
- `tests/run_police_tests.py`
- `tests/police.spec.luau`
- `tests/police.studio.luau`
- `tests/police.play.studio.luau`
- `tests/police.edge.play.studio.luau`

Updated regression test: `tests/scooter_stability.spec.luau`.

Documentation: new `docs/POLICE_SYSTEM.md` and `docs/POLICE_VALIDATION.md`; updated
`docs/ARCHITECTURE.md`, `docs/TRAFFIC_SYSTEM.md`, `docs/GDD.md` and `tests/README.md`.
No map snapshot, existing native source model or unrelated system was replaced.

## Local commits

| Commit | Subject |
| --- | --- |
| c5e9e7c | docs: document existing traffic and police integration architecture |
| 606aeef | feat: extend shared traffic controller with directed destinations and vehicle tuning |
| b83cc08 | feat: adapt authored Kia and Ducato assets for shared NPC traffic |
| 905817a | feat: add server violation evidence, pursuit ownership and reversible scooter detention |
| a265c55 | feat: integrate police patrols, officer navigation and arrest flow into traffic fleet |
| 5020dc0 | fix: harden police actor validation, lifecycle cleanup and real-map pursuit tuning |
| e74bcf2 | test: validate police rules, native models and live pursuit detention lifecycle |
| 84fa6e7 | fix: stop previous traffic runtime during fresh module reloads |
| dd5e80a | fix: enforce fair police scan budgets and refresh pursuit diagnostics |

The final documentation commit records this report and the updated architecture,
GDD scope, configuration guide and test instructions.

## Studio synchronization

Git script contents and sanitized native model snapshots were transferred into
the actual connected Edit datamodel via Studio MCP and a temporary localhost HTTP
bridge. Script Sources were read back and compared exactly; template names,
geometry counts and executable-content removal were checked. HttpEnabled was
restored to false. Play was stopped after validation. Workspace.Map and the
original Workspace.Kia / Workspace["Fiat Ducato Policja"] were preserved.

This is verified Studio synchronization, not a claim of a live Rojo plugin
connection or cloud save/publication. The declared Rojo hierarchy builds correctly;
use `rojo serve default.project.json` with the Studio plugin for ongoing sync and
save the authored Studio place normally.
