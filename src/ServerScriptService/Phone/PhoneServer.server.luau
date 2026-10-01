--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local GangService = require(script.Parent.Parent.Gang.GangService)
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

	local passiveAvailable = gangName == nil
	if not passiveAvailable and player:GetAttribute("PassiveMode") == true then
		player:SetAttribute("PassiveMode", false)
	end

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

request.OnServerInvoke = function(player: Player, action: unknown, payload: unknown)
	if typeof(action) ~= "string" then
		return response(false, "Nieprawidlowe zadanie.", player)
	end
	if action == "GetState" then
		return response(true, "", player)
	end

	local now = os.clock()
	if now - (lastRequestAt[player] or 0) < PhoneConfig.RequestCooldown then
		return response(false, "Zwolnij na moment.", player)
	end
	lastRequestAt[player] = now

	if action == "SetPassive" then
		if typeof(payload) ~= "boolean" then
			return response(false, "Nieprawidlowy tryb ochrony.", player)
		end
		if optionalStringAttribute(player, "GangName") ~= nil then
			player:SetAttribute("PassiveMode", false)
			return response(false, "Czlonkowie gangu nie moga wlaczyc ochrony.", player)
		end
		player:SetAttribute("PassiveMode", payload)
		return response(true, if payload then "Tryb ochronny wlaczony." else "Tryb ochronny wylaczony.", player)
	end

	if action == "SpawnScooter" then
		if typeof(payload) ~= "string" or #payload > 64 then
			return response(false, "Nieprawidlowy model.", player)
		end
		local success, message = ScooterServer.RequestSpawnForPlayer(player, payload)
		return response(success, message, player)
	end

	if action == "CreateGang" then
		if typeof(payload) ~= "string" or #payload > 64 then
			return response(false, "Nieprawidlowa nazwa.", player)
		end
		local success, message = GangService.Create(player, payload)
		return response(success, message, player)
	end

	if action == "InviteGangMember" then
		if typeof(payload) ~= "number" or payload ~= math.floor(payload) or payload < 1 or payload > 9_007_199_254_740_991 then
			return response(false, "Nieprawidlowy gracz.", player)
		end
		local success, message = GangService.Invite(player, payload)
		return response(success, message, player)
	end

	if action == "RespondGangInvite" then
		if typeof(payload) ~= "boolean" then
			return response(false, "Nieprawidlowa odpowiedz.", player)
		end
		local success, message = GangService.RespondInvite(player, payload)
		return response(success, message, player)
	end

	if action == "KickGangMember" then
		if typeof(payload) ~= "number" or payload ~= math.floor(payload) or payload < 1 or payload > 9_007_199_254_740_991 then
			return response(false, "Nieprawidlowy gracz.", player)
		end
		local success, message = GangService.Kick(player, payload)
		return response(success, message, player)
	end

	if action == "LeaveGang" then
		local success, message = GangService.Leave(player)
		return response(success, message, player)
	end

	return response(false, "Nieznana operacja.", player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAt[player] = nil
end)
