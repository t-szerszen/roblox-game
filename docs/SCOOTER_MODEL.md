# Articulated scooter model contract

For a raw imported model that does not yet satisfy this contract, use the
[read-only hierarchy inspection](SCOOTER_INSPECTION.md) before assembling it.
The approved nested `ScooterFinal` uses the explicit [preview and runtime installer](SCOOTER_FINAL_RIG.md).
Its CentralShockRig contract preserves approved mounts, uses two central shocks
and a generated helper for the riding deck. The legacy assembler/repair commands
below describe the older direct-child rig; use InstallNewModel for ScooterFinal.

An optional handlebar speedometer is available as a separate, manually mounted
asset. See [dashboard creation and mounting](SCOOTER_DASHBOARD.md); it is never
automatically inserted into the authored production template.

The only visual/physical template is `ServerStorage.ScooterModels.scooter`. Catalog model names still select existing tuning and ownership rules; they all use this rig. The old five-part KuKirin template and procedural fallback are retired.

## Install the authored Studio model

Sync Rojo, stop Play, select the complete new `scooter` Folder, and run in Studio's Server Command Bar:

```lua
require(game.ServerScriptService.Scooter.ScooterWorkflow).Assemble()
```

The assembler validates the complete hierarchy, constraint endpoints and mechanical geometry before replacing either the previous `scooter` template or legacy `KuKirin G2 Pro` template. It clones the authored assembly into a Model with the same direct child names, preserving mesh assets, SurfaceAppearances, attachments and suspension welds. The front linkage rest pose is aligned to the working rear geometry as described below. Calibrated spring tuning retains the original parameter values in diagnostic attributes. The original selected source is moved from Workspace to ServerStorage after successful installation so it does not collide with spawned scooters. Save the place. Studio-authored MeshParts and constraint settings are not supplied by Rojo source files; running this command is required to install the actual asset.

`ScooterWorkflow.Assemble()` loads fresh clones of the assembler, rig and canonical configuration on every invocation, and destroys temporary modules on success or failure. This follows the existing MapWorkflow pattern and avoids Studio's cached `require()` result. It validates the articulated assembler version before installing a template.

If Output mentions `Missing selected BasePart named Fork`, `collectSelectedParts`, or the old assembler's line 117, Studio executed the retired assembler. First connect the Rojo plugin to `rojo serve default.project.json` in this repository and sync. Confirm `ServerScriptService.Scooter` contains both `ScooterRig` and `ScooterWorkflow`, then select the new `scooter` Folder and use the workflow command above. Missing modules or an old version produce a sync error; the workflow cannot update unsynchronized Studio source files. If the workflow itself was previously required and then edited, reopen Studio or require a fresh clone of that wrapper. [ModuleScript results are cached per Luau environment](https://create.roblox.com/docs/reference/engine/classes/ModuleScript).

## Diagnose or repair a collapsing scooter

Sync the current Rojo project first. Select the complete scooter Folder/Model in Explorer, then run this read-only command in the Studio Server Command Bar (Edit mode or Play):

```lua
require(game.ServerScriptService.Scooter.DevScooterRepair).DiagnoseSelection()
```

Output reports joint position gaps and world X-axis alignment, incompatible welds between moving assemblies, coaxial suspension pivots, spring length/free length/stiffness/damping/maximum force, part masses, collision flags/groups and wheel radius sources. For a live scooter it also tests enabled wheel contacts and samples the collidable floor using each collider's collision group. Missing authored components and endpoints are reported without inventing paths.

For repair, **stop Play**, select the original authored Folder or the installed ServerStorage.ScooterModels.scooter template in its Edit-mode pose, and run:

```lua
require(game.ServerScriptService.Scooter.DevScooterRepair).RepairSelection()
```

Repair stages a clone and loads fresh copies of rig, geometry, collision and configuration modules. Front pivot endpoint repair uses the arm's original local mounting positions, retained as AuthoredPivotCFrame attributes. The subsequent rest alignment moves the entire front linkage and its fixed pivots to the deck-side mount derived from the working rear, then rotates the arm/axle/wheel together to align tire ground levels. Rear pivot repair continues to use its two authored base positions. The repair aligns each hinge pair in world space, centers wheel AxlePivot attachments on WheelCenter and makes suspension pivots passive. Wheel hinges become unlimited/passive until the existing burnout controller activates the rear motor. Incompatible extra welds are disabled on the staged clone. A valid authored steering axis is preserved; if nearly horizontal, its direction is estimated from SteerBase toward HandleBar and reported for manual inspection.

