# Map authoring

The production map is authored manually in Roblox Studio. Automatic runtime generation is disabled; `MapInit.server.luau` intentionally does not invoke the builder. The versioning toolchain remains available for explicit use:

```text
MapData -> AssetRegistry -> MapBuilder -> Workspace.Map
```

- `src/ServerScriptService/Map/MapData.luau` is the latest version-controlled snapshot. It contains placements with an asset ID, world position, Euler rotation in degrees, and uniform scale.
- `AssetRegistry.luau` creates anchored low-poly Roblox models for the mock asset IDs, including an explicit `Spawn` pad. This procedural registry proves the pipeline; production assets can replace its factories without changing the placement schema or builder.
- `MapBuilder.luau` validates each placement, creates and transforms its model, then publishes the completed folder as `Workspace.Map`. It stages the build so a failed generation does not replace the current map.
- `MapInit.server.luau` leaves the manually authored Studio map untouched when the server starts.
- `Environment/RoadPhysicsSanitizer.server.luau` keeps authored road visuals separate from physics. Raised lane markings are non-colliding, regular road parts use a moderate-grip material, and collidable road `MeshPart` instances are replaced at runtime by slightly overlapping invisible box proxies. This avoids precise mesh collision seams without attempting the restricted runtime write to `CollisionFidelity`.

The MVP does not include a Studio GUI map editor. For Edit Mode placement, `DevMapTool.luau` exposes `DevBuildMap()` and `DevSerializeMap()`. Use `MapWorkflow.luau` from the Command Bar to reload fresh copies of the tool and its dependencies on every invocation:

```lua
require(game.ServerScriptService.Map.MapWorkflow).Build()
require(game.ServerScriptService.Map.MapWorkflow).Serialize()
```

The serializer recursively reads `Model` instances from `Workspace.Map`; logical `Folder` levels such as `Map/Roads` and `Map/Trees` are allowed. Each encountered model is serialized as one asset, so nested models inside an asset model are not serialized separately. Keeping a dedicated map root prevents characters, scooters, cameras, and unrelated Workspace content from entering `MapData`. Move, rotate, and uniformly scale each model as a whole; serialization reads each model's pivot and `GetScale()` value. `MapWorkflow` itself is required normally, so changes to that wrapper module require a fresh wrapper require (for example, a Studio restart or the earlier clone runner); edits to `DevMapTool`, `MapData`, and `AssetRegistry` are picked up by its internal reload on every call.

`src/ServerScriptService/Environment/TowerBeacon.server.luau` controls warning lights on skyscraper roofs. For compatibility with the manually authored map, it recognizes `BasePart` instances named `czerwonabulba`; new lights should use the `TowerBeacon` CollectionService tag. Their parts and descendant `PointLight` instances blink briefly every 30 seconds. Runtime world effects live under `Environment`, separately from the map builder and serialization tools.

## Blender city mockup pipeline

Run `tools/blender/generate_warsaw_city.py` from Blender's Scripting workspace. It clears the Blender scene, generates a 3x3 layout of 500-stud districts with 22 objects in each of the eight urban districts, a Palace of Culture with four plaza tiles in the center, one continuous 1500-stud avenue, exactly two Kukirin workshops, and one railway crossing with a toll gate. It exports every unique low-poly asset individually as FBX to the repository's `assets/buildings/` directory and writes strict Luau placement data to the repository root as `MapData.luau`. Both paths are based on `PROJECT_ROOT` in the script, independent of Blender's current working directory. Generated IDs include `District_Ground`, `Road_Straight`, `Road_Intersection`, `Road_Avenue`, `Park_Trees`, `Park_Plaza`, `Shop_Small`, `Building_Residential`, `Building_Small`, `Building_Midrise`, `Building_Skyscraper`, `Palace_Of_Culture`, `Workshop_Kukirin`, `Railway_Crossing`, and `Toll_Gate`.

The generated root `MapData.luau` is kept separate from `src/ServerScriptService/Map/MapData.luau`: the current mock `AssetRegistry` does not load imported FBX assets or recognize all generated IDs. Import the FBX files into Roblox Studio, register those models in the runtime asset registry, and then move the generated placements into the runtime module as an integration step. The script header lists Roblox Studio's FBX import settings for matching scale and axes, based on the [Roblox Blender and Studio guidance](https://create.roblox.com/docs/art/blender).

