--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScooterConfig = require(ReplicatedStorage.Shared.ScooterConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local PlayerDataService = require(script.Parent.Parent.Activity.PlayerDataService)

export type Visuals = {
	smokeEnabled: boolean,
	smokeColor: Color3,
	neonEnabled: boolean,
	neonColor: Color3,
}
export type ModelState = { owned: boolean, speedTier: number, maxSpeed: number, nextUpgradeCost: number? }
export type GarageState = {
	coins: number,
	dataReady: boolean,
	models: { [string]: ModelState },
	visuals: Visuals,
	smokeOwned: boolean,
	neonOwned: boolean,
}
type Entitlements = { smoke: boolean, neon: boolean, checkedAt: number }

local GarageService = {}
local started = false
local generation = 0
local changed: ((Player) -> ())? = nil
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: RBXScriptConnection } = {}
local entitlements: { [Player]: Entitlements } = {}
local checking: { [Player]: boolean } = {}
local refreshQueued: { [Player]: boolean } = {}
local pending: { [Player]: boolean } = {}
local lastRequest: { [Player]: number } = {}

local function notifyChanged(player: Player)
	local callback = changed
	if callback and player.Parent == Players then
		local success, message = pcall(function(): string?
			callback(player)
			return nil
		end)
		if not success then
			warn("GarageService: scooter refresh failed: " .. tostring(message))
		end
	end
end

local function ownsGamePass(player: Player, productName: string): boolean
	local product = ShopConfig.GetProduct(productName)
	local productId = if product then product.productId else nil
	if not product or product.kind ~= "GamePass" or not productId or productId <= 0 then
		return false
	end
	local success, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, productId)
	end)
	return success and owned == true
end

local function refreshEntitlements(player: Player, force: boolean): boolean
	if not started or player.Parent ~= Players then
		return false
	end
	local cached = entitlements[player]
	if not force and cached and os.clock() - cached.checkedAt < ScooterConfig.EntitlementCacheSeconds then
		return true
	end
	if checking[player] then
		if force then
			refreshQueued[player] = true
		end
		return false
	end
	local requestGeneration = generation
	checking[player] = true
	local smoke = ownsGamePass(player, "burnout_smoke")
	local neon = ownsGamePass(player, "scooter_neons")
	if not started or generation ~= requestGeneration or player.Parent ~= Players then
		return false
	end
	checking[player] = nil
	entitlements[player] = { smoke = smoke, neon = neon, checkedAt = os.clock() }
	notifyChanged(player)
	if refreshQueued[player] then
		refreshQueued[player] = nil
		task.defer(function()
			refreshEntitlements(player, true)
		end)
	end
	return true
end

function GarageService.OwnsModel(player: Player, modelName: string): boolean
	return ScooterConfig.Models[modelName] ~= nil and PlayerDataService.OwnsScooter(player, modelName)
end

function GarageService.GetTuning(player: Player, modelName: string): ScooterConfig.Tuning?
	if not GarageService.OwnsModel(player, modelName) then
		return nil
	end
	local profile = PlayerDataService.GetProfile(player)
	local tier = if profile then profile.scooterUpgrades[modelName] or 0 else 0
	return ScooterConfig.GetTuning(modelName, tier)
end

function GarageService.GetVisuals(player: Player): Visuals
	local profile = PlayerDataService.GetProfile(player)
	local verified = entitlements[player]
	local smoke = if profile then profile.scooterVisuals.Smoke else nil
	local neon = if profile then profile.scooterVisuals.Neon else nil
	local smokeEnabled = verified ~= nil and verified.smoke and smoke ~= nil and smoke.enabled
	local neonEnabled = verified ~= nil and verified.neon and neon ~= nil and neon.enabled
	return {
		smokeEnabled = smokeEnabled,
		smokeColor = if verified and verified.smoke and smoke then Color3.new(smoke.color[1], smoke.color[2], smoke.color[3]) else Color3.new(1, 1, 1),
		neonEnabled = neonEnabled,
		neonColor = if verified and verified.neon and neon then Color3.new(neon.color[1], neon.color[2], neon.color[3]) else Color3.new(0, 1, 1),
	}
end

local function getState(player: Player): GarageState
	local models: { [string]: ModelState } = {}
	for modelName, base in ScooterConfig.Models do
		local tuning = GarageService.GetTuning(player, modelName)
		local tier = if tuning then tuning.speedTier else 0
		models[modelName] = {
			owned = tuning ~= nil,
			speedTier = tier,
			maxSpeed = if tuning then tuning.maxSpeed else base.maxSpeed,
			nextUpgradeCost = ScooterConfig.GetUpgradeCost(modelName, tier),
		}
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	local verified = entitlements[player]
	return {
		coins = if coins and coins:IsA("IntValue") then coins.Value else 0,
		dataReady = PlayerDataService.GetProfile(player) ~= nil and player:GetAttribute("DataPersistenceAvailable") == true,
		models = models,
		visuals = GarageService.GetVisuals(player),
		smokeOwned = verified ~= nil and verified.smoke,
		neonOwned = verified ~= nil and verified.neon,
	}
