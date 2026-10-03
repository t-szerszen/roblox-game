--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityConfig = require(ReplicatedStorage.Shared.Activity.ActivityConfig)
local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local ScooterConfig = require(ReplicatedStorage.Shared.ScooterConfig)

export type VisualPreference = { enabled: boolean, color: { number } }

export type Profile = {
	coins: number,
	xp: number,
	deliveries: number,
	raceWins: number,
	longestBurnout: number,
	longestWheelie: number,
	totalDistanceKm: number,
	dailyDate: string,
	daily: { [string]: number },
	loginDay: number,
	loginStreak: number,
	owned: { [string]: boolean },
	scooterUpgrades: { [string]: number },
	scooterVisuals: { Smoke: VisualPreference, Neon: VisualPreference },
	canCreateGang: boolean,
	ownsPepperSpray: boolean,
}

local PlayerDataService = {}
local profileStore = DataStoreService:GetDataStore("PlayerProfiles_v1")
local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local statConnections: { [Player]: { RBXScriptConnection } } = {}
local started = false
local shuttingDown = false

local function utcDate(): string
	return os.date("!%Y-%m-%d")
end

local function utcDay(): number
	return math.floor(os.time() / 86_400)
end

local function defaultProfile(): Profile
	return {
		coins = 0,
		xp = 0,
		deliveries = 0,
		raceWins = 0,
		longestBurnout = 0,
		longestWheelie = 0,
		totalDistanceKm = 0,
		dailyDate = utcDate(),
		daily = {},
		loginDay = 0,
		loginStreak = 0,
		owned = {},
		scooterUpgrades = {},
		scooterVisuals = {
			Smoke = { enabled = false, color = { 1, 1, 1 } },
			Neon = { enabled = false, color = { 0, 1, 1 } },
		},
		canCreateGang = false,
		ownsPepperSpray = false,
	}
end

local function finiteNumber(value: unknown, fallback: number): number
	return if typeof(value) == "number" and value == value and math.abs(value) < math.huge then value else fallback
end

local function deserialize(value: unknown): Profile
	local profile = defaultProfile()
	if typeof(value) ~= "table" then
		return profile
	end
	local data = value :: { [string]: any }
	profile.coins = math.max(0, math.floor(finiteNumber(data.coins, 0)))
	profile.xp = math.max(0, math.floor(finiteNumber(data.xp, 0)))
	profile.deliveries = math.max(0, math.floor(finiteNumber(data.deliveries, 0)))
	profile.raceWins = math.max(0, math.floor(finiteNumber(data.raceWins, 0)))
	profile.longestBurnout = math.max(0, finiteNumber(data.longestBurnout, 0))
	profile.longestWheelie = math.max(0, finiteNumber(data.longestWheelie, 0))
	profile.totalDistanceKm = math.max(0, finiteNumber(data.totalDistanceKm, 0))
	profile.dailyDate = if typeof(data.dailyDate) == "string" then data.dailyDate else utcDate()
	profile.loginDay = math.floor(finiteNumber(data.loginDay, 0))
	profile.loginStreak = math.clamp(math.floor(finiteNumber(data.loginStreak, 0)), 0, 7)
	profile.canCreateGang = data.canCreateGang == true
	profile.ownsPepperSpray = data.ownsPepperSpray == true
	if typeof(data.daily) == "table" then
		for key, amount in data.daily do
			if typeof(key) == "string" then
				profile.daily[key] = math.max(0, finiteNumber(amount, 0))
			end
		end
	end
	if typeof(data.owned) == "table" then
		for key, owned in data.owned do
			if typeof(key) == "string" and owned == true then
				profile.owned[key] = true
			end
		end
	end
	if typeof(data.scooterUpgrades) == "table" then
		for modelName in ScooterConfig.Models do
			local tier = data.scooterUpgrades[modelName]
			if ScooterConfig.IsValidSpeedTier(tier) then
				profile.scooterUpgrades[modelName] = tier
			end
		end
	end
	if typeof(data.scooterVisuals) == "table" then
		for _, kind in { "Smoke", "Neon" } do
			local preference = data.scooterVisuals[kind]
			if typeof(preference) == "table" and typeof(preference.color) == "table" then
				local color = preference.color
				local r, g, b = finiteNumber(color[1], -1), finiteNumber(color[2], -1), finiteNumber(color[3], -1)
				if r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
					local visual = { enabled = preference.enabled == true, color = { r, g, b } }
					if kind == "Smoke" then
						profile.scooterVisuals.Smoke = visual
					else
						profile.scooterVisuals.Neon = visual
					end
				end
			end
		end
	end
	return profile
end

local function resetDailyIfNeeded(profile: Profile): boolean
	local today = utcDate()
	if profile.dailyDate ~= today then
		profile.dailyDate = today
		table.clear(profile.daily)
		return true
	end
	return false