# Articulated scooter

The approved nested ScooterFinal uses DevScooterBuild for an anchored preview
and ScooterWorkflow.InstallNewModel / DevScooterInstall for explicit installation
at the current test scale 0.30. Its eight hinges and two central shocks are adapted to the existing
ScooterRig contract without moving approved mounts. CentralShockRig selects
single-shock leverage calibration at each end, a real deck helper, actual grip
targets and balanced assembly masses. The existing driving controller is reused; handling tuning is centralized in ScooterConfig.
The old template is retained in ScooterTemplateBackups; source and preview live
in ScooterAuthoring outside Play. See [assembly and verification](SCOOTER_FINAL_RIG.md).

The optional handlebar dashboard is a Studio-mounted asset, versioned under
`assets/scooter` and regenerated by `scripts/generate_scooter_dashboard.py`.
`DevScooterDashboard` creates an Edit-mode preview and explicitly welds the chosen
placement to `HandleBar`. `ScooterDashboardClient` and the shared dashboard module
render server-published `SpeedKmh` and `BrakeActive` without new remotes or drive
logic of their own. The scooter controller owns ECO/SPORT, enforces the selected
motor limit and publishes `DriveMode`; a separate zero-argument `ToggleDriveMode`
request is validated by the server. The mounted client binds `P` and owns the
temporary instruction popup. ScooterSpeedometer adds a mounted third-person analog HUD
from the same server attributes, with cleanup owned by ScooterClient. The physical
screen is enlarged in DevScooterBuildConfig. The battery is a fixed 67% visual.
`ScooterDecoration = true` retains massless decorative parts during rig
preparation. Prediction presentations bind their own GUI copy to the real scooter.
See [dashboard installation and verification](SCOOTER_DASHBOARD.md).

`ScooterRig` validates the Studio-authored `scooter` assembly, preserving its physical virtual axles, suspension hinges, springs and welds. `ScooterWorkflow.Assemble()` reloads fresh assembler, rig and configuration modules for Edit-mode use; `DevScooterAssembler.AssembleFromSelection()` installs that rig as the only template in `ServerStorage.ScooterModels.scooter` and replaces the old KuKirin template. The procedural scooter fallback and five-part assembly workflow are retired. Catalog names, tuning, ownership and economy are unchanged.

`ScooterServer` validates rider intent and retains server ownership of every articulated assembly. Existing ground-aligned VectorForce propulsion and AlignOrientation stabilization remain authoritative. Collision proxies follow the physical wheels, while probes use VirtualFrontAxle.AxlePivot and VirtualBackAxle.AxlePivot. Steering writes the physical Servo target; the rear wheel motor runs during fresh W+S input at up to 5 km/h with rear contact. Its torque scales with supported mass and tire radius. Burnout starts directly from accepted DriveInput rather than depending on a second remote's arrival order. Authored springs provide suspension, and burnout smoke follows the rear axle. ScooterScrape owns replicated particles at a chassis scrape point: actual pitch of 48 degrees, sufficient speed and nearby road contact enable sparks, with a 43-degree hysteresis threshold. Reset, fall and cleanup stop emission; clients send no effect decisions.

