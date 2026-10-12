--!strict
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local ScooterConfig=require(ReplicatedStorage.Shared.ScooterConfig)
local Config=require(ReplicatedStorage.Shared.Shop.ShopConfig)
local Data=require(script.Parent.Parent.Activity.PlayerDataService)
local Premium=require(script.Parent.PremiumService)
local Equipment=require(script.Parent.ItemEquipment)
local Scooter=require(script.Parent.Parent.Scooter.ScooterServer)
local Shop={}
local started=false
local connections: {RBXScriptConnection}={}
local lastRequest: {[Player]: number}={}
local busy: {[Player]: boolean}={}
local bindings: {[Player]: {RBXScriptConnection}}={}
local function vehicleReady(product: Config.Product): boolean
	if product.assetReady==false then return false end
	if not product.modelName then return true end
	local folder=ServerStorage:FindFirstChild("ScooterModels")
	local template=if folder then folder:FindFirstChild(ScooterConfig.TemplateName) else nil
	return template~=nil and template:IsA("Model") and template.PrimaryPart~=nil
end
local function state(player: Player): any
	local owned,available,equipped={},{},{}
	local profile=Data.GetProfile(player)
	for _,products in {Config.CoinProducts,Config.RobuxProducts} do
		for _,product in products do
			owned[product.id]=Data.OwnsProduct(player,product.id)
			available[product.id]=vehicleReady(product) and (product.currency=="Coins" or (product.productId or 0)>0)
			if profile then
				local model=profile.selectedScooter
				local visuals=profile.visualsByModel[model]
				equipped[product.id]=if product.modelName then model==product.modelName
					elseif product.id=="radio" or product.id=="pepper_spray" then profile.equippedItems[product.id]==true
					elseif product.id=="rainbow_paint" then profile.rainbowModels[model]==true
					elseif product.id=="burnout_smoke" then visuals~=nil and visuals.Smoke.enabled
					elseif product.id=="scooter_neons" then visuals~=nil and visuals.Neon.enabled else false
			end
		end
	end
	return {coins=if profile then profile.coins else 0,coinSystemReady=Data.Ready(player),owned=owned,equipped=equipped,available=available}
end
local messages: {[string]: string}={Purchased="Zakup zapisany. Przedmiot odblokowany.",AlreadyOwned="Ten przedmiot jest już odblokowany.",
	InsufficientCoins="Brakuje Coins.",DataUnavailable="Dane gracza są niedostępne.",Busy="Operacja nadal trwa.",
	SaveFailed="Zapis nie powiódł się. Nie pobrano Coins.",SessionLost="Sesja danych jest niedostępna.",NotOwned="Najpierw odblokuj przedmiot.",
	Selected="Pojazd wybrany.",Equipped="Wyposażenie zapisane."}
local function execute(player: Player, action: string, id: unknown): (boolean,string,any,number?)
	if action=="GetState" then
		if id~=nil then return false,"Nieprawidłowe żądanie.",nil,nil end
		Premium.Refresh(player)
		return true,"",state(player),nil
	end
	if typeof(id)~="string" or #id>64 then return false,"Nieprawidłowy produkt.",nil,nil end
	local product=Config.GetProduct(id)
	if not product then return false,"Nieprawidłowy produkt.",nil,nil end
	if (action=="PurchaseCoins" or action=="Equip") and not vehicleReady(product) then return false,"Pojazd jest chwilowo niedostępny.",state(player),nil end
	if action=="PrepareRobux" then
		if product.kind~="GamePass" then return false,"Nieprawidłowy produkt.",nil,nil end
		local ok,reason,passId=Premium.Prepare(player,product)
		return ok,reason,state(player),passId
	end
	local ok,reason=false,"Nieznana operacja."
	if action=="PurchaseCoins" then
		if Premium.Pending(player) then return false,"Zakończ poprzedni zakup Robux.",state(player),nil end
		if Data.OwnsProduct(player,id) then return false,messages.AlreadyOwned,state(player),nil end
		if product.coinPrice and not Premium.Refresh(player,true) then return false,"Nie można sprawdzić własności radia.",state(player),nil end
		ok,reason=Data.PurchaseProduct(player,id)
	elseif action=="Equip" then
		if not Data.OwnsProduct(player,id) then return false,messages.NotOwned,state(player),nil end
		local profile=Data.GetProfile(player)
		if not profile then return false,messages.DataUnavailable,nil,nil end
		if product.modelName then
			ok,reason=Data.SelectScooter(player,product.modelName)
			if ok then
				local spawned,message=Scooter.RequestSpawnForPlayer(player,product.modelName)
				if not spawned then return false,message,state(player),nil end
			end
		elseif id=="radio" or id=="pepper_spray" then
			ok,reason=Data.SetItemEquipped(player,id,not profile.equippedItems[id]);Equipment.Sync(player)
		elseif id=="rainbow_paint" then
			ok=Data.SetRainbow(player,profile.selectedScooter,not profile.rainbowModels[profile.selectedScooter]);reason=if ok then "Equipped" else "DataUnavailable"
			if ok then Scooter.RefreshCosmetics(player) end
		elseif id=="burnout_smoke" or id=="scooter_neons" then
			local kind=if id=="burnout_smoke" then "Smoke" else "Neon"
			local visuals=profile.visualsByModel[profile.selectedScooter]
			local preference=if visuals then visuals[kind] else nil
			local rgb=if preference then preference.color else {0,1,1}
			ok=Data.SetScooterVisual(player,kind,not (preference and preference.enabled),Color3.new(rgb[1],rgb[2],rgb[3]),profile.selectedScooter)
			reason=if ok then "Equipped" else "DataUnavailable"
			if ok then Scooter.RefreshCosmetics(player) end
		end
	end
	return ok,messages[reason] or reason,state(player),nil
end
function Shop.Handle(player: Player, action: unknown, id: unknown): (boolean,string,any,number?)
	if player.Parent~=Players or typeof(action)~="string" or #action>32 then return false,"Nieprawidłowe żądanie.",nil,nil end
	if os.clock()-(lastRequest[player] or -math.huge)<Config.RequestCooldown or busy[player] then return false,"Odczekaj chwilę.",nil,nil end
	lastRequest[player]=os.clock();busy[player]=true
	local worked,ok,reason,result,passId=pcall(execute,player,action,id)
	busy[player]=nil
	if not worked then warn("Shop: "..tostring(ok));return false,"Sklep jest chwilowo niedostępny.",nil,nil end
	return ok,reason,result,passId
end
function Shop.Start()
	if started then return end;started=true
	Data.Start();Premium.Start()
	local function bind(player: Player) if not bindings[player] then bindings[player]=Equipment.Bind(player) end end
	for _,player in Players:GetPlayers() do bind(player) end
	table.insert(connections,Players.PlayerAdded:Connect(bind))
	table.insert(connections,Players.PlayerRemoving:Connect(function(player)
		for _,connection in bindings[player] or {} do connection:Disconnect() end
		bindings[player]=nil;busy[player]=nil;lastRequest[player]=nil
	end))
end
function Shop.Stop()
	started=false
	for _,connection in connections do connection:Disconnect() end
	table.clear(connections)
	for player,list in bindings do for _,connection in list do connection:Disconnect() end;bindings[player]=nil end
	table.clear(lastRequest);table.clear(busy)
	Premium.Stop()
end
return Shop
