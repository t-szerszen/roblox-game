--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
local Data = require(script.Parent.TerritoryData)
local Tool = {}

function Tool.PlaceFlags()
	assert(not RunService:IsRunning(), "Stop Play before placing flags")
	local map = assert(workspace:FindFirstChild("Map"), "Workspace.Map is missing")
	local template = ServerStorage:FindFirstChild("TerritoryFlagTemplate")
	assert(template and template:IsA("Model"), "Sync TerritoryFlagTemplate with Rojo first")
	local root = template:FindFirstChild("Anchor")
	assert(root and root:IsA("BasePart"), "Flag template needs its ground Anchor")
	local existing = map:FindFirstChild("Territories")
	assert(not existing or existing:IsA("Folder"), "Map.Territories must be a Folder")
	-- Repeated installation leaves manually moved flags in their authored positions.
	for _, definition in Data do
		assert(#definition.modelPath == 2 and definition.modelPath[1] == "Territories", "Flag snapshot needs a direct Map.Territories model")
		local old = if existing then existing:FindFirstChild(definition.modelPath[2]) else nil
		for _, zone in CollectionService:GetTagged(Config.ZoneTag) do
			if zone:IsDescendantOf(map) and zone:GetAttribute(Config.IdAttribute) == definition.id then
				assert(old and zone.Parent == old, "This territory already exists at another path; serialize after renaming")
			end
		end
		if old then
			assert(old:IsA("Model"), "Existing flag must be a Model")
			local zone = old:FindFirstChild("CaptureZone")
			assert(zone and zone:IsA("BasePart") and zone:GetAttribute(Config.IdAttribute) == definition.id, "Existing flag has a different identity")
		end
	end
	local folder = existing
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Territories"; created.Parent = map
		folder = created
	end
	for _, definition in Data do
		local name = definition.modelPath[2]
		if folder:FindFirstChild(name) then continue end
		local model = template:Clone()
		model.Name = name
		local anchor = model:FindFirstChild("Anchor")
		assert(anchor and anchor:IsA("BasePart"), "Flag template needs its ground Anchor")
		model.PrimaryPart = anchor
		model:PivotTo(definition.cframe * CFrame.new(0, -definition.size.Y * 0.5, 0))
		local zone = Instance.new("Part")
		zone.Name = "CaptureZone"; zone.Size = definition.size; zone.CFrame = definition.cframe
		zone.Anchored = true; zone.Transparency = 1
		zone.CanCollide = false; zone.CanTouch = false; zone.CanQuery = false
		zone:SetAttribute(Config.IdAttribute, definition.id)
		zone:SetAttribute(Config.NameAttribute, definition.name)
		zone.Parent = model
		local half = definition.size * 0.5
		for index, edge in {
			{ Vector3.new(half.X, 0, 0), Vector3.new(0.14, 0.06, definition.size.Z) },
			{ Vector3.new(-half.X, 0, 0), Vector3.new(0.14, 0.06, definition.size.Z) },
			{ Vector3.new(0, 0, half.Z), Vector3.new(definition.size.X, 0.06, 0.14) },
			{ Vector3.new(0, 0, -half.Z), Vector3.new(definition.size.X, 0.06, 0.14) },
		} do
			local border = Instance.new("Part")
			border.Name = "ZoneEdge_" .. index; border.Size = edge[2]
			border.CFrame = definition.cframe * CFrame.new(edge[1] + Vector3.new(0, -half.Y + 0.07, 0))
			border.Anchored = true; border.CanCollide = false; border.CanTouch = false; border.CanQuery = false
			border.CastShadow = false; border.Transparency = 0.45
			border.Color = Config.NeutralColor; border.Material = Enum.Material.Neon
			border:SetAttribute(Config.TintAttribute, true); border.Parent = model
		end
		model.Parent = folder
		CollectionService:AddTag(zone, Config.ZoneTag)
	end
	print("Territory flags installed under Workspace.Map.Territories. Move whole Models, then serialize.")
end
return Tool
