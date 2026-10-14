-- Engine, Marketplace and DataStore doubles; no real player account is touched.
getfenv().Enum={InfoType={GamePass="GamePass"}}
Vector.one=Vector.new(1,1,1)
function vectorMethods:Lerp(other,alpha) return self+(other-self)*alpha end
function instanceMethods:FindFirstChildOfClass(class)
 for _,child in self:GetChildren() do if child:IsA(class) then return child end end
 return nil
end
function instanceMethods:IsDescendantOf(ancestor)
 local parent=self.Parent
 while parent do if parent==ancestor then return true end;parent=parent.Parent end
 return false
end
local oldIsA=instanceMethods.IsA
function instanceMethods:IsA(class)
 return oldIsA(self,class) or (class=="BasePart" and self.ClassName=="Part")
end
services.Workspace=InstanceMock.new("Workspace");services.Workspace.ChildAdded=signal()
services.ServerStorage=InstanceMock.new("ServerStorage")
services.Lighting={ClockTime=12}
services.RunService={Heartbeat=signal()}
function services.Workspace:GetServerTimeNow() return testClock end
local tagged={}
local added,removed=signal(),signal()
services.CollectionService={GetTagged=function(_,tag) return tagged[tag] or {} end,
 GetInstanceAddedSignal=function() return added end,GetInstanceRemovedSignal=function() return removed end,
 HasTag=function(_,instance,tag) return table.find(tagged[tag] or {},instance)~=nil end}
local baseNew=InstanceMock.new
InstanceMock.new=function(class)
 local object=baseNew(class)
 object.Destroying=signal();object.Triggered=signal();object.ChildAdded=signal();object.ChildRemoved=signal()
 return object
end
local scooterAPI={states={}}
function scooterAPI.GetRidingState(player) return scooterAPI.states[player] end
function scooterAPI.RefreshCosmetics() end
function scooterAPI.RequestSpawnForPlayer() return true,"Spawned" end
moduleCache["ServerScriptService/Scooter/ScooterServer"]=scooterAPI
moduleCache["ServerScriptService/Scooter/GarageService"]={HandleRequest=function() return true,"VisualUpdated" end}
moduleCache["ServerScriptService/Shop/ItemEquipment"]={Sync=function() end,Bind=function() return {} end}
local gangAPI={groups={}}
function gangAPI.Exists(id) return gangAPI.groups[id]~=nil end
function gangAPI.GetOnlineMembers(id) return gangAPI.groups[id] or {} end
moduleCache["ServerScriptService/Gang/GangService"]=gangAPI
local Config=loadModule("ReplicatedStorage/Shared/Activity/EconomyConfig")
local Catalog=loadModule("ReplicatedStorage/Shared/Shop/ShopConfig")
local Math=loadModule("ServerScriptService/Activity/RewardMath")
local Data=loadModule("ServerScriptService/Activity/PlayerDataService")
local Persistence=loadModule("ServerScriptService/Activity/ProfilePersistence")
local rich=makePlayer(8001,{coins=500000,futureFeature={kept=true},scooterEquipment={['KuKirin G2 Pro']={owned={dual_motor=true},equipped={dual_motor=true}}},
 scooterDesigns={['KuKirin G2 Pro']={['1']={Deck='aabbcc'}}}})
