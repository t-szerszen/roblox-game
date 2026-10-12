--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScooterCustomConfig"))
local Paint = require(ReplicatedStorage.Shared:WaitForChild("ScooterCustomPaint"))
local Zone = require(ReplicatedStorage.Shared:WaitForChild("ScooterCustomZone"))
local action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ScooterCustom"):WaitForChild("Action") :: RemoteFunction
local opened = action.Parent:WaitForChild("Opened") :: RemoteEvent
local garage = workspace:WaitForChild(Config.GarageName)
local station = garage:WaitForChild(Config.AccessModelName):WaitForChild(Config.StationName) :: BasePart
local ready: {[Player]: boolean} = {}
local loadedReady: {[Player]: boolean} = {}
local inside: {[Player]: Model} = {}
local lastRequest: {[Player]: number} = {}
local defaults: {[Model]: {[string]: Color3}} = {}
local sessions: {[Player]: Model} = {}
local modelConnections: {[Model]: RBXScriptConnection} = {}
local connections: {RBXScriptConnection} = {}
local active = true
local Data = require(script.Parent.Activity.PlayerDataService)
local Upgrades = require(script.Parent.Scooter.ScooterUpgradeService)
local UpgradeCatalog = require(ReplicatedStorage.Shared.ScooterUpgradeCatalog)
local ScooterServer = require(script.Parent.Scooter.ScooterServer)
local allowed: {[string]: boolean} = {}
for _,group in Config.Groups do allowed[group.Id] = true end

local function eligibleModel(player: Player, model: Instance?): boolean
 if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace)
  or model:GetAttribute("OwnerUserId") ~= player.UserId or model:GetAttribute("ScooterModel") == nil
  or model:GetAttribute("Fallen") == true then return false end
 local seat = model:FindFirstChild("DriverSeat",true)
 return seat ~= nil and seat:IsA("VehicleSeat")
  and Zone.Contains(station,seat.Position,if inside[player] then Config.ZoneExitMargin else 0)
end
local function garageScooter(player: Player): Model?
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
 if not Zone.Contains(station,root.Position,if inside[player] then Config.ZoneExitMargin else 0) then return nil end
 local seat = humanoid.SeatPart
 if seat then
  if not seat:IsA("VehicleSeat") or seat.Occupant ~= humanoid or seat.Name ~= "DriverSeat" then return nil end
  local model = seat:FindFirstAncestorOfClass("Model")
  return if eligibleModel(player,model) then model else nil
 end
 local current = sessions[player]
 if eligibleModel(player,current) then return current end
 local folder = workspace:FindFirstChild(Config.ScooterFolderName)
 if not folder then return nil end
 local nearest: Model? = nil
 local distance = math.huge
 for _,candidate in folder:GetChildren() do
  if candidate:IsA("Model") and eligibleModel(player,candidate) then
   local d=(candidate:GetPivot().Position-root.Position).Magnitude
   if d<distance then nearest,distance=candidate,d end
  end
 end
 return nearest
end
local function atGarage(player: Player, model: Model): boolean
 local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
 local seat=model:FindFirstChild("DriverSeat",true)
 return station:IsDescendantOf(workspace) and root~=nil and root:IsA("BasePart")
  and seat~=nil and seat:IsA("BasePart")
  and Zone.Contains(station,root.Position,if inside[player] then Config.ZoneExitMargin else 0)
  and Zone.Contains(station,seat.Position,if inside[player] then Config.ZoneExitMargin else 0)
end
local function validColor(value: any): boolean
 if typeof(value) ~= "Color3" then return false end
 for _,channel in {value.R, value.G, value.B} do
  if channel ~= channel or channel < 0 or channel > 1 then return false end
 end
 return true
end
local function validatePalette(value: any): boolean
 if typeof(value) ~= "table" then return false end
 local count = 0
 for id, color in value do
  if typeof(id) ~= "string" or not allowed[id] or not validColor(color) then return false end
  count += 1
 end
 if count ~= #Config.Groups then return false end
 for _,group in Config.Groups do if not validColor(value[group.Id]) then return false end end
 return true
end
local function remember(model: Model): boolean
 local colors = Paint.Read(model)
 for _,group in Config.Groups do if not colors[group.Id] then return false end end
 if not defaults[model] then
  defaults[model] = colors
  modelConnections[model] = model.Destroying:Connect(function()
   defaults[model] = nil
   local connection = modelConnections[model]
   if connection then connection:Disconnect() end
   modelConnections[model] = nil
   for player, selected in sessions do if selected == model then sessions[player] = nil end end
  end)
 end
 return true
end
local function designs(player: Player, model: Model)
 local profile=Data.GetProfile(player)
 local name=model:GetAttribute("ScooterModel")
 local slots=profile and profile.scooterDesigns[name]
 local result={}
 for index=1,Config.DesignSlots do
  local palette=slots and slots[tostring(index)]
  if palette then result[tostring(index)]=table.clone(palette) end
 end
 return result
end

