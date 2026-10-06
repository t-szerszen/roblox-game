--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Data = require(script.Parent.TerrainExpansionData)

local terrain = workspace.Terrain
local MARKER_NAME = "TerrainExpansion"
local BACKUP_NAME = "TerrainExpansionBackup"
local halfSize = Data.TileSize * Data.TilesPerAxis / 2
local outerHalfSize = halfSize + Data.MountainWidth
local minimum = Data.Center - Vector3.new(outerHalfSize, Data.Depth, outerHalfSize)
local maximum = Data.Center + Vector3.new(outerHalfSize, Data.MountainHeight + Data.Resolution, outerHalfSize)
local chunksPerAxis = outerHalfSize * 2 / Data.ChunkSize
local totalChunks = chunksPerAxis * chunksPerAxis

local DevTerrainExpand = {}

local function assertEdit(): ()
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Terrain authoring requires Studio Edit mode")
end

local function heightAt(x: number, z: number): number
	local distance = math.max(math.abs(x - Data.Center.X), math.abs(z - Data.Center.Z)) - halfSize
	if distance <= 0 or distance >= Data.MountainWidth then
		return 0
	end

	local t = distance / Data.MountainWidth
	local envelope = math.sin(math.pi * t) ^ 1.35
	local broad = math.noise(x / 680, z / 680, Data.Seed)
	local ridges = 1 - math.abs(math.noise(x / 245, z / 245, Data.Seed + 11)) * 2
	local detail = math.noise(x / 85, z / 85, Data.Seed + 29)
	return math.clamp(envelope * (350 + broad * 175 + ridges * 150 + detail * 32), 0, Data.MountainHeight)
end

local function fillBounds(low: Vector3, high: Vector3, material: Enum.Material): ()
	if high.X <= low.X or high.Y <= low.Y or high.Z <= low.Z then
		return
	end
	terrain:FillBlock(CFrame.new((low + high) / 2), high - low, material)
end

local function grassOutsideOriginal(low: Vector3, high: Vector3): ()
	local oldLow, oldHigh = Data.OriginalMin, Data.OriginalMax
	-- Preserve authored surface voxels and small hills on the original two tiles.
	fillBounds(Vector3.new(low.X, -Data.GrassDepth, low.Z), Vector3.new(math.min(high.X, oldLow.X), -4, high.Z), Enum.Material.Grass)
	fillBounds(Vector3.new(math.max(low.X, oldHigh.X), -Data.GrassDepth, low.Z), Vector3.new(high.X, -4, high.Z), Enum.Material.Grass)
	local innerLowX, innerHighX = math.max(low.X, oldLow.X), math.min(high.X, oldHigh.X)
	fillBounds(Vector3.new(innerLowX, -Data.GrassDepth, low.Z), Vector3.new(innerHighX, -4, math.min(high.Z, oldLow.Z)), Enum.Material.Grass)
	fillBounds(Vector3.new(innerLowX, -Data.GrassDepth, math.max(low.Z, oldHigh.Z)), Vector3.new(innerHighX, -4, high.Z), Enum.Material.Grass)
	-- Match the original 0.5-occupancy surface: a full top voxel renders two studs higher.
	local region = Region3.new(Vector3.new(low.X, -4, low.Z), Vector3.new(high.X, 0, high.Z))
	local materials, occupancy = terrain:ReadVoxels(region, Data.Resolution)
	for x = 1, #materials do
		local worldX = low.X + (x - 0.5) * Data.Resolution
		for z = 1, #materials[x][1] do
			local worldZ = low.Z + (z - 0.5) * Data.Resolution
			if worldX < oldLow.X or worldX >= oldHigh.X or worldZ < oldLow.Z or worldZ >= oldHigh.Z then
				materials[x][1][z] = Enum.Material.Grass
				occupancy[x][1][z] = 0.5
			end
		end
	end
	terrain:WriteVoxels(region, Data.Resolution, materials, occupancy)
end

