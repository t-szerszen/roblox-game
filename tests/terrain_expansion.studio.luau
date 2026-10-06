--!strict
-- Run in Studio Edit mode. Exercises the real authoring module on an isolated 80x80 fixture.
local ServerScriptService = game:GetService("ServerScriptService")
local terrain = workspace.Terrain
local center = Vector3.new(20000, 0, 20000)
local low = center - Vector3.new(48, 20, 48)
local high = center + Vector3.new(48, 60, 48)
local region = Region3.new(low, high)
local original = terrain:CopyRegion(Region3int16.new(
	Vector3int16.new(low.X / 4, low.Y / 4, low.Z / 4),
	Vector3int16.new(high.X / 4 - 1, high.Y / 4 - 1, high.Z / 4 - 1)
))
local reload = Instance.new("Folder")
reload.Name = "_TerrainExpansionTest"
reload.Parent = ServerScriptService
local recipe = Instance.new("ModuleScript")
recipe.Name = "TerrainExpansionData"
recipe.Source = [[return table.freeze({
	Version=1, Seed=73, TileSize=16, TilesPerAxis=3, Center=Vector3.new(20000,0,20000),
	Depth=16, GrassDepth=8, MountainWidth=16, MountainHeight=48, ChunkSize=16,
	Resolution=4, BoundaryOffset=12, BoundaryHeight=80,
	OriginalMin=Vector3.new(19992,-16,19984), OriginalMax=Vector3.new(20008,0,20016),
})]]
recipe.Parent = reload
local module = ServerScriptService.Map.DevTerrainExpand:Clone()
module.Parent = reload
local tool = require(module)
local checks = 0
local function check(value: boolean, message: string): ()
	assert(value, message)
	checks += 1
end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { terrain }
local function hit(x: number, z: number): RaycastResult?
	return workspace:Raycast(center + Vector3.new(x, 64, z), Vector3.new(0, -96, 0), params)
end
local ok, failure = pcall(function()
	check(not workspace:FindFirstChild("TerrainExpansion"), "Run fixture before production expansion")
	terrain:FillBlock(CFrame.new(center + Vector3.new(0, -1, 0)), Vector3.new(16, 2, 32), Enum.Material.Grass)
	terrain:FillBall(center + Vector3.new(3, 0, 3), 3, Enum.Material.Grass)
	task.wait(0.5)
	local beforeMaterials, beforeOccupancy = terrain:ReadVoxels(region, 4)
	local oldTop = hit(0, 0)
	assert(oldTop)
	local mapCount = #workspace.Map:GetDescendants()
	local marker = tool.Begin()
	check(marker:GetAttribute("TotalChunks") == 25, "Bounded chunk grid")
	check(not pcall(tool.Begin), "Repeated Begin rejects overwriting original backup")
	check(not pcall(tool.Step, 0), "Invalid chunk budgets rejected")
	while not tool.Step(4) do end
	task.wait(0.5)
	check(marker:GetAttribute("Status") == "Complete", "All chunks complete")
	check(#game.ServerStorage.TerrainExpansionBackup:GetChildren() == 25, "Every changed region backed up")
	check(#workspace.Map:GetDescendants() == mapCount, "Authored Map untouched")
	local afterTop = hit(0, 0)
	check(afterTop ~= nil and math.abs(afterTop.Position.Y - oldTop.Position.Y) < 0.001, "Original hill height preserved")
	for x = -20, 20, 8 do
		for z = -20, 20, 8 do
			local result = hit(x, z)
			check(result ~= nil and result.Material == Enum.Material.Grass, "Grass across all nine fields")
			if x < -8 or x >= 8 or z < -16 or z >= 16 then
				check(result ~= nil and math.abs(result.Position.Y) < 0.001, "New grass matches original Y=0 without a raised seam")
			end
		end
	end
	local materials, occupancy = terrain:ReadVoxels(Region3.new(center + Vector3.new(-4, -16, -4), center + Vector3.new(4, -4, 4)), 4)
	check(materials[1][1][1] == Enum.Material.Ground and occupancy[1][1][1] == 1, "Diggable foundation fills old terrain depth")
	for _, point in { Vector2.new(32, 0), Vector2.new(-32, 0), Vector2.new(0, 32), Vector2.new(0, -32), Vector2.new(32, 32) } do
		local result = hit(point.X, point.Y)
		check(result ~= nil and result.Position.Y > 0, "Continuous mountains on sides and corner")
	end
	for _, wall in marker.MountainBoundary:GetChildren() do
		check(wall:IsA("BasePart") and wall.Anchored and wall.CanCollide and wall.Transparency == 1, "Boundary collision behind ridge")
	end
	tool.Restore()
	local restoredMaterials, restoredOccupancy = terrain:ReadVoxels(region, 4)
	local same = true
	for x = 1, #beforeMaterials do
		for y = 1, #beforeMaterials[x] do
			for z = 1, #beforeMaterials[x][y] do
				if beforeMaterials[x][y][z] ~= restoredMaterials[x][y][z] or beforeOccupancy[x][y][z] ~= restoredOccupancy[x][y][z] then
					same = false
				end
			end
		end
	end
	check(same, "Restore reproduces every original material and occupancy including empty cells")
	check(not workspace:FindFirstChild("TerrainExpansion") and not game.ServerStorage:FindFirstChild("TerrainExpansionBackup"), "Restore removes its markers and boundaries")
end)
if workspace:FindFirstChild("TerrainExpansion") then
	tool.Restore()
end
terrain:PasteRegion(original, Vector3int16.new(low.X / 4, low.Y / 4, low.Z / 4), true)
original:Destroy()
reload:Destroy()
assert(ok, tostring(failure))
print(string.format("Terrain expansion: %d native Studio checks passed", checks))
return checks
