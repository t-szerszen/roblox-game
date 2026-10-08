--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
local Data = require(script.Parent.TerritoryData)
local Tool = {}
local function editMap(): Instance
	assert(not RunService:IsRunning(), "Stop Play before authoring territories")
	return assert(workspace:FindFirstChild("Map"), "Workspace.Map is missing")
end
function Tool.ConfigureSelection()
	local map = editMap()
	local selected = Selection:Get()
	local selectedZones: { [Instance]: boolean } = {}
	assert(#selected > 0, "Select authored flag Models under Workspace.Map")
	for _, model in selected do
		assert(model:IsA("Model") and model:IsDescendantOf(map), "Select only flag Models under Workspace.Map")
		local existing = model:FindFirstChild("CaptureZone")
		assert(not existing or existing:IsA("BasePart"), "CaptureZone must be a BasePart")
		if existing then selectedZones[existing] = true end
	end
	local usedIds: { [string]: boolean } = {}
	for _, zone in CollectionService:GetTagged(Config.ZoneTag) do
		if zone:IsDescendantOf(map) and not selectedZones[zone] then
			local id = zone:GetAttribute(Config.IdAttribute)
			if typeof(id) == "string" then usedIds[id] = true end
		end
	end
	for _, instance in selected do
		local model = instance :: Model
		local zone = model:FindFirstChild("CaptureZone") :: BasePart?
		if not zone then
			local created = Instance.new("Part")
			created.Name = "CaptureZone"
			created.Size = Config.DefaultZoneSize
			created.CFrame = model:GetPivot() * CFrame.new(0, Config.DefaultZoneSize.Y * 0.5, 0)
			created.Transparency = 1
			created.CanCollide = false
			created.CanTouch = false
			created.CanQuery = false
			created.Anchored = true
			created.Parent = model
			zone = created
		end
		assert(zone)
		local id = zone:GetAttribute(Config.IdAttribute)
		-- Studio duplication copies attributes; reserve a new identity for each clone.
		if typeof(id) ~= "string" or #id < 1 or #id > 64 or not string.match(id, "^[%w_-]+$") or usedIds[id] then
			id = HttpService:GenerateGUID(false)
		end
		usedIds[id :: string] = true
		zone.Anchored = true
		zone.Transparency = 1
		zone.CanCollide = false
		zone.CanTouch = false
		zone.CanQuery = false
		zone:SetAttribute(Config.IdAttribute, id)
		zone:SetAttribute(Config.NameAttribute, model.Name)
		CollectionService:AddTag(zone, Config.ZoneTag)
	end
	print("Configured " .. #selected .. " territories. Adjust CaptureZone sizes/positions in Studio, then serialize.")
end
function Tool.Serialize(): string
	local map = editMap()
	local rows: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, instance in CollectionService:GetTagged(Config.ZoneTag) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(map) then continue end
		local id = instance:GetAttribute(Config.IdAttribute)
		assert(typeof(id) == "string" and #id > 0 and not seen[id], "Each zone needs a unique TerritoryId")
		seen[id] = true
		local path: { string } = {}
		local parent = instance.Parent
		while parent and parent ~= map do table.insert(path, 1, string.format("%q", parent.Name)); parent = parent.Parent end
		local numbers = { instance.CFrame:GetComponents() }
		local frame: { string } = {}
		for _, value in numbers do table.insert(frame, string.format("%.9g", value)) end
		local size = instance.Size
		local name = instance:GetAttribute(Config.NameAttribute)
		table.insert(rows, string.format("\t{ id = %q, name = %q, modelPath = {%s}, cframe = CFrame.new(%s), size = Vector3.new(%.9g, %.9g, %.9g) },",
			id, if typeof(name) == "string" then name else id, table.concat(path, ", "), table.concat(frame, ", "), size.X, size.Y, size.Z))
	end
	table.sort(rows)
	local source = "--!strict\nexport type Zone = { id: string, name: string, modelPath: { string }, cframe: CFrame, size: Vector3 }\nreturn {\n" .. table.concat(rows, "\n") .. "\n} :: { Zone }"
	print(source)
	return source
end
function Tool.RestoreZones()
	local map = editMap()
	local targets: { { definition: Data.Zone, parent: Instance } } = {}
	-- Validate every parent before touching the authored map.
	for _, definition in Data do
		local parent = map
		for _, name in definition.modelPath do parent = assert(parent:FindFirstChild(name), "Missing authored parent: " .. name) end
		local old = parent:FindFirstChild("CaptureZone")
		assert(not old or old:IsA("BasePart"), "CaptureZone must be a BasePart")
		table.insert(targets, { definition = definition, parent = parent })
	end
	for _, target in targets do
		local definition = target.definition
		local zone = target.parent:FindFirstChild("CaptureZone") :: BasePart?
		if not zone then
			local created = Instance.new("Part")
			created.Name = "CaptureZone"; created.Parent = target.parent
			zone = created
		end
		assert(zone)
		zone.CFrame = definition.cframe
		zone.Size = definition.size
		zone.Anchored = true
		zone.Transparency = 1
		zone.CanCollide = false; zone.CanTouch = false; zone.CanQuery = false
		zone:SetAttribute(Config.IdAttribute, definition.id)
		zone:SetAttribute(Config.NameAttribute, definition.name)
		CollectionService:AddTag(zone, Config.ZoneTag)
	end
end
return Tool
