-- Integration doubles exercise production code, not native physics or visual rendering.
function vectorMethods:Lerp(other,alpha) return self+(other-self)*alpha end
Vector.one=Vector.new(1,1,1)
services.Workspace={GetServerTimeNow=function() return 1000 end}
services.ServerStorage=InstanceMock.new("ServerStorage")
local function frame(p,d) return {Position=p,LookVector=d or -Vector.zAxis} end
Frame.lookAt=function(p,target) return frame(p,(target-p).Unit) end
local Config=loadModule("ServerScriptService/Police/PoliceConfig")
local TrafficConfig=loadModule("ServerScriptService/Traffic/TrafficConfiguration")
local Lifecycle=loadModule("ServerScriptService/Traffic/VehicleLifecycle")
local Rules=loadModule("ServerScriptService/Police/TrafficViolationDetector")
local Scooter=loadModule("ServerScriptService/Scooter/ScooterServer")
local Controller=loadModule("ServerScriptService/Traffic/VehicleController")
local Police=loadModule("ServerScriptService/Police/PoliceService")
local Registry=loadModule("ServerScriptService/Police/PolicePursuitController")
local Machine=loadModule("ServerScriptService/Police/PoliceStateMachine")
local Intersections=loadModule("ServerScriptService/Traffic/IntersectionManager")
local Network=loadModule("ServerScriptService/Traffic/RoadNetwork")
function instanceMethods:IsDescendantOf(parent)
 local current=self.Parent
 while current do if current==parent then return true end;current=current.Parent end
 return false
end
function instanceMethods:FindFirstChildOfClass(name)
 for _,child in self:GetChildren() do if child:IsA(name) then return child end end
 return nil
end

for _,reason in {"DeadEnd","Irrelevant","Stuck","PoliceStuck","RecoveryTimeout","IntersectionTimeout","NightReduction"} do
 check(not Lifecycle.CanRemove(true,reason),"Protected unit survives "..reason)
 check(Lifecycle.CanRemove(false,reason),"Unprotected vehicle can retire for "..reason)
end
check(Lifecycle.CanRemove(true,"RemovedRoot"),"Structural loss still cleans up a pursuit")
check(Lifecycle.CanRemove(true,"ControllerError"),"Broken controllers still clean up")
local npc=InstanceMock.new("Model");npc:SetAttribute("NPCVehicle",true)
local bumper=InstanceMock.new("Part");bumper.Parent=npc
for _,reason in {"StopSign","IntersectionYield","CommandedStop","RouteEnd"} do
 check(Lifecycle.NormalWait(reason,nil),"Expected wait: "..reason)
end
check(Lifecycle.NormalWait("EmergencyBrake",bumper),"Civilian queue is an expected wait")
check(not Lifecycle.NormalWait("NoRoadSupport",nil),"Unsupported car can recover")
check(not Lifecycle.NormalWait("Obstacle",InstanceMock.new("Part")),"World blocker can recover")
check(Rules.Impact(-Vector.zAxis*20,Vector.zero,-Vector.zAxis),"Approaching rider impact")
check(not Rules.Impact(Vector.xAxis*30,Vector.zero,-Vector.zAxis),"Tangential scraping is ignored")
check(not Rules.Impact(Vector.zero,Vector.zAxis*30,-Vector.zAxis),"Police hitting stationary rider is ignored")
check(not Rules.Impact(-Vector.zAxis*5,Vector.zero,-Vector.zAxis),"Low-speed contact is ignored")
check(not Rules.Impact(-Vector.zAxis*20,-Vector.zAxis*20,-Vector.zAxis),"No relative closing motion is ignored")
local p1=makePlayer(91,{});local p2=makePlayer(92,{})
local evidence,confirmed=Rules.Blocking(nil,p1,0)
check(not confirmed,"First blockage sample is not an offence")
for i=1,Config.TrafficBlockDuration*Config.ObservationRate do
 evidence,confirmed=Rules.Blocking(evidence,p1,i/Config.ObservationRate)
end
check(confirmed,"Sustained same-player obstruction confirms")
evidence,confirmed=Rules.Blocking(evidence,p2,Config.TrafficBlockDuration+0.2)
check(not confirmed and evidence.player==p2,"Changing blocker resets evidence")
evidence,confirmed=Rules.Blocking(evidence,nil,Config.TrafficBlockDuration+0.4)
check(evidence==nil and not confirmed,"Intersection/queue/no culprit clears offence")
evidence=Rules.Blocking(nil,p1,0)
evidence,confirmed=Rules.Blocking(evidence,p1,100)
check(not confirmed and evidence.since==100,"Stale evidence cannot confirm after a sampling gap")

