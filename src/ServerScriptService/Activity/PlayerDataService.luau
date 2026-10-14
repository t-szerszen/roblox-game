--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeCatalog=require(ReplicatedStorage.Shared.ScooterUpgradeCatalog)
local CustomConfig=require(ReplicatedStorage.Shared.ScooterCustomConfig)
local Persistence = require(script.Parent.ProfilePersistence)
local EconomyConfig = require(ReplicatedStorage.Shared.Activity.EconomyConfig)

local ActivityConfig = require(ReplicatedStorage.Shared.Activity.ActivityConfig)
local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local ScooterConfig = require(ReplicatedStorage.Shared.ScooterConfig)
local CustomConfig = require(ReplicatedStorage.Shared.ScooterCustomConfig)
local UpgradeCatalog = require(ReplicatedStorage.Shared.ScooterUpgradeCatalog)

export type VisualPreference = { enabled: boolean, color: { number } }

export type Profile = {
	coins: number,
	unlocks: { [string]: boolean },
	selectedScooter: string,
	equippedItems: {[string]: boolean},
	visualsByModel: { [string]: { Smoke: VisualPreference, Neon: VisualPreference } },
	rainbowModels: { [string]: boolean },
	scooterEquipment: {[string]: {owned: {[string]: boolean},equipped: {[string]: boolean}}},
	scooterDesigns: {[string]: {[string]: {[string]: string}}},
	paintByModel: { [string]: { [string]: { number } } },
	rewardProgress: { rideStuds: number, rideCoins: number, rideRemainder: number, burnoutRemainder: number, gangRemainder: number },
	transactions: { { reason: string, amount: number, at: number } },
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
	scooterDesigns: {[string]: {[string]: {[string]: string}}},
	scooterEquipment: {[string]: {owned: {[string]: boolean}, equipped: {[string]: boolean}}},
	scooterVisuals: { Smoke: VisualPreference, Neon: VisualPreference },
	canCreateGang: boolean,
	ownsPepperSpray: boolean,
}