local poor=makePlayer(8002,{coins=10})
local reward=makePlayer(8003,{coins=0})
Data.Start()
-- Autosave is suspended by the shared mock. Fault retries below don't sleep.
taskMock.wait=function() return nil end
check(Data.Ready(rich) and rich.leaderstats.Coins.Value==500000,"Loaded balance is authoritative")
local richProfile=Data.GetProfile(rich)
check(richProfile.scooterDesigns['KuKirin G2 Pro']['1'].Deck=='aabbcc',"Studio design slots survive migration")
check(type(richProfile.scooterEquipment['KuKirin G2 Pro'])=='table',"Part upgrades survive migration")
check(Catalog.CoinProducts[1].name=='KuKirin 1' and Catalog.CoinProducts[1].price==0,"Free KuKirin 1")
check(Catalog.CoinProducts[2].price==10000 and Catalog.CoinProducts[3].price==40000,"Approved paid vehicle prices")
check(Data.OwnsProduct(poor,Catalog.CoinProducts[1].id),"Default vehicle is free")
check(Catalog.GetProduct('suron').price==800 and Catalog.GetProduct('suron').assetReady==false,"Missing Suron asset is explicit")
for id,price in {pepper_spray=500,scooter_neons=100,burnout_smoke=100,rainbow_paint=100,radio=500} do
 check(Catalog.GetProduct(id).price==price and Catalog.GetProduct(id).kind=='GamePass',"Permanent SKU "..id)
end
check(Catalog.GetProduct('radio').coinPrice==250000,"Radio alternative price")
local ok,reason=Data.PurchaseProduct(poor,'kukirin_g2_max')
check(not ok and reason=='InsufficientCoins' and poor.leaderstats.Coins.Value==10,"No overspending")
ok=Data.PurchaseProduct(rich,'kukirin_g2_max')
check(ok and rich.leaderstats.Coins.Value==490000 and writes['8001'].unlocks.kukirin_g2_max,"Debit/unlock persisted before acknowledgement")
check(writes["8001"].futureFeature.kept==true,"Economy save preserves unknown existing profile fields")
ok,reason=Data.PurchaseProduct(rich,'kukirin_g2_max')
check(not ok and reason=='AlreadyOwned' and rich.leaderstats.Coins.Value==490000,"Duplicate vehicle purchase is harmless")
ok=Data.PurchaseProduct(rich,'kukirin_g2_master')
check(ok and rich.leaderstats.Coins.Value==450000,"KuKirin 3 exact debit")
check(Data.SelectScooter(rich,'KuKirin G2 Max') and writes['8001'].selectedScooter=='KuKirin G2 Max',"Selected internal model persists")
check(not Data.SelectScooter(poor,'KuKirin G2 Master'),"Selection cannot bypass ownership")
local before=rich.leaderstats.Coins.Value
dataStoreService.failSaves['8001']=Config.SaveAttempts
ok,reason=Data.PurchaseProduct(rich,'radio')
check(not ok and reason=='SaveFailed' and not Data.OwnsProduct(rich,'radio') and rich.leaderstats.Coins.Value==before,"Failed purchase neither charges nor unlocks")
dataStoreService.failSaves['8001']=2
check(Data.PurchaseProduct(rich,'radio'),"Transient save retries finish one purchase")
check(rich.leaderstats.Coins.Value==200000 and writes['8001'].unlocks.radio,"Radio coin purchase persists")
check(not Data.PurchaseProduct(rich,'radio') and rich.leaderstats.Coins.Value==200000,"No duplicate radio charge")
check(Data.GrantProduct(rich,'radio') and rich.leaderstats.Coins.Value==200000,"Alternative entitlement is idempotent")
check(Data.SetItemEquipped(rich,'radio',true) and rich:GetAttribute('RadioEquipped')==true,"Unlock and activation are separate")
check(not Data.SetItemEquipped(poor,'radio',true),"Unowned radio cannot be equipped")
local concurrent=makePlayer(8004,{coins=50000})
playersService.PlayerAdded:Fire(concurrent)
local competing=false
dataStoreService.updateHook=function(id)
 if id~='8004' then return end
 dataStoreService.updateHook=nil
 check(Data.AddCoins(concurrent,100,'ConcurrentReward'),"Reward queues during purchase")
 local bought,why=Data.PurchaseProduct(concurrent,'kukirin_g2_master')
 competing=not bought and why=='Busy'
