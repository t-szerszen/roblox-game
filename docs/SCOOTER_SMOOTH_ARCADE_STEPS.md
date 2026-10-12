# Smooth arcade obstacle traversal

Small, anchored obstacles up to the existing 2.5-stud height budget use
`ScooterArcadeSteps`, selected by `ScooterConfig.ArcadeSteps.Enabled`.
`ScooterTerrain.Probe` still validates the contacted face, walkable top, overhead
clearance and local radius budget. The former tire climbing forces and rebound
correction are bypassed for this mode.

The server temporarily creates `NoCollisionConstraint` pairs between the three
scooter collision proxies and each verified obstacle. Other riders and world
objects retain their collisions; no map part is edited. Only anchored BaseParts
qualify. Terrain voxels and moving obstacles retain native collision behavior.

During a crossing, the server smoothly advances the chassis height toward the
sampled support envelope using a world-Y-only LinearVelocity constraint. Targets
follow a critically damped curve with bounded acceleration (24 studs/s²) and
vertical speed (6 studs/s). Feed-forward velocity and position tracking avoid
amplifying small support errors by dividing them by frame time. Anticipation is
0.25 seconds, capped at 16 studs, giving the chassis time to ease onto the top.
Height integration is substepped and tested at 30/60/120 Hz. Targets
are calculated before simulation; native physics and replication move and
interpolate the articulated rig. Gameplay does not call PivotTo or overwrite
assembly velocities each tick. It preserves horizontal velocity,
native drive forces, steering and server ownership. Ground orientation stays
level through the ledge rather than pitching the deck into it. Both tires can
temporarily leave physical support while the verified local surfaces provide
virtual drive support. Unsupported flight cannot start traversal. Small downward
edges require two sampled flat surfaces within the same height budget.

The actual suspension hinges use bounded Servo targets for a separate front/rear
compression pulse. Springs are temporarily disabled so their load does not launch
the chassis; their original enabled states and hinge actuator settings return
after the crossing. The pulse eases back before releasing this presentation mode.
Its neutral angle is captured under the mounted rider's load, rather than
returning to an unloaded calibration angle.
Compression has a timed 0.12-second attack, 0.08-second hold and 0.4-second
release, so fast crossings still show shock travel. Servo torque scales with
rider/rig mass; a fixed weak torque previously failed to move the loaded arms.
Support changes from 0.06 studs can trigger the animation.
`ScooterSpringVisuals` draws local noncolliding coil and wheel copies outside the
replicated mechanism. It filters shock anchors relative to the chassis, scales
coil length and integrates wheel rotation every rendered frame from forward
speed and radius (native spin during burnout). This removes solver/replication
vibration without delaying the chassis world movement. Originals are locally
hidden only while these copies are shown; scopes restore visibility and remove
copies when models disappear. Every client draws nearby visible riders;
no client obstacle decisions or new remotes are involved.
Wheel centers also have a 2-stud/s visual suspension travel limit. Their rest
transform comes from the wheel's local hinge attachment, avoiding unsettled
spawn poses being captured as an eccentric rotation offset.
Rendering runs at the Last render priority, after camera/character updates,
so copies use the final chassis pose rather than a different phase of the frame.

Steering uses softer hinge response (24), input smoothing (9/s), measured wheel
steering smoothing (8/s), and yaw smoothing (10/s) with an acceleration cap of
400 degrees/s². The heading and heading-lead limit share the same smoothed yaw.
Release explicitly targets zero. Lateral grip now eases slip away at 10/s while
retaining the existing 100-stud/s² cap, instead of cancelling it within one tick.

Dismount, death, input reset, wheelie, falling, destroyed models and the bounded
crossing timeout clear collision pairs and restore suspension settings. Wheelie
and burnout retain the existing controller. High walls still use normal collision
and crash detection. Catalog tuning, ECO/SPORT and upgrade rules are unchanged.