local data={version=1,approved=true,nodes={},edges={},spawns={"N0"},review={}}
for i=0,4 do
 table.insert(data.nodes,{id="N"..i,position=-Vector.zAxis*100*i,direction=-Vector.zAxis,
  road="r",lane="r",speed=32,outgoing=if i<4 then {"E"..i} else {}})
 if i<4 then table.insert(data.edges,{id="E"..i,from="N"..i,to="N"..(i+1),
  control1=-Vector.zAxis*(100*i+30),control2=-Vector.zAxis*(100*i+70),road="r",lane="r",speed=32}) end
end
local network=Network.Load(data)
local random={NextInteger=function(_,a) return a end}
local owner=InstanceMock.new("Folder")
local function car(id)
 local model=InstanceMock.new("Model");model.Parent=owner
 local root=InstanceMock.new("Part");root.Parent=model;model.PrimaryPart=root
 root.Position=Vector.zero;root.CFrame=frame(Vector.zero);root.Size=Vector.new(6,4,12)
 function model:PivotTo(cf) root.Position=cf.Position;root.CFrame=cf end
 return Controller.new(id,{model=model,root=root,bounds=root.Size,wheelbase=7.5},network,{"E0","E1","E2","E3"},random)
end
local sensor={Ground=function(_,p,d) return frame(p,d) end,Clear=function() return false,nil end,Sweep=function() return false,nil end}
local intersections=Intersections.new()
local civilian=car(1)
civilian.reason="Obstacle";civilian.target=0
for _=1,3599 do civilian:Step(1/30,sensor,intersections) end
check(not civilian.remove and civilian.recoveryAttempts==0,"No civilian recovery before 120 seconds without route progress")
for _=1,2 do civilian:Step(1/30,sensor,intersections) end
check(not civilian.remove and civilian.recoveryAttempts==1,"First 120-second recovery preserves the car")
for _=1,1000 do civilian:Step(1/30,sensor,intersections) end
check(civilian.remove and civilian.exitReason=="Stuck","Confirmed failed recovery eventually retires one civilian")
local queued=car(2)
queued.obstacle=bumper;queued.reason="Obstacle"
function sensor:Sweep() return false,bumper end
for _=1,10000 do queued:Step(1/30,sensor,intersections) end
check(not queued.remove and queued.recoveryAttempts==0,"Long legitimate traffic queue survives")
function sensor:Clear() return false,bumper end
queued.reason="EmergencyBrake";queued:Sense(sensor,intersections,400)
check(not queued.remove,"Sensing lifetime check also preserves a legitimate queue")
queued.reason="Driving";queued.obstacle=nil;queued.target=10
check(not queued:RecoveryBlocked(),"Released queue with a positive driving target does not enter recovery")
function sensor:Clear() return false,nil end
function sensor:Sweep() return false,nil end
local protected=car(3);protected.lifecycleProtected=true
for _,reason in {"DeadEnd","Irrelevant","IntersectionTimeout","PoliceStuck"} do
 check(not protected:Fail(reason) and not protected.remove,"Actual controller protects "..reason)
end
local progressing=car(4)
function sensor:Sweep() return true,nil end
progressing.noProgressTime=119;progressing.recoveryAttempts=1;progressing.target=5
for _=1,90 do progressing:Step(1/30,sensor,intersections) end
check(progressing.noProgressTime<2 and progressing.recoveryAttempts==0,"Verified curve-distance progress resets recovery")
local waiting=car(5);waiting.hold=true
for _=1,4000 do waiting:Step(1/30,sensor,intersections) end
check(not waiting.remove and waiting.recoveryAttempts==0,"Intervention hold never causes recovery")

local function character(player,position)
 local model=InstanceMock.new("Model");model.Parent=owner;player.Character=model
 local root=InstanceMock.new("BasePart");root.Name="HumanoidRootPart";root.Position=position
 root.AssemblyLinearVelocity=Vector.zero;root.Parent=model;model.PrimaryPart=root
 local human=InstanceMock.new("Humanoid");human.Health=100;human.Parent=model
 return model,root
