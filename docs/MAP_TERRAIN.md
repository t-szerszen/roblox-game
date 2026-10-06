# Expanded Studio terrain

The October 2026 authoring pass expands the grass field to nine 2048x2048 regions,
forming a 6144x6144 square centered at `(72, 0, -1484)`. The flat field spans
X `[-3000, 3144]` and Z `[-4556, 1588]`. An additional 768-stud mountain belt
surrounds all four sides and corners, for a total terrain footprint of 7680x7680.
The flat surface stays at Y=0. The foundation extends to Y=-128, with Grass on
top and Ground underneath. New top cells match the original 0.5 occupancy so
native terrain filling does not introduce a two-stud raised seam. Grass also
extends beneath the old surface to match material blending. Existing surface voxels, small hills, material colors,
roads, buildings and other authored instances are preserved.

The mountain belt uses a continuous noise height field with grassy foothills,
Ground/Rock on steep slopes and snow above an irregular snow line. Heights vary
up to the recipe's 560-stud cap. The belt joins the flat field continuously and
returns to ground level outside the ridge. Invisible anchored collision walls
behind the ridge prevent players from reaching the outer drop, including through
the shallow subsurface. They live in `Workspace.TerrainExpansion.MountainBoundary`,
separately from `Workspace.Map` and its model placement serializer.

This supplies terrain volume suitable for excavation tools. It does not add a
digging gameplay system or make digging possible without such a system.

## Authoring and recovery

`Map/TerrainExpansionData.luau` is the versioned authoring recipe.
`Map/DevTerrainExpand.luau` is an explicit Edit-mode tool. Neither is invoked at
server startup; the manually authored `Workspace.Map` remains authoritative.
Rojo does not synchronize Workspace terrain. Save the edited place in Studio to
persist the actual voxel terrain and its backup. The recipe is not a replacement
for the saved place or for versioning the authored model placements in MapData.

To apply the recipe to the original two-tile terrain in a recovered place, use a
fresh tool require (clone the module and its data together, as MapWorkflow does):

```lua
local folder = Instance.new("Folder")
folder.Name = "_TerrainExpansionReload"
folder.Parent = game.ServerScriptService
for _, name in { "TerrainExpansionData", "DevTerrainExpand" } do
    game.ServerScriptService.Map[name]:Clone().Parent = folder
end
local tool = require(folder.DevTerrainExpand)
tool.Start()
```

`Start()` yields between four-chunk batches. Progress and any failure are exposed
on `Workspace.TerrainExpansion` through `Status`, `CompletedChunks`, `TotalChunks`
and `Error` attributes. `Begin()` followed by `Step(1..32)` is also available for
manual batching. A second application is rejected to protect the original backup.
Remove the reload folder after the background operation finishes.

Each chunk is copied before modification into
`ServerStorage.TerrainExpansionBackup`, with its original voxel corner recorded
as an attribute. Keep this backup until accepting the edit. To undo the expansion,
use a fresh require of the same recipe version, then:

```lua
tool.Restore()
```

Restore pastes original materials, occupancies and empty cells, removes the added
boundaries and progress marker, and deletes the consumed backup. It works after a
partial failure as well. Restoring also overwrites subsequent terrain edits within
the backed-up footprint; save the current place first if those edits are needed.
The tool creates Studio history waypoints on completion and restoration.

## Verification

`tests/terrain_expansion.studio.luau` exercises the actual module with a small
isolated terrain fixture in Edit mode before applying the production expansion.
Its 100 assertions cover all nine fields, exact new surface height, foundation depth, original hill height,
sides/corners, boundary collision, repeated-call rejection, authored Map
preservation and exact restoration of all material/occupancy values. The fixture
restores its original region and removes temporary modules when finished.

Production checks passed for 128 original surface samples, 448 new flat-field
samples, 42 seam samples, 220 mountain ridge samples and the foundation under all
nine tile centers. No original surface height/material changed. Before Play, all
27,706 pre-existing BaseParts matched their original count, position sum and size
sum. After returning to Edit, part counts, size sums and all 22,206 authored Map
descendants still matched. Ridge samples had heights approximately 277–562
studs, including Terrain surface interpolation above the 560-stud voxel cap.
Studio overview/detail captures verified the mountain appearance.

Native Play confirmed normal spawn, a healthy character standing on Grass in a
new field, collision against a hidden perimeter wall above the ridge, and a
temporary excavation at Y=-64. The excavation was restored and Play was stopped;
the Edit-mode terrain stayed intact. Luau type analysis and a Rojo build passed
without enabling runtime generation.