end

local function syncAttributes(player: Player, profile: Profile)
	player:SetAttribute("XP", profile.xp)
	player:SetAttribute("Deliveries", profile.deliveries)
	player:SetAttribute("RaceWins", profile.raceWins)
	player:SetAttribute("LongestBurnout", profile.longestBurnout)
	player:SetAttribute("LongestWheelie", profile.longestWheelie)
	player:SetAttribute("TotalDistanceKm", profile.totalDistanceKm)
	player:SetAttribute("DailyLoginStreak", profile.loginStreak)
	player:SetAttribute("CanCreateGang", profile.canCreateGang)
	player:SetAttribute("OwnsPepperSpray", profile.ownsPepperSpray)
	for key, value in profile.daily do
		player:SetAttribute(key, value)
	end
	for _, product in ShopConfig.CoinProducts do
		if product.stat then
			player:SetAttribute(product.stat, product.price == 0 or profile.owned[product.stat] == true)
		end
	end
end

local function makeLeaderstats(player: Player, profile: Profile)
	local previousConnections = statConnections[player]
	if previousConnections then
		for _, connection in previousConnections do
			connection:Disconnect()
		end
	end
	local connections: { RBXScriptConnection } = {}
	statConnections[player] = connections
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.coins
	coins.Parent = leaderstats
	table.insert(connections, coins.Changed:Connect(function(value: number)
		profile.coins = math.max(0, math.floor(value))
	end))
	local xp = Instance.new("IntValue")
	xp.Name = "XP"
	xp.Value = profile.xp
	xp.Parent = leaderstats
	table.insert(connections, xp.Changed:Connect(function(value: number)
		profile.xp = math.max(0, math.floor(value))
		player:SetAttribute("XP", profile.xp)
	end))
end

local function applyDailyLogin(player: Player, profile: Profile)
	local today = utcDay()
	if profile.loginDay == today then
		return
	end
	profile.loginStreak = if profile.loginDay == today - 1 then (profile.loginStreak % 7) + 1 else 1
	profile.loginDay = today
	local reward = ActivityConfig.DailyLoginCoinRewards[profile.loginStreak] or 0
	profile.coins += reward
	player:SetAttribute("DailyLoginStreak", profile.loginStreak)
	player:SetAttribute("DailyLoginReward", reward)
end

local function savePlayer(player: Player)
	local profile = profiles[player]
	if not profile or not canSave[player] then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	local xp = if leaderstats then leaderstats:FindFirstChild("XP") else nil
	if coins and coins:IsA("IntValue") then
		profile.coins = coins.Value
	end
	if xp and xp:IsA("IntValue") then
		profile.xp = xp.Value
	end
	for _, product in ShopConfig.CoinProducts do
		if product.stat and player:GetAttribute(product.stat) == true then
			profile.owned[product.stat] = true
		end
	end
	profile.canCreateGang = player:GetAttribute("CanCreateGang") == true
	profile.ownsPepperSpray = player:GetAttribute("OwnsPepperSpray") == true
	local success, message = pcall(function()
		profileStore:SetAsync(tostring(player.UserId), profile)
	end)
	if not success then
		warn(string.format("PlayerDataService: save failed for %s: %s", player.Name, tostring(message)))
	end
end

local function loadPlayer(player: Player)
	local loaded: unknown = nil
	local success, message = pcall(function()
		loaded = profileStore:GetAsync(tostring(player.UserId))
	end)
	if not success then
		warn(string.format("PlayerDataService: load failed for %s; using session data: %s", player.Name, tostring(message)))
	end
	-- An outstanding datastore request can complete after the player has left.
	if player.Parent ~= Players or shuttingDown then
		return
	end
	local profile = deserialize(loaded)
	resetDailyIfNeeded(profile)
	profiles[player] = profile
	-- Never overwrite a real profile after a failed read with temporary defaults.
	canSave[player] = success
	applyDailyLogin(player, profile)
	makeLeaderstats(player, profile)
	syncAttributes(player, profile)
	player:SetAttribute("DataPersistenceAvailable", success)
	player:SetAttribute("DataLoaded", true)
end

function PlayerDataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

function PlayerDataService.OwnsScooter(player: Player, modelName: string): boolean
	local product = ShopConfig.GetScooterProduct(modelName)
	if not product or not product.stat then
		return false
	end
	local profile = profiles[player]
	return product.price == 0 or (profile ~= nil and profile.owned[product.stat] == true)
end

local function transactionCoins(player: Player): (Profile?, IntValue?)
	local profile = profiles[player]
	if not profile or not canSave[player] or player.Parent ~= Players then
		return nil, nil
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	return profile, if coins and coins:IsA("IntValue") then coins else nil
end

