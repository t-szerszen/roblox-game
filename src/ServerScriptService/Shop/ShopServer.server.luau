--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

type ShopState = {
	coins: number,
	coinSystemReady: boolean,
	owned: { [string]: boolean },
}

local lastRequestAt: { [Player]: number } = {}

local remotes = ReplicatedStorage:FindFirstChild(ShopConfig.RemoteFolderName)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = ShopConfig.RemoteFolderName
	remotes.Parent = ReplicatedStorage
end

local existingRequest = remotes:FindFirstChild(ShopConfig.RequestFunctionName)
local request: RemoteFunction
if existingRequest and existingRequest:IsA("RemoteFunction") then
	request = existingRequest
else
	request = Instance.new("RemoteFunction")
	request.Name = ShopConfig.RequestFunctionName
	request.Parent = remotes
end

local function getCoinsValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = if leaderstats then leaderstats:FindFirstChild("Coins") else nil
	return if coins and coins:IsA("IntValue") then coins else nil
end

local function ownsGamePass(player: Player, productId: number): boolean
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, productId)
	end)
	return success and result
end

local function getState(player: Player): ShopState
	local coinsValue = getCoinsValue(player)
	local owned: { [string]: boolean } = {}

	for _, product in ShopConfig.CoinProducts do
		owned[product.id] = product.price == 0 or (product.stat ~= nil and player:GetAttribute(product.stat) == true)
	end

	for _, product in ShopConfig.RobuxProducts do
		local productId = product.productId or 0
		local isOwned = product.kind == "GamePass" and productId > 0 and ownsGamePass(player, productId)
		owned[product.id] = isOwned
		if product.id == "pepper_spray" and isOwned then
			player:SetAttribute("OwnsPepperSpray", true)
		end
	end

	return {
		coins = if coinsValue then coinsValue.Value else 0,
		coinSystemReady = coinsValue ~= nil,
		owned = owned,
	}
end

local function purchaseWithCoins(player: Player, itemId: string): (boolean, string, ShopState)
	local product = ShopConfig.GetProduct(itemId)
	if not product or product.currency ~= "Coins" or product.kind ~= "Scooter" or not product.stat then
		return false, "Nieprawidlowy produkt.", getState(player)
	end

	if product.price == 0 or player:GetAttribute(product.stat) == true then
		return false, "Ten model jest juz odblokowany.", getState(player)
	end

	local coins = getCoinsValue(player)
	if not coins then
		return false, "System Coinow nie jest jeszcze podlaczony.", getState(player)
	end
	if coins.Value < product.price then
		return false, "Brakuje Coinow.", getState(player)
	end

	coins.Value -= product.price
	player:SetAttribute(product.stat, true)
	return true, "Zakup zakonczony.", getState(player)
end

request.OnServerInvoke = function(player: Player, action: unknown, itemId: unknown)
	if typeof(action) ~= "string" then
		return false, "Nieprawidlowe zadanie.", getState(player), nil
	end

	local now = os.clock()
	if action ~= "GetState" and now - (lastRequestAt[player] or 0) < ShopConfig.RequestCooldown then
		return false, "Zwolnij na moment.", getState(player), nil
	end
	lastRequestAt[player] = now

	if action == "GetState" then
		return true, "", getState(player), nil
	end
	if typeof(itemId) ~= "string" or #itemId > 64 then
		return false, "Nieprawidlowy produkt.", getState(player), nil
	end
	if action == "PurchaseCoins" then
		local success, message, state = purchaseWithCoins(player, itemId)
		return success, message, state, nil
	end
	if action == "PrepareRobux" then
		local product = ShopConfig.GetProduct(itemId)
		if not product or product.currency ~= "Robux" then
			return false, "Nieprawidlowy produkt.", getState(player), nil
		end
		local productId = product.productId or 0
		if productId <= 0 then
			return false, "Produkt Robux nie ma jeszcze przypisanego ID.", getState(player), nil
		end
		if product.kind ~= "GamePass" then
			return false, "Ten typ produktu nie jest jeszcze obslugiwany.", getState(player), nil
		end
		return true, "", getState(player), productId
	end

	return false, "Nieznana operacja.", getState(player), nil
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAt[player] = nil
end)