action.OnServerInvoke = function(player: Player, operation: any, modelArgument: any, palette: any, ...: any)
 if not active then return {ok = false} end
 local now = os.clock()
 local cooldown=if operation=="Upgrade" then math.max(Config.RequestCooldown,UpgradeCatalog.RequestCooldown) else Config.RequestCooldown
 if now - (lastRequest[player] or -math.huge) < cooldown then return {ok = false, message = "Chwilę…"} end
 lastRequest[player] = now
 if select("#", ...) ~= 0 or typeof(operation) ~= "string" then return {ok = false} end
 if operation == "Ready" then
  if modelArgument ~= nil or palette ~= nil then return {ok=false} end
  ready[player] = true
  return {ok=true}
 end
 if operation ~= "Apply" and operation ~= "Reset" and operation ~= "Upgrade" and operation ~= "SaveDesign" and operation ~= "LoadDesign" then return {ok = false} end
 local model = garageScooter(player)
 if not model or not atGarage(player,model) then
  sessions[player]=nil
  return {ok=false,message="Podjedź swoją hulajnogą do garażu."}
 end
 if modelArgument~=model or sessions[player]~=model then return {ok=false,message="Otwórz custom przy garażu."} end
 if operation=="SaveDesign" or operation=="LoadDesign" then
  if typeof(palette)~="table" then return {ok=false} end
  for key in palette do if key~="slot" and not (operation=="SaveDesign" and key=="colors") then return {ok=false} end end
  local slot=palette.slot
  if typeof(slot)~="number" or slot~=slot or slot%1~=0 or slot<1 or slot>Config.DesignSlots then return {ok=false} end
  local profile=Data.GetProfile(player)
  local name=model:GetAttribute("ScooterModel")
  if not profile or typeof(name)~="string" or not Data.OwnsScooter(player,name) then return {ok=false,message="Poczekaj na wczytanie danych."} end
  local key=tostring(slot)
  if operation=="SaveDesign" then
   if not validatePalette(palette.colors) then return {ok=false} end
   local encoded={}
   for id,color in palette.colors do encoded[id]=color:ToHex() end
   profile.scooterDesigns[name]=profile.scooterDesigns[name] or {}
   profile.scooterDesigns[name][key]=encoded
   return {ok=true,model=model,designs=designs(player,model),message="Zapisano projekt w slocie "..slot..(if player:GetAttribute("DataPersistenceAvailable")==true then "." else " — tylko na tę sesję.")}
  end
  local saved=profile.scooterDesigns[name] and profile.scooterDesigns[name][key]
  if not saved then return {ok=false,message="Ten slot jest pusty."} end
  local restored=Paint.Read(model)
  for id,hex in saved do if allowed[id] and typeof(hex)=="string" and #hex==6 and hex:match("^%x+$") then restored[id]=Color3.fromHex(hex) end end
  return {ok=true,model=model,colors=restored,designs=designs(player,model),message="Wczytano projekt "..slot.." — zatwierdź, aby zastosować."}
 end
 if operation=="Upgrade" then
  if typeof(palette)~="table" then return {ok=false} end
  for key in palette do if key~="id" and key~="enabled" then return {ok=false} end end
  local name=model:GetAttribute("ScooterModel")
  if typeof(name)~="string" then return {ok=false} end
  local success,message=Upgrades.Set(player,name,palette.id,palette.enabled)
  if success then ScooterServer.RefreshUpgrades(player,model) end
  return {ok=success,message=message,model=model,upgrades=Upgrades.State(player,name)}
 end
 if operation=="Apply" then
  if not validatePalette(palette) then return {ok=false} end
  Paint.Apply(model,palette)
 else
  if palette~=nil or not defaults[model] then return {ok=false} end
  Paint.Apply(model,defaults[model])
 end
 return {ok = true, model = model, colors = Paint.Read(model)}
end
-- One bounded server scan detects entry even when an anchored scooter never fires Touched.
local elapsed = 0
table.insert(connections,RunService.Heartbeat:Connect(function(delta)
 elapsed += delta
 if not active or elapsed < Config.AccessInterval then return end
 elapsed = 0
 for _,player in Players:GetPlayers() do
  if not ready[player] then continue end
  local model=garageScooter(player)
  if model and atGarage(player,model) then
   if (inside[player] ~= model or (player:GetAttribute("DataLoaded") == true and not loadedReady[player])) and remember(model) then
    loadedReady[player]=player:GetAttribute("DataLoaded") == true
    inside[player],sessions[player]=model,model
    opened:FireClient(player,{model=model,colors=Paint.Read(model),designs=designs(player,model),upgrades=Upgrades.State(player,model:GetAttribute("ScooterModel"))})
   end
  else
   sessions[player]=nil
   if inside[player] then
    inside[player]=nil
    opened:FireClient(player,{close=true})
   end
  end
 end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(player)
 lastRequest[player],sessions[player],ready[player],inside[player],loadedReady[player]=nil,nil,nil,nil,nil
end))
table.insert(connections, script.Destroying:Connect(function()
 active = false action.OnServerInvoke = nil
 for _,connection in connections do connection:Disconnect() end
 for _,connection in modelConnections do connection:Disconnect() end
 table.clear(modelConnections) table.clear(defaults) table.clear(sessions) table.clear(lastRequest)
 table.clear(ready) table.clear(inside) table.clear(loadedReady)
end))
