--!strict
-- Edit-mode acceptance of the current estate, including removing and rebuilding it.
local ServerScriptService = game:GetService("ServerScriptService")
local reload = Instance.new("Folder")
reload.Name = "_HousingEstateAcceptance"
reload.Parent = ServerScriptService
for _, name in { "HousingEstateData", "DevHousingEstate" } do
	ServerScriptService.Map[name]:Clone().Parent = reload
end
local tool = require(reload.DevHousingEstate)
local data = require(reload.HousingEstateData)
local existing = workspace.Map:FindFirstChild(data.Name)
assert(existing, "Build the draft estate before running acceptance")
local originalParts = {}
for _, p in workspace:GetDescendants() do
	if p:IsA("BasePart") and not p:IsA("Terrain") and not p:IsDescendantOf(existing) then
		table.insert(originalParts, { instance = p, parent = p.Parent, frame = p.CFrame, size = p.Size, color = p.Color, anchored = p.Anchored })
	end
end
local region = Region3.new(data.Center + Vector3.new(-4, -132, -4), data.Center + Vector3.new(4, 8, 4))
local beforeMaterials, beforeOccupancy = workspace.Terrain:ReadVoxels(region, 4)
local checks = 0
local function check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end
local ok, failure = pcall(function()
	check(not pcall(tool.Build), "Repeated Build must not replace an existing estate")
	existing:SetAttribute("AuthoringTool", "UnrelatedAuthoringTool")
	check(not pcall(tool.Remove), "Remove must reject a folder without its ownership marker")
	check(existing.Parent == workspace.Map, "Rejected Remove leaves folder intact")
	existing:SetAttribute("AuthoringTool", data.Owner)
	tool.Remove()
	check(not workspace.Map:FindFirstChild(data.Name), "Remove deletes the entire generated estate")
	local count = 0
	for _, p in workspace:GetDescendants() do
		if p:IsA("BasePart") and not p:IsA("Terrain") then
			count += 1
		end
	end
	check(count == #originalParts, "Remove returns Workspace to its original part count")
	local changed = 0
	for _, snapshot in originalParts do
		local p = snapshot.instance
		if p.Parent ~= snapshot.parent or p.CFrame ~= snapshot.frame or p.Size ~= snapshot.size or p.Color ~= snapshot.color or p.Anchored ~= snapshot.anchored then
			changed += 1
		end
	end
	check(changed == 0, "Remove preserves every original part and its authored properties")
	local estate = tool.Build()
	check(#estate.Bloki:GetChildren() == 8, "Eight residential blocks published")
	local scripts, movingParts, outside, parts, seats = 0, 0, 0, 0, 0
	for _, p in estate:GetDescendants() do
		if p:IsA("LuaSourceContainer") then scripts += 1 end
		if p:IsA("Seat") then seats += 1 end
		if p:IsA("BasePart") then
			parts += 1
			if not p.Anchored then movingParts += 1 end
			local relative = p.Position - data.Center
			if math.abs(relative.X) > data.Footprint.X / 2 or math.abs(relative.Z) > data.Footprint.Z / 2 then outside += 1 end
		end
	end
	check(scripts == 0, "Inherited scripts cannot run in the new scenery")
	check(movingParts == 0, "All scenery remains anchored")
	check(outside == 0, "All new part centers remain inside the empty reserved site")
	check(seats > 0, "Benches and playground seats retain engine seating")
	local towers, slabs = 0, 0
	local boxes = {}
	for _, block in estate.Bloki:GetChildren() do
		local box, size = block:GetBoundingBox()
		local right, look = box.RightVector, box.LookVector
		local hx = (math.abs(right.X) * size.X + math.abs(look.X) * size.Z) / 2
		local hz = (math.abs(right.Z) * size.X + math.abs(look.Z) * size.Z) / 2
		for _, previous in boxes do
			check(math.abs(box.X - previous.x) >= hx + previous.hx or math.abs(box.Z - previous.z) >= hz + previous.hz, "Residential buildings do not intersect")
		end
		table.insert(boxes, { x = box.X, z = box.Z, hx = hx, hz = hz })
		if block:GetAttribute("BuildingKind") == "Tower" then
			towers += 1
		else
			slabs += 1
			for _, child in block:GetChildren() do
				if child:IsA("Model") then
					check(#child:GetChildren() == data.FloorCount + 1, "Low blocks retain five existing floor modules plus their ground floor")
				end
			end
		end
	end
	check(towers == 4 and slabs == 4, "Four towers and four low slabs")
	check(estate.Park_i_Rekreacja:FindFirstChild("Plac_Zabaw_1") ~= nil and estate.Park_i_Rekreacja:FindFirstChild("Plac_Zabaw_2") ~= nil, "Two playgrounds")
	for index = 1, 4 do
		check(estate.Drogi_i_Parkingi:FindFirstChild("Parking_" .. index) ~= nil, "Parking court exists")
		check(estate.Drogi_i_Parkingi:FindFirstChild("Wiata_Smietnikowa_" .. index) ~= nil, "Waste shelter exists")
	end
	local materials, occupancy = workspace.Terrain:ReadVoxels(region, 4)
	local sameTerrain = true
	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				if materials[x][y][z] ~= beforeMaterials[x][y][z] or occupancy[x][y][z] ~= beforeOccupancy[x][y][z] then sameTerrain = false end
			end
		end
	end
	check(sameTerrain, "Build/Remove preserve native terrain")
	changed = 0
	for _, snapshot in originalParts do
		local p = snapshot.instance
		if p.Parent ~= snapshot.parent or p.CFrame ~= snapshot.frame or p.Size ~= snapshot.size or p.Color ~= snapshot.color or p.Anchored ~= snapshot.anchored then changed += 1 end
	end
	check(changed == 0, "Rebuild preserves every original instance")
	check(not game.ServerStorage:FindFirstChild("_HousingEstateStaging"), "No temporary staging folder remains")
	print(string.format("Housing estate: %d native checks passed; %d static parts and %d seats", checks, parts, seats))
end)
existing:SetAttribute("AuthoringTool", data.Owner)
reload:Destroy()
assert(ok, tostring(failure))
return checks
