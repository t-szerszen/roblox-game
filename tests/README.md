# Scooter verification

## Runtime regression suite

Run with Python 3 and the [official Luau CLI](https://github.com/luau-lang/luau/releases):

```sh
python3 tests/run_scooter_tests.py --luau /path/to/luau
```

The runner loads the actual source files without rewriting their implementation.
`support/roblox_mock.luau` supplies a controlled clock, vector arithmetic, player
instances, signals, DataStore and Marketplace responses. No live account, currency,
Marketplace purchase or DataStore is accessed. The expected warning for a simulated
failed profile load is part of the test.

Assertions cover the five GDD base speeds and all 15 upgrade prices, acceleration
scaling, tier limits, malformed/NaN/infinite input, packet cooldowns, input expiry,
held-button reset, gradual coasting, braking, speed-sensitive steering, lateral grip,
airborne drive rejection, exact coin debits, duplicate expected tiers, ownership,
profile migration, failed-load protection, saved upgrades, disconnected profile
listeners, validated RGB, garage rate limits, unconfigured premium IDs, verified
game passes, entitlement caching/failure and garage shutdown.

The additional rig/animation suite executes actual ScooterRig preparation, ScooterAnimator lifecycle and ScooterWorkflow reload code. It checks missing parts and invalid links, cloned constraint references, preserved spring parameters and source objects, idempotent preparation, moving hand targets, speed/lateral/steering lean, elbow lift, remount/death cleanup, R6 fallback and transform restoration. Reload tests prepopulate stale assembler/configuration caches, verify repeated assembly loads fresh modules, and check temporary-folder cleanup and template preservation on failure. The leg-state suite verifies wheelie priority, idle/riding hysteresis, controller attribute transitions, single state-entry playback, fade/weight parameters, foot IK handoff, unloaded/missing/failed asset fallback, owned track cleanup and observer reuse of replicated clips. The object doubles do not solve IK, collisions, spring forces or actual animation asset evaluation.

These tests do not simulate Roblox physics integration or real network replication.
The visual suite executes the brake-light lifecycle with and without PBR appearance,
checking restoration and disposal. It also checks Servo attachment conventions,
asymmetric limits shared with yaw, neutral-limit rejection, inward lean in both
travel directions, acceleration scaling, maximum roll and frame-rate-independent smoothing.
In particular, torque stability, humanoid seating, raycast contacts, remote delivery
ordering and the physical mesh/template must also be checked in Studio.

The suspension suite checks passive bounded compression/droop, restoring spring
torque across the allowed arc, neutral-pose freedom within length limits, hidden
constraint visuals, disabled fender lighting, reference-mass scaling, reversed
hinge attachments and rejection of mountings with no spring leverage. It also
checks tuning retention during cloning and reload/cleanup through the suspension
developer entry point when the old repair wrapper is cached.

The front mounting suite reproduces a fixed attachment displaced from the arm's
visible mounting point. It checks restoration from an untouched reference, preservation
of mesh poses and steering, compression/droop around the corrected pivot, preservation
of custom rear tuning/geometry, repeatability, invalid/missing reference rejection,
staged installation with backups and cleanup after failure.

The stability suite verifies actual front mesh repositioning, rear-referenced deck
mounting and tire ground level, repeatable cloning/repair, deck contact and tire
self-collision exclusions, and original recovery by matching retained mesh assets.
It exercises the real ScooterServer spawn and unoccupied PreSimulation loop with
service doubles to check initial yaw/torque, articulated support mass, preserved
deck collision, subsequent balance torque and cleanup. It does not integrate the
Roblox constraint/contact solver.

The handling suite checks the inclusive 5 km/h W+S threshold, wheelbase-based
curvature at crawling speeds, bounded heading lead, the reduced handlebar deflection,
smooth wheelie return while moving, frame-rate independence and increased world
travel speed. Server integration also checks real DriveInput activation without
a burnout hint, motor torque/acceleration, speed/input expiry shutdown, release
of Shift/C followed by W/coast/S balancing, rejection below the wheelie threshold,
stationary burnout steering in both directions, a complete donut, exit on brake
release, blocked Servo behavior and airborne yaw rejection.

Reverse regressions integrate production drive forces through braking and direction
changes at 30/60/120 FPS. They cover forward and reverse crawl transitions, the
18 km/h cap and overspeed correction, coasting on release, W+S stopping without
reverse, and braking against downhill gravity before reversing uphill. Server
integration drives actual accepted S input and checks the force, cap and state.

Spawn regressions exercise a correction-limit rejection through the real server
spawn path and inject calibration failure after front mesh movement. Both must
retain a usable baseline, its calibrated springs and valid welds/attachments,
leave the installed source intact, report the skipped correction and clean up
the spawned fallback on server stop. Baseline validation remains enforced.

The repair suite checks divergent hinge positions/axes, noncoaxial paired pivots,
incompatible welds, passive suspension pivots, zero/invalid spring support, preserved
mesh transforms and spring tuning, source/previous-template backups and cleanup on
failed staging. It verifies independent tire radii, override precedence, contact
centering, idempotent collider/weld updates and spawn clearance for wheels below the deck.

## Build and strict type analysis

```sh
rojo build default.project.json --output /tmp/scooter-check.rbxlx
rojo sourcemap default.project.json --output /tmp/scooter-sourcemap.json
```

Use `luau-compile --null` for syntax/bytecode verification. For actual Roblox-aware
type analysis, use [Luau Language Server](https://github.com/JohnnyMorganz/luau-lsp)
with its generated `scripts/globalTypes.d.luau` definitions and the Rojo sourcemap:

```sh
luau-lsp analyze --platform=roblox \
  --sourcemap=/tmp/scooter-sourcemap.json \
  --definitions=@roblox=/path/to/globalTypes.d.luau \
  src/ReplicatedStorage/Shared/ScooterConfig.luau \
  src/ReplicatedStorage/Shared/Scooter/ScooterPhysics.luau \
  src/ServerScriptService/Scooter \
  src/ServerScriptService/Activity/PlayerDataService.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterAnimator.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterRiderPose.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterRiderVisualizer.client.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterPrediction.luau
```

## Studio multiplayer acceptance checks

Use an isolated test place with the current Rojo source, a flat test road and the
production scooter template. Install the new selected rig with DevScooterAssembler
before starting a server with two clients. Repeat physical
checks with R6/R15. No legacy template or generated fallback is used.
Avoid changing the production `Workspace.Map` for testing.

1. **Ownership and collision.** Player B cannot mount or control player A's scooter.
   Inspect every articulated assembly on the server: `GetNetworkOwner()` remains `nil`
   while mounted and unmounted. Meshes remain noncolliding; fork, wheel and suspension
   assemblies retain mass. Only the invisible wheel proxies contact the road, moving
   with physical wheel/axle travel. Confirm all four SpringConstraints compress on
   curbs without a rigid axle-to-Root weld. Local prediction remains disabled. The
   standing rider stays on the deck; both hands follow HandleBar at both steering
   limits and while suspension compresses. Confirm speed-dependent torso lean and
   corresponding elbow lift with two clients, turning in both directions.
2. **Driving.** Accelerate each model on level ground and compare the settled
   speed to the replicated `MaxSpeedKmh` (before and after each purchased tier).
   Release W to coast, press S to brake, then continue S to reverse responsively
   from a complete stop on both flat road and a mild slope. Steering
   cannot rotate the scooter at rest; at high speed the same input produces a
   smaller turn. Cross raised road markings, seams, ramps and curbs up to the
   configured step height from rest and at low speed, both forward and backward,
   without catching meshes or repeatedly injecting step impulses in midair. Dismount while
   moving and crash from a wheelie; the abandoned scooter should settle nearby
   instead of bouncing or accelerating away. Test 30/60/120 FPS and Studio
   network emulation around 150–250 ms latency.
   Hold S continuously from forward travel: braking should transition smoothly
   into reverse below 2 km/h, reaching 18 km/h. Release S to coast backward, then
   hold W to brake and transition forward. Repeat on uphill/downhill roads and
   around zero speed; no second press or stationary pause should be required.
3. **Wheelie and pitch.** Space performs no action and does not unseat the rider.
   Tap Shift or C above 10 km/h, release it, and use W to raise the front. Release W:
   the front must lower smoothly while speed remains positive. Before it lands,
   add W again: it must rise without another Shift/C. S must lower it faster.
   After landing, W alone must not restart wheelie. Brake hard and
   stop: the front must drop rapidly instead of balancing
   at zero speed. Outside wheelie, W/S must not tilt the chassis. Wheelie cannot
   start while reversing.
   Falling releases the rider and recovers after the configured stun. Pepper-spray
   stun overlapping a crash must retain the longer authoritative stun.
4. **Burnout replication.** Hold W+S at rest and at 4.9/5 km/h, then test 5.1 km/h.
   Only the first three speeds permit burnout. Both clients see the server emitter
   on `VirtualBackAxle.RearWheelAttachment`; confirm the rear wheel physically spins
   and returns to passive rolling on release; only an entitled owner sees their selected premium
   color. Releasing either key, being pushed above the low-speed threshold,
   leaving the ground, death, dismount and stale drive input all disable the emitter.
   Calling `TrickState:FireServer("Burnout", true)` without fresh simultaneous
   throttle/brake intent cannot activate it. Supplying an extra client color has
   no authority over the server emitter. Hold W+S at rest, steer A/D and complete
   a donut in each direction. Releasing S must disable stationary rotation along
   with the motor and smoke; blocked steering must still produce no yaw.
   Crawl in both directions with full steering: the scooter must follow a finite
   turning radius without spinning around its center. Block the steering Servo
   and verify that requested input alone cannot yaw the chassis. On open road,
   verify the reduced 30-degree deflection and 60% higher world travel speed;
   authored Servo limits still cap the visible angle.
5. **Hostile remotes.** From the test client call `DriveInput` with strings, tables,
   NaN (`0/0`), infinity, steering outside `[-1,1]` and nonboolean trick buttons.
   Spam both valid and invalid requests and confirm the server stays responsive,
   input does not become NaN, and speed/coins/tier/ownership do not change. Stop
   sending accepted drive packets while holding W; intent resets within
   `DriveInputTimeout`. Send requests from player B while player A is mounted.
6. **Garage transactions.** Seed Coins only from the test server. Buy each speed
   tier, verify the exact GDD debit, immediate scooter attribute update and tier-3
   cap. Send two requests with the same expected tier; only one debit occurs.
   Attempt an unowned model, insufficient balance and purchases before profile
   load. Rejoin the isolated place to confirm persisted tiers/preferences. A
   failed DataStore read must keep purchases disabled and cannot overwrite data.
7. **Premium verification.** IDs of zero leave premium effects unavailable. In the
   isolated place configure actual experience-owned test game passes, test a real
   entitled account and a non-owner, and verify RGB/enable changes replicate to
   both clients. A saved preference, local attribute, purchase prompt or forged
   request alone must not grant entitlement. Invalid RGB values are rejected.
8. **Cleanup.** Repeat mount/dismount, reset, death, scooter replacement and server
   Stop/Start. No extra input/render callbacks, prediction models or smoke remain.
   Rider collisions, Animate enabled state, torso transforms and character network ownership
   return to normal on dismount. No hand/foot IKControls or elbow poles remain.
   Remount repeatedly with R6/R15 and observe both clients. Typing in chat or losing focus releases controls.
   Lose focus, die/dismount, refocus while unmounted, then remount: controls work.
   Compare client memory and event/network activity before and after repeated cycles.

9. **Leg animation clips.** Supply your actual R15 IDs in RiderAnimations before this
   check. At rest, IDLE fades into IdleFootAnim: one foot reaches the ground and
   the supporting foot remains on the deck. Accelerate into RIDING and brake to
   IDLE repeatedly, including speeds around the two hysteresis thresholds; the
   clip must not restart every frame or flicker between states. Trigger wheelie
   while moving: WheelieBalanceAnim takes priority, shifts balance rearward and
   moves its balance leg. End wheelie while moving and at rest to exercise both
   exit paths. Verify foot IK does not hold the animated leg on the deck, hands
   stay attached to HandleBar and observers see one replicated clip per state.
   Test different avatar scales and slopes. Confirm missing/unavailable IDs retain
   foot support, and death/dismount/remount leave no owned tracks or state listeners.

10. **Optional brake light and chassis roll.** BrakeLight.Enabled defaults to false;
    verify S/reverse and W+S leave the authored fender appearance intact and add no
    brake glow. The following light checks apply only if explicitly enabled for a
    future lamp test. With two clients, hold S while moving and
    while reversing, then W+S during burnout: BackFender is red and the brake glow
    is visible to both. Release S or use W alone: all authored appearance returns.
    Test expiry, death, dismount, crash and replacement while braking; no light
    remains enabled or accumulates. Check textured and untextured fenders in daylight
    and darkness. Drive both turn directions at increasing speed: roll is inward,
    capped at 16 degrees and smooth. Stop, lose wheel contact and trigger wheelie:
    roll returns toward neutral without upsetting pitch or spring travel. Test slopes.
    In a test template set asymmetric Servo limits containing zero; inspect TargetAngle
    and Steering to confirm the chassis uses the same reduced steering. Reverse
    Attachment0/Attachment1 and verify the handlebar still follows input. Actual
    steering response may lag TargetAngle according to authored torque/angular speed.

Record Studio results separately from CLI checks; a successful Rojo build alone
does not establish gameplay or multiplayer correctness.

For a collapsing rig, stop Play, sync Rojo and use the DiagnoseSelection/RepairSelection
commands in [SCOOTER_MODEL.md](../docs/SCOOTER_MODEL.md#diagnose-or-repair-a-collapsing-scooter).
In a new Play session verify that the spawned scooter supports itself on the road
without a rider, both colliders contact the road and arms remain joined. Repeat with
a rider, bumps, reverse, wheelie and burnout. Inspect the axis inferred for steering
and inferred tire bounds, especially on unusually oriented/imported meshes. Capture
live diagnostics for any remaining spring collapse; CLI doubles do not solve suspension.

After DevScooterSuspension.Apply, test repeated strong wheelie and front landing:
neither arm may fold through the chassis, and both wheels must return to contact.
Compare front/back travel with and without the rider and on bumps. Confirm the
green debug coils stay hidden and no red whole-fender effect appears on S/reverse.
Inspect the paired hinge limits and spring length stops at rest for free movement.

After DevScooterFrontMount.Apply, inspect both front arm pivots in Edit mode and Play:
the visible proximal arm joint must stay attached to the deck-side mounting as the
wheel rises/drops over a curb. Check straight and turned steering, unloaded/loaded
rest pose, front landing after wheelie and suspension return. Compare rear pivot
frames and spring parameters before/after application; the front-only repair must
preserve them. Legacy templates need the untouched original as a second selection
if AuthoredPivotCFrame is unavailable. See the front repair workflow in SCOOTER_MODEL.md.

With an older prepared template, start a new Play after syncing: verify that the
server applies FrontRestPoseRevision once and the front visible arm now moves to
the rear-referenced deck mount. Diagnostics expose correction angle, mount shift,
UprightSupportMass and upright torque. Leave the scooter unattended for at least
30 seconds: it must retain balance and stay above the collidable road. Push it
sideways or force a wheelie crash and verify the deck proxy stops ground penetration.
Confirm the deck does not touch its own wheel proxies through the entire suspension
stroke. Repeat on a curb, slope and with rider mount/dismount; real solver behavior
and visual mounting alignment require Studio checks.