local function mountainChunk(low: Vector3, high: Vector3): ()
	local resolution = Data.Resolution
	local count = Data.ChunkSize / resolution
	local heights: { { number } } = {}
	local smallest, largest = math.huge, 0
	for x = 1, count do
		local column = table.create(count)
		heights[x] = column
		for z = 1, count do
			local height = heightAt(low.X + (x - 0.5) * resolution, low.Z + (z - 0.5) * resolution)
			column[z] = height
			smallest = math.min(smallest, height)
			largest = math.max(largest, height)
		end
	end
	if largest == 0 then
		return
	end

	-- Native fills handle the solid core; only the varied surface needs Lua voxel arrays.
	local bottom = math.max(0, math.floor((smallest - 16) / resolution) * resolution)
	local top = math.ceil(largest / resolution) * resolution + resolution
	fillBounds(Vector3.new(low.X, 0, low.Z), Vector3.new(high.X, bottom, high.Z), Enum.Material.Rock)
	local region = Region3.new(Vector3.new(low.X, bottom, low.Z), Vector3.new(high.X, top, high.Z))
	local materials, occupancy = terrain:ReadVoxels(region, resolution)
	for x = 1, count do
		local worldX = low.X + (x - 0.5) * resolution
		for z = 1, count do
			local height = heights[x][z]
			local worldZ = low.Z + (z - 0.5) * resolution
			local dx = heightAt(worldX + resolution, worldZ) - heightAt(worldX - resolution, worldZ)
			local dz = heightAt(worldX, worldZ + resolution) - heightAt(worldX, worldZ - resolution)
			local slope = math.sqrt(dx * dx + dz * dz) / (resolution * 2)
			local surface = Enum.Material.Grass
			if height > 420 + math.noise(worldX / 120, worldZ / 120, Data.Seed) * 40 then
				surface = Enum.Material.Snow
			elseif height > 210 or slope > 1.05 then
				surface = Enum.Material.Rock
			elseif slope > 0.7 then
				surface = Enum.Material.Ground
			end
			for y = 1, #materials[x] do
				local cellBottom = bottom + (y - 1) * resolution
				local amount = math.clamp((height - cellBottom) / resolution, 0, 1)
				if amount > occupancy[x][y][z] then
					occupancy[x][y][z] = amount
					materials[x][y][z] = cellBottom >= height - 12 and surface or Enum.Material.Rock
				end
			end
		end
	end
	terrain:WriteVoxels(region, resolution, materials, occupancy)
end

local function addBoundaries(marker: Folder): ()
	local folder = Instance.new("Folder")
	folder.Name = "MountainBoundary"
	folder.Parent = marker
	local extent = halfSize + Data.BoundaryOffset
	local segmentCount = math.ceil(extent * 2 / Data.TileSize)
	local length = extent * 2 / segmentCount
	for side = 1, 4 do
		for segment = 1, segmentCount do
			local along = -extent + (segment - 0.5) * length
			local wall = Instance.new("Part")
			wall.Name = string.format("Boundary_%d_%d", side, segment)
			wall.Anchored = true
			wall.Transparency = 1
			wall.CastShadow = false
			wall.CanTouch = false
			wall.Locked = true
			local y = (Data.BoundaryHeight - Data.Depth) / 2
			if side <= 2 then
				wall.Size = Vector3.new(8, Data.BoundaryHeight + Data.Depth, length + 8)
				wall.Position = Data.Center + Vector3.new(side == 1 and -extent or extent, y, along)
			else
				wall.Size = Vector3.new(length + 8, Data.BoundaryHeight + Data.Depth, 8)
				wall.Position = Data.Center + Vector3.new(along, y, side == 3 and -extent or extent)
			end
			wall.Parent = folder
		end
	end
end

function DevTerrainExpand.Begin(): Folder
	assertEdit()
	assert(not workspace:FindFirstChild(MARKER_NAME), "Expansion already exists; restore before applying again")
	assert(not ServerStorage:FindFirstChild(BACKUP_NAME), "Existing terrain backup must be retained or restored first")
	assert(workspace:FindFirstChild("Map"), "The authored Workspace.Map must already exist")
	local backup = Instance.new("Folder")
	backup.Name = BACKUP_NAME
	backup:SetAttribute("RecipeVersion", Data.Version)
	backup.Parent = ServerStorage
	local marker = Instance.new("Folder")
	marker.Name = MARKER_NAME
	marker:SetAttribute("RecipeVersion", Data.Version)
	marker:SetAttribute("CompletedChunks", 0)
	marker:SetAttribute("TotalChunks", totalChunks)
	marker:SetAttribute("Status", "Building")
	marker:SetAttribute("MapSize", Data.TileSize * Data.TilesPerAxis)
	marker:SetAttribute("Depth", Data.Depth)
	marker.Parent = workspace
	return marker
