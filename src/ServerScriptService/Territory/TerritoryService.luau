--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
local GangService = require(script.Parent.Parent.Gang.GangService)
local CombatService = require(script.Parent.Parent.Combat.CombatService)
local PlayerDataService = require(script.Parent.Parent.Activity.PlayerDataService)
local Capture = require(script.Parent.TerritoryCapture)
local Rewards = require(script.Parent.TerritoryRewards)

type Record = { id: string, zone: BasePart, state: Capture.State, published: Folder, label: TextLabel, gui: BillboardGui, connections: { RBXScriptConnection }, tints: { [BasePart]: Color3 } }
local Service = {}
local records: { [BasePart]: Record } = {}
local byId: { [string]: Record } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribe: (() -> ())? = nil
local stateFolder: Folder? = nil
local started = false
local function attribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then instance:SetAttribute(name, value) end
end
local function publish(record: Record)
	local state = record.state
	local ownerName, ownerColor = nil, nil
	local capturerName, capturerColor = nil, nil
	if state.ownerGangId then ownerName, ownerColor = GangService.GetIdentity(state.ownerGangId) end
	for part in record.tints do
		local color = ownerColor or Config.NeutralColor
		if part.Parent and part.Color ~= color then part.Color = color end
	end
	if state.capturingGangId then capturerName, capturerColor = GangService.GetIdentity(state.capturingGangId) end
	local title = record.zone:GetAttribute(Config.NameAttribute)
	local name = if typeof(title) == "string" and #title > 0 and #title <= 64 then title else record.id
	local percent = math.floor(state.progress / Config.CaptureSeconds * 100)
	attribute(record.published, "DisplayName", name)
	attribute(record.published, "Center", record.zone.Position)
	attribute(record.published, "OwnerGangId", state.ownerGangId)
	attribute(record.published, "OwnerName", ownerName)
	attribute(record.published, "OwnerColor", ownerColor)
	attribute(record.published, "CapturingGangId", state.capturingGangId)
	attribute(record.published, "CapturingName", capturerName)
	attribute(record.published, "Progress", percent)
	attribute(record.published, "Phase", state.phase)
	attribute(record.published, "Advantage", state.advantage)
	local detail = if state.phase == "contested" then "Sporne terytorium"
		elseif state.phase == "capturing" then string.format("%s: %d%% (+%d)", capturerName or "Gang", percent, state.advantage)
		elseif state.capturingGangId then string.format("Postęp zanika: %d%%", percent)
		else ownerName or "Niczyje"
	record.label.Text = name .. "\n" .. detail
	record.label.TextColor3 = capturerColor or ownerColor or Config.NeutralColor
end
local function flagCounts(): { [string]: number }
	local counts: { [string]: number } = {}
	for _, record in records do
		local owner = record.state.ownerGangId
		if owner and GangService.Exists(owner) then counts[owner] = (counts[owner] or 0) + 1 end
	end
	return counts
end
local function syncIncome()
	local counts = flagCounts()
	for _, player in Players:GetPlayers() do
		local id = GangService.GetGangId(player)
		local flags = if id then counts[id] or 0 else 0
		local online = if id then #GangService.GetOnlineMembers(id) else 0
		attribute(player, "GangFlagsOwned", flags)
		attribute(player, "GangIncomePerMinute", if online > 0 then math.floor(flags * Config.CoinsPerFlag / online) else 0)
	end
	GangService.NotifyAll()
end
local function unregister(zone: BasePart)
	local record = records[zone]
	if not record then return end
	records[zone] = nil
	byId[record.id] = nil
	for _, connection in record.connections do connection:Disconnect() end
	for part, original in record.tints do if part.Parent then part.Color = original end end
	record.gui:Destroy()
	record.published:Destroy()
	syncIncome()
