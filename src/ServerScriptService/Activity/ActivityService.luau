--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ActivityConfig = require(ReplicatedStorage.Shared.Activity.ActivityConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Scooter = require(script.Parent.Parent.Scooter.ScooterServer)
local ScooterConfig = require(ReplicatedStorage.Shared.ScooterConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Activity.EconomyConfig)
local RewardMath = require(script.Parent.RewardMath)

type DeliveryRecord = {
	pickup: Instance,
	pickupName: string,
	stage: "Pickup" | "Dropoff",
	destination: Instance,
	destinationName: string,
	distance: number,
	travelled: number,
	position: Vector3?,
	sampledAt: number,
	character: Model?,
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
local motions: { [Player]: {model: Model, motion: RewardMath.Motion} } = {}
local lastInteraction: {[Player]: number} = {}
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
		and character ~= nil and character:FindFirstChildOfClass("Humanoid") ~= nil
		and (character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health>0
		and position ~= nil
		and (root.Position - position).Magnitude <= ActivityConfig.InteractionDistance + 3
end

local function setDeliveryAttributes(player: Player, delivery: DeliveryRecord?)
	if delivery then
		player:SetAttribute("DeliveryActive", true)
		player:SetAttribute("DeliveryStage", delivery.stage)
		player:SetAttribute("DeliveryPickup", delivery.pickupName)
		player:SetAttribute("DeliveryDestination", if delivery.stage=="Pickup" then delivery.pickupName else delivery.destinationName)
		player:SetAttribute("DeliveryReward", RewardMath.Delivery(delivery.distance))
		local target=if delivery.stage=="Pickup" then delivery.pickup else delivery.destination
		local targetPosition=positionOf(target)
		player:SetAttribute("DeliveryTargetPosition",targetPosition)
		local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		player:SetAttribute("DeliveryDistance",if targetPosition and root and root:IsA("BasePart") then (targetPosition-root.Position).Magnitude else delivery.distance)
	else
		player:SetAttribute("DeliveryActive", false)
		player:SetAttribute("DeliveryStage", nil)
		player:SetAttribute("DeliveryPickup", nil)
		player:SetAttribute("DeliveryReward", nil)
		player:SetAttribute("DeliveryDestination", nil)
		player:SetAttribute("DeliveryDistance", nil)
		player:SetAttribute("DeliveryTargetPosition",nil)
	end
end

local function chooseDestination(origin: Vector3): (Instance?, number)
	local available: { { instance: Instance, distance: number } } = {}
	for _, candidate in CollectionService:GetTagged(ActivityConfig.DestinationTag) do
		if candidate:IsDescendantOf(Workspace) then
			local position = positionOf(candidate)
			if position and (position-origin).Magnitude>ActivityConfig.InteractionDistance*2 then
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

function ActivityService.AcceptDelivery(player: Player): (boolean, string)
	if player.Parent~=Players or not PlayerDataService.Ready(player) then return false,"Dane gracza są niedostępne." end
	if deliveries[player] then return false,"Masz już aktywne zlecenie." end
	local pickups: {Instance} = {}
	for _,candidate in CollectionService:GetTagged(ActivityConfig.PickupTag) do
		if candidate:IsDescendantOf(Workspace) and positionOf(candidate) then table.insert(pickups,candidate) end
	end
	if #pickups==0 then return false,"Brak dostępnych sklepów odbioru." end
	local pickup=pickups[math.random(1,#pickups)]
	local origin=positionOf(pickup) :: Vector3
	local destination,distance=chooseDestination(origin)
	if not destination then return false,"Brak dostępnych budynków dostawy." end
	local delivery: DeliveryRecord = {
		pickup=pickup,pickupName=destinationName(pickup),stage="Pickup",
		destination=destination,destinationName=destinationName(destination),
		distance=distance,travelled=0,position=nil,sampledAt=os.clock(),character=player.Character,
	}
	deliveries[player]=delivery
	setDeliveryAttributes(player,delivery)
	return true,"Zlecenie przyjęte. Odbierz zamówienie w wyznaczonym sklepie."
end

function ActivityService.CancelDelivery(player: Player): (boolean, string)
	if not deliveries[player] then return false,"Nie masz aktywnego zlecenia." end
	deliveries[player]=nil
	setDeliveryAttributes(player,nil)
	return true,"Zlecenie anulowane."
end

local function collectOrder(player: Player, pickup: Instance): (boolean,string)
	local delivery=deliveries[player]
	if not delivery then return false,"Najpierw przyjmij zlecenie w aplikacji Dostawy w telefonie." end
	if delivery.stage~="Pickup" or delivery.pickup~=pickup then return false,"To nie jest sklep odbioru twojego zlecenia." end
	if not PlayerDataService.Ready(player) then return false,"Dane gracza są niedostępne." end
	delivery.stage="Dropoff"
	delivery.travelled=0
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	delivery.position=if root and root:IsA("BasePart") then root.Position else nil
	delivery.character=character
	delivery.sampledAt=os.clock()
	setDeliveryAttributes(player,delivery)
	return true,"Zamówienie odebrane. Dostarcz je pod wskazany budynek."
end

local function finishDelivery(player: Player, destination: Instance): (boolean, string)
	local delivery = deliveries[player]
	if not delivery or delivery.stage~="Dropoff" or delivery.destination ~= destination then
		return false, "To nie jest cel twojej dostawy."
	end
	if delivery.travelled < math.max(0,delivery.distance-ActivityConfig.InteractionDistance*2) then
		return false,"Trasa dostawy nie została jeszcze poprawnie pokonana."
	end
	-- The assigned route is fixed, so looping around cannot inflate the order price.
	-- Check the final displacement too: a prompt can arrive before the next heartbeat.
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local human=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local riding=Scooter.GetRidingState(player)
	if not root or not root:IsA("BasePart") or not human or human.Health<=0 or delivery.character~=player.Character or not delivery.position then return false,"Zlecenie jest niedostępne." end
	local delta=root.Position-delivery.position
	local flat=Vector3.new(delta.X,0,delta.Z)
	local limit=if riding then riding.maxSpeedKmh*ScooterConfig.StudsPerKmH else human.WalkSpeed
	if flat.Magnitude>limit*math.max(0,os.clock()-delivery.sampledAt)*EconomyConfig.MotionTolerance+0.5 or math.abs(delta.Y)>EconomyConfig.MaxVerticalStep then
		ActivityService.CancelDelivery(player)
		return false,"Nieprawidłowy ruch na trasie. Zlecenie anulowane."
	end
	local coins = RewardMath.Delivery(delivery.distance)
	if not PlayerDataService.Ready(player) then return false,"Dane gracza są niedostępne." end
	-- Consume before crediting, with no yield between these operations.
	deliveries[player] = nil
	PlayerDataService.AddCurrency(player, coins, ActivityConfig.BaseXP,"DeliveryCompleted")
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
	prompt.ActionText = if isPickup then "Odbierz zamówienie" else "Dostarcz zamówienie"
	prompt.ObjectText = destinationName(instance)
	promptConnections[instance] = prompt.Triggered:Connect(function(player: Player)
		if player.Parent~=Players or not instance:IsDescendantOf(Workspace) or not CollectionService:HasTag(instance,if isPickup then ActivityConfig.PickupTag else ActivityConfig.DestinationTag) then return end
		if os.clock()-(lastInteraction[player] or -math.huge)<0.5 then return end
		lastInteraction[player]=os.clock()
		local success: boolean
		local message: string
		if not playerIsNear(player, instance) then
			success, message = false, "Podejdz blizej do punktu."
		else
			success, message = if isPickup then collectOrder(player, instance) else finishDelivery(player, instance)
		end
		player:SetAttribute("ActivityMessage", message)
		player:SetAttribute("ActivityMessageSuccess", success)
		local oldNonce = player:GetAttribute("ActivityMessageNonce")
		local nonce = if typeof(oldNonce) == "number" then oldNonce else 0
		player:SetAttribute("ActivityMessageNonce", nonce + 1)
	end)
end

local function detachPrompt(instance: Instance)
	for player,delivery in deliveries do if delivery.destination==instance or delivery.pickup==instance then deliveries[player]=nil;setDeliveryAttributes(player,nil) end end
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

-- Presentation only: values are measured by RewardMath on the server. The last values stay
-- after the wheelie ends so the HUD can show the final result before hiding.
local function publishWheelie(player: Player, motion: RewardMath.Motion?)
	local active=motion~=nil and motion.wheelieTime>0
	-- Values first: the client reads them when the active flag flips on.
	if motion and active then
		player:SetAttribute("RideWheelieSeconds",math.floor(motion.wheelieTime*100+0.5)/100)
		player:SetAttribute("RideWheelieMeters",math.floor(motion.wheelieDistance/EconomyConfig.StudsPerKilometer*10000+0.5)/10)
	end
	player:SetAttribute("RideWheelieActive",active)
end

local function updateDistance(player: Player, elapsed: number)
	local character=player.Character
	local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	local delivery=deliveries[player]
	local state=Scooter.GetRidingState(player)
	if delivery and root and root:IsA("BasePart") then
		local human=character and character:FindFirstChildOfClass("Humanoid")
		local previous=delivery.position
		if delivery.character~=character then
			ActivityService.CancelDelivery(player)
			player:SetAttribute("ActivityMessage","Zlecenie anulowane po odrodzeniu.")
		else
			delivery.position=root.Position
			delivery.sampledAt=os.clock()
			if delivery.stage=="Dropoff" and previous and human and human.Health>0 and elapsed>0 then
				local delta=root.Position-previous
				local flat=Vector3.new(delta.X,0,delta.Z)
				local limit=if state then state.maxSpeedKmh*ScooterConfig.StudsPerKmH else human.WalkSpeed
				if flat.Magnitude>limit*elapsed*EconomyConfig.MotionTolerance+0.5 or math.abs(delta.Y)>EconomyConfig.MaxVerticalStep then
					ActivityService.CancelDelivery(player)
					player:SetAttribute("ActivityMessage","Zlecenie anulowane: nieprawidłowy ruch na trasie.")
				elseif elapsed<=EconomyConfig.MaxSampleSeconds and flat:Dot(root.AssemblyLinearVelocity)>0 then
					delivery.travelled+=flat.Magnitude
				end
			end
			local target=if delivery.stage=="Pickup" then delivery.pickup else delivery.destination
			local targetPosition=positionOf(target)
			if deliveries[player] and targetPosition then player:SetAttribute("DeliveryDistance",(targetPosition-root.Position).Magnitude)
			elseif deliveries[player] then ActivityService.CancelDelivery(player) end
		end
	end
	if not state or not PlayerDataService.Ready(player) then
		-- Wheelie end goes out before the x1 reset so the HUD can hold the final multiplier.
		publishWheelie(player,nil)
		motions[player]=nil;player:SetAttribute("RideRewardActive",false);player:SetAttribute("RideRewardMultiplier",1)
		return
	end
	player:SetAttribute("RideRewardActive",true)
	local record=motions[player]
	if not record or record.model~=state.model then
		record={model=state.model,motion=RewardMath.NewMotion(state.root.Position)};motions[player]=record
		publishWheelie(player,nil);player:SetAttribute("RideRewardMultiplier",1);return
	end
	local studs,multiplier,average=RewardMath.Sample(record.motion,state.root.Position,state.root.AssemblyLinearVelocity,
		state.maxSpeedKmh*ScooterConfig.StudsPerKmH,state.grounded,state.wheelie,state.burnout,elapsed)
	publishWheelie(player,record.motion)
	player:SetAttribute("RideRewardMultiplier",math.floor(multiplier*100+0.5)/100)
	if state.burnout and elapsed<=EconomyConfig.MaxSampleSeconds then PlayerDataService.RecordTimedReward(player,"Burnout",elapsed) end
	if studs<=0 then return end
	PlayerDataService.RecordRide(player,studs,average)
	local kilometers=studs/EconomyConfig.StudsPerKilometer
	PlayerDataService.Increment(player,"totalDistanceKm",kilometers)
	PlayerDataService.IncrementDaily(player,"DailyDistanceKm",kilometers)
	local hour=Lighting.ClockTime
	if hour>=18 or hour<6 then PlayerDataService.IncrementDaily(player,"DailyNightDistanceKm",kilometers) end
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
		motions[player] = nil
		lastInteraction[player]=nil
	end))
	local accumulated = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime)
		accumulated += deltaTime
		if accumulated >= EconomyConfig.SampleInterval then
			local elapsed=accumulated
			accumulated = 0
			for _, player in Players:GetPlayers() do
				updateDistance(player,elapsed)
			end
		end
	end))
end

function ActivityService.Stop()
	if not started then return end
	started=false
	for _,connection in connections do connection:Disconnect() end
	table.clear(connections)
	for instance,connection in promptConnections do connection:Disconnect();promptConnections[instance]=nil end
	for model,record in trickRecords do
		for _,connection in record.connections do connection:Disconnect() end
		trickRecords[model]=nil
	end
	for player in deliveries do setDeliveryAttributes(player,nil) end
	table.clear(deliveries);table.clear(motions);table.clear(lastInteraction)
end

return ActivityService
