--!strict

local AssetRegistry = {}

local COLORS = {
	Road = Color3.fromRGB(58, 64, 72),
	RoadMarking = Color3.fromRGB(245, 220, 130),
	SmallBuilding = Color3.fromRGB(226, 164, 116),
	TallBuilding = Color3.fromRGB(126, 163, 190),
	Roof = Color3.fromRGB(74, 82, 98),
	Window = Color3.fromRGB(255, 224, 145),
	Grass = Color3.fromRGB(111, 174, 104),
	TreeTrunk = Color3.fromRGB(115, 79, 55),
	TreeCanopy = Color3.fromRGB(63, 132, 82),
}

local function makePart(
	parent: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
		if shape == Enum.PartType.Cylinder then
			part.Orientation = Vector3.new(0, 0, 90)
		end
	end
	part.Parent = parent
	return part
end

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = CFrame.identity
	return model
end

local function makeWedge(parent: Model, name: string, size: Vector3, position: Vector3, color: Color3): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Anchored = true
	wedge.Size = size
	wedge.Position = position
	wedge.Color = color
	wedge.Material = Enum.Material.Slate
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

local function createRoad(): Model
	local model = newModel("Road")
	local asphalt = makePart(
		model,
		"Asphalt",
		Vector3.new(80, 1, 12),
		Vector3.new(0, -0.5, 0),
		COLORS.Road,
		Enum.Material.Slate
	)
	asphalt.CanTouch = false
	asphalt.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 10, 10)
	local centerLine = makePart(
		model,
		"CenterLine",
		Vector3.new(72, 0.08, 0.35),
		Vector3.new(0, 0.04, 0),
		COLORS.RoadMarking,
		Enum.Material.SmoothPlastic
	)
	centerLine.CanCollide = false
	centerLine.CanTouch = false
	centerLine.CanQuery = false
	return model
end

local function addWindows(model: Model, width: number, height: number, floorCount: number, color: Color3)
	local floorHeight = height / floorCount
	for floor = 1, floorCount do
		local y = floorHeight * (floor - 0.5)
		for _, x in ipairs({ -width * 0.28, 0, width * 0.28 }) do
			makePart(
				model,
				"Window",
				Vector3.new(2.2, 2.4, 0.12),
				Vector3.new(x, y, -9.06),
				color,
				Enum.Material.Glass
			)
		end
	end
end

local function createBuilding(name: string, height: number, color: Color3, floorCount: number): Model
	local model = newModel(name)
	local width = 18
	makePart(model, "BuildingBody", Vector3.new(width, height, width), Vector3.new(0, height / 2, 0), color, Enum.Material.SmoothPlastic)
	if name == "Building_Small" then
		makeWedge(model, "PitchedRoof", Vector3.new(width + 1, 5, width + 1), Vector3.new(0, height + 2.5, 0), COLORS.Roof)
	else
		makePart(model, "Roof", Vector3.new(width + 1, 1.5, width + 1), Vector3.new(0, height + 0.75, 0), COLORS.Roof, Enum.Material.Slate)
	end
	addWindows(model, width, height, floorCount, COLORS.Window)
	return model
end

local function createPark(): Model
	local model = newModel("Park_Grass")
	makePart(model, "Grass", Vector3.new(22, 1, 22), Vector3.new(0, -0.5, 0), COLORS.Grass, Enum.Material.Grass)
	for _, position in ipairs({ Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) }) do
		makePart(model, "TreeTrunk", Vector3.new(4, 1.2, 1.2), position + Vector3.new(0, 2, 0), COLORS.TreeTrunk, Enum.Material.Wood, Enum.PartType.Cylinder)
		makePart(model, "TreeCanopy", Vector3.new(4.5, 4.5, 4.5), position + Vector3.new(0, 5, 0), COLORS.TreeCanopy, Enum.Material.Grass, Enum.PartType.Ball)
	end
	return model
end

local function createSpawn(): Model
	local model = newModel("Spawn")
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "SpawnLocation"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(0, 0.5, 0)
	spawnLocation.Color = Color3.fromRGB(85, 190, 120)
	spawnLocation.Material = Enum.Material.SmoothPlastic
	spawnLocation.Neutral = true
	spawnLocation.Enabled = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = model
	return model
end

local function anchorAllParts(model: Model): Model
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	return model
end

function AssetRegistry.Create(assetId: string): Model
	if assetId == "Road" then
		return anchorAllParts(createRoad())
	elseif assetId == "Building_Small" then
		return anchorAllParts(createBuilding("Building_Small", 16, COLORS.SmallBuilding, 3))
	elseif assetId == "Building_Tall" then
		return anchorAllParts(createBuilding("Building_Tall", 38, COLORS.TallBuilding, 7))
	elseif assetId == "Park_Grass" then
		return anchorAllParts(createPark())
	elseif assetId == "Spawn" then
		return anchorAllParts(createSpawn())
	end

	error(string.format("Unknown map asset ID: %s", assetId), 2)
end

return AssetRegistry