end
check(Data.PurchaseProduct(concurrent,'kukirin_g2_max'),"Original purchase succeeds")
check(competing and concurrent.leaderstats.Coins.Value==40100,"Competing purchase rejected; queued reward survives")
check(Data.Save(concurrent) and writes['8004'].coins==40100,"Queued reward persists")
concurrent.leaderstats.Coins.Value=999999
check(concurrent.leaderstats.Coins.Value==40100,"Presentation cannot mint currency")
check(not Data.AddCoins(concurrent,0/0,'Bad') and not Data.AddCoins(concurrent,math.huge,'Bad') and not Data.AddCoins(concurrent,-5,'Bad'),"Invalid coin operations rejected")
check(not Data.SpendCoins(concurrent,999999,'Purchase') and concurrent.leaderstats.Coins.Value==40100,"No negative debit")
check(Data.SpendCoins(concurrent,100,'TestDebit') and concurrent.leaderstats.Coins.Value==40000,"Central reasoned debit")
check(Data.GetProfile(concurrent).transactions[#Data.GetProfile(concurrent).transactions].reason=='TestDebit',"Audit reasons recorded")
check(Config.StudsPerKilometer==5760,"Arcade kilometer conversion")
Data.RecordRide(reward,5760,1)
check(reward.leaderstats.Coins.Value==100,"1 km pays 100")
Data.RecordRide(reward,11520,1)
check(reward.leaderstats.Coins.Value==300,"2 km pay 200 once")
Data.RecordRide(reward,2880,1);Data.RecordRide(reward,2880,2)
check(reward.leaderstats.Coins.Value==450,"Mixed wheelie pays weighted distance")
Data.RecordRide(reward,5760,2)
check(reward.leaderstats.Coins.Value==650,"x2 km pays 200")
Data.RecordRide(reward,2880,1)
check(reward.leaderstats.Coins.Value==700,"Ride pays 1 coin per 10 m without waiting for a kilometer")
Data.RecordRide(reward,Config.RideCoinStepStuds/2,1);Data.Save(reward)
check(math.abs(writes['8003'].rewardProgress.rideStuds-Config.RideCoinStepStuds/2)<0.001 and reward.leaderstats.Coins.Value==700,"Partial 10 m step persists unpaid")
local step=0.25
for _=1,240 do Data.RecordTimedReward(reward,'Burnout',step) end
check(reward.leaderstats.Coins.Value==725,"Minute of real burnout pays 25")
check(not Data.RecordTimedReward(reward,'Gang',1,0/0),"Invalid timed inputs rejected")
check(Math.Delivery(0)==100 and Math.Delivery(1000)==175 and Math.Delivery(2000)==250 and Math.Delivery(99999)==250,"Delivery interpolation bounded")
local motion=Math.NewMotion(Vector.zero)
local _,multiplier=Math.Sample(motion,Vector.zAxis*10,Vector.zAxis*40,100,true,true,false,step)
check(multiplier>1 and multiplier<2 and multiplier==1.01,"Wheelie ramps gradually in 0.01 steps")
for i=2,80 do _,multiplier=Math.Sample(motion,Vector.zAxis*10*i,Vector.zAxis*40,100,true,true,false,step) end
check(multiplier==2,"Twenty-second ramp reaches x2")
check(Math.WheelieMultiplier(10)==1.5 and Math.WheelieMultiplier(4.3)==1.21,"Multiplier rounds down to 0.01")
local distance
distance,multiplier=Math.Sample(motion,Vector.zAxis*810,Vector.zAxis*40,100,true,false,false,step)
check(distance>0 and multiplier==1 and motion.wheelieTime==0 and motion.wheelieDistance==0,"Ending wheelie returns x1")
distance,multiplier=Math.Sample(motion,Vector.zAxis*810,Vector.zero,100,true,true,false,step)
check(distance==0 and multiplier==1,"Standing yields nothing")
distance=Math.Sample(motion,Vector.zAxis*10000,Vector.zAxis*40,100,true,true,false,step)
check(distance==0,"Teleport yields nothing")
motion=Math.NewMotion(Vector.zero)
local oscillated=0
for i=1,100 do local p=if i%2==1 then Vector.zAxis*2 else Vector.zero;local v=if i%2==1 then Vector.zAxis*8 else -Vector.zAxis*8
 local d=Math.Sample(motion,p,v,100,true,false,false,step);oscillated+=d end
check(oscillated==0,"Local oscillation yields nothing")
motion=Math.NewMotion(Vector.zero)
check(Math.Sample(motion,Vector.zAxis*10,Vector.zAxis*40,100,true,false,true,step)==0,"Burnout doesn't double-pay ride distance")
check(Math.Sample(motion,Vector.zAxis*20,Vector.zAxis*40,100,false,true,false,step)==0,"Airborne displacement excluded")
check(Math.Sample(motion,Vector.zAxis*30,Vector.zAxis*40,100,true,true,false,5)==0,"Sampling gap cannot backfill rewards")
local Rewards=loadModule('ServerScriptService/Territory/TerritoryRewards')
gangAPI.groups.a={rich,poor};gangAPI.groups.b={concurrent}
local startRich=rich.leaderstats.Coins.Value;local startPoor=poor.leaderstats.Coins.Value;local startConcurrent=concurrent.leaderstats.Coins.Value
Rewards.Update({a=2},0);Rewards.Update({a=2},60)
check(rich.leaderstats.Coins.Value==startRich+200 and poor.leaderstats.Coins.Value==startPoor+200,"Two flags pay 200 per member")
Rewards.Update({b=2},60);Rewards.Update({b=2},90)
check(rich.leaderstats.Coins.Value==startRich+200 and concurrent.leaderstats.Coins.Value==startConcurrent+100,"Owner switch changes future accrual")
Rewards.Update({},90);Rewards.Update({},150)
check(concurrent.leaderstats.Coins.Value==startConcurrent+100,"Uncontrolled flags don't pay")
Rewards.Update({},150)
check(concurrent.leaderstats.Coins.Value==startConcurrent+100,"Timestamp cannot pay twice")
local store=dataStoreService:GetDataStore('Fixture')
local acquired=Persistence.Acquire(store,'8001','competing-server')
check(not acquired,"Second server cannot acquire active session")
local saved,why=Persistence.Save(store,'8001','foreign-token',{coins=0},false)
check(not saved and why=='SessionLost' and writes['8001'].coins>0,"Foreign snapshot cannot erase healthy data")
playersService.PlayerRemoving:Fire(reward)
check(writes['8003']._session==nil and Data.GetProfile(reward)==nil,"Disconnect saves/releases lease")
local rejoined=makePlayer(8003,{})
playersService.PlayerAdded:Fire(rejoined)
check(rejoined.leaderstats.Coins.Value==725 and math.abs(Data.GetProfile(rejoined).rewardProgress.rideStuds-Config.RideCoinStepStuds/2)<0.001,"Rejoin restores partial reward progress")
local savedRadio=rich.leaderstats.Coins.Value
playersService.PlayerRemoving:Fire(rich)
local richAgain=makePlayer(8001,{})
playersService.PlayerAdded:Fire(richAgain)
check(richAgain.leaderstats.Coins.Value==savedRadio and Data.OwnsProduct(richAgain,'radio') and Data.OwnsScooter(richAgain,'KuKirin G2 Max'),"Wallet/unlocks survive rejoin")
local Premium=loadModule('ServerScriptService/Shop/PremiumService')
Premium.Start()
local prompted=0
function marketplaceService:GetProductInfoAsync(id) return {IsForSale=true,PriceInRobux=if id==701 then 500 else 100} end
function marketplaceService:PromptGamePassPurchase() prompted+=1 end
local passPlayer=makePlayer(8005,{coins=500000});playersService.PlayerAdded:Fire(passPlayer)
local radio=Catalog.GetProduct('radio');radio.productId=701
check(Premium.Prepare(passPlayer,radio) and Premium.Pending(passPlayer) and prompted==1,"Server reserves/opens one radio prompt")
check(not Premium.Prepare(passPlayer,radio) and prompted==1,"Duplicate prompt blocked")
marketplaceService.PromptGamePassPurchaseFinished:Fire(passPlayer,701,false)
check(not Premium.Pending(passPlayer) and not Data.OwnsProduct(passPlayer,'radio'),"Cancel grants nothing")
check(Premium.Prepare(passPlayer,radio),"Prompt retry after cancel")
marketplaceService.PromptGamePassPurchaseFinished:Fire(passPlayer,701,true)
check(not Data.OwnsProduct(passPlayer,'radio'),"Finished flag alone grants nothing")
marketplaceService.ownership['8005:701']=true
marketplaceService.PromptGamePassPurchaseFinished:Fire(passPlayer,701,true)
check(Data.OwnsProduct(passPlayer,'radio') and writes['8005'].unlocks.radio,"Marketplace ownership durably granted")
local passCoins=passPlayer.leaderstats.Coins.Value
marketplaceService.PromptGamePassPurchaseFinished:Fire(passPlayer,701,true)
check(passPlayer.leaderstats.Coins.Value==passCoins and not Data.PurchaseProduct(passPlayer,'radio'),"Repeated confirmation/Coins alternative idempotent")
radio.productId=0
check(not Premium.Prepare(poor,radio) and prompted==2,"Missing IDs never prompt fictional products")
local smoke=Catalog.GetProduct('burnout_smoke');smoke.productId=702
function marketplaceService:GetProductInfoAsync() return {IsForSale=true,PriceInRobux=999} end
check(not Premium.Prepare(poor,smoke),"Real price mismatch blocks sale")
function marketplaceService:GetProductInfoAsync() return {IsForSale=true,PriceInRobux=100} end
marketplaceService.failRequests=true
check(not Premium.Prepare(poor,smoke) and not Data.OwnsProduct(poor,'burnout_smoke'),"Marketplace outage fails closed")
marketplaceService.failRequests=false
local folder=InstanceMock.new('Folder');folder.Name='ScooterModels';folder.Parent=services.ServerStorage
local rig=InstanceMock.new('Model');rig.Name='scooter';rig.PrimaryPart=InstanceMock.new('Part');rig.Parent=folder
local Shop=loadModule('ServerScriptService/Shop/ShopService')
local shopPlayer=makePlayer(8006,{coins=500000});playersService.PlayerAdded:Fire(shopPlayer)
radio.productId=701
function marketplaceService:GetProductInfoAsync() return {IsForSale=true,PriceInRobux=500} end
testClock+=1
check(Shop.Handle(shopPlayer,'PrepareRobux','radio'),"Shop uses server premium path")
testClock+=1
check(not Shop.Handle(shopPlayer,'PurchaseCoins','radio') and shopPlayer.leaderstats.Coins.Value==500000,"Open Robux prompt excludes Coins charge")
marketplaceService.PromptGamePassPurchaseFinished:Fire(shopPlayer,701,false)
testClock+=1
check(Shop.Handle(shopPlayer,'PurchaseCoins','radio') and shopPlayer.leaderstats.Coins.Value==250000,"Coins works after cancelling Robux")
testClock+=1
check(not Shop.Handle(shopPlayer,'PrepareRobux','radio'),"Coins unlock excludes later Robux sale")
testClock+=1
check(not Shop.Handle(shopPlayer,'PurchaseCoins',{}) and not Shop.Handle(shopPlayer,'ForgedGrant','radio'),"Hostile remote requests rejected")
-- Exercise the real delivery prompt lifecycle with verified walking displacement.
local depot=InstanceMock.new('Part');depot.Name='Depot';depot.Position=Vector.zero;depot.Parent=services.Workspace
local destination=InstanceMock.new('Part');destination.Name='Destination';destination.Position=Vector.zAxis*128;destination.Parent=services.Workspace
tagged.DeliveryPickup={depot};tagged.DeliveryDestination={destination}
local deliveryPlayer=makePlayer(8007,{coins=0});playersService.PlayerAdded:Fire(deliveryPlayer)
local character=InstanceMock.new('Model');character.Parent=services.Workspace;deliveryPlayer.Character=character
local root=InstanceMock.new('Part');root.Name='HumanoidRootPart';root.Position=Vector.zero;root.AssemblyLinearVelocity=Vector.zAxis*16;root.Parent=character
local human=InstanceMock.new('Humanoid');human.Health=100;human.WalkSpeed=16;human.Parent=character
local Activity=loadModule('ServerScriptService/Activity/ActivityService');Activity.Start()
depot.DeliveryPickupPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer:GetAttribute('DeliveryActive')~=true,"Pickup cannot start a job without the phone")
check(Activity.AcceptDelivery(deliveryPlayer),"Phone action accepts real server-selected order")
check(deliveryPlayer:GetAttribute('DeliveryStage')=='Pickup',"Accepted order requires shop pickup first")
check(not Activity.AcceptDelivery(deliveryPlayer),"Cannot accept two concurrent orders")
testClock+=1
destination.DeliveryDestinationPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer.leaderstats.Coins.Value==0,"No completion before collecting order")
testClock+=1
depot.DeliveryPickupPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer:GetAttribute('DeliveryStage')=='Dropoff',"Matching shop advances to delivery")
testClock+=0.25;services.RunService.Heartbeat:Fire(0.25)
for i=1,32 do root.Position=Vector.zAxis*i*4;testClock+=0.25;services.RunService.Heartbeat:Fire(0.25) end
destination.DeliveryDestinationPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer.leaderstats.Coins.Value==110 and deliveryPlayer:GetAttribute('DeliveryActive')==false,"Valid actual route completes and pays once")
testClock+=1;destination.DeliveryDestinationPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer.leaderstats.Coins.Value==110,"Repeated delivery completion cannot pay twice")
root.Position=Vector.zero
testClock+=1
check(Activity.AcceptDelivery(deliveryPlayer),"Can accept another order after completion")
check(Activity.CancelDelivery(deliveryPlayer) and deliveryPlayer.leaderstats.Coins.Value==110,"Cancellation pays nothing")
check(Activity.AcceptDelivery(deliveryPlayer),"Fresh order can be accepted")
testClock+=1;depot.DeliveryPickupPrompt.Triggered:Fire(deliveryPlayer)
testClock+=0.25;services.RunService.Heartbeat:Fire(0.25)
root.Position=Vector.zAxis*128
testClock+=0.25;services.RunService.Heartbeat:Fire(0.25)
check(deliveryPlayer:GetAttribute('DeliveryActive')==false,"Teleport cancels assigned order")
testClock+=1;destination.DeliveryDestinationPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer.leaderstats.Coins.Value==110,"Teleport cannot generate delivery payout")
-- Per-model effects can be equipped directly in the accepted shop, without a garage.
check(Data.GrantProduct(shopPlayer,'scooter_neons'),"Verified neon unlock")
testClock+=1
check(Shop.Handle(shopPlayer,'Equip','scooter_neons'),"Shop equips neon without garage transport")
check(Data.GetProfile(shopPlayer).visualsByModel[Data.GetProfile(shopPlayer).selectedScooter].Neon.enabled,"Equipped effect targets selected vehicle")
testClock+=1
check(Shop.Handle(shopPlayer,'Equip','scooter_neons'),"Shop can disable permanent effect")
check(not Data.GetProfile(shopPlayer).visualsByModel[Data.GetProfile(shopPlayer).selectedScooter].Neon.enabled,"Disabling retains entitlement")
check(Data.OwnsProduct(shopPlayer,'scooter_neons'),"Toggled accessory remains owned")
-- Oscillating first and teleporting just before a completion prompt must not bypass sampling.
root.Position=Vector.zero
testClock+=1;check(Activity.AcceptDelivery(deliveryPlayer),"Order accepted for prompt-race regression")
testClock+=1;depot.DeliveryPickupPrompt.Triggered:Fire(deliveryPlayer)
for i=1,30 do
 root.Position=Vector.zAxis*(if i%2==0 then 0 else 8)
 root.AssemblyLinearVelocity=Vector.zAxis*(if i%2==0 then -16 else 16)
 testClock+=0.5;services.RunService.Heartbeat:Fire(0.5)