`ScooterBrakeLight` prefers the authored StopLight and reuses its PointLight,
restoring authored properties on cleanup. The old whole-BackFender fallback stays
disabled. StopLightActive includes braking, held S and reverse travel; BrakeActive
means actual opposing-direction braking or W+S. ScooterHeadlight owns a white
SpotLight on FrontLight. Mounted L requests ToggleHeadlight with no arguments;
server ownership, seat/life/state and cooldown validation authorize the toggle.
Its beam and appearance are disposed/restored with the scooter record. Shared ScooterPhysics derives chassis yaw from measured Servo angle, forward speed and actual axle spacing, with no minimum yaw rate during normal riding. Server-accepted burnout allows A/D steering at rest and bounded sustained donut yaw from measured Servo deflection. Release or loss of eligibility immediately restores normal steering rules. A speed-dependent heading lead bounds orientation error when motion is blocked. Chassis roll follows signed speed times yaw rate divided by gravity. The previous full-axis AlignOrientation controller follows the bounded heading target. Its 165-degree/s yaw cap, 12-degree initial heading lead and high-speed input scale of 0.55 preserve predictable steering; a low-speed curvature boost of 1.2 fades out as speed rises. Heading lead scales with smoothed rider input so a sustained partial turn cannot build up full steering strength. After 0.18 seconds of supported steering, its maximum ramps from 12 to 20 degrees over 0.45 seconds for tighter sustained turns. Release, direction changes and loss of normal riding eligibility clear the bounded server timer; burnout retains its original limit. Ground propulsion corrects lateral slip with the previous 100-studs/s² limit. No suspension weld is added. See [SCOOTER_MODEL.md](SCOOTER_MODEL.md) for formulas, configuration and texture limitations.

Shift/C triggers wheelie above 10 km/h; afterward W raises the front, releasing W eases it down, and W can raise it again before landing. S lowers it faster, and low-speed loss of balance remains active. World speed conversion is 1.6 stud/s per catalog km/h, 60% above the previous 1.0 scale; catalog ratings, ownership and upgrade schedules remain unchanged.

Direction changes remain force-driven: opposing input brakes at 60 studs/s², engages the requested direction below 2 km/h and receives hill assistance during the braking stage as well as powered travel. Reverse accelerates at 25 studs/s² toward 18 km/h. This removes the near-zero-speed gate that could stall reversing on slopes without changing the W+S burnout input or assigning velocity directly. All thresholds remain in ScooterConfig.

ScooterRigGeometry checks coincident hinge endpoints, matching primary axes, coaxial pivots on welded suspension arms and incompatible cross-assembly welds before a rig can spawn. ScooterCollision supplies reusable wheel contacts plus a massless FootRest deck contact that excludes both tires through NoCollisionConstraints. Ground probes and spawn clearance use the same contact geometry. AlignOrientation initializes to the spawn orientation and scales its torque with the chassis plus articulated moving mass, avoiding the undersized Root-only limit. DevScooterRepair provides Studio diagnostics and staged geometry repair, retaining originals under ServerStorage.ScooterRepairBackups. ScooterSuspension calibrates spring stiffness/preload/damping from wheel leverage and supported reference mass, bounds passive pivots before linkage inversion and hides constraint debug visuals. DevScooterSuspension.Apply reloads and reinstalls this tune with backups; actual spring support and stability remain Studio verification requirements. Whole-fender brake visuals are disabled by default pending a dedicated lamp.

Front endpoint repair restores AuthoredPivotCFrame when available. FrontRestPose then mirrors the working rear mount about FootRest, moves the complete front linkage to that deck-side mount and rotates it to match rear tire ground level. HandleBarStick remains the fixed parent to preserve steering. Prepared legacy templates receive this bounded rest correction on a clone at spawn; versioned templates keep their rest tuning. DevScooterFrontMount.Apply persists front-only correction with backups and preserves rear geometry/tuning and steering. It can recover a unique original from matching mesh assets in retained sources; otherwise existing validated mounts are used and ambiguity is reported. Missing original local mesh mounting points cannot be reconstructed. See docs/SCOOTER_MODEL.md for the Studio recovery workflow and limits.

Optional spawn correction is transactional: ScooterRig retains a validated baseline and corrects/calibrates a separate clone. Failure discards that clone and spawns the baseline, exposing FrontRestPoseStatus/FrontRestPoseError and an Output warning. This prevents model-specific correction limits from suppressing a usable scooter. Baseline hierarchy/constraint validation remains mandatory, and explicit Edit-mode repair still rejects invalid replacements.

`ScooterClient.client.luau` sends input and handles mounted controls. `ScooterBaseRidingPose.client.luau` observes occupied scooters and applies the shared R15 base pose after Animator evaluation on each client. It supports Motor6D and AnimationConstraint, restores joint transforms on release, and leaves Animate enabled. The server retains native SeatWeld mounting and owns scooter physics. See [avatar behavior and rider fit](SCOOTER_RIDER_POSE.md).

