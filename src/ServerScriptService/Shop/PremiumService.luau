--!strict
local Marketplace=game:GetService("MarketplaceService")
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Shop.ShopConfig)
local Data=require(script.Parent.Parent.Activity.PlayerDataService)
local Premium={}
local pending: {[Player]: string}={}
local refreshing: {[Player]: boolean}={}
local checked: {[Player]: number}={}
local connected=false
local connections: {RBXScriptConnection}={}

function Premium.Refresh(player: Player, force: boolean?): boolean
	if not Data.Ready(player) or refreshing[player] then return false end
	if not force and checked[player] and os.clock()-checked[player]<30 then return true end
	refreshing[player]=true
	local complete=true
	for _,product in Config.RobuxProducts do
		local id=product.productId or 0
		if id<=0 or Data.OwnsProduct(player,product.id) then continue end
		local ok,owned=pcall(function() return Marketplace:UserOwnsGamePassAsync(player.UserId,id) end)
		if not ok then complete=false
		elseif owned==true then
			local granted=Data.GrantProduct(player,product.id)
			if not granted then complete=false end
		end
	end
	refreshing[player]=nil
	if complete then checked[player]=os.clock() end
	return complete
end

function Premium.Pending(player: Player): boolean return pending[player]~=nil end
function Premium.Available(product: Config.Product): (boolean,string)
	if product.assetReady==false then return false,"Pojazd jest w przygotowaniu." end
	local id=product.productId or 0
	if id<=0 then return false,"Produkt jest jeszcze niedostępny." end
	local ok,info=pcall(function() return Marketplace:GetProductInfoAsync(id,Enum.InfoType.GamePass) end)
	if not ok or typeof(info)~="table" then return false,"Nie można sprawdzić produktu Marketplace." end
	if info.IsForSale~=true or info.PriceInRobux~=product.price then return false,"Produkt jest chwilowo niedostępny." end
	return true,""
end
function Premium.Prepare(player: Player, product: Config.Product): (boolean,string,number?)
	if not Data.Ready(player) then return false,"Dane gracza są niedostępne.",nil end
	if pending[player] then return false,"Poprzedni zakup nadal trwa.",nil end
	if not Premium.Refresh(player,true) then return false,"Weryfikacja własności jest niedostępna.",nil end
	if Data.OwnsProduct(player,product.id) then return false,"Ten przedmiot jest już odblokowany.",nil end
	local available,reason=Premium.Available(product)
	if not available then return false,reason,nil end
	if player.Parent~=Players then return false,"Gracz opuścił serwer.",nil end
	-- No yield between the final ownership/pending check and reserving the prompt.
	if pending[player] or Data.OwnsProduct(player,product.id) then return false,"Zakup jest już obsługiwany.",nil end
	pending[player]=product.id
	local ok=pcall(function() Marketplace:PromptGamePassPurchase(player,product.productId :: number) end)
	if not ok then pending[player]=nil;return false,"Nie można otworzyć okna zakupu.",nil end
	return true,"",product.productId
end
function Premium.Start()
	if connected then return end;connected=true
	table.insert(connections,Marketplace.PromptGamePassPurchaseFinished:Connect(function(player: Player,id: number,purchased: boolean)
		local productId=pending[player]
		local product=if productId then Config.GetProduct(productId) else nil
		if product and product.productId~=id then return end
		if purchased and player.Parent==Players then
			checked[player]=nil
			Premium.Refresh(player,true)
		end
		pending[player]=nil
	end))
	table.insert(connections,Players.PlayerRemoving:Connect(function(player)
		pending[player]=nil;refreshing[player]=nil;checked[player]=nil
	end))
end
function Premium.Stop()
	connected=false
	for _,connection in connections do connection:Disconnect() end
	table.clear(connections);table.clear(pending);table.clear(refreshing);table.clear(checked)
end
return Premium