end
local char1,root1=character(p1,-Vector.zAxis*40)
local char2,root2=character(p2,-Vector.zAxis*50)
local function unit(id)
 local vehicle=car(id);vehicle.role="Police"
 local model,root=character({},Vector.zero)
 return {car=vehicle,machine=Machine.new(0),officer={model=model,root=root,humanoid={Health=100},outside=false,
  Animate=function() end},nextRoute=0,recoveries=0,recoveryStart=0,scanCursor=0}
end
local first,second=unit(10),unit(11)
local service=setmetatable({units={[10]=first,[11]=second},pursuits=Registry.new(),contacts={},blocks={},
 context={cars={first.car,second.car},root=owner},arrests={ReleaseOwner=function() end}},Police)
check(service:Begin(first,p1,root1.Position,0,"PoliceImpact"),"Incident starts pursuit directly from PATROL")
check(first.target==p1 and first.character==char1 and first.car.lifecycleProtected,"Player, character and lifecycle claim are recorded together")
check(not service:Begin(second,p1,root1.Position,1,"TrafficBlocking"),"Another unit cannot duplicate a pursuit")
check(not service:Begin(first,p2,root2.Position,1,"PoliceImpact"),"Active unit cannot steal another player's target")
check(service:Begin(second,p2,root2.Position,0,"Speeding"),"Independent multiplayer pursuit can start")
local oldVisible=Rules.Visible
Rules.Visible=function() return true end
local scooterModel=InstanceMock.new("Model");scooterModel.Parent=owner
local scooterRoot=InstanceMock.new("BasePart");scooterRoot.Position=-Vector.zAxis*80
scooterRoot.AssemblyLinearVelocity=-Vector.zAxis*50;scooterRoot.Parent=scooterModel
Scooter.states[p1]={model=scooterModel,root=scooterRoot,speedKmh=31.25,wheelie=false}
service:UpdateUnit(first,1)
check(service.pursuits.memories[p1].position==scooterRoot.Position,"Pursuit remembers the physical scooter root")
Scooter.states[p1]=nil
service:UpdateUnit(first,1.2)
check(first.target==p1 and first.machine.state=="PURSUIT","Dismount does not cancel an existing pursuit")
Rules.Visible=function() return false end
service:UpdateUnit(first,1.4)
check(first.target==p1,"Short loss of sight retains ownership")
service:Finish(first,2,"TargetFleeing",true)
check(first.target==p1 and first.car.lifecycleProtected,"Returning to board retains a resumed pursuit's protection")
service:Finish(first,3,"Escaped",false)
check(first.target==nil and service.pursuits.owners[p1]==nil and not first.car.lifecycleProtected,"Finished pursuit releases target and retirement protection")
check(second.target==p2 and service.pursuits:Owns(p2,second),"Finishing one pursuit leaves the other owner intact")
service:UpdateUnit(second,Config.PursuitTimeout+1)
check(second.target==nil,"Pursuit deadline returns the unit and clears its claim")
Rules.Visible=oldVisible

-- The actual orchestration consumes server riding records and contact query results.
getfenv().Enum={RaycastFilterType={Include="Include"}}
getfenv().OverlapParams={new=function() return {} end}
first,second=unit(20),unit(21)
service=setmetatable({units={[20]=first,[21]=second},pursuits=Registry.new(),contacts={},blocks={},
 context={cars={first.car,second.car},root=owner},arrests={ReleaseOwner=function() end}},Police)
