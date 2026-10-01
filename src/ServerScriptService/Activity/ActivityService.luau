--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ActivityConfig = require(ReplicatedStorage.Shared.Activity.ActivityConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

type DeliveryRecord = {
	destination: Instance,
	destinationName: string,
	distance: number,
}
type TrickRecord = {
	owner: Player,
	burnoutStartedAt: number?,
	wheelieStartedAt: number?,
	connections: { RBXScriptConnection },
}

local ActivityService = {}
local deliveries: { [Player]: DeliveryRecord } = {}
local promptConnections: { [Instance]: RBXScriptConnection } = {}
local trickRecords: { [Model]: TrickRecord } = {}
local lastPositions: { [Player]: Vector3 } = {}
local connections: { RBXScriptConnection } = {}
local started = false

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function promptParent(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function destinationName(instance: Instance): string
	local displayName = instance:GetAttribute("DeliveryName")
	return if typeof(displayName) == "string" and displayName ~= "" then displayName else instance.Name
end

local function playerIsNear(player: Player, instance: Instance): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local position = positionOf(instance)
	return root ~= nil
		and root:IsA("BasePart")
		and position ~= nil
		and (root.Position - position).Magnitude <= ActivityConfig.InteractionDistance + 3
end

local function setDeliveryAttributes(player: Player, delivery: DeliveryRecord?)
	if delivery then
		player:SetAttribute("DeliveryActive", true)
		player:SetAttribute("DeliveryDestination", delivery.destinationName)
		player:SetAttribute("DeliveryDistance", delivery.distance)
	else
		player:SetAttribute("DeliveryActive", false)
		player:SetAttribute("DeliveryDestination", nil)
		player:SetAttribute("DeliveryDistance", nil)
	end
end

local function chooseDestination(origin: Vector3): (Instance?, number)
	local available: { { instance: Instance, distance: number } } = {}
	for _, candidate in CollectionService:GetTagged(ActivityConfig.DestinationTag) do
		if candidate:IsDescendantOf(Workspace) then
			local position = positionOf(candidate)
			if position then
				table.insert(available, { instance = candidate, distance = (position - origin).Magnitude })
			end
		end
	end
	if #available == 0 then
		return nil, 0
	end
	local selected = available[math.random(1, #available)]
	return selected.instance, selected.distance
end

local function startDelivery(player: Player, pickup: Instance): (boolean, string)
	if deliveries[player] then
		return false, "Masz juz aktywna dostawe."
	end
	local origin = positionOf(pickup)
	if not origin then
		return false, "Punkt odbioru jest nieprawidlowy."
	end
	local destination, distance = chooseDestination(origin)
	if not destination then
		return false, "Brak oznaczonych celow dostawy."
	end
	local delivery: DeliveryRecord = {
		destination = destination,
		destinationName = destinationName(destination),
		distance = distance,
	}
	deliveries[player] = delivery
	setDeliveryAttributes(player, delivery)
	return true, "Dostawa rozpoczeta."
end

local function finishDelivery(player: Player, destination: Instance): (boolean, string)
	local delivery = deliveries[player]
	if not delivery or delivery.destination ~= destination then
		return false, "To nie jest cel twojej dostawy."
	end
	local distanceSteps = math.floor(delivery.distance / ActivityConfig.DistanceStepStuds)
	local coins = ActivityConfig.BaseCoins + distanceSteps * ActivityConfig.DistanceBonusCoins
	PlayerDataService.AddCurrency(player, coins, ActivityConfig.BaseXP)
	PlayerDataService.Increment(player, "deliveries", 1)
	PlayerDataService.IncrementDaily(player, "DailyDeliveries", 1)
	deliveries[player] = nil
	setDeliveryAttributes(player, nil)
	player:SetAttribute("LastDeliveryCoins", coins)
	return true, string.format("Dostawa ukonczona: +%d Coins, +%d XP", coins, ActivityConfig.BaseXP)
end

local function attachPrompt(instance: Instance, isPickup: boolean)
	if promptConnections[instance] or not instance:IsDescendantOf(Workspace) then
		return
	end
	local parent = promptParent(instance)
	if not parent then
		warn(string.format("ActivityService: tagged instance %s has no BasePart", instance:GetFullName()))
		return
	end
	local promptName = if isPickup then "DeliveryPickupPrompt" else "DeliveryDestinationPrompt"
	local existing = parent:FindFirstChild(promptName)
	local prompt: ProximityPrompt
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = promptName
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = ActivityConfig.InteractionDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	prompt.ActionText = if isPickup then "Wez paczke" else "Dostarcz paczke"
	prompt.ObjectText = if isPickup then "Punkt odbioru" else destinationName(instance)
	promptConnections[instance] = prompt.Triggered:Connect(function(player: Player)
		local success: boolean
		local message: string
		if not playerIsNear(player, instance) then
			success, message = false, "Podejdz blizej do punktu."
		else
			success, message = if isPickup then startDelivery(player, instance) else finishDelivery(player, instance)
		end
		player:SetAttribute("ActivityMessage", message)
		player:SetAttribute("ActivityMessageSuccess", success)
		local oldNonce = player:GetAttribute("ActivityMessageNonce")
		local nonce = if typeof(oldNonce) == "number" then oldNonce else 0
		player:SetAttribute("ActivityMessageNonce", nonce + 1)
	end)
end

local function detachPrompt(instance: Instance)
	local connection = promptConnections[instance]
	if connection then
		connection:Disconnect()
		promptConnections[instance] = nil
	end
end

local function finishTrick(record: TrickRecord, kind: string)
	local startedAt = if kind == "Burnout" then record.burnoutStartedAt else record.wheelieStartedAt
	if not startedAt then
		return
	end
	local duration = os.clock() - startedAt
	if kind == "Burnout" then
		record.burnoutStartedAt = nil
		PlayerDataService.SetBest(record.owner, "longestBurnout", duration)
	else
		record.wheelieStartedAt = nil
		PlayerDataService.SetBest(record.owner, "longestWheelie", duration)
	end
end

local function trackScooter(scooter: Model)
	if trickRecords[scooter] then
		return
	end
	local ownerId = scooter:GetAttribute("OwnerUserId")
	if typeof(ownerId) ~= "number" then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then
		return
	end
	local record: TrickRecord = { owner = owner, burnoutStartedAt = nil, wheelieStartedAt = nil, connections = {} }
	trickRecords[scooter] = record
	local function update(kind: string, attribute: string)
		local active = scooter:GetAttribute(attribute) == true
		if active then
			if kind == "Burnout" and not record.burnoutStartedAt then
				record.burnoutStartedAt = os.clock()
			elseif kind == "Wheelie" and not record.wheelieStartedAt then
				record.wheelieStartedAt = os.clock()
			end
		else
			finishTrick(record, kind)
		end
	end
	table.insert(record.connections, scooter:GetAttributeChangedSignal("BurnoutActive"):Connect(function()
		update("Burnout", "BurnoutActive")
	end))
	table.insert(record.connections, scooter:GetAttributeChangedSignal("WheelieActive"):Connect(function()
		update("Wheelie", "WheelieActive")
	end))
	table.insert(record.connections, scooter.Destroying:Connect(function()
		finishTrick(record, "Burnout")
		finishTrick(record, "Wheelie")
		for _, connection in record.connections do
			connection:Disconnect()
		end
		trickRecords[scooter] = nil
	end))
	update("Burnout", "BurnoutActive")
	update("Wheelie", "WheelieActive")
end

local function updateDistance(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		lastPositions[player] = nil
		return
	end
	local current = root.Position
	local delivery = deliveries[player]
	if delivery then
		local destinationPosition = positionOf(delivery.destination)
		if destinationPosition then
			player:SetAttribute("DeliveryDistance", (destinationPosition - current).Magnitude)
		end
	end
	local previous = lastPositions[player]
	lastPositions[player] = current
	if not previous then
		return
	end
	local offset = current - previous
	local studs = math.min(Vector2.new(offset.X, offset.Z).Magnitude, ActivityConfig.MaxCreditedStudsPerSample)
	if studs < 0.1 then
		return
	end
	local kilometers = studs / ActivityConfig.StudsPerKilometer
	PlayerDataService.Increment(player, "totalDistanceKm", kilometers)
	PlayerDataService.IncrementDaily(player, "DailyDistanceKm", kilometers)
	local hour = Lighting.ClockTime
	if hour >= 18 or hour < 6 then
		PlayerDataService.IncrementDaily(player, "DailyNightDistanceKm", kilometers)
	end
end

function ActivityService.RecordRaceWin(player: Player)
	PlayerDataService.Increment(player, "raceWins", 1)
	PlayerDataService.IncrementDaily(player, "DailyRaceWins", 1)
end

function ActivityService.RecordPoliceEscape(player: Player)
	PlayerDataService.IncrementDaily(player, "DailyPoliceEscapes", 1)
end

function ActivityService.Start()
	if started then
		return
	end
	started = true
	PlayerDataService.Start()

	for _, pickup in CollectionService:GetTagged(ActivityConfig.PickupTag) do
		attachPrompt(pickup, true)
	end
	for _, destination in CollectionService:GetTagged(ActivityConfig.DestinationTag) do
		attachPrompt(destination, false)
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(ActivityConfig.PickupTag):Connect(function(instance)
		attachPrompt(instance, true)
	end))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(ActivityConfig.PickupTag):Connect(detachPrompt))
	table.insert(connections, CollectionService:GetInstanceAddedSignal(ActivityConfig.DestinationTag):Connect(function(instance)
		attachPrompt(instance, false)
	end))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(ActivityConfig.DestinationTag):Connect(detachPrompt))

	local scooterFolder = Workspace:FindFirstChild("Scooters")
	if scooterFolder then
		for _, child in scooterFolder:GetChildren() do
			if child:IsA("Model") then
				trackScooter(child)
			end
		end
		table.insert(connections, scooterFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				trackScooter(child)
			end
		end))
	end
	table.insert(connections, Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Scooters" and child:IsA("Folder") then
			table.insert(connections, child.ChildAdded:Connect(function(scooter)
				if scooter:IsA("Model") then
					trackScooter(scooter)
				end
			end))
		end
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		deliveries[player] = nil
		lastPositions[player] = nil
	end))
	local accumulated = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime)
		accumulated += deltaTime
		if accumulated >= ActivityConfig.DistanceSampleInterval then
			accumulated = 0
			for _, player in Players:GetPlayers() do
				updateDistance(player)
			end
		end
	end))
end

return ActivityService
