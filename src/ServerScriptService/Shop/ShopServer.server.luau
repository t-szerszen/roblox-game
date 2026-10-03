--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local PlayerDataService = require(game:GetService("ServerScriptService").Activity.PlayerDataService)

type ShopState = {
	coins: number,
	coinSystemReady: boolean,
	owned: { [string]: boolean },
}

local lastRequestAt: { [Player]: number } = {}
local pendingRequests: { [Player]: boolean } = {}

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
		owned[product.id] = PlayerDataService.OwnsScooter(player, product.name)
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

local function purchaseWithCoins(player: Player, itemId: string): (boolean, string, ShopState?)
	local product = ShopConfig.GetProduct(itemId)
	if not product or product.currency ~= "Coins" or product.kind ~= "Scooter" or not product.stat then
		return false, "Nieprawidlowy produkt.", nil
	end

	local success, reason = PlayerDataService.PurchaseScooter(player, product.name)
	local messages = {
		Purchased = "Zakup zakonczony.",
		AlreadyOwned = "Ten model jest juz odblokowany.",
		InsufficientCoins = "Brakuje Coinow.",
		DataUnavailable = "Dane gracza nie sa jeszcze dostepne.",
	} :: { [string]: string }
	return success, messages[reason] or "Nieprawidlowy produkt.", if success then getState(player) else nil
end

local function handleRequest(player: Player, action: string, itemId: unknown): (boolean, string, ShopState?, number?)
	if action == "GetState" then
		if itemId ~= nil then
			return false, "Nieprawidlowe zadanie.", nil, nil
		end
		return true, "", getState(player), nil
	end
	if typeof(itemId) ~= "string" or #itemId > 64 then
		return false, "Nieprawidlowy produkt.", nil, nil
	end
	if action == "PurchaseCoins" then
		local success, message, state = purchaseWithCoins(player, itemId)
		return success, message, state, nil
	end
	if action == "PrepareRobux" then
		local product = ShopConfig.GetProduct(itemId)
		if not product or product.currency ~= "Robux" then
			return false, "Nieprawidlowy produkt.", nil, nil
		end
		local productId = product.productId or 0
		if productId <= 0 then
			return false, "Produkt Robux nie ma jeszcze przypisanego ID.", nil, nil
		end
		if product.kind ~= "GamePass" then
			return false, "Ten typ produktu nie jest jeszcze obslugiwany.", nil, nil
		end
		return true, "", getState(player), productId
	end

	return false, "Nieznana operacja.", nil, nil
end

request.OnServerInvoke = function(player: Player, action: unknown, itemId: unknown)
	if player.Parent ~= Players then
		return false, "Gracz jest niedostepny.", nil, nil
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < ShopConfig.RequestCooldown then
		return false, "Zwolnij na moment.", nil, nil
	end
	lastRequestAt[player] = now
	if pendingRequests[player] then
		return false, "Poprzednie zadanie jeszcze trwa.", nil, nil
	end
	if typeof(action) ~= "string" or #action > 32 then
		return false, "Nieprawidlowe zadanie.", nil, nil
	end
	pendingRequests[player] = true
	local ok, success, message, state, productId = pcall(handleRequest, player, action, itemId)
	pendingRequests[player] = nil
	if not ok then
		warn("ShopServer: request failed: " .. tostring(success))
		return false, "Sklep jest chwilowo niedostepny.", nil, nil
	end
	return success, message, state, productId
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAt[player] = nil
	pendingRequests[player] = nil
end)