local PlayerDataService = {}
local profileStore = DataStoreService:GetDataStore("PlayerProfiles_v1")
local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local statConnections: { [Player]: { RBXScriptConnection } } = {}
local tokens: { [Player]: string } = {}
local saving: { [Player]: boolean } = {}
local purchasing: { [Player]: boolean } = {}
local queuedCredits: { [Player]: { {coins: number, xp: number, reason: string} } } = {}
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
		unlocks = {}, selectedScooter = ScooterConfig.DefaultModel, equippedItems = {},
		visualsByModel = {}, rainbowModels = {}, paintByModel = {}, scooterEquipment = {}, scooterDesigns = {},
		rewardProgress = {rideStuds=0,rideCoins=0,rideRemainder=0,burnoutRemainder=0,gangRemainder=0},
		transactions = {},
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
		scooterEquipment = {},
		scooterDesigns = {},
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
	if typeof(data.scooterEquipment) == "table" then
		for modelName in ScooterConfig.Models do
			local state = data.scooterEquipment[modelName]
			if typeof(state) == "table" then
				profile.scooterEquipment[modelName] = UpgradeCatalog.Normalize(state)
			end
		end
	end
	if typeof(data.scooterDesigns) == "table" then
		for modelName in ScooterConfig.Models do
			local saved = data.scooterDesigns[modelName]
			if typeof(saved) ~= "table" then continue end
			local slots: {[string]: {[string]: string}} = {}
			for index=1,CustomConfig.DesignSlots do
				local palette=saved[tostring(index)]
				if typeof(palette) ~= "table" then continue end
				local clean: {[string]: string} = {}
				for _,group in CustomConfig.Groups do
					local hex=palette[group.Id]
					if typeof(hex)=="string" and #hex==6 and hex:match("^%x+$") then clean[group.Id]=hex end
				end
				if next(clean) then slots[tostring(index)]=clean end
			end
			profile.scooterDesigns[modelName]=slots
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
	if typeof(data.unlocks) == "table" then
		for _, product in ShopConfig.GetScooters() do
			profile.unlocks[product.id] = product.price == 0 or data.unlocks[product.id] == true or (product.stat ~= nil and profile.owned[product.stat] == true)
		end
		for _, product in ShopConfig.RobuxProducts do profile.unlocks[product.id] = data.unlocks[product.id] == true end
	else
		for _, product in ShopConfig.GetScooters() do profile.unlocks[product.id] = product.price == 0 or (product.stat ~= nil and profile.owned[product.stat] == true) end
	end
	if profile.ownsPepperSpray then profile.unlocks.pepper_spray = true end
	if typeof(data.equippedItems)=="table" then for _,id in {"radio","pepper_spray"} do profile.equippedItems[id]=data.equippedItems[id]==true and profile.unlocks[id]==true end end
	local selected = if typeof(data.selectedScooter) == "string" then ShopConfig.GetScooterProduct(data.selectedScooter) else nil
	if selected and profile.unlocks[selected.id] then profile.selectedScooter = data.selectedScooter end
	if typeof(data.rewardProgress) == "table" then
		local raw = data.rewardProgress
		-- Older profiles accumulated a whole kilometer; keep the coins already earned as remainder.
		local legacyRide = finiteNumber(raw.rideStuds, 0) >= EconomyConfig.RideCoinStepStuds
		for key in profile.rewardProgress do
			local value = finiteNumber(raw[key], 0)
			local limit = 1
			if key == "rideStuds" then
				limit = EconomyConfig.RideCoinStepStuds
				if legacyRide then value = 0 end
			elseif key == "rideCoins" then
				limit = EconomyConfig.RideCoinsPerStep * EconomyConfig.WheelieMaxMultiplier
				if legacyRide then value = 0 end
			elseif key == "rideRemainder" then
				limit = EconomyConfig.RideCoinsPerKilometer * EconomyConfig.WheelieMaxMultiplier + 1
				if legacyRide then value += finiteNumber(raw.rideCoins, 0) end
			end
			profile.rewardProgress[key] = math.clamp(value, 0, limit - 0.000001)
		end
	end
	local function validRGB(color: any): boolean
		return typeof(color)=="table" and #color==3 and finiteNumber(color[1],-1)>=0 and finiteNumber(color[1],2)<=1
			and finiteNumber(color[2],-1)>=0 and finiteNumber(color[2],2)<=1 and finiteNumber(color[3],-1)>=0 and finiteNumber(color[3],2)<=1
	end
	for modelName in ScooterConfig.Models do
		local visual = if typeof(data.visualsByModel)=="table" then data.visualsByModel[modelName] else nil
		if typeof(visual)=="table" then
			profile.visualsByModel[modelName] = Persistence.Copy(profile.scooterVisuals)
			for _, kind in {"Smoke","Neon"} do
				if typeof(visual[kind])=="table" and validRGB(visual[kind].color) then profile.visualsByModel[modelName][kind]={enabled=visual[kind].enabled==true,color=table.clone(visual[kind].color)} end
			end
		end
		if typeof(data.rainbowModels)=="table" then profile.rainbowModels[modelName]=data.rainbowModels[modelName]==true end
		local paint = if typeof(data.paintByModel)=="table" then data.paintByModel[modelName] else nil
		if typeof(paint)=="table" then
			profile.paintByModel[modelName]={}
			for key,color in paint do if typeof(key)=="string" and #key<=40 and validRGB(color) then profile.paintByModel[modelName][key]=table.clone(color) end end
		end
	end
	profile.visualsByModel[ScooterConfig.DefaultModel] = profile.visualsByModel[ScooterConfig.DefaultModel] or Persistence.Copy(profile.scooterVisuals)
	if typeof(data.transactions)=="table" then
		for index=math.max(1,#data.transactions-EconomyConfig.TransactionHistoryLimit+1),#data.transactions do
			local entry=data.transactions[index]
			if typeof(entry)=="table" and typeof(entry.reason)=="string" and #entry.reason<=80 then
				table.insert(profile.transactions,{reason=entry.reason,amount=finiteNumber(entry.amount,0),at=finiteNumber(entry.at,0)})
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
	player:SetAttribute("OwnsPepperSpray", profile.unlocks.pepper_spray==true)
	player:SetAttribute("RadioEquipped", profile.equippedItems.radio==true)
	player:SetAttribute("SelectedScooter",profile.selectedScooter)
	for key, value in profile.daily do
		player:SetAttribute(key, value)
	end
	for _, product in ShopConfig.GetScooters() do
		if product.stat then
			player:SetAttribute(product.stat, product.price == 0 or profile.unlocks[product.id] == true)
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
		-- leaderstats is presentation; economic writes must use the central API.
		if value ~= profile.coins then coins.Value = profile.coins end
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
	PlayerDataService.AddCurrency(player,reward,0,"DailyLogin")
	player:SetAttribute("DailyLoginStreak", profile.loginStreak)
	player:SetAttribute("DailyLoginReward", reward)
end

local function savePlayer(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or not canSave[player] or saving[player] or purchasing[player] then return false end
	saving[player] = true
	local ok, reason = Persistence.Save(profileStore,tostring(player.UserId),tokens[player],profile,release == true)
	saving[player] = nil
	if not ok then
		warn(string.format("PlayerDataService: %s for %s",reason,player.Name))
		if reason == "SessionLost" then canSave[player]=false;player:SetAttribute("DataPersistenceAvailable",false) end
	end
	player:SetAttribute("LastSaveSucceeded",ok)
	return ok
end

function PlayerDataService.Save(player: Player): boolean return savePlayer(player) end

local function loadPlayer(player: Player)
	local token = Persistence.Token()
	local success, loaded = Persistence.Acquire(profileStore,tostring(player.UserId),token)
	if not success then warn("PlayerDataService: profile unavailable for "..player.Name) end
	if player.Parent ~= Players or shuttingDown then
		if success then Persistence.Save(profileStore,tostring(player.UserId),token,loaded,true) end
		return
	end
	tokens[player] = token
	local profile = deserialize(if success then loaded else nil)
	resetDailyIfNeeded(profile)
	profiles[player] = profile
	-- Never overwrite a real profile after a failed read with temporary defaults.
	canSave[player] = success
	player:SetAttribute("DataPersistenceAvailable",success)
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
	return product.price == 0 or (profile ~= nil and (profile.unlocks[product.id] == true or profile.owned[product.stat] == true))
end


local function publishCoins(player: Player, profile: Profile)
	local stats=player:FindFirstChild("leaderstats")
	local coins=if stats then stats:FindFirstChild("Coins") else nil
	if coins and coins:IsA("IntValue") then coins.Value=profile.coins end
end
local function journal(profile: Profile, amount: number, reason: string)
	local now=os.time()
	local last=profile.transactions[#profile.transactions]
	if last and last.reason==reason and amount>0 and last.amount>0 and now-last.at<=EconomyConfig.TransactionMergeSeconds then
		last.amount+=amount;last.at=now;return
	end
	table.insert(profile.transactions,{amount=amount,reason=reason,at=now})
	if #profile.transactions>EconomyConfig.TransactionHistoryLimit then table.remove(profile.transactions,1) end
end
function PlayerDataService.Ready(player: Player): boolean
	return not shuttingDown and profiles[player]~=nil and canSave[player]==true and player.Parent==Players and player:GetAttribute("DataPersistenceAvailable")==true
end
function PlayerDataService.OwnsProduct(player: Player, id: string): boolean
	local product=ShopConfig.GetProduct(id)
	local profile=profiles[player]
	return product~=nil and ((product.currency=="Coins" and product.price==0) or (profile~=nil and profile.unlocks[id]==true))
end
local function credit(player: Player, profile: Profile, amount: number, xpAmount: number, reason: string)
	profile.coins+=amount;profile.xp+=xpAmount
	if amount~=0 then journal(profile,amount,reason) end
	publishCoins(player,profile)
	local stats=player:FindFirstChild("leaderstats")
	local xp=if stats then stats:FindFirstChild("XP") else nil
	if xp and xp:IsA("IntValue") then xp.Value=profile.xp end
end
function PlayerDataService.AddCoins(player: Player, amount: number, reason: string): boolean
	return PlayerDataService.AddCurrency(player,amount,0,reason)
end
local function durable(player: Player, modify: (Profile) -> (boolean,string)): (boolean,string)
	local profile=profiles[player]
	if not PlayerDataService.Ready(player) or not profile then return false,"DataUnavailable" end
	if purchasing[player] or saving[player] then return false,"Busy" end
	purchasing[player]=true
	local candidate=Persistence.Copy(profile) :: Profile
	local checked,allowed,reason=pcall(modify,candidate)
	if not checked or not allowed then purchasing[player]=nil;return false,if checked then reason else "InvalidTransaction" end
	local saved,saveReason=Persistence.Save(profileStore,tostring(player.UserId),tokens[player],candidate,false)
	if saved then
		-- Other stat/progress updates may have occurred while persistence yielded.
		profile.coins=candidate.coins;profile.unlocks=candidate.unlocks;profile.owned=candidate.owned
		profile.scooterUpgrades=candidate.scooterUpgrades;profile.transactions=candidate.transactions
		profile.selectedScooter=candidate.selectedScooter;profile.ownsPepperSpray=candidate.ownsPepperSpray
		profile.equippedItems=candidate.equippedItems
		publishCoins(player,profile);syncAttributes(player,profile)
	elseif saveReason=="SessionLost" then canSave[player]=false;player:SetAttribute("DataPersistenceAvailable",false) end
	purchasing[player]=nil
	local credits=queuedCredits[player];queuedCredits[player]=nil
	if credits and canSave[player] then for _,entry in credits do credit(player,profile,entry.coins,entry.xp,entry.reason) end end
	return saved,if saved then reason else saveReason
end
function PlayerDataService.PurchaseProduct(player: Player, id: string): (boolean,string)
	local product=ShopConfig.GetProduct(id)
	local price=if product then (if product.currency=="Coins" then product.price else product.coinPrice) else nil
	if not product or price==nil or product.retired or product.assetReady==false then return false,"InvalidProduct" end
	return durable(player,function(candidate)
		if PlayerDataService.OwnsProduct(player,id) then return false,"AlreadyOwned" end
		if candidate.coins<price then return false,"InsufficientCoins" end
		candidate.coins-=price;candidate.unlocks[id]=true
		if product.stat then candidate.owned[product.stat]=true end
		journal(candidate,-price,"Purchase:"..id)
		return true,"Purchased"
	end)
end
function PlayerDataService.PurchaseScooter(player: Player, modelName: string): (boolean,string)
	local product=ShopConfig.GetScooterProduct(modelName)
	if not product then return false,"InvalidModel" end
	return PlayerDataService.PurchaseProduct(player,product.id)
end
function PlayerDataService.GrantProduct(player: Player, id: string): (boolean,string)
	local product=ShopConfig.GetProduct(id)
	if not product or product.kind~="GamePass" then return false,"InvalidProduct" end
	if PlayerDataService.OwnsProduct(player,id) then return true,"AlreadyOwned" end
	return durable(player,function(candidate)
		candidate.unlocks[id]=true
		if id=="pepper_spray" then candidate.ownsPepperSpray=true end
		journal(candidate,0,"VerifiedGamePass:"..id)
		return true,"Unlocked"
	end)
end
function PlayerDataService.SelectScooter(player: Player, modelName: string): (boolean,string)
	if not PlayerDataService.OwnsScooter(player,modelName) then return false,"NotOwned" end
	return durable(player,function(candidate) candidate.selectedScooter=modelName;return true,"Selected" end)
end
function PlayerDataService.SpendCoins(player: Player, amount: number, reason: string): (boolean,string)
	if typeof(amount)~="number" or amount~=amount or amount<=0 or amount%1~=0 or amount==math.huge
		or typeof(reason)~="string" or #reason==0 or #reason>80 then return false,"InvalidTransaction" end
	return durable(player,function(candidate)
		if candidate.coins<amount then return false,"InsufficientCoins" end
		candidate.coins-=amount;journal(candidate,-amount,reason);return true,"Debited"
	end)
end

function PlayerDataService.PurchaseSpeedUpgrade(player: Player, modelName: string, expectedTier: number): (boolean, string)
	if not ScooterConfig.Models[modelName] or not ScooterConfig.IsValidSpeedTier(expectedTier) then
		return false, "InvalidUpgrade"
	end
	return durable(player,function(candidate)
		if not PlayerDataService.OwnsScooter(player,modelName) then return false,"NotOwned" end
		local tier=candidate.scooterUpgrades[modelName] or 0
		if tier~=expectedTier then return false,"StaleTier" end
		local price=ScooterConfig.GetUpgradeCost(modelName,tier)
		if not price then return false,"MaximumTier" end
		if candidate.coins<price then return false,"InsufficientCoins" end
		candidate.coins-=price;candidate.scooterUpgrades[modelName]=tier+1
		journal(candidate,-price,"SpeedUpgrade:"..modelName)
		return true,"Purchased"
	end)
end

function PlayerDataService.SetScooterVisual(player: Player, kind: "Smoke" | "Neon", enabled: boolean, color: Color3, modelName: string?): boolean
	local profile=profiles[player]
	local model=modelName or (if profile then profile.selectedScooter else ScooterConfig.DefaultModel)
	if not profile or not PlayerDataService.Ready(player) or not PlayerDataService.OwnsScooter(player,model)
		or not PlayerDataService.OwnsProduct(player,if kind=="Smoke" then "burnout_smoke" else "scooter_neons") then return false end
	local visual=profile.visualsByModel[model]
	if not visual then visual={Smoke={enabled=false,color={1,1,1}},Neon={enabled=false,color={0,1,1}}};profile.visualsByModel[model]=visual end
	visual[kind]={enabled=enabled,color={color.R,color.G,color.B}}
	if model==ScooterConfig.DefaultModel then profile.scooterVisuals[kind]=visual[kind] end
	return true
end
function PlayerDataService.SetRainbow(player: Player, modelName: string, enabled: boolean): boolean
	local profile=profiles[player]
	if not profile or not PlayerDataService.Ready(player) or not PlayerDataService.OwnsScooter(player,modelName)
		or not PlayerDataService.OwnsProduct(player,"rainbow_paint") then return false end
	profile.rainbowModels[modelName]=enabled;return true
end
function PlayerDataService.SetPaint(player: Player, modelName: string, colors: {[string]: Color3}): boolean
	local profile=profiles[player]
	if not profile or not PlayerDataService.Ready(player) or not PlayerDataService.OwnsScooter(player,modelName) then return false end
	local saved: {[string]: {number}}={}
	for id,color in colors do saved[id]={color.R,color.G,color.B} end
	profile.paintByModel[modelName]=saved
	profile.rainbowModels[modelName]=false
	return true
end
function PlayerDataService.SetItemEquipped(player: Player, id: string, enabled: boolean): (boolean,string)
	if (id~="radio" and id~="pepper_spray") or not PlayerDataService.OwnsProduct(player,id) then return false,"NotOwned" end
	return durable(player,function(candidate) candidate.equippedItems[id]=enabled;return true,"Equipped" end)
end

function PlayerDataService.AddCurrency(player: Player, coinsAmount: number, xpAmount: number, reason: string?): boolean
	local profile=profiles[player]
	local label=reason or "LegacyReward"
	if not profile or not PlayerDataService.Ready(player) or typeof(coinsAmount)~="number" or typeof(xpAmount)~="number"
		or coinsAmount~=coinsAmount or xpAmount~=xpAmount or coinsAmount<0 or xpAmount<0
		or coinsAmount>=math.huge or xpAmount>=math.huge or typeof(label)~="string" or #label==0 or #label>80 then return false end
	local amount,xp=math.floor(coinsAmount),math.floor(xpAmount)
	if profile.coins+amount>9007199254740991 then return false end
	if purchasing[player] then
		local queue=queuedCredits[player] or {};queuedCredits[player]=queue
		table.insert(queue,{coins=amount,xp=xp,reason=label})
	else credit(player,profile,amount,xp,label) end
	return true
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

function PlayerDataService.RecordRide(player: Player, studs: number, multiplier: number): boolean
	local profile=profiles[player]
	if not profile or not PlayerDataService.Ready(player) or studs~=studs or studs<=0 or studs==math.huge
		or multiplier~=multiplier or multiplier<1 or multiplier>EconomyConfig.WheelieMaxMultiplier then return false end
	local progress=profile.rewardProgress
	local step=EconomyConfig.RideCoinStepStuds
	local remaining=studs
	while remaining>0 do
		local distance=math.min(remaining,math.max(0,step-progress.rideStuds))
		progress.rideStuds+=distance
		progress.rideCoins+=distance/step*EconomyConfig.RideCoinsPerStep*multiplier
		remaining-=distance
		if progress.rideStuds>=step-0.000001 then
			local value=progress.rideCoins+progress.rideRemainder
			local coins=math.floor(value+0.0000001)
			if coins>0 then PlayerDataService.AddCoins(player,coins,"RideDistance") end
			progress.rideStuds=0;progress.rideCoins=0;progress.rideRemainder=math.max(0,value-coins)
		end
	end
	return true
end

function PlayerDataService.RecordTimedReward(player: Player, kind: "Burnout" | "Gang", seconds: number, flags: number?): boolean
	local profile=profiles[player]
	if not profile or not PlayerDataService.Ready(player) or seconds~=seconds or seconds<=0 or seconds==math.huge then return false end
	local key=if kind=="Burnout" then "burnoutRemainder" else "gangRemainder"
	if kind~="Burnout" and kind~="Gang" then return false end
	if kind=="Gang" and (typeof(flags)~="number" or flags~=flags or flags<0 or flags==math.huge or flags%1~=0) then return false end
	local rate=if kind=="Burnout" then EconomyConfig.BurnoutCoinsPerMinute else EconomyConfig.FlagCoinsPerMinute*(flags or 0)
	local value=profile.rewardProgress[key]+seconds/60*rate
	local coins=math.floor(value+0.0000001)
	if coins>0 then PlayerDataService.AddCoins(player,coins,if kind=="Burnout" then "BurnoutTime" else "GangFlagControl") end
	profile.rewardProgress[key]=math.max(0,value-coins)
	return true
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
	local function discard(player: Player)
		local listeners=statConnections[player]
		if listeners then for _,connection in listeners do connection:Disconnect() end end
		statConnections[player]=nil;profiles[player]=nil;canSave[player]=nil;tokens[player]=nil;queuedCredits[player]=nil
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		while saving[player] or purchasing[player] do task.wait() end
		if savePlayer(player,true) or not canSave[player] then discard(player);return end
		-- Retain the final snapshot briefly for a transient outage, without allowing a newer session to be overwritten.
		task.spawn(function()
			for _=1,5 do
				task.wait(30)
				if shuttingDown or not profiles[player] then return end
				if savePlayer(player,true) or not canSave[player] then discard(player);return end
			end
			warn("PlayerDataService: final save unavailable for "..player.Name);discard(player)
		end)
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
		shuttingDown=true
		local pending=0
		for player in profiles do
			pending+=1
			task.spawn(function()
				while saving[player] or purchasing[player] do task.wait() end
				savePlayer(player,true);pending-=1
			end)
		end
		local deadline=os.clock()+25
		while pending>0 and os.clock()<deadline do task.wait(0.1) end
	end)
end

return PlayerDataService
