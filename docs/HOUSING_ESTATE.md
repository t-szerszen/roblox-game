# Osiedle Parkowe: reversible Studio draft

The estate is an explicitly authored scene at `Workspace.Map.Osiedle_Parkowe`,
west of the existing city, centered at `(-1660, 0, -850)`. Its reserved site is
900x1000 studs and was empty before construction. Existing map assets and Terrain
are not moved, recolored, removed or overwritten.

The scene contains:

- Four 131-stud apartment towers cloned from the existing `HDB flat` model.
- Four 56-stud low slabs, each with two stairwell sections assembled from the
  original ground module and five existing floor modules, with enclosed ground
  floors and flat roofs. Source geometry is preserved on the original buildings.
- A central park with 56 trees, trimmed hedges, paths, a paved square and 16
  benches. Existing tree and bench models are reused.
- Two playgrounds reusing the existing wooden playforts, with separate surfaces
  and low fences, plus a small basketball court and a neighborhood seating square.
- An access street loop, sidewalks, pedestrian crossings, four parking courts
  with 56 marked spaces, four covered recycling/bin areas and 28 street lamps.

Colors are muted concrete, cream, sage, blue-gray and terracotta accents rather
than the source tower's bright yellow. Changes apply only to the new copies.
The east entrance ends within the reserved empty site; extending it into the
existing city road network is a separate manual authoring step.

## Build and undo

`HousingEstateData.luau` records the footprint, positions, variants, source asset
paths and palette. `DevHousingEstate.luau` resolves the live Studio assets,
validates a flat empty site, builds in ServerStorage and publishes the completed
folder in one step. A failed build discards only its staging folder. Repeated
builds reject an existing estate instead of replacing authored work.

No scripts call this tool at server startup. The saved Studio place contains the
actual assets; Rojo synchronizes only the development tool and layout recipe.
Save the place after accepting the draft. The normal MapData model serializer
remains unchanged; it does not register these imported asset names as factories
in the mock AssetRegistry.

To remove everything added by this tool, delete only
`Workspace.Map.Osiedle_Parkowe` in Explorer, or run in the Edit-mode Command Bar:

```lua
require(game.ServerScriptService.Map.DevHousingEstate).Remove()
```

`Remove()` checks the dedicated folder and its `AuthoringTool` marker before
deleting it. It cannot remove the parent Map folder or an unmarked folder. Because
the estate contains every new instance and there are no Terrain edits, removal
does not require restoring terrain or existing buildings. Studio history
waypoints are also recorded for building and removing the estate.

To rebuild from the current recipe and existing source assets, use a fresh require:

```lua
local reload = Instance.new("Folder")
reload.Name = "_HousingEstateReload"
reload.Parent = game.ServerScriptService
for _, name in { "HousingEstateData", "DevHousingEstate" } do
    game.ServerScriptService.Map[name]:Clone().Parent = reload
end
local ok, result = pcall(function()
    return require(reload.DevHousingEstate).Build()
end)
reload:Destroy()
assert(ok, result)
```

The new asset copies are static, anchored scenery. Inherited playground scripts,
welds, constraints and legacy movers are removed from the copies before they
enter Workspace. Existing scripts and source models are untouched. Engine Seats
are retained on benches and playground equipment; scripted slide/swing behavior
is not added by this authoring pass. No remotes, economy or progression change.

## Acceptance

`tests/housing_estate.studio.luau` runs against an existing draft in Edit mode. It
verifies repeated-build rejection, ownership protection, complete removal,
preservation of each original BasePart's parent/CFrame/size/color/anchored state,
rebuilding, terrain preservation, building separation, scenery anchoring and
script stripping. It finishes with the latest estate rebuilt in Workspace.

The final draft passed 60 native Studio assertions. Removal restored the original
27,722 BaseParts, including the mountain boundaries. Rebuilding left every
original part unchanged. The estate adds 11,513 anchored parts, contains no
LuaSourceContainers, and retains 40 engine Seats. Luau type analysis, Rojo build
and diff whitespace checks passed. An initial Studio overview verified the block
layout, playground pads, parking and green central area. Native Play confirmed
healthy character support on the central plaza, entrance sidewalk and asphalt
street, as well as real collision with the copied slab facade. The final
promenade approaches and both playground bypasses were also verified in Play;
they route outside the fenced playgrounds and around the basketball court.
The test character was returned to its original position, and Studio was left
in Edit mode with the final estate intact.