Only a replacement passing structural and geometry validation is installed. The original selection and previous templates are moved into ServerStorage.ScooterRepairBackups with unique names; none are deleted. Originals stay outside Workspace and do not participate in gameplay. On a validation failure, the selected source and installed template remain unchanged. Save the place, then start a **new Play session** so the server loads current module code. Regular ScooterWorkflow.Assemble remains the installer for already-correct rigs.

The [HingeConstraint contract](https://create.roblox.com/docs/reference/engine/classes/HingeConstraint) requires coincident attachment positions and matching world X axes. Because each end's arms are welded to one virtual axle, its two chassis pivots must additionally describe one shared axis; two incompatible hinge axes overconstrain the same rigid assembly. Geometry validation rejects these conflicts before spawning a scooter.

Repair preserves spring mounting locations. Zero stiffness/maximum force, zero spring length or a rest pose outside hard spring length limits blocks installation with an actionable report. The prepared replacement now calibrates passive suspension as described below; original spring values are retained in diagnostic attributes. Preload, leverage, damping, force limits and masses still need a Studio test. See the [SpringConstraint contract](https://create.roblox.com/docs/reference/engine/classes/SpringConstraint).

## Suspension stroke and calibration

After synchronizing Rojo and stopping Play, select the installed template (or complete original Folder) and run:

```lua
require(game.ServerScriptService.Scooter.DevScooterSuspension).Apply()
```

This entry point reloads the repair wrapper as well as its dependencies, avoiding the Command Bar's older cached wrapper. It stages geometry repair and suspension calibration, installs the validated template and retains original models in ScooterRepairBackups. Save and start a new Play session.

ScooterSuspension bounds both ends using passive suspension HingeConstraints. Starting from the authored rest pose, it samples wheel and spring movement around each shared pivot axis. Travel stops before a wheel vertical derivative or spring length derivative reverses direction, preventing the arm from crossing its linkage turning point and folding above the chassis after wheelie. Left/right limits share the same physical arc, including when a hinge's attachment order is reversed. Stop restitution is zero. Suspension pivots remain passive; wheelie, steering and wheel motor controls are unchanged.

Shared/ScooterConfig.Suspension configures front/back maximum compression/droop angles (22/12 degrees), desired travel relative to tire radius (0.4/0.2), a one-degree safety margin and sampling precision. The geometric checks can reduce those maxima on a particular model. Spring length limits cover the entire safe arc with clearance so they do not lock a shock at the neutral pose.

Spring stiffness is computed at the wheel, using the actual shocks' length change per pivot rotation and the wheel's vertical change. Short and long spring linkages therefore have comparable wheel compliance instead of receiving the same arbitrary raw stiffness. Both ends use half the model's non-massless part mass plus half the configured reference rider mass (default 20 Roblox mass units). This is a starting tune, not measured runtime load distribution.

The default tune preloads 80% of that reference load and targets sag of 40% of safe compression travel at the front and 30% at the rear for the remaining load. This deliberately gives the front a softer target. DampingRatio is 0.8, and maximum spring force includes configurable headroom. Increase Front.SagFraction or Back.SagFraction to soften that end's supported wheel response; front/back travel settings can be adjusted separately. Original Stiffness, Damping and FreeLength remain in AuthoredStiffness/AuthoredDamping/AuthoredFreeLength attributes, while SuspensionRestLength and SuspensionRestAngle identify the calibrated pose.

Constraint.Visible defaults to false via ShowConstraints: the green SpringConstraint coils are debug visuals and are hidden in the prepared/live scooter. SuspensionRevision prevents recalibrating a cloned or moving scooter from a compressed pose; use Apply after configuration/geometry changes, or increment the configuration revision when installing revised tuning. Invalid spring leverage rejects calibration rather than assigning extreme forces. Verify loaded/unloaded support, front/rear compression and return after repeated wheelie in Studio; CLI checks evaluate geometry and force response rather than Roblox's solver.

## Repair the front mounting while preserving the working rear

Sync Rojo and **stop Play**. Select `ServerStorage.ScooterModels.scooter`. Optionally Ctrl-select the untouched original new-model Folder/Model (retained in ServerStorage or ScooterRepairBackups) to recover overwritten arm attachment frames. Selection order does not matter when only the installed template is marked ArticulatedScooter. Run:

```lua
require(game.ServerScriptService.Scooter.DevScooterFrontMount).Apply()
```

The command reloads the repair code, stages a clone and restores the front arm's original local pivot frames from the reference when available. With one selection, it looks for an uncalibrated original with identical front arm MeshIds and Sizes in ServerStorage or ScooterRepairBackups. It only chooses automatically if all matching candidates agree on both original pivot frames. Otherwise it retains the current validated mounts and reports the ambiguity. Front compression/droop, preload and damping are recomputed using the existing calibrated reference mass. Rear pivots, spring parameters and travel limits are preserved, including custom tuning. Installation retains the old template in backups and leaves the reference untouched. Save and start a new Play session.

FrontRestPose mirrors the working rear pivot midpoint across the FootRest center plane perpendicular to travel. This supplies the front deck-side mount height and longitudinal position while retaining front arm spacing and the shared transverse axis. The full front arm/axle/wheel assembly translates to that mount and rotates around it until front and rear tire bottoms share the same deck-relative level, using each tire's actual radius. Internal welds are disabled while individual parts move and restored afterward so writing CFrame cannot move welded parts twice. Fixed spring endpoints and the steering shaft stay authored. Calibration then checks leverage and safe travel at the corrected pose. Corrections over 45 degrees or a mounting shift over four front tire radii reject the replacement. These limits and the revision are centralized in ScooterConfig.FrontRestPose. FrontRestPoseRevision, FrontRestCorrectionDegrees and FrontMountShift record the result.

During spawn, ScooterRig first prepares a validated baseline with collision contacts and suspension tuning. If FrontRestPoseRevision is missing/outdated, it attempts the optional front correction and front-only recalibration on a second staged clone. The corrected clone is used only after all geometry checks pass. On any correction or calibration error, the staged clone is destroyed and the baseline spawns with its original pose, springs and welds intact. Output reports the concrete reason; FrontRestPoseStatus = Skipped and FrontRestPoseError retain it on the spawned model. A successful correction records Applied. Structural or mechanical errors in the baseline still reject spawning. The template source and working rear are untouched. Current templates retain their corrected pose when cloned; updates never rebase springs from a compressed live state. Explicit Edit-mode front repair still rejects invalid corrections without replacing the installed template.

The front fixed attachments still belong to HandleBarStick, as required by the authored steering architecture. Their world positions are at the arm's deck-side joints. Welding the front axle to ScooterBody or reparenting its fixed pivots directly onto the deck would bypass steering. The wheel and both arms move together around the shared passive hinge axis, with the same leverage-based spring calculation as the rear.

The old repair overwrote arm attachment positions. If no untouched source or saved original frames exist, rest alignment can move the current validated linkage but cannot reconstruct a lost local mesh mounting point. In that case manually position both front arm PivotAtt_FrontSuspensionLeft/Right attachments at their actual visible hinge centers in Edit mode, then set each attachment's AuthoredPivotCFrame attribute to its corrected local CFrame. Explicit calibrated references without saved original frames are rejected. Invalid transverse axes or insufficient spring leverage reject installation without replacing the working template. Verify rest alignment, curb travel, return after wheelie and steering in Play; local tests do not run the Roblox physics solver.

## Authored hierarchy

Names are case-sensitive. Do not rename `BackWheel` to `RearWheel` or `HandleBar` to `Handlebar`.

```text
scooter (Folder in source; Model in ServerStorage.ScooterModels)
├── ScooterBody (MeshPart)
│   ├── SteerBase (Attachment)
│   ├── HingeConstraint (HingeConstraint, steering Servo)
│   ├── PivotAttBase_BackSuspensionLeft/Right (Attachment, each)
│   ├── PivotHinge_BackSuspensionLeft/Right (HingeConstraint, each)
│   ├── SpringAttBase_BackSuspensionLeft/Right (Attachment, each)
│   └── ShockAbsorber_BackSuspensionLeft/Right (SpringConstraint, each)
├── HandleBarStick (MeshPart)
│   ├── SteerPivot (Attachment)
│   ├── WeldConstraint (welds HandleBarStick to HandleBar)
│   ├── PivotAttBase_FrontSuspensionLeft/Right (Attachment, each)
│   ├── PivotHinge_FrontSuspensionLeft/Right (HingeConstraint, each)
│   ├── SpringAttBase_FrontSuspensionLeft/Right (Attachment, each)
│   └── ShockAbsorber_FrontSuspensionLeft/Right (SpringConstraint, each)
├── HandleBar (MeshPart)
├── FrontWheel (MeshPart)
│   └── WheelCenter (Attachment)
├── BackWheel (MeshPart)
│   └── WheelCenter (Attachment)
├── FrontSuspensionLeft/Right (MeshPart, each)
│   ├── PivotAtt_FrontSuspensionLeft/Right (matching Attachment)
│   └── SpringAtt_FrontSuspensionLeft/Right (matching Attachment)
├── BackSuspensionLeft/Right (MeshPart, each)
│   ├── PivotAtt_BackSuspensionLeft/Right (matching Attachment)
│   └── SpringAtt_BackSuspensionLeft/Right (matching Attachment)
├── VirtualFrontAxle (Part)
│   ├── WeldConstraint (x2: connects both front suspension arms)
│   ├── AxlePivot (Attachment)
│   └── HingeConstraint (links AxlePivot to FrontWheel.WheelCenter)
├── VirtualBackAxle (Part)
│   ├── WeldConstraint (x2: connects both back suspension arms)
│   ├── AxlePivot (Attachment)
│   └── HingeConstraint (links AxlePivot to BackWheel.WheelCenter)
├── FootRest (MeshPart)
└── BackFender (MeshPart)
```

The steering hinge links `ScooterBody.SteerBase` to `HandleBarStick.SteerPivot`. Each suspension pivot and spring links its named base attachment to the matching attachment on the corresponding suspension arm. Reversed Attachment0/Attachment1 order is accepted. Constraints and axle welds must be enabled. Extra authored Attachments and SurfaceAppearances remain intact. No missing authored part is created or waited for.

## Generated runtime support

`ScooterRig` adds an invisible `Root` welded only to ScooterBody and uses it as PrimaryPart. Its negative Z axis is derived from the rear-to-front axle direction, without changing any mesh's authored orientation. An invisible `DriverSeat`, rider/foot attachments and burnout emitter keep the existing authoritative mount and drive workflow working.

`FootRest` is welded to ScooterBody; `BackFender` is welded to VirtualBackAxle so it follows rear suspension travel. `LeftHandGrip` and `RightHandGrip` are generated directly under HandleBar, initially at the configured half-width along the scooter's right axis. Adjust these generated grip attachments in the installed template to the actual grip centers and the rider/foot targets to the deck before playtesting. Prepared templates are cloned without recreating these offsets. No weld connects either axle to the chassis.

All meshes and virtual axes are noncolliding. ScooterCollision creates two invisible spherical contact proxies centered at each wheel's WheelCenter and welded to that wheel, plus a massless DeckCollider welded to FootRest. The deck proxy is inset within its bounding box by DeckColliderInset (default 0.03 studs per side) and prevents the chassis disappearing through the road if it rolls or bottoms out. NoCollisionConstraints exclude the deck from both wheel proxies, so this protection cannot lock suspension against its own tires. Reconfiguration updates existing contacts without duplicating proxies or exclusion pairs. Server initialization preserves their CanCollide flags. Actual spring/hinge motion carries the wheel contact points and transmits forces through the suspension. Steering, wheel and suspension assemblies retain mass; all assemblies remain server-owned. Original spring parameters remain available in attributes.

Set a finite positive `WheelRadius` attribute (studs) on each wheel or the template for an exact tire radius. Each wheel resolves independently: its own attribute, then the template attribute, then half the middle of its sorted Size dimensions (the smallest is normally tire thickness). Bounds inference is approximate for unusual meshes; verify the collider in Studio and supply an attribute when needed. ResolvedFrontWheelRadius/ResolvedBackWheelRadius and FrontWheelRadiusSource/BackWheelRadiusSource record the result without replacing authored overrides. Ground probes and step assistance use the corresponding wheel radius. Spawn height accounts for the lowest wheel/deck contact, including deck rotation. Root and DriverSeat never collide. Existing VectorForce propulsion includes the moving assemblies' mass. AlignOrientation now uses that same support mass instead of only the small Root assembly and initializes its target/torque before the first simulation update. UprightSupportMass exposes the reference in diagnostics. Wheelie/crash state rules, input validation and cooldowns retain their existing behavior.

The steering hinge runs as a Servo, using the existing bounded, speed-dependent steering input. Authored positive ServoMaxTorque and AngularSpeed are preserved; centralized defaults supply zero values. Limits remain authored and must include neutral (0 degrees). `SteeringServoSign` configures the authored axis convention. Wheels roll physically rather than using Motor6D visual rotation. The front hinge is passive; the rear hinge becomes a Motor during server-accepted W+S burnout at up to 5 km/h with rear contact, then returns to passive rolling. Its AngularVelocity is 55 rad/s with endpoint/axis sign correction, MotorMaxAcceleration is 120 rad/s², and MotorMaxTorque is at least 100, otherwise supportedMass * gravity * backWheelRadius * 0.6. These settings follow the [HingeConstraint motor contract](https://create.roblox.com/docs/physics/constraints/hinge). BurnoutSmoke is attached to VirtualBackAxle, so it follows suspension travel without spinning with the wheel. Tuning the new mechanical assembly still requires Studio playtests.

StudsPerKmH = 1.6 raises world travel speed 60% from the previous 1.0 scale without changing catalog speed ratings. A wheelie starts on the Shift/C rising edge above WheelieMinSpeedKmh (10 km/h). The trick key only triggers the state: afterward W raises the front, releasing W lowers it, and adding W again before landing regains pitch without another trigger. Once the front lands and the state ends, W alone cannot restart wheelie. Natural return is capped at WheelieNaturalDropRate (58 degrees/s), then eases exponentially at WheelieReturnSpeed (3.2/s) near landing. S uses the faster brake return. The existing low-speed drop and crash limits remain active; WheelieRestAngle (0.25 degrees) ends the residual pitch.

Direction changes are controlled by the existing authoritative VectorForce. S brakes forward motion at DirectionChangeBrakingDeceleration (60 studs/s²), engages reverse below DirectionChangeSpeedKmh (2 km/h) and accelerates at ReverseAcceleration (25 studs/s²) toward MaxReverseSpeedKmh (18). W similarly engages forward drive during a reverse crawl. The existing hill assistance compensates slope gravity during both braking and powered travel. The force calculation bounds speed changes by the configured acceleration and frame time; it does not teleport velocity. Coasting, normal steering and W+S burnout keep their separate behavior.

## Scooter brake light and cornering lean

`ScooterServer` creates a dedicated rear `StopLight` controller when the model
contains that lamp. Braking, held S, or occupied reverse motion illuminates its
red surface and PointLight. `BrakeActive` is separate: S while moving forward, W
while moving backward, or W+S is braking; reversing with S alone is not. Both
physical dashboard and HUD read this server state. Dismount/crash disables the
rear lamp. Cleanup restores authored material, color, PBR and PointLight settings.
`ScooterConfig.StopLight` holds the dedicated settings. The optional legacy
whole-fender effect remains disabled via `BrakeLight.Enabled = false`.

Mounted L toggles a white front beam through the zero-argument `ToggleHeadlight`
remote. The server validates the owner, occupied seat, life/state and 0.35-second
cooldown; the client never supplies lamp state or properties. `ScooterHeadlight`
orients a SpotLight attachment along the scooter's forward direction on FrontLight,
so the beam follows steering. It restores appearance and destroys its attachment
on cleanup. Shared `Headlight` configuration controls beam color/range/brightness.

The authored [SurfaceAppearance](https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance)
can mask mesh material changes. Existing tint and emission are adjusted without
replacing textures; the lamps also emit actual PointLight/SpotLight illumination.

Servo target degrees are `sign * effectiveInput * deg(MaxHandlebarAngle)`, with sign inverted when Attachment0 belongs to HandleBarStick. MaxHandlebarAngle is 48 degrees; speed fade spans 25–80 km/h. Effective input retains existing smoothing and speed fade, including at zero speed: a mounted rider can steer without throttle or burnout. MinSteeringSpeed gates normal chassis yaw, not the Servo target. Authored LowerAngle/UpperAngle clamp the target. When accepted steering input is neutral, chassis yaw ignores residual Servo noise.
Otherwise chassis steering uses the wheel kingpin CurrentAngle when present,
or the legacy column CurrentAngle, divided by the signed full angle, so a blocked Servo cannot rotate the chassis from requested input alone. The [HingeConstraint Servo contract](https://create.roblox.com/docs/reference/engine/classes/HingeConstraint) specifies TargetAngle in degrees. Actual movement still depends on AngularSpeed/ServoMaxTorque; SteeringAngle publishes the measured angle in radians for rider IK/lean.

The bicycle turn model is `yawRate = -abs(speed) * tan(turnInput * MaxHandlebarAngle) / actualWheelbase`, with reverse travel inverting turnInput and magnitude capped by TurnRate. Wheelbase is the initial separation of the virtual axle pivots. No wheel contact produces zero yaw; outside burnout, speed below MinSteeringSpeed also produces zero yaw. Unlike a minimum turn-rate floor, this keeps a finite radius while crawling. Desired heading stays within `min(MaxHeadingLeadAngle, abs(yawRate) * HeadingLeadSeconds)` of the actual planar chassis heading (12 degrees maximum, 0.15 seconds of lead), preventing orientation windup against obstacles. During accepted burnout, yaw instead uses `-measuredSteeringInput * BurnoutTurnRate` (90 degrees/s maximum), independent of travel speed. This allows sustained donuts without weakening normal low-speed steering rules. Releasing either W/S, stale input, losing rear contact, or exceeding 5 km/h disables that mode. The same heading lead bounds still prevent winding up against obstacles, and cornering roll is disabled during burnout. Outside burnout, cornering roll is `atan2(signedSpeed * yawRate, Workspace.Gravity)`, capped by MaxSteeringLean (16 degrees). This ties lean to centripetal acceleration and gives right turns negative roll. Exponential smoothing at SteeringLeanSmoothSpeed eases entry/exit independent of frame rate. Only an occupied, upright chassis with both wheel contacts requests roll; wheelie, airborne and parked states request zero.

The roll replaces the old linear lean in the existing root [AlignOrientation](https://create.roblox.com/docs/reference/engine/classes/AlignOrientation) target. It does not teleport individual meshes, change center of mass, add a competing orientation actuator or change suspension spring parameters. Wheelie pitch, drive force and rear-wheel burnout motor retain their separate existing controls. Test the capped roll on the authored springs and slopes in Studio before changing its limits.

## Rider animation

`ScooterAnimator.new(scooter)` returns an animator exposing dot-call methods:

```lua
local animator = ScooterAnimator.new(scooter)
animator.mount(character)
animator.dismount()
local state = animator.getState() -- IDLE / RIDING / WHEELIE, or nil when unmounted
```

ScooterRiderVisualizer binds an animator to every replicated scooter's DriverSeat.Occupant on each client. Missing streamed model/character descendants are retried through events, without per-frame hierarchy scans. Existing ScooterRiderPose supplies foot IK, wheelie foot balance and the R6 standing fallback. It no longer creates hand IK.

For R15, two IKControls target attachments directly on HandleBar, so physical steering moves the hands. Elbow poles lift the arm on the corresponding turn side. Complete Motor6D/AnimationConstraint chains now use ScooterLimbSolver after the torso layer, with their competing IKControls disabled; incomplete chains retain IK fallback. Fixed joint lengths, original rest-bone axes and a steering torso twist keep hands on the grips even at full lock. See [current rider pose](SCOOTER_RIDER_POSE.md). The [IKControl contract](https://create.roblox.com/docs/reference/engine/classes/IKControl) documents moving targets, chain overrides and pole control.

Body lean blends forward speed, lateral speed (`velocity:Dot(root.CFrame.RightVector)`) and the measured steering angle. The server publishes `SteeringAngle` in radians with positive values representing right input, because HingeConstraint.CurrentAngle is [not replicated](https://create.roblox.com/docs/reference/engine/classes/HingeConstraint). Lean is bounded and shared between Root/RootJoint and Waist. PreAnimation updates IK targets and removes the previous procedural torso layer; PreSimulation applies torso transforms. R6 uses its RootJoint and existing procedural standing pose, as it lacks R15 hands.

Dismount, death, character/scooter destruction and remount disconnect callbacks, remove generated IK/poles, restore saved motor transforms and restore the Animate script's previous enabled state. New steering, lean, grip-width and elbow settings live in Shared/ScooterConfig. No new remote grants client authority over physics or tricks.

## Leg animation state machine

The client derives leg states only from controller-published attributes. `WheelieActive` takes priority; `SpeedKmh` selects idle/riding with hysteresis. `DriveState = Airborne/Fallen` and `Fallen = true` prevent the idle ground-foot pose. Missing speed defaults to riding until replicated data arrives. These visual states do not change drive input, force, wheelie rules or burnout.

| State | Entry | Legs |
| --- | --- | --- |
| `IDLE` | Speed at/below `IdleEnterSpeedKmh`; retains idle up to `IdleExitSpeedKmh` | Play `IdleFootAnim`, with one foot removed from the support/deck and resting on the ground. |
| `RIDING` | Speed above the exit threshold or unsuitable ground-foot state | Fade out state clips; left foot returns to the deck, right foot stays near the middle of the deck. |
| `WHEELIE` | Authoritative `WheelieActive = true`, unless fallen | Play `WheelieBalanceAnim` for rearward body balance and the moving balance leg. |

Set your R15 animation IDs in `Shared/ScooterConfig.RiderAnimations.IdleFootAnim` and `.WheelieBalanceAnim`, using either a numeric **string** or `rbxassetid://<ID>`. Both default to an empty string, which deliberately loads no asset. Until the IDs are supplied, or while a clip is unavailable/not yet loaded, the existing procedural foot/wheelie pose remains active. R6 retains its procedural standing/balance fallback; these clips are intended for R15.

Author both clips with the legs and pelvis keyed; in idle, key the supporting leg on the deck as well as the ground leg. Arms remain driven by hand IK. Wheelie can key the pelvis/root for the rearward shift, with procedural steering lean applied as an additional layer. The actual ground-foot height and reach must be checked against the scooter, slopes and avatar scales in Studio after supplying your assets.

Clips load once per mount and loop at matching Action priority. Attribute-change events drive transitions: entering a state calls `AnimationTrack:Play(FadeTime, Weight, PlaybackSpeed)` once, while the outgoing clip uses `Stop(FadeTime)`. The defaults are a 0.25-second fade, weight 1, playback speed 1 and idle thresholds of 0.5/1.5 km/h. Change these in the same configuration table. Stable states never restart a track every frame; see [AnimationTrack blending](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack).

PreAnimation sums the loaded tracks' current blend weights, then reduces foot IK by that amount. Fully blended clips disable foot IK entirely so poles cannot pin animated feet to the deck; fading back to riding restores the procedural foot pose. Hands stay on the grips through the manual solver or IK fallback. The character owner's client starts clips; observers follow the owner's replicated tracks through Animator.AnimationPlayed and never load or play a second copy. Existing replicated state clips are preserved when attaching an observer. A player character waits for its server-created Animator, because a client-created Animator cannot replicate tracks; see [Animator replication](https://create.roblox.com/docs/reference/engine/classes/Animator).

Dismount stops/destroys the locally owned tracks and animation objects, disconnects state/animation listeners and resets `getState()` to nil. Observers release their references without stopping or destroying the owner's tracks. Asset load/play errors fall back to procedural foot support.

The current central-shock template is rebuilt at scale 0.30 with a 1.48 dashboard
scale multiplier. Native steering Servo tuning and the 0.65-stud threshold test
are recorded in [SCOOTER_FINAL_RIG.md](SCOOTER_FINAL_RIG.md). Forward acceleration
is 25–40 studs/s² by tier, multiplied by 0.7 in ECO; existing top speeds and
upgrade economics are preserved. Step assistance uses the inset collision sphere bottom and both wheels, with
continuous wheel-local support and radius/height/force limits. It does not apply
chassis launch impulses. The central rig now has deck-mounted front swingarms and
a separate steering carrier at the front axle. Wall impacts use actual approach
speed loss and existing rider crash recovery. See [SCOOTER_TERRAIN.md](SCOOTER_TERRAIN.md).