end

local function validColor(color: unknown): boolean
	if typeof(color) ~= "Color3" then
		return false
	end
	for _, channel in { color.R, color.G, color.B } do
		if channel ~= channel or channel < 0 or channel > 1 then
			return false
		end
	end
	return true
end

local function executeRequest(player: Player, action: string, modelName: unknown, payload: unknown): (boolean, string, GarageState?)
	if action == "GetState" then
		if modelName ~= nil or payload ~= nil then
			return false, "InvalidRequest", nil
		end
		if not refreshEntitlements(player, false) then
			return false, "Busy", nil
		end
		return true, "", getState(player)
	elseif action == "PurchaseSpeed" then
		if typeof(modelName) ~= "string" or #modelName > 64 or typeof(payload) ~= "number" then
			return false, "InvalidRequest", nil
		end
		local success, reason = PlayerDataService.PurchaseSpeedUpgrade(player, modelName, payload)
		if success then
			notifyChanged(player)
		end
		return success, reason, getState(player)
	elseif action == "SetVisual" then
		if modelName ~= nil or typeof(payload) ~= "table" then
			return false, "InvalidRequest", nil
		end
		local preference = payload :: { [string]: unknown }
		for key in preference do
			if key ~= "kind" and key ~= "enabled" and key ~= "color" then
				return false, "InvalidRequest", nil
			end
		end
		local kind, enabled, color = preference.kind, preference.enabled, preference.color
		if (kind ~= "Smoke" and kind ~= "Neon") or typeof(enabled) ~= "boolean" or not validColor(color) then
			return false, "InvalidVisual", nil
		end
		if not refreshEntitlements(player, false) then
			return false, "Busy", nil
		end
		local verified = entitlements[player]
		local owned = verified ~= nil and (if kind == "Smoke" then verified.smoke else verified.neon)
		if not owned then
			return false, "GamePassRequired", getState(player)
		end
		local success = PlayerDataService.SetScooterVisual(player, kind :: "Smoke" | "Neon", enabled, color :: Color3)
		if success then
			notifyChanged(player)
		end
		return success, if success then "VisualUpdated" else "DataUnavailable", getState(player)
	end
	return false, "UnknownAction", nil
end

function GarageService.HandleRequest(player: Player, action: unknown, modelName: unknown, payload: unknown): (boolean, string, GarageState?)
	if not started or player.Parent ~= Players then
		return false, "Unavailable", nil
	end
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < ScooterConfig.GarageRequestCooldown then
		return false, "RateLimited", nil
	end
	lastRequest[player] = now
	if pending[player] then
		return false, "Busy", nil
	end
	if typeof(action) ~= "string" or #action > 32 then
		return false, "InvalidRequest", nil
	end
	pending[player] = true
	local requestGeneration = generation
	local ok, success, reason, state = pcall(executeRequest, player, action, modelName, payload)
	if generation ~= requestGeneration then
		return false, "Unavailable", nil
	end
	pending[player] = nil
	if not ok then
		warn("GarageService: request failed: " .. tostring(success))
		return false, "Unavailable", nil
	end
	return success, reason, state
end

local function removePlayer(player: Player)
	local connection = playerConnections[player]
	if connection then
		connection:Disconnect()
	end
	playerConnections[player] = nil
	entitlements[player] = nil
	checking[player] = nil
	refreshQueued[player] = nil
	pending[player] = nil
	lastRequest[player] = nil
end

local function addPlayer(player: Player)
	if not started or player.Parent ~= Players or playerConnections[player] then
		return
	end
	playerConnections[player] = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		notifyChanged(player)
	end)
	task.spawn(function()
		refreshEntitlements(player, false)
	end)
end

function GarageService.Start(onChanged: (Player) -> ())
	if started then
		return
	end
	started = true
	generation += 1
	changed = onChanged
	PlayerDataService.Start()
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	table.insert(connections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		for _, productName in { "burnout_smoke", "scooter_neons" } do
			local product = ShopConfig.GetProduct(productName)
			if product and product.productId and product.productId > 0 and product.productId == passId then
				-- The server rechecks MarketplaceService; a prompt or client flag never grants access.
				entitlements[player] = nil
				task.spawn(function()
					refreshEntitlements(player, true)
				end)
				return
			end
		end
	end))
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
end

function GarageService.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	changed = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in playerConnections do
		removePlayer(player)
	end
end

return GarageService
