# KuKirin scale comparisons and crosswalk contact — 2026-10-05

`ScooterWorkflow.InstallScaleVariants()` rebuilds the two sizes from the preserved
`ServerStorage.ScooterAuthoring.ScooterFinal`, using the accepted whole-front
steering layout. It prepares both before replacing templates and archives previous
templates in ScooterTemplateBackups. The accepted 0.30 draft/source are preserved.

| Scale | Template | Selection in Studio Play |
| --- | --- | --- |
| 0.20 | ServerStorage.ScooterModels.scooter_scale020 | E at KuKirin 0,20 |
| 0.25 | ServerStorage.ScooterModels.scooter | E at KuKirin 0,25; default spawn |

The user selected 0.25. Comparison displays are now disabled by default; set
`ScooterConfig.StudioScaleComparisonEnabled = true` to enable the two anchored
displays beside SpawnLocation in Studio Play again. Both templates are retained. E requests the selected playable scooter at the normal scooter spawn;
then use its usual E ride prompt. Dismount before changing size. Spawn requests
share the existing three-second cooldown, ownership and alive-character checks.
The server checks prompt proximity; a separate Studio-only, whitelisted server
method chooses the template. Client RequestSpawn still accepts only owned shop
models. There are no new shop products, remotes, purchases or profile fields.
Display connections and models are cleaned up with the initializer.

Each size has freshly placed joints, grip/foot targets, wheel/deck contacts and
individually calibrated spring travel. Chassis mass remains 12 and reference
rider mass 40; shrinking a prepared runtime model would incorrectly scale those
properties. The full front assembly retains the approved coupled steering.
The builder now defaults to the selected 0.25. The earlier accepted 0.30 review
draft remains archived unchanged; the comparison generator still explicitly
supplies 0.20 and 0.25.

## Cause of the crosswalk blockage

The imported `Zebra crossing lines` models contain 35 colliding paper-thin Parts
(rendered thickness about 0.0013 stud). On the crossing around X=213, measured
paint heights are 0.11–0.51 stud above the road. Physical collision thickness can
also exceed rendered thickness. These are floating plates, not continuous road
surfaces: low curb-face rays can pass underneath while the round tire catches a
plate edge. Extending those rays or increasing torque cannot resolve that missed
contact reliably.

The explicit Edit tool `ServerScriptService.Map.DevRoadPaint.MakeCrosswalksDecorative(workspace.Map)`
disables collision on those named paint groups only. Applied to the active Studio
map, it changed 35 Parts; it preserves their transforms, appearance, road and
sidewalk collisions. `RoadPaintPreviousCanCollide` records each original flag.
The repair is idempotent and is never run automatically at server startup. Save
the place to persist these authored property changes and the templates; the tool
and generation settings are versioned in Git.

During comparison, the smaller tire needed a radius-based climb allowance of 1.6 instead of
1.35. At scale 0.20, the old allowance was below the authored one-stud sidewalk,
so it rejected a genuine curb even with correct ray detection. MaxStepHeight
was 1.6 studs during that pass. The subsequent accepted arcade handling raises
the limit to 2.5; see [SCOOTER_ARCADE_HANDLING.md](SCOOTER_ARCADE_HANDLING.md). This remains a
bounded gameplay assist on the tire, through the existing hinges and springs.

## Verification

Native Play reproduced a blocked 0.25 scooter on the X=213 crossing with W held,
zero speed and no step support. Disabling only stripe collision let the same
scooter leave the same position. Both sizes then crossed the painted area.
With the new radius allowance, 0.20 launched from rest against the actual one-stud
sidewalk at a 30-degree approach; both tires climbed and the rider stayed mounted.
0.25 crossed the painted section and sidewalk under the same angled approach.
Both real E selection prompts replaced the active owned scooter correctly.

753 CLI assertions pass, including small-tire curb limits and rejection of
production/unknown scale requests. The native scale fixture verifies both models'
seven hinges, two calibrated springs, 21 meshes, alignment, proportional sizes,
chassis mass and grip positions. Roblox-aware type analysis and Rojo build pass.
Temporary automation affected Play only; Studio is left in Edit for manual tests.
Further map acceptance remains useful for other imported assets and avatar sizes.