Garage/premium features remain parked, and local prediction remains disabled. Shop and other gameplay systems remain independent. `Workspace.Map` is never rebuilt. Model installation, exact names and animation APIs are documented in [SCOOTER_MODEL.md](SCOOTER_MODEL.md); controls and server input validation are in [SCOOTER_SYSTEMS.md](SCOOTER_SYSTEMS.md).

Forward acceleration is 25–40 studs/s² across existing scooter tiers; ECO applies
0.7 of the selected tier acceleration. Catalog speeds and upgrade prices are
unchanged. ScooterTerrain probes the physical tire bottom at both wheels and adds bounded
wheel-local climbing support, leaving the real springs free to compress. Chassis
balance follows sampled ground height under both axles, including a lower
surface below an airborne tire when the other still supports the chassis.
A rigid up-axis constraint prevents collision-driven pitch/roll kicks during
normal supported riding, while the existing full-axis controller retains yaw
and wheelie behavior. Revision 3 limits shock force headroom to 1.1 and raises
damping ratio to 1.4. Post-solver stabilization damps road rebound and restores
only verified climb momentum through a short, expiring rear-clearance cache. IndependentFrontSteering keeps
front swingarms/spring fixed to the chassis and adds a wheel kingpin Servo; legacy
rigs retain their original topology. ScooterImpact requires recent wall contact
and an actual loss of approach speed, then uses existing crash/stun/recovery.
See [terrain and steering](SCOOTER_TERRAIN.md). The selected runtime scale is now
0.25. Server-side arcade tire assistance supports verified ledges up to 2.5 studs,
keeps vertical support through the corner and permits a bounded 1.25-second
ground-contact grace during an ongoing climb. It shares normal validated input
and clears on release, wheelie, dismount or fall. The 0.20 template remains stored;
Studio comparison displays default off. See [arcade handling](SCOOTER_ARCADE_HANDLING.md).

The reference remodel uses configurable 1.95-stud tires at the same 0.25 body
scale. Short forward/side face probes admit one-degree curb approaches; verified
entry assistance also sets the drive grip direction, and simultaneous tire
contacts share one supported load. If both tire ground probes miss, a short
Blockcast over the complete deck underside can still authorize grounded drive.
The deck uses skid friction so W/S can slide off a narrow support. This preserves
the airborne-drive restriction, height limit and server-owned geometry decisions.
Default spawn waits for the character root and chooses the enabled spawn nearest
that root, avoiding scooters at another spawn across the map. See
[reference remodel and native checks](SCOOTER_LARGE_WHEELS.md).

The 2026-10-05 remodeled draft uses the user's selected full-front steering:
fork, front suspension and tire follow the column, with seven hinges and two
central springs. Independent-front-wheel rigs remain supported. The new source
maps imported fork, levers, spring support and caliper explicitly; yellow review
adornments are removed before preparing gameplay copies. The user accepted this
rig and it is now the active template, using the measured remodeled deck for
seat/foot targets and actual grips for hand targets. Existing gameplay controllers
and remote validation are reused; see [current assembly](SCOOTER_FINAL_RIG.md).


Avatar Settings retains the intended 8-stud height; gameplay does not scale
characters. Mounted R15 limbs are posed without changing joint lengths. See [avatar
behavior](SCOOTER_RIDER_POSE.md).

# Server-local gangs and territories

`GangService` owns session membership keyed by UserId, leader succession, filtered
unique names, exclusive palette colors, invitations and join requests. Only an
offline leader retains membership for 30 minutes; a gang with no online members
disbands immediately. No gang or flag ownership enters PlayerData/DataStore. The
legacy profile `canCreateGang` field remains readable for migration, but grants no
gameplay permission: creating a gang is free.

Phone actions reuse `PhoneRemotes.Request` and `Changed`. `GangRequests` validates
an allowlist of commands and payload keys; the service rechecks permissions,
capacity, cooldowns and freshness. Responses carry server-generated request IDs.
Name filtering yields, so creation and renaming validate their state again before
committing. `PhoneServer` limits every request, including GetState, and serializes
each player's in-flight calls. `GangAppView` reuses the existing phone components
and scoped cleanup. `GangTags` owns the overhead label and restores the original
Humanoid display setting when membership ends.

