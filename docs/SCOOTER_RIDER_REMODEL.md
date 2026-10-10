# Scooter remodel around the accepted rider pose

On 2026-10-10 the user authorized rebuilding the complete scooter to fit the
current 8-stud avatar. The earlier visual-only shaft corrections left an obsolete
steering neck and connected the straight shaft behind its original mount.
Revision 3 replaces that inconsistent visual arrangement with a coherent body.

## Geometry and existing rig

`DevScooterRiderFit.Build` is an explicit Studio Edit-mode authoring operation.
Its input is the preserved installed large-wheel template **before** any
`ReferenceRiderFit` operation. Dimensions and finish live in
`DevScooterRiderFitConfig`; the final measurement snapshot is
`assets/scooter/rider-fit-components.json`. No asset generator runs at startup.

The accepted neutral grip positions are retained: 1.015 studs toward the rider
and 0.35 studs lower than the original large-wheel template. The original straight
shaft axis is retained and the shaft shortened along that axis. The entire front
module, its actual steering bearing, suspension arms, spring, wheel and contact
sphere move together approximately 1.077 studs toward the deck. Suspension
relative geometry, wheel sizes, shaft mass, spring settings and hinge settings
stay intact. The wheel-center separation changes from approximately 7.701 to
6.624 studs. Existing server steering uses the actual axle spacing; this geometric
change can affect the turning radius and balance, even though controller tuning,
throttle, braking and input validation have not been changed.

The old `ScooterBody` MeshPart remains the invisible mechanical attachment owner:
its mesh contains the old neck as one indivisible component. `RiderFitBody`
provides a new battery case, aligned rubber deck, side panels, orange edge trims,
two neck rails, crossmember and one steering head around the actual bearing.
These parts are massless decorations with collision/touch/query disabled, welded
only to the body assembly. The original wheels, fork, suspension, shaft, grips,
levers, lights, dashboard, rear kick plate, fender and kickstand are reused.

Root, FootRest support target, DriverSeat, native character SeatWeld and the
accepted avatar pose are unchanged. Deck contact height remains 0.11875 studs
above Root. The existing deck/rear-wheel collision proxies stay in place; the
front proxy moves with its tire. No new character scaling, animation clip,
wheelie, transition, steering animation or physics controller is introduced.

The new side panels carry the existing Deck customization group. The paint
helper accepts explicitly tagged solid-color parts as well as the existing
MeshPart/SurfaceAppearance targets, preserving other component colors and
texture-based customization. The original imported texture assets are retained.

## Installation and verification

The revised template is installed under `ServerStorage.ScooterModels.scooter`.
Previous templates are retained under `ServerStorage.ScooterTemplateBackups`,
including the untouched input for rebuilding. Save the Studio place to retain
this authored template; Rojo builds alone do not serialize native Studio assets.
The recipe and measured component manifest are versioned in Git.

`tests/scooter_rider_fit.studio.luau`.Run(previousTemplate) passes 139 native
assertions, including coherent front translation, matching tire/proxy centers,
original shaft direction and mass, shared hinge positions, visual deck height,
non-colliding body decorations, customization and detached mechanical steering
sweeps at -48, -20, 20 and 48 degrees. The current mounted base-pose test passes
91 assertions. Strict type analysis, bytecode compilation and Rojo build pass.

Side and front views were inspected in Play. A normal-throttle probe traveled
30.50 studs and reached 35.40 studs/s, with maximum palm error of 0.0112 studs on
the straight section. The actual servo reached approximately 17 degrees during
left steering, and the existing dismount remote released the rider.

The fixed-torso hand-reach limitation remains during steering: one measured
hand target error was 0.338 studs at approximately 11 degrees. The model's
mechanical connections remain coherent, but neutral-pose tests do not establish
perfect hand contact at all steering angles. Torso adaptation is a separate,
previously raised scope decision and has not been silently added. Fit across
other avatar proportions and two-client observation still need gameplay review.