The retained force-based controller is selected with ArcadeSteps.Enabled=false
for recovery/development and legacy service-double regressions. Nothing changes
the manually authored Workspace.Map or replaces the installed scooter asset.
The Studio server contained upgrade integration ahead of Git at implementation
time; only the arcade changes were applied to that script, preserving that code.
Studio's duplicate nested configuration was restored to the repository wrapper
which requires the canonical Shared.ScooterConfig, so tuning has one source.

## Verification

Run the focused numerical regression:

```sh
python3 tests/run_scooter_tests.py --arcade-only --luau /path/to/luau
```

Paste `tests/scooter_arcade_steps.studio.luau` into the Server Command Bar in a
fresh one-player Studio Play session. Results appear on
`Workspace._ScooterArcadeStepsQA`. This creates temporary geometry outside Map
and sends ordinary validated drive input from a temporary LocalScript. Stop Play
afterward to remove automation and fixtures and restore normal controls.

The CLI checks bounded, monotonic height response and settling at 30/60/120 Hz.
Native Play checks starts, rolling entry, forward/reverse, oblique/glancing entry,
coasting, rounded bumps, downward edges, rider retention, chassis pitch and
collision-mask cleanup; a 3-stud wall must remain blocked. Inspect the visible
shock travel and coils as well. Test subjective camera feel, repeated map curbs,
different avatars and two-client observation manually.

Paste `tests/scooter_motion.studio.luau` into the Server Command Bar in a fresh
Play session, keeping the Client viewport foreground. Its CLIENT-only
`Workspace._ScooterCurbPerfResults` compares moving frames on a flat road and
during active crossings. `Passed` rejects a high frozen-frame ratio or a large
movement jump relative to speed and frame time. This catches replication
stutter that the server's pitch and collision checks cannot detect.

The first implementation moved the whole model with PivotTo in PostSimulation.
That preserved server-side pitch but broke client motion interpolation: 9 of
18 sampled active frames had no position change, followed by a jump of up to
12.59 studs, while rendering remained approximately 60 FPS. Replacing these
teleports with the vertical velocity constraint yielded zero frozen active
frames out of 20, with a maximum movement of 1.35 studs per frame. Ordinary
road travel also had zero frozen frames out of 405 in the same corrected run.
The saved motion regression also passed on a repeat: zero frozen frames out of
18 active and 407 native frames, with maximum active movement of 1.32 studs.

Implementation verification: all 13 native scenarios passed in the connected
Studio with the installed scooter and its existing upgrade integration. The
measured pitch stayed below 0.005 degrees across the sampled crossings and
their recovery interval; no collision masks remained afterward. The focused
CLI passed 1,695 assertions, Roblox-aware Luau analysis passed, and Rojo built
the project. Local animated coils were observed updating between shock anchors.
Additional native checks passed for dismount during traversal (collision masks,
springs and hinge actuators restored) and replacement of an active scooter.
Native vertical velocity after returning to passive suspension can still vary;
the authored height path suppresses the curb impact during active traversal.

The smooth-feel follow-up passes 8,332 focused numerical assertions, including
acceleration bounds on height retargeting and yaw reversals at 30/60/120 Hz.
Native shock travel measures roughly 8–14 degrees and 0.06–0.09 studs of spring
length change. A fresh client motion test records zero frozen frames among 60
active and 363 ordinary-road frames at approximately 60 FPS; maximum active
movement is 1.53 studs and 1.03 times speed times frame duration.
`tests/scooter_handling.studio.luau` separately checks full left/right/release,
rider retention, neutral yaw, four visible local copies and wheel-center
continuity in chassis space. Its results live on the CLIENT under
`Workspace._ScooterHandlingResults`. Keep the client foreground and stop Play
after testing. These fixtures do not replace multiplayer latency testing.
The final handling run passed all four phases (115–152 rendered frames each),
with four visible copies, wheel-center movement below 0.035 stud per frame and
neutral yaw below 0.006 rad/s. Earlier raw PreRender ordering mixed poses from
different frame phases and reported jumps; the explicit rendering order fixes
that synchronization and the observer samples immediately afterward.

The pre-existing general CLI suite fails after its first 229 runtime assertions
at an undefined `make` helper in scooter_visuals.spec.luau; this failure predates
the arcade change. It is separate from the focused checks and native solver tests.