scooterRoot.Position=-Vector.zAxis*5;scooterRoot.AssemblyLinearVelocity=Vector.zAxis*20
Scooter.states[p1]={model=scooterModel,root=scooterRoot,speedKmh=12.5,wheelie=false}
services.Workspace.GetPartBoundsInBox=function() return {scooterRoot} end
service:Incidents({p1,p2},0)
check(first.target==p1 or second.target==p1,"Physical scooter contact starts a police impact pursuit")
local claimed=service.pursuits.owners[p1]
service:Incidents({p1,p2},0.2)
check(service.pursuits.owners[p1]==claimed,"Repeated parts/contact samples retain exactly one owner")
local claims=0;for _ in service.pursuits.owners do claims+=1 end
check(claims==1,"One collision cannot create independent duplicate pursuits")
service:Finish(claimed,0.4,"Escaped",false)
claimed.machine:Transition("PATROL",0.4,"TestReturn")
service:Incidents({p1,p2},0.4)
check(service.pursuits.owners[p1]==nil,"Continuous scraping does not restart the completed pursuit")
services.Workspace.GetPartBoundsInBox=function() return {} end
service:Incidents({p1,p2},0.6)
services.Workspace.GetPartBoundsInBox=function() return {scooterRoot} end
service:Incidents({p1,p2},0.8)
check(service.pursuits.owners[p1]==nil,"Repeated collision is suppressed during the incident cooldown")
local unrelated=InstanceMock.new("BasePart");unrelated.Parent=InstanceMock.new("Model")
services.Workspace.GetPartBoundsInBox=function() return {unrelated} end
service:Incidents({p1,p2},4)
check(service.pursuits.owners[p1]==nil,"Unowned/contact-only model cannot impersonate a server rider")
Scooter.states[p1]=nil
services.Workspace.GetPartBoundsInBox=function() return {} end
Rules.Visible=function() return true end
root2.Position=-Vector.zAxis*12
local blockedCar=car(30);blockedCar.obstacle=char2;blockedCar.reason="Obstacle"
table.insert(service.context.cars,blockedCar)
for i=0,Config.TrafficBlockDuration*Config.ObservationRate do
 service:Incidents({p1,p2},10+i/Config.ObservationRate)
end
check(service.pursuits.owners[p2]~=nil,"Sustained attributed pedestrian obstruction dispatches a patrol")
local blockOwner=service.pursuits.owners[p2]
check(blockOwner.violation=="TrafficBlocking","Dispatch preserves the blockage reason")
service:Finish(blockOwner,23,"Escaped",false)
blockOwner.machine:Transition("PATROL",23,"TestReturn")
blockedCar.reason="IntersectionYield"
for i=0,Config.TrafficBlockDuration*Config.ObservationRate do service:Incidents({p1,p2},24+i/Config.ObservationRate) end
check(service.pursuits.owners[p2]==nil and service.blocks[30]==nil,"Normal intersection wait cannot dispatch police")
blockedCar.reason="Obstacle";blockedCar.obstacle=bumper
for i=0,Config.TrafficBlockDuration*Config.ObservationRate do service:Incidents({p1,p2},40+i/Config.ObservationRate) end
check(service.pursuits.owners[p2]==nil,"Queue behind an NPC cannot be attributed to a nearby player")
blockedCar.obstacle=char2
service:Incidents({p1,p2},60)
service.context.cars={first.car,second.car}
service:Incidents({p1,p2},60.2)
check(service.blocks[30]==nil,"Removed civilian releases blockage evidence")
Scooter.states[p1]={model=scooterModel,root=scooterRoot,speedKmh=12.5,wheelie=false}
service:Incidents({p1,p2},61)
Scooter.states[p1]=nil
service:Incidents({p2},61.2)
check(service.contacts[p1]==nil,"Removed/dismounted player releases contact samples")
local p3=makePlayer(93,{})
local char3,root3=character(p3,-Vector.zAxis*60)
check(service:Begin(first,p3,root3.Position,62,"Speeding"),"A returned unit can claim a new player")
char3:FindFirstChildOfClass("Humanoid").Health=0
service:UpdateUnit(first,62.2)
check(first.target==nil and service.pursuits.owners[p3]==nil,"Death releases the exact target claim")
first.machine:Transition("PATROL",63,"TestReturn")
char3,root3=character(p3,-Vector.zAxis*60)
check(service:Begin(first,p3,root3.Position,63,"Speeding"),"Living respawn can start a fresh pursuit")
character(p3,-Vector.zAxis*60)
service:UpdateUnit(first,63.2)
check(first.target==nil and service.pursuits.owners[p3]==nil,"Character replacement cannot inherit an old pursuit")
first.machine:Transition("PATROL",64,"TestReturn")
root3=p3.Character.PrimaryPart
check(service:Begin(first,p3,root3.Position,64,"Speeding"),"Replaced character can be claimed through a new incident")
p3.Parent=nil
service:UpdateUnit(first,64.2)
check(first.target==nil and service.pursuits.owners[p3]==nil,"Disconnect clears the active target and claim")
Rules.Visible=oldVisible
print(string.format("PASS: %d police/traffic integration assertions",testCount))