`CombatService` remains the sole damage/stun/protection authority. Its territory
eligibility query accepts living stunned players and seated riders, and excludes
protected players. All combat paths retain existing safe-zone, spawn protection
and friendly-fire checks. Pepper stun lasts three seconds with no damage; the
existing Roblox death/respawn flow is retained. Gang does not require Combat,
keeping the existing Scooter → Combat → Gang dependency acyclic.

`TerritoryService` discovers anchored BaseParts tagged `GangTerritory` below the
manually authored `Workspace.Map`. Every 0.25 seconds it gathers eligible player
root positions once, then checks each oriented zone's bounds. `TerritoryCapture`
is a pure state machine: the largest gang needs a majority over all opposition;
net advantage determines linear capture speed, and tied/empty zones gradually
decay. Ownership changes only on completed capture or gang disband. Runtime
Folders under `ReplicatedStorage.Territories` publish owner, progress and phase
attributes for the phone and world labels, without progress remote polling.
Connections, world labels and published state are disposed when zones disappear
or the service stops.

`TerritoryRewards` distributes the configured per-flag pool through the existing
`PlayerDataService.AddCurrency` every minute, with integer remainder carried per
gang. Unavailable profiles and offline members receive no rewards. No missed
intervals are paid retroactively.

Territory geometry and metadata have a separate explicit `TerritoryData` snapshot
because the map serializer only versions asset placements. `DevTerritoryTool` and
`TerritoryWorkflow` configure selected authored flag models, serialize zones and
restore zones in Edit mode. No runtime map builder or automatic flag placement is
introduced. See [configuration and authoring](GANG_SYSTEM.md).


`ServerStorage.TerritoryFlagTemplate` is an additive Rojo mapping of the reusable
asset generated by `scripts/generate_territory_flag.py`. Unknown ServerStorage
children are preserved. `DevTerritoryFlags.PlaceFlags` explicitly installs missing
flag models from TerritoryData in Edit mode, preserving authored positions on
repeat calls. Three initial points were inspected and placed away from spawn:
ParkZachodni, SkwerOsiedlowy and BoiskoKamienice. Each model includes its capture
zone and noncolliding boundary lines, so Model:PivotTo moves the whole point.
TerritoryService colors opted-in BaseParts (`TerritoryTint = true`) using the
owner's palette color, resets neutral ownership and restores authored colors on
cleanup. Visual parts add no capture or damage authority. No runtime flag generator
or second territory script is introduced.

# NPC road traffic

`ServerScriptService.Traffic` owns a shared server fleet with continuous kinematic
Bezier trajectories, explicit swept collision/road-support checks, cached scooter
bodies, safe distributed spawns, FIFO intersection reservations and bounded recovery.
It reads an approved city-derived road graph; it never invokes the map builder or
regenerates roads at startup. `TrafficWorkflow` is the explicit Edit-mode inspection,
generation, correction, validation and export entry point. The initial graph was
built from the actual Studio `Workspace.Map.Drogi` road surfaces, rather than the
older mock `MapData`. Traffic assets preserve authored replacement models during
Rojo sync. Scooter mechanics and remotes are unchanged. See
[traffic architecture, workflow, validation and limitations](TRAFFIC_SYSTEM.md).

# NPC police

`ServerScriptService.Police` joins the existing traffic fleet with adapted native
Kia and Fiat Ducato Policja templates. Directed destinations and per-car tuning
extend the shared trajectory controller without changing civilian defaults.
Server scooter records supply precise speed and accepted, grounded wheelie;
bounded FOV/LOS evidence and exclusive claims authorize pursuits. R15 officers
exit supported car doors, navigate on foot and request a separately validated
arrest. The shared scooter dismount and an owner-scoped mount lock make ten-second
detention reversible on expiry, actor removal, death, respawn, disconnect or stop.
The client only renders replicated notices. No new remote, economy penalty or
production map generator is introduced. A server BindableEvent under TrafficSystem
stops the previous fleet when development creates a fresh manager require context.
See [police architecture and configuration](POLICE_SYSTEM.md) and
[executed validation and remaining acceptance](POLICE_VALIDATION.md).
