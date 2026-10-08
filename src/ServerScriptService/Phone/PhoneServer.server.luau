--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local GangService = require(script.Parent.Parent.Gang.GangService)
local GangRequests = require(script.Parent.Parent.Gang.GangRequests)
local CombatService = require(script.Parent.Parent.Combat.CombatService)
local ScooterServer = require(script.Parent.Parent.Scooter.ScooterServer)

type GangState = GangService.GangState

type DeliveryState = {
	active: boolean,
	destination: string,
	distance: number,
}
type DailyState = {
	id: string,
	progress: number,
	target: number,
}
type PhoneState = {
	passiveEnabled: boolean,
	passiveAvailable: boolean,
	gangName: string?,
	gang: GangState,
	delivery: DeliveryState,
	daily: { DailyState },
	ownedScooters: { string },
	loginStreak: number,
	loginReward: number,
}

local lastRequestAt: { [Player]: number } = {}
local pendingRequests: { [Player]: boolean } = {}

local remotes = ReplicatedStorage:FindFirstChild(PhoneConfig.RemoteFolderName)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = PhoneConfig.RemoteFolderName
	remotes.Parent = ReplicatedStorage
end

local existingRequest = remotes:FindFirstChild(PhoneConfig.RequestFunctionName)
local request: RemoteFunction
if existingRequest and existingRequest:IsA("RemoteFunction") then
	request = existingRequest
else
	request = Instance.new("RemoteFunction")
	request.Name = PhoneConfig.RequestFunctionName
	request.Parent = remotes
end

local existingStateChanged = remotes:FindFirstChild(PhoneConfig.StateChangedEventName)
local stateChanged: RemoteEvent
if existingStateChanged and existingStateChanged:IsA("RemoteEvent") then
	stateChanged = existingStateChanged
else
	stateChanged = Instance.new("RemoteEvent")
	stateChanged.Name = PhoneConfig.StateChangedEventName
	stateChanged.Parent = remotes
end

GangService.Start()
GangService.SetChangedCallback(function(player: Player)
	stateChanged:FireClient(player)
end)

local function optionalStringAttribute(player: Player, name: string): string?
	local value = player:GetAttribute(name)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

local function numericAttribute(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" and value == value then math.max(0, value) else 0
end

local function getState(player: Player): PhoneState
	local gangName = optionalStringAttribute(player, "GangName")
	local ownedScooters: { string } = {}
	for _, product in ShopConfig.CoinProducts do
		if product.price == 0 or (product.stat ~= nil and player:GetAttribute(product.stat) == true) then
			table.insert(ownedScooters, product.name)
		end
	end

	local daily: { DailyState } = {}
	for _, mission in PhoneConfig.DailyMissions do
		table.insert(daily, {
			id = mission.id,
			progress = math.min(numericAttribute(player, mission.progressAttribute), mission.target),
			target = mission.target,
		})
	end

	local passiveAvailable = true

	return {
		passiveEnabled = passiveAvailable and player:GetAttribute("PassiveMode") == true,
		passiveAvailable = passiveAvailable,
		gangName = gangName,
		gang = GangService.GetState(player),
		delivery = {
			active = player:GetAttribute("DeliveryActive") == true,
			destination = optionalStringAttribute(player, "DeliveryDestination") or "",
			distance = numericAttribute(player, "DeliveryDistance"),
		},
		daily = daily,
		ownedScooters = ownedScooters,
		loginStreak = numericAttribute(player, "DailyLoginStreak"),
		loginReward = numericAttribute(player, "DailyLoginReward"),
	}
end

local function response(success: boolean, message: string, player: Player)
	return success, message, getState(player)
end

local function handleRequest(player: Player, action: string, payload: unknown)
	if action == "GetState" then
		if payload ~= nil then return response(false, "Nieprawidłowe żądanie.", player) end
		return response(true, "", player)
	end
	if action == "SetPassive" then
		if typeof(payload) ~= "boolean" then return response(false, "Nieprawidłowy tryb ochrony.", player) end
		local success, message = CombatService.SetPassive(player, payload)
		GangService.NotifyAll()
		return response(success, message, player)
	end
	if action == "SpawnScooter" then
		if typeof(payload) ~= "string" or #payload > 64 then return response(false, "Nieprawidłowy model.", player) end
		local success, message = ScooterServer.RequestSpawnForPlayer(player, payload)
		return response(success, message, player)
	end
	if GangRequests.IsCommand(action) then
		local success, message = GangRequests.Handle(player, action, payload)
		return response(success, message, player)
	end
	return response(false, "Nieznana operacja.", player)
end

request.OnServerInvoke = function(player: Player, action: unknown, payload: unknown, ...: unknown)
	if player.Parent ~= Players or select("#", ...) ~= 0 or typeof(action) ~= "string" or #action > 32 then
		return false, "Nieprawidłowe żądanie.", nil
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < PhoneConfig.RequestCooldown or pendingRequests[player] then
		return false, if action == "GetState" then "" else "Zwolnij na moment.", nil
	end
	lastRequestAt[player] = now
	pendingRequests[player] = true
	local ok, success, message, state = pcall(handleRequest, player, action, payload)
	pendingRequests[player] = nil
	if not ok then
		warn("PhoneServer: request failed: " .. tostring(success))
		return false, "Telefon jest chwilowo niedostępny.", nil
	end
	return success, message, state
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAt[player] = nil
	pendingRequests[player] = nil
end)
