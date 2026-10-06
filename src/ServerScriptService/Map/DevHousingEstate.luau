--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Data = require(script.Parent.HousingEstateData)
local assetPaths = Data.Assets :: { [string]: string }

local DevHousingEstate = {}

local function assertEdit(): ()
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Housing estate authoring requires Studio Edit mode")
end

local function resolve(path: string): Instance
	local current: Instance = game
	for name in path:gmatch("[^.]+") do
		local child = current:FindFirstChild(name)
		assert(child, "Missing estate source asset: " .. path)
		current = child
	end
	return current
end

local function staticClone(source: Instance, name: string): Model
	local clone = source:Clone()
	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		assert(clone:IsA("BasePart"), "Estate assets must be Models or BaseParts")
		model = Instance.new("Model")
		clone.Parent = model
	end
	model.Name = name
	model.PrimaryPart = nil
	-- These are authored scenery copies; inherited playground scripts and welded
	-- physics must not introduce gameplay or retain references to the source scene.
	for _, child in model:GetDescendants() do
		if child:IsA("LuaSourceContainer") or child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("BodyMover") then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored = true
			child.AssemblyLinearVelocity = Vector3.zero
			child.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return model
end

local function place(model: Model, x: number, z: number, yaw: number, base: number): ()
	local box, size = model:GetBoundingBox()
	local target = CFrame.new(Data.Center + Vector3.new(x, base + size.Y / 2, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	model:PivotTo(target * box:Inverse() * model:GetPivot())
	model:SetAttribute("EstatePlacement", true)
end

local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = Data.Center + position
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function model(parent: Instance, name: string): Model
	local result = Instance.new("Model")
	result.Name = name
	result.Parent = parent
	return result
end

local function sign(parent: Instance, text: string, position: Vector3, width: number, yaw: number): ()
	local board = part(parent, "Tablica", Vector3.new(width, 2.5, 0.25), position, Data.Colors.Metal, Enum.Material.Metal)
	board.CFrame *= CFrame.Angles(0, math.rad(yaw), 0)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Napis"
	gui.CanvasSize = Vector2.new(512, 80)
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(239, 236, 222)
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.Parent = gui
end

local function paintBlock(block: Model, accent: Color3): ()
	for _, p in block:GetDescendants() do
		if p:IsA("BasePart") then
			local color = p.Color
			if color.R > 0.8 and color.G > 0.65 and color.B < 0.6 then
				p.Color = accent
				p.Material = Enum.Material.Concrete
			elseif color.R > 0.85 and color.G > 0.85 and color.B > 0.85 then
				p.Color = Data.Colors.Wall
				p.Material = Enum.Material.Concrete
			end
		end
	end
end

local function slab(source: Instance, name: string): Model
	assert(source:IsA("Model"), "Block source must be a Model")
	local result = Instance.new("Model")
	result.Name = name
	local _, originalSize = source:GetBoundingBox()
	for sectionIndex = 1, Data.SlabSections do
		local section = staticClone(source, "Klatka_" .. sectionIndex)
		local floors: { Model } = {}
		for _, child in section:GetChildren() do
			assert(child:IsA("Model"), "Expected the existing HDB floor module structure")
			table.insert(floors, child)
		end
		table.sort(floors, function(a: Model, b: Model): boolean
			return a:GetBoundingBox().Y < b:GetBoundingBox().Y
		end)
		assert(#floors > Data.FloorCount + 1, "Block source has insufficient floor modules")
		for index = Data.FloorCount + 2, #floors do
			floors[index]:Destroy()
		end
		local box, size = section:GetBoundingBox()
		local x = (sectionIndex - (Data.SlabSections + 1) / 2) * originalSize.X
		section:PivotTo(CFrame.new(x, size.Y / 2, 0) * box:Inverse() * section:GetPivot())
		section.Parent = result
		-- Enclose the original stilt base to give the low slab a residential ground floor.
		local base = Instance.new("Part")
		base.Name = "Parter"
		base.Anchored = true
		base.Size = Vector3.new(originalSize.X - 1, 11, originalSize.Z - 1)
		base.Position = Vector3.new(x, 5.5, 0)
		base.Color = Data.Colors.Wall
		base.Material = Enum.Material.Concrete
		base.Parent = result
		local door = Instance.new("Part")
		door.Name = "Wejscie"
		door.Anchored = true
		door.Size = Vector3.new(4, 7, 0.35)
		door.Position = Vector3.new(x, 3.5, -originalSize.Z / 2)
		door.Material = Enum.Material.Metal
		door.Color = Data.Colors.Metal
		door.Parent = result
	end
	local box, size = result:GetBoundingBox()
	local roof = Instance.new("Part")
	roof.Name = "PlaskiDach"
	roof.Anchored = true
	roof.Size = Vector3.new(size.X + 1, 0.8, size.Z + 1)
	roof.Position = Vector3.new(box.X, box.Y + size.Y / 2 + 0.4, box.Z)
	roof.Material = Enum.Material.Slate
	roof.Color = Data.Colors.Roof
	roof.Parent = result
	return result
end

local function road(parent: Instance, name: string, x: number, z: number, sx: number, sz: number): ()
	local m = model(parent, name)
	part(m, "Asfalt", Vector3.new(sx, 0.2, sz), Vector3.new(x, 0, z), Data.Colors.Road, Enum.Material.Asphalt)
	local longX = sx > sz
	for _, side in { -1, 1 } do
		local offset = (Data.RoadWidth + Data.SidewalkWidth) / 2
		local size = longX and Vector3.new(sx, 0.6, Data.SidewalkWidth) or Vector3.new(Data.SidewalkWidth, 0.6, sz)
		local pos = Vector3.new(x + (longX and 0 or side * offset), 0.2, z + (longX and side * offset or 0))
		part(m, "Chodnik", size, pos, Data.Colors.Curb, Enum.Material.Concrete)
	end
	local length = longX and sx or sz
	for offset = -length / 2 + 18, length / 2 - 12, 32 do
		local dash = part(m, "Linia_Przerywana", longX and Vector3.new(10, 0.03, 0.2) or Vector3.new(0.2, 0.03, 10),
			Vector3.new(x + (longX and offset or 0), 0.12, z + (longX and 0 or offset)), Data.Colors.Marking, Enum.Material.SmoothPlastic)
		dash.CanCollide = false
		dash.CanTouch = false
		dash.CanQuery = false
	end
end

local function paving(parent: Instance, name: string, x: number, z: number, sx: number, sz: number): Part
	return part(parent, name, Vector3.new(sx, 0.3, sz), Vector3.new(x, 0.1, z), Data.Colors.Paving, Enum.Material.Cobblestone)
end

local function cloneAsset(assets: { [string]: Instance }, kind: string, parent: Instance, x: number, z: number, yaw: number, scale: number, base: number): Model
	local clone = staticClone(assets[kind], kind)
	clone:ScaleTo(clone:GetScale() * scale)
	clone:SetAttribute("SourceAsset", assetPaths[kind])
	place(clone, x, z, yaw, base)
	clone.Parent = parent
	return clone
end

local function buildParking(parent: Instance, assets: { [string]: Instance }): ()
	for index, lot in Data.Parking do
		local m = model(parent, "Parking_" .. index)
		part(m, "Asfalt", Vector3.new(58, 0.2, 152), Vector3.new(lot.x, 0, lot.z), Data.Colors.Road, Enum.Material.Asphalt)
		for _, side in { -1, 1 } do
			for slot = 0, 7 do
				local stripe = part(m, "Linia", Vector3.new(17, 0.035, 0.18), Vector3.new(lot.x + side * 20.5, 0.12, lot.z - 56 + slot * 16), Data.Colors.Marking, Enum.Material.SmoothPlastic)
				stripe.CanCollide = false
				stripe.CanTouch = false
				stripe.CanQuery = false
			end
		end
		road(parent, "Dojazd_" .. index, lot.x < 0 and -370 or 370, lot.z, 60, Data.RoadWidth)
	end
	for index, location in Data.BinShelters do
		local m = model(parent, "Wiata_Smietnikowa_" .. index)
		paving(m, "Podest", location.x, location.z, 36, 15)
		for _, dx in { -17, 17 } do
			for _, dz in { -6, 6 } do
				part(m, "Slup", Vector3.new(0.5, 9, 0.5), Vector3.new(location.x + dx, 4.75, location.z + dz), Data.Colors.Metal, Enum.Material.Metal)
			end
		end
		part(m, "Dach", Vector3.new(38, 0.6, 17), Vector3.new(location.x, 9.5, location.z), Data.Colors.Roof, Enum.Material.Metal)
		part(m, "Tyl", Vector3.new(34, 7, 0.4), Vector3.new(location.x, 3.75, location.z + 6), Data.Colors.Metal, Enum.Material.WoodPlanks)
		for bin, label in { "PAPIER", "SZKLO", "PLASTIK", "ZMIESZANE" } do
			local x = location.x - 10.5 + (bin - 1) * 7
			cloneAsset(assets, "Bin", m, x, location.z, 0, 0.45, 0.25)
			sign(m, label, Vector3.new(x, 8, location.z - 6), 6.5, 0)
		end
	end
end

local function buildPark(parent: Instance, assets: { [string]: Instance }): ()
	local paths = model(parent, "Alejki")
	paving(paths, "Aleja_Glowna", 0, 0, 14, 310)
	for _, side in { -1, 1 } do
		paving(paths, "Aleja_Wejsciowa", 0, side * 345, 14, 160)
		paving(paths, "Obejscie_Placu_Zabaw", 66, side * 210, 14, 110)
		for _, z in { side * 155, side * 265 } do
			paving(paths, "Lacznik_Alei", 33, z, 80, 10)
		end
		paving(paths, "Aleja_Skrajna", 0, side * 410, 320, 8)
	end
	-- Route the east approach around the court instead of across its playing surface.
	paving(paths, "Aleja_Poprzeczna", -90, 0, 590, 12)
	paving(paths, "Obejscie_Boiska", 200, 27.5, 12, 55)
	paving(paths, "Dojscie_Wschodnie", 292.5, 55, 185, 12)
	for _, z in { -150, 150 } do
		paving(paths, "Dojscie_Do_Blokow", 0, z, 450, 8)
	end
	for _, z in { -300, 300 } do
		paving(paths, "Dojscie_Do_Wiezowcow", 0, z, 450, 8)
		for _, x in { -220, 220 } do
			paving(paths, "Podest_Przy_Wejsciu", x, z < 0 and -306 or 306, 30, 16)
		end
	end
	for _, x in { -160, 160 } do
		paving(paths, "Aleja_Boczna", x, 0, 8, 820)
	end
	local square = model(parent, "Skwer_Centralny")
	local disk = part(square, "Plac", Vector3.new(0.4, 76, 76), Vector3.new(0, 0.12, 0), Data.Colors.Paving, Enum.Material.Cobblestone)
	disk.Shape = Enum.PartType.Cylinder
	disk.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
	for _, x in { -24, 24 } do
		for _, z in { -24, 24 } do
			paving(square, "Donica", x, z, 9, 9).Color = Data.Colors.Curb
			cloneAsset(assets, "Bush", square, x, z, 0, 0.75, 0.4)
		end
	end
	for _, tree in Data.Trees do
		cloneAsset(assets, tree.kind, parent, tree.x, tree.z, (tree.x + tree.z) % 360, tree.scale, 0)
	end
	for _, side in { -1, 1 } do
		for z = -320, 320, 18 do
			if math.abs(z) > 18 and math.abs(math.abs(z) - 150) > 15 and math.abs(math.abs(z) - 300) > 16 then
				cloneAsset(assets, "Bush", parent, side * 130, z, 90, 1.3, 0)
			end
		end
		for _, z in { -270, -230, -55, 55, 230, 270 } do
			cloneAsset(assets, "Beech", parent, side * 190, z, 0, 0.9, 0)
		end
		for _, x in { -310, -110, 110, 310 } do
			cloneAsset(assets, "Tree", parent, x, side * 390, 0, 1, 0)
		end
		for z = -370, 370, 74 do
			cloneAsset(assets, "Beech", parent, side * 365, z, 0, 0.85, 0)
		end
		for _, z in { -295, -105, 105, 295 } do
			cloneAsset(assets, "Bench", parent, side * 151, z, side == -1 and 180 or 0, 1, 0.25)
			cloneAsset(assets, "Trash", parent, side * 151, z + 12, 0, 0.75, 0.25)
		end
		for _, z in { -52, 52 } do
			cloneAsset(assets, "Bench", parent, side * 40, z, 90, 1, 0)
		end
		for z = -330, 330, 110 do
			cloneAsset(assets, "Lamp", parent, side * 165, z, side == -1 and 0 or 180, 0.7, 0.25)
		end
	end
	for index, location in Data.Playgrounds do
		local m = model(parent, "Plac_Zabaw_" .. index)
		part(m, "Nawierzchnia", Vector3.new(102, 0.35, 100), Vector3.new(location.x, 0.12, location.z), Data.Colors.PlaySurface, Enum.Material.Sand)
		cloneAsset(assets, "Playground", m, location.x, location.z, location.yaw, 0.8, 0.3)
		for _, side in { -1, 1 } do
			part(m, "Ogrodzenie", Vector3.new(0.35, 2.5, 100), Vector3.new(location.x + side * 51, 1.5, location.z), Data.Colors.Metal, Enum.Material.Metal)
			for _, dx in { -31, 31 } do
				part(m, "Ogrodzenie", Vector3.new(40, 2.5, 0.35), Vector3.new(location.x + dx, 1.5, location.z + side * 50), Data.Colors.Metal, Enum.Material.Metal)
			end
		end
	end
	local court = model(parent, "Boisko")
	part(court, "Nawierzchnia", Vector3.new(64, 0.3, 80), Vector3.new(250, 0.1, 0), Data.Colors.Court, Enum.Material.Concrete)
	for _, z in { -36, 0, 36 } do
		local line = part(court, "Linia", Vector3.new(56, 0.03, 0.25), Vector3.new(250, 0.27, z), Data.Colors.Marking, Enum.Material.SmoothPlastic)
		line.CanCollide = false
	end
	for _, x in { 222, 278 } do
		local line = part(court, "Linia", Vector3.new(0.25, 0.03, 72), Vector3.new(x, 0.27, 0), Data.Colors.Marking, Enum.Material.SmoothPlastic)
		line.CanCollide = false
	end
	for _, z in { -38, 38 } do
		part(court, "Slup_Kosza", Vector3.new(0.4, 12, 0.4), Vector3.new(250, 6.25, z), Data.Colors.Metal, Enum.Material.Metal)
		part(court, "Tablica_Kosza", Vector3.new(8, 4, 0.4), Vector3.new(250, 11, z), Data.Colors.Marking, Enum.Material.SmoothPlastic)
		local center = Vector3.new(250, 9.5, z + (z < 0 and 1.5 or -1.5))
		for segment = 0, 15 do
			local a = center + Vector3.new(math.cos(segment * math.pi / 8), 0, math.sin(segment * math.pi / 8)) * 1.2
			local b = center + Vector3.new(math.cos((segment + 1) * math.pi / 8), 0, math.sin((segment + 1) * math.pi / 8)) * 1.2
			local ring = part(court, "Obrecz", Vector3.new((a - b).Magnitude, 0.15, 0.15), (a + b) / 2, Color3.fromRGB(176, 89, 53), Enum.Material.Metal)
			ring.Shape = Enum.PartType.Cylinder
			ring.CFrame = CFrame.lookAt(Data.Center + (a + b) / 2, Data.Center + b) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end
	local resting = model(parent, "Plac_Sasiedzki")
	paving(resting, "Plac", -250, 0, 58, 64)
	for _, z in { -20, 20 } do
		cloneAsset(assets, "Bench", resting, -270, z, 180, 1, 0.25)
		cloneAsset(assets, "Bench", resting, -230, z, 0, 1, 0.25)
	end
end

function DevHousingEstate.Build(): Folder
	assertEdit()
	local map = workspace:FindFirstChild("Map")
	assert(map and map:IsA("Folder"), "Authored Workspace.Map must already exist")
	assert(not map:FindFirstChild(Data.Name), "Estate already exists; remove that estate explicitly before rebuilding")
	local assets: { [string]: Instance } = {}
	for kind, path in assetPaths do
		assets[kind] = resolve(path)
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { workspace.Terrain }
	local conflicts = workspace:GetPartBoundsInBox(CFrame.new(Data.Center + Vector3.new(0, 100, 0)), Data.Footprint, overlap)
	assert(#conflicts == 0, "Estate site contains existing objects; inspect it before building")
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Include
	rays.FilterDescendantsInstances = { workspace.Terrain }
	for _, dx in { -400, 0, 400 } do
		for _, dz in { -440, 0, 440 } do
			local hit = workspace:Raycast(Data.Center + Vector3.new(dx, 50, dz), Vector3.new(0, -100, 0), rays)
			assert(hit and math.abs(hit.Position.Y - Data.Center.Y) < 0.1, "Estate needs a flat, supported terrain site")
		end
	end
	local staged = Instance.new("Folder")
	staged.Name = "_HousingEstateStaging"
	staged:SetAttribute("AuthoringTool", Data.Owner)
	staged:SetAttribute("RecipeVersion", Data.Version)
	staged:SetAttribute("Center", Data.Center)
	staged.Parent = ServerStorage
	local ok, message = pcall(function()
		local buildings = Instance.new("Folder")
		buildings.Name = "Bloki"
		buildings.Parent = staged
		for _, entry in Data.Buildings do
			local block = entry.kind == "Tower" and staticClone(assets.Block, entry.name) or slab(assets.Block, entry.name)
			paintBlock(block, Data.Colors.Accents[entry.accent])
			block:SetAttribute("SourceAsset", Data.Assets.Block)
			block:SetAttribute("BuildingKind", entry.kind)
			place(block, entry.x, entry.z, entry.yaw, 0.25)
			block.Parent = buildings
		end
		local roads = Instance.new("Folder")
		roads.Name = "Drogi_i_Parkingi"
		roads.Parent = staged
		for _, side in { -1, 1 } do
			road(roads, "Ulica_Boczna", side * Data.RoadHalfWidth, 0, Data.RoadWidth, Data.RoadHalfLength * 2 + Data.RoadWidth)
			road(roads, "Ulica_Poprzeczna", 0, side * Data.RoadHalfLength, Data.RoadHalfWidth * 2 + Data.RoadWidth, Data.RoadWidth)
			for z = -330, 330, 110 do
				cloneAsset(assets, "Lamp", roads, side * 420, z, side == -1 and 0 or 180, 0.8, 0.25)
			end
		end
		road(roads, "Wjazd", 425, 0, 50, Data.RoadWidth)
		local crossings = model(roads, "Przejscia_Dla_Pieszych")
		for _, side in { -1, 1 } do
			for stripeIndex = -3, 3 do
				for _, vertical in { false, true } do
					local size = vertical and Vector3.new(18, 0.03, 1.2) or Vector3.new(1.2, 0.03, 18)
					local position = vertical and Vector3.new(side * Data.RoadHalfWidth, 0.14, stripeIndex * 2) or Vector3.new(stripeIndex * 2, 0.14, side * Data.RoadHalfLength)
					local stripe = part(crossings, "Pas", size, position, Data.Colors.Marking, Enum.Material.SmoothPlastic)
					stripe.CanCollide = false
					stripe.CanTouch = false
					stripe.CanQuery = false
				end
			end
		end
		sign(model(roads, "Tablica_Osiedla"), "OSIEDLE PARKOWE", Vector3.new(426, 10, -23), 24, -90)
		buildParking(roads, assets)
		local park = Instance.new("Folder")
		park.Name = "Park_i_Rekreacja"
		park.Parent = staged
		buildPark(park, assets)
	end)
	if not ok then
		staged:Destroy()
		error(message, 2)
	end
	staged.Name = Data.Name
	staged.Parent = map
	ChangeHistoryService:SetWaypoint("Build Osiedle Parkowe")
	return staged
end

function DevHousingEstate.Remove(): ()
	assertEdit()
	local map = workspace:FindFirstChild("Map")
	local estate = map and map:FindFirstChild(Data.Name)
	assert(estate and estate:IsA("Folder"), "Estate folder is missing")
	assert(estate:GetAttribute("AuthoringTool") == Data.Owner, "Refusing to remove an unrelated map folder")
	estate:Destroy()
	ChangeHistoryService:SetWaypoint("Remove Osiedle Parkowe")
end

return DevHousingEstate