end

function DevTerrainExpand.Step(chunkBudget: number): boolean
	assertEdit()
	assert(chunkBudget >= 1 and chunkBudget <= 32 and chunkBudget % 1 == 0, "Chunk budget must be an integer from 1 to 32")
	local marker = workspace:FindFirstChild(MARKER_NAME)
	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	assert(marker and marker:IsA("Folder") and backup, "Call Begin() first")
	local completed = marker:GetAttribute("CompletedChunks") :: number
	for index = completed, math.min(completed + chunkBudget, totalChunks) - 1 do
		local xIndex, zIndex = math.floor(index / chunksPerAxis), index % chunksPerAxis
		local low = minimum + Vector3.new(xIndex * Data.ChunkSize, 0, zIndex * Data.ChunkSize)
		local high = Vector3.new(low.X + Data.ChunkSize, maximum.Y, low.Z + Data.ChunkSize)
		local region = Region3int16.new(
			Vector3int16.new(low.X / Data.Resolution, low.Y / Data.Resolution, low.Z / Data.Resolution),
			Vector3int16.new(high.X / Data.Resolution - 1, high.Y / Data.Resolution - 1, high.Z / Data.Resolution - 1)
		)
		local original = terrain:CopyRegion(region)
		original.Name = string.format("Chunk_%04d", index)
		original:SetAttribute("Corner", Vector3.new(region.Min.X, region.Min.Y, region.Min.Z))
		original.Parent = backup
		backup:SetAttribute("SavedChunks", index + 1)
		fillBounds(low, Vector3.new(high.X, -Data.GrassDepth, high.Z), Enum.Material.Ground)
		-- Existing half-filled top cells stay untouched, including their surface elevation.
		local innerLowX, innerHighX = math.max(low.X, Data.OriginalMin.X), math.min(high.X, Data.OriginalMax.X)
		local innerLowZ, innerHighZ = math.max(low.Z, Data.OriginalMin.Z), math.min(high.Z, Data.OriginalMax.Z)
		fillBounds(Vector3.new(innerLowX, -Data.GrassDepth, innerLowZ), Vector3.new(innerHighX, -4, innerHighZ), Enum.Material.Grass)
		grassOutsideOriginal(low, high)
		mountainChunk(low, high)
		marker:SetAttribute("CompletedChunks", index + 1)
	end
	if marker:GetAttribute("CompletedChunks") == totalChunks then
		if not marker:FindFirstChild("MountainBoundary") then
			addBoundaries(marker)
		end
		marker:SetAttribute("Status", "Complete")
		ChangeHistoryService:SetWaypoint("Expand grass terrain to 3x3 with mountains")
		return true
	end
	return false
end

function DevTerrainExpand.Restore(): ()
	assertEdit()
	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	assert(backup, "No terrain expansion backup exists")
	assert(backup:GetAttribute("RecipeVersion") == Data.Version, "Backup recipe version differs")
	for _, original in backup:GetChildren() do
		assert(original:IsA("TerrainRegion"), "Unexpected backup instance")
		local corner = original:GetAttribute("Corner") :: Vector3
		terrain:PasteRegion(original, Vector3int16.new(corner.X, corner.Y, corner.Z), true)
		task.wait()
	end
	local marker = workspace:FindFirstChild(MARKER_NAME)
	if marker then
		marker:Destroy()
	end
	backup:Destroy()
	ChangeHistoryService:SetWaypoint("Restore terrain before expansion")
end

function DevTerrainExpand.Start(): Folder
	local marker = DevTerrainExpand.Begin()
	task.defer(function()
		local ok, message = pcall(function()
			while not DevTerrainExpand.Step(4) do
				task.wait(0.05)
			end
		end)
		if not ok then
			marker:SetAttribute("Status", "Failed")
			marker:SetAttribute("Error", tostring(message))
			warn("Terrain expansion failed; retained backup can restore it: " .. tostring(message))
		end
	end)
	return marker
end

return DevTerrainExpand