function PlayerDataService.PurchaseScooter(player: Player, modelName: string): (boolean, string)
	local product = ShopConfig.GetScooterProduct(modelName)
	if not product or not product.stat then
		return false, "InvalidModel"
	end
	local profile, coins = transactionCoins(player)
	if not profile or not coins then
		return false, "DataUnavailable"
	end
	if PlayerDataService.OwnsScooter(player, modelName) then
		return false, "AlreadyOwned"
	end
	if coins.Value < product.price then
		return false, "InsufficientCoins"
	end
	-- Validation, debit and ownership update must remain in one non-yielding transaction.
	profile.coins = coins.Value - product.price
	profile.owned[product.stat] = true
	coins.Value = profile.coins
	player:SetAttribute(product.stat, true)
	return true, "Purchased"
end

function PlayerDataService.PurchaseSpeedUpgrade(player: Player, modelName: string, expectedTier: number): (boolean, string)
	if not ScooterConfig.Models[modelName] or not ScooterConfig.IsValidSpeedTier(expectedTier) then
		return false, "InvalidUpgrade"
	end
	local profile, coins = transactionCoins(player)
	if not profile or not coins then
		return false, "DataUnavailable"
	end
	if not PlayerDataService.OwnsScooter(player, modelName) then
		return false, "NotOwned"
	end
	local currentTier = profile.scooterUpgrades[modelName] or 0
	if currentTier ~= expectedTier then
		return false, "StaleTier"
	end
	local price = ScooterConfig.GetUpgradeCost(modelName, currentTier)
	if not price then
		return false, "MaximumTier"
	end
	if coins.Value < price then
		return false, "InsufficientCoins"
	end
	-- Checking the expected tier makes delayed duplicate requests harmless.
	profile.coins = coins.Value - price
	profile.scooterUpgrades[modelName] = currentTier + 1
	coins.Value = profile.coins
	return true, "Purchased"
end

function PlayerDataService.SetScooterVisual(player: Player, kind: "Smoke" | "Neon", enabled: boolean, color: Color3): boolean
	local profile = profiles[player]
	if not profile or not canSave[player] or player.Parent ~= Players then
		return false
	end
	local preference = { enabled = enabled, color = { color.R, color.G, color.B } }
	if kind == "Smoke" then
		profile.scooterVisuals.Smoke = preference
	else
		profile.scooterVisuals.Neon = preference
	end
	return true
end

function PlayerDataService.AddCurrency(player: Player, coinsAmount: number, xpAmount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	local xp = if leaderstats then leaderstats:FindFirstChild("XP") else nil
	if coins and coins:IsA("IntValue") then
		coins.Value += math.max(0, math.floor(coinsAmount))
	end
	if xp and xp:IsA("IntValue") then
		xp.Value += math.max(0, math.floor(xpAmount))
	end
end

function PlayerDataService.Increment(player: Player, key: string, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	if key == "deliveries" then
		profile.deliveries += amount
		player:SetAttribute("Deliveries", profile.deliveries)
	elseif key == "raceWins" then
		profile.raceWins += amount
		player:SetAttribute("RaceWins", profile.raceWins)
	elseif key == "totalDistanceKm" then
		profile.totalDistanceKm += amount
		player:SetAttribute("TotalDistanceKm", profile.totalDistanceKm)
	end
end

function PlayerDataService.IncrementDaily(player: Player, attribute: string, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	if resetDailyIfNeeded(profile) then
		for _, mission in PhoneConfig.DailyMissions do
			player:SetAttribute(mission.progressAttribute, 0)
		end
	end
	profile.daily[attribute] = (profile.daily[attribute] or 0) + amount
	player:SetAttribute(attribute, profile.daily[attribute])
end

function PlayerDataService.SetBest(player: Player, key: string, value: number)
	local profile = profiles[player]
	if not profile or value <= 0 then
		return
	end
	if key == "longestBurnout" and value > profile.longestBurnout then
		profile.longestBurnout = value
		player:SetAttribute("LongestBurnout", value)
	elseif key == "longestWheelie" and value > profile.longestWheelie then
		profile.longestWheelie = value
		player:SetAttribute("LongestWheelie", value)
	end
end

function PlayerDataService.Start()
	if started then
		return
	end
	started = true
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		savePlayer(player)
		local playerStatConnections = statConnections[player]
		if playerStatConnections then
			for _, connection in playerStatConnections do
				connection:Disconnect()
			end
		end
		statConnections[player] = nil
		profiles[player] = nil
		canSave[player] = nil
	end)
	task.spawn(function()
		while not shuttingDown do
			task.wait(ActivityConfig.ProfileAutosaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(savePlayer, player)
			end
		end
	end)
	game:BindToClose(function()
		shuttingDown = true
		for _, player in Players:GetPlayers() do
			task.spawn(savePlayer, player)
		end
		task.wait(2)
	end)
end

return PlayerDataService