end
root.Position=Vector.zAxis*128
-- No heartbeat before firing: completion must validate the final jump itself.
destination.DeliveryDestinationPrompt.Triggered:Fire(deliveryPlayer)
check(deliveryPlayer:GetAttribute('DeliveryActive')==false and deliveryPlayer.leaderstats.Coins.Value==110,"Final prompt rejects teleport after unrelated movement")
root.Position=Vector.zero
testClock+=1;check(Activity.AcceptDelivery(deliveryPlayer),"Order exists before shutdown")
Activity.Stop()
check(deliveryPlayer:GetAttribute("DeliveryActive")==false,"Activity shutdown clears jobs")
local Cosmetics=loadModule('ServerScriptService/Scooter/ScooterCosmetics')
check(not Cosmetics.GetVisuals(poor,'KuKirin G2 Pro').neonEnabled,"Cosmetics reject unowned effects")
check(Data.SetScooterVisual(shopPlayer,'Neon',true,Color.new(0.2,0.4,0.6),'KuKirin G2 Pro'),"Server stores selected model effect")
check(Cosmetics.GetVisuals(shopPlayer,'KuKirin G2 Pro').neonEnabled and Cosmetics.GetVisuals(shopPlayer,'KuKirin G2 Pro').neonColor.G==0.4,"Cosmetics use owned saved effect")
check(not Cosmetics.GetVisuals(shopPlayer,'KuKirin G2 Max').neonEnabled,"Effects do not automatically equip on another vehicle")
local painted=InstanceMock.new('Model');painted:SetAttribute('ScooterModel','KuKirin G2 Pro')
local deck=InstanceMock.new('Part');deck.Name='ScooterBody';deck.Parent=painted
local PaintConfig=loadModule('ReplicatedStorage/Shared/ScooterCustomConfig')
deck:SetAttribute(PaintConfig.Attribute,'Deck');deck:SetAttribute('ScooterCustomSolidColor',true);deck.Color=Color.new(0.8,0.8,0.8)
check(Data.SetPaint(shopPlayer,'KuKirin G2 Pro',{Deck=Color.new(0.2,0.4,0.6)}),"Existing paint is stored independently")
Cosmetics.ApplyPaint(shopPlayer,painted)
check(deck.Color.G==0.4,"Cosmetics apply actual paint groups")
function Color.fromHSV(h,s,v) return Color.new(h,s,v) end -- The engine owns HSV conversion; this fixture checks palette restoration.
check(Data.GrantProduct(shopPlayer,'rainbow_paint') and Data.SetRainbow(shopPlayer,'KuKirin G2 Pro',true),"Rainbow requires permanent ownership")
Cosmetics.ApplyPaint(shopPlayer,painted)
check(deck.Color.G==0.8 and Data.GetProfile(shopPlayer).paintByModel['KuKirin G2 Pro'].Deck[2]==0.4,"Rainbow applies without overwriting saved paint")
Data.SetRainbow(shopPlayer,'KuKirin G2 Pro',false);Cosmetics.ApplyPaint(shopPlayer,painted)
check(deck.Color.G==0.4,"Disabling rainbow restores prior paint")
painted:Destroy()
print(string.format('PASS: %d economy, persistence, rewards and shop assertions',testCount))

