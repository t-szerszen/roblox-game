--!strict
-- Edit-mode fixture: native vectors/assets and a table DataStore double. No account writes.
local Scope=require(game.ReplicatedStorage.Shared.UI.Scope)
local Config=require(game.ReplicatedStorage.Shared.Activity.EconomyConfig)
local mathCopy=game.ServerScriptService.Activity.RewardMath:Clone()
local storeCopy=game.ServerScriptService.Activity.ProfilePersistence:Clone()
local count=0
local function check(condition: boolean,message: string) assert(condition,message);count+=1 end
local ok,problem=pcall(function()
 local RewardMath=require(mathCopy)
 local Persistence=require(storeCopy)
 check(Config.StudsPerKilometer==5760,"Native arcade distance conversion")
 check(RewardMath.Delivery(0)==100 and RewardMath.Delivery(2000)==250,"Native delivery range")
 local motion=RewardMath.NewMotion(Vector3.zero)
 local total,multiplier=0,1
 for i=1,80 do
  local d,m=RewardMath.Sample(motion,Vector3.new(0,0,10*i),Vector3.new(0,0,40),100,true,true,false,0.25)
  total+=d;multiplier=m
 end
 check(total==800 and multiplier==2,"Native vectors produce physical distance and x2 ramp")
 check(RewardMath.Sample(motion,Vector3.new(0,0,10000),Vector3.new(0,0,40),100,true,true,false,0.25)==0,"Native teleport rejection")
 local store: any={value={coins=80},writes=0}
 function store:UpdateAsync(_key: string,transform: (any)->any)
  local value=transform(self.value)
  if value~=nil then self.value=value;self.writes+=1 end
  return value
 end
 local token=Persistence.Token()
 check(Persistence.Acquire(store,"fixture",token),"Native GUID lease acquisition")
 check(not Persistence.Acquire(store,"fixture","foreign"),"Native active-session exclusion")
 check(Persistence.Save(store,"fixture",token,{coins=120},false) and store.value.coins==120,"Native ownership-checked persistence")
 check(not Persistence.Save(store,"fixture","foreign",{coins=0},false) and store.value.coins==120,"Foreign snapshot rejected")
 check(Persistence.Save(store,"fixture",token,{coins=120},true) and store.value._session==nil,"Lease release")
 check(Persistence.Acquire(store,"fixture","new-session"),"Released lease supports a new session")
 local gas=game.ServerStorage:FindFirstChild("PepperSprayTemplate")
 check(gas~=nil and gas:IsA("Tool"),"Actual gas tool is mapped")
 check((gas :: Tool):FindFirstChild("GasOrigin",true)~=nil,"Existing spray nozzle retained")
 local scripts=0
 for _,v in (gas :: Tool):GetDescendants() do if v:IsA("LuaSourceContainer") then scripts+=1 end end
 check(scripts==0,"Versioned gas template contains no executable code")
 local template=game.ServerStorage.ScooterModels:FindFirstChild("scooter")
 check(template~=nil and template:IsA("Model") and template.PrimaryPart~=nil,"Approved common vehicle model exists")
 local ShopConfig=require(game.ReplicatedStorage.Shared.Shop.ShopConfig)
 check(#ShopConfig.CoinProducts==3 and #ShopConfig.RobuxProducts==6,"Native approved catalog")
 local owner=Scope.new();local gui=Instance.new("ScreenGui")
 owner:Give(gui)
 local viewModule=game.StarterGui.Shop.ShopView:Clone()
 local view=require(viewModule).new(gui,owner,{
  Toggle=function() end,Close=function() end,Tab=function() end,Purchase=function() end,
  Confirm=function() end,Cancel=function() end,Refresh=function() end,
 })
 local state={coins=500000,coinSystemReady=true,owned={kukirin_g2_pro=true},equipped={kukirin_g2_pro=true},available={}}
 view.Render("Classic",function() end);view.Update(state,false)
 check(view.Scroll:FindFirstChild("kukirin_g2_max")~=nil,"Classic renders actual mapped products")
 view.Render("Premium",function() end);view.SetCategory("Dodatki");view.Update(state,false)
 local radio=view.Scroll:FindFirstChild("radio")
 check(radio~=nil and radio:FindFirstChild("PurchaseCoins")~=nil,"Radio exposes two payment choices")
 view.SetCategory("Walka");view.Update(state,false)
 check(view.Scroll:FindFirstChild("pepper_spray")~=nil and view.Scroll:FindFirstChild("radio")==nil,"Categories filter product scopes")
 view.SetCategory("Dodatki do pojazdów");view.Update(state,false)
 check(view.Scroll:FindFirstChild("rainbow_paint")~=nil,"Rainbow appears in vehicle accessories")
 owner:Clean();viewModule:Destroy()
 check(#owner._tasks==0,"Native UI scopes clean up")
end)
mathCopy:Destroy();storeCopy:Destroy()
assert(ok,problem)
print("PASS: "..count.." native economy/asset/UI assertions")
return count