end
local function register(instance: Instance)
	local map = Workspace:FindFirstChild("Map")
	if not instance:IsA("BasePart") or not map or not instance:IsDescendantOf(map) or records[instance] then return end
	local id = instance:GetAttribute(Config.IdAttribute)
	if typeof(id) ~= "string" or #id < 1 or #id > 64 or not string.match(id, "^[%w_-]+$") or byId[id] then
		warn("TerritoryService: invalid or duplicate TerritoryId on " .. instance:GetFullName())
		return
	end
	if not instance.Anchored then warn("TerritoryService: capture zones must be anchored: " .. id); return end
	local tints: { [BasePart]: Color3 } = {}
	local model = instance.Parent
	if model and model:IsA("Model") then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute(Config.TintAttribute) == true then tints[part] = part.Color end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = id
	folder.Parent = stateFolder
	local gui = Instance.new("BillboardGui")
	gui.Name = "TerritoryStatus"
	gui.Adornee = instance
	gui.Size = UDim2.fromOffset(230, 64)
	gui.StudsOffset = Vector3.new(0, if next(tints) then 3 else instance.Size.Y * 0.5 + 3, 0)
	gui.MaxDistance = Config.WorldLabelDistance
	gui.AlwaysOnTop = true
	gui.Parent = instance
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextWrapped = true
	label.Parent = gui
	local record: Record = { id = id, zone = instance, state = Capture.New(), published = folder, label = label, gui = gui, connections = {}, tints = tints }
	records[instance] = record
	byId[id] = record
	table.insert(record.connections, instance.Destroying:Connect(function() unregister(instance) end))
	table.insert(record.connections, instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(map) then unregister(instance) end
	end))
	publish(record)
	GangService.NotifyAll()
end
local function sample(delta: number)
	local participants: { { id: string, position: Vector3 } } = {}
	for _, player in Players:GetPlayers() do
		local id = GangService.GetGangId(player)
		local position = CombatService.GetTerritoryPosition(player)
		if id and position then table.insert(participants, { id = id, position = position }) end
	end
	local ownershipChanged = false
	for zone, record in records do
		local counts: { [string]: number } = {}
		local half = zone.Size * 0.5
		for _, participant in participants do
			local localPosition = zone.CFrame:PointToObjectSpace(participant.position)
			if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z then
				counts[participant.id] = (counts[participant.id] or 0) + 1
			end
		end
		local oldOwner = record.state.ownerGangId
		Capture.Step(record.state, counts, delta)
		if oldOwner ~= record.state.ownerGangId then ownershipChanged = true end
		publish(record)
	end
	if ownershipChanged then syncIncome() end
end
function Service.Start()
	if started then return end
	started = true
	GangService.Start()
	PlayerDataService.Start()
	local folder = Instance.new("Folder")
	folder.Name = Config.StateFolderName
	folder.Parent = ReplicatedStorage
	stateFolder = folder
	for _, zone in CollectionService:GetTagged(Config.ZoneTag) do register(zone) end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(Config.ZoneTag):Connect(register))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(Config.ZoneTag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then unregister(instance) end
	end))
	unsubscribe = GangService.Subscribe(function(id: string)
		for _, record in records do
			if not GangService.Exists(id) then Capture.RemoveGang(record.state, id) end
			publish(record)
		end
		syncIncome()
	end)
	syncIncome()
	local accumulated = 0
	local nextReward = Workspace:GetServerTimeNow() + Config.RewardInterval
	table.insert(connections, RunService.Heartbeat:Connect(function(delta: number)
		accumulated += delta
		if accumulated >= Config.SampleInterval then
			local elapsed = math.min(accumulated, Config.MaxStepSeconds)
			accumulated = 0
			sample(elapsed)
			if Workspace:GetServerTimeNow() >= nextReward then
				nextReward = Workspace:GetServerTimeNow() + Config.RewardInterval
				Rewards.Pay(flagCounts())
			end
		end
	end))
end
function Service.Stop()
	if not started then return end
	started = false
	if unsubscribe then unsubscribe(); unsubscribe = nil end
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	for zone in table.clone(records) do unregister(zone) end
	if stateFolder then stateFolder:Destroy(); stateFolder = nil end
	Rewards.Clear()
end
return Service
