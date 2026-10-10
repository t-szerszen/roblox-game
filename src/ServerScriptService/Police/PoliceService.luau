--!strict
local Players=game:GetService("Players")
local ServerStorage=game:GetService("ServerStorage")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ScooterConfig=require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Traffic=script.Parent.Parent.Traffic
local TrafficConfig=require(Traffic.TrafficConfiguration)
local Types=require(Traffic.TrafficTypes)
local Controller=require(Traffic.VehicleController)
local Sensors=require(Traffic.TrafficSensors)
local Config=require(script.Parent.PoliceConfig)
local Adapter=require(script.Parent.PoliceVehicleAdapter)
local Spawner=require(script.Parent.PoliceSpawner)
local Machine=require(script.Parent.PoliceStateMachine)
local Rules=require(script.Parent.TrafficViolationDetector)
local Pursuits=require(script.Parent.PolicePursuitController)
local Officer=require(script.Parent.PoliceOfficerController)
local Arrest=require(script.Parent.ArrestService)
local Debug=require(script.Parent.PoliceDebugService)
local Combat=require(script.Parent.Parent.Combat.CombatService)
local Police={};Police.__index=Police
export type Context={network: Types.Network, sensor: Sensors.Sensor, cars: {Controller.Vehicle},
 parent: Instance, root: Instance, random: Random, nextId: () -> number}
type Unit={car: Controller.Vehicle, machine: Machine.State, officer: Officer.Controller,
 observed: Player?, evidence: Rules.Evidence?, target: Player?, character: Model?,
 nextRoute: number, slowSince: number?, sequenceSince: number?, resume: boolean,
 recoveries: number, recoveryStart: number, speed: number, wheelie: boolean, violation: string,
 scanCursor: number}
export type Service=typeof(setmetatable({} :: {context: Context, units: {[number]: Unit},
 templates: {Model}, officerTemplate: Model?, pursuits: Pursuits.Registry, arrests: Arrest.Service,
 now: number, destroyed: boolean, nextSpawn: number, nextScan: number, scanOffset: number, templateIndex: number,
 officers: Folder, connections: {RBXScriptConnection}},Police))
local function characterRoot(character: Model?): BasePart?
 local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
 local human=if character then character:FindFirstChildOfClass("Humanoid") else nil
 return if root and root:IsA("BasePart") and human and human.Health>0 then root else nil
end
function Police.new(context: Context): Service
 local registry=Pursuits.new()
 local units: {[number]: Unit}={}
 local officers=context.root:FindFirstChild("PoliceOfficers")
 assert(not officers or officers:IsA("Folder"),"PoliceOfficers must be Folder")
 local folder=(officers or Instance.new("Folder")) :: Folder
 folder.Name="PoliceOfficers";folder.Parent=context.root
 for _,v in folder:GetChildren() do if v:GetAttribute("PoliceOwned")==true then v:Destroy() end end
 local self: Service=setmetatable({context=context,units=units,templates={},officerTemplate=nil,pursuits=registry,
  arrests=Arrest.new(function(player,owner,officer,vehicle)
   if not registry:Owns(player,owner) then return false end
   for _,unit in units do
    if unit==owner then
     return unit.machine.state=="ARRESTING" and unit.officer.model==officer and unit.car.vehicle.model==vehicle
      and not unit.car.remove and not unit.officer.destroyed
    end
   end
   return false
  end),
  now=0,destroyed=false,nextSpawn=0,nextScan=0,scanOffset=0,templateIndex=0,officers=folder,connections={}},Police)
 if not Config.Enabled then return self end
 local assets=ServerStorage:FindFirstChild("PoliceVehicleModels")
 for _,entry in Config.Vehicles do
  local source=if assets then assets:FindFirstChild(entry.name) else nil
  if source and source:IsA("Model") then
   local ok,template=pcall(Adapter.Template,source,entry.scale)
   if ok then table.insert(self.templates,template) else warn("[Police] "..entry.name..": "..tostring(template)) end
  else warn("[Police] missing ServerStorage.PoliceVehicleModels."..entry.name) end
 end
 task.spawn(function()
  local ok,template=pcall(Officer.CreateTemplate)
  if not ok then warn("[Police] officer template unavailable: "..tostring(template));return end
  if self.destroyed then template:Destroy() else self.officerTemplate=template end
 end)
 table.insert(self.connections,Players.PlayerRemoving:Connect(function(player)
  self.arrests:Release(player)
  for _,unit in self.units do if unit.target==player or unit.observed==player then self:Finish(unit,self.now,"Disconnected",false) end end
 end))
 return self
end
function Police.Transition(self: Service, unit: Unit, state: string, now: number, reason: string)
 unit.machine:Transition(state,now,reason)
 Debug.Write(unit.car.vehicle.model,{PoliceState=state,PoliceReason=reason})
end
function Police.Finish(self: Service, unit: Unit, now: number, reason: string, resume: boolean)
 unit.resume=resume
 unit.sequenceSince=nil;unit.slowSince=nil;unit.observed=nil;unit.evidence=nil
 if not resume and unit.target then
  Debug.Write(unit.car.vehicle.model,{LastPursuitEndReason=reason,LastPursuitUserId=unit.target.UserId})
  Debug.Signal(unit.target,nil);self.pursuits:Release(unit.target,unit)
  unit.target=nil;unit.character=nil
 end
 local state=unit.machine.state
 if state=="PATROL" or state=="OBSERVING" then
  if state=="OBSERVING" then self:Transition(unit,"PATROL",now,reason) end
 else self:Transition(unit,"RETURNING",now,reason) end
 unit.car.hold=unit.officer.outside
end
function Police.Observe(self: Service, unit: Unit, players: {Player}, now: number, budget: number): number
 if unit.machine.state=="PATROL" then
  for _=1,math.min(#players,budget) do
   unit.scanCursor=unit.scanCursor%#players+1
   local player=players[unit.scanCursor];budget-=1
   local riding=Rules.Read(player)
   if not riding or self.pursuits.owners[player] then continue end
   if riding.speedKmh<=Config.SpeedLimitKmh and not riding.wheelie then continue end
   local character=player.Character
   if not character or not Rules.Visible(unit.car.vehicle.model,unit.car.vehicle.root.CFrame,character,riding.model) then continue end
   unit.observed=player;unit.evidence=Rules.NewEvidence(now)
   self:Transition(unit,"OBSERVING",now,"PossibleViolation");break
  end
 end
 local player=unit.observed
 if not player or budget<=0 then return budget end
 budget-=1
 local riding=Rules.Read(player);local evidence=unit.evidence :: Rules.Evidence
 local visible=riding~=nil and player.Character~=nil
  and Rules.Visible(unit.car.vehicle.model,unit.car.vehicle.root.CFrame,player.Character :: Model,(riding :: Rules.ReadState).model)
 unit.speed=if riding then riding.speedKmh else 0;unit.wheelie=riding~=nil and riding.wheelie
 local reason=Rules.Accumulate(evidence,now,visible,riding~=nil,unit.speed,unit.wheelie)
 if reason and riding and self.pursuits:Claim(player,unit,riding.root.Position,now) then
  unit.target=player;unit.character=player.Character;unit.observed=nil;unit.evidence=nil;unit.violation=reason
  unit.car.driving.maxSpeed=Config.MaxPursuitSpeed
  unit.car.driving.edgeSpeedMultiplier=Config.MaxPursuitSpeed/TrafficConfig.MaxSpeed
  self:Transition(unit,"PURSUIT",now,reason);Debug.Signal(player,unit.car.id)
 elseif not riding or (not visible and now-evidence.lastSeen>Config.OcclusionTolerance)
  or (unit.speed<=Config.SpeedLimitKmh and not unit.wheelie) or self.pursuits.owners[player] then
  unit.observed=nil;unit.evidence=nil;self:Transition(unit,"PATROL",now,"ObservationEnded")
 end
 return budget
end
function Police.Intervene(self: Service, unit: Unit, root: BasePart, speed: number, visible: boolean, now: number)
 local car=unit.car;local state=unit.machine.state
 local distance=(root.Position-car.vehicle.root.Position).Magnitude
 if not visible then
  unit.sequenceSince=nil
  local memory=if unit.target then self.pursuits.memories[unit.target] else nil
  if state~="PURSUIT" and memory and now-memory.lastSeen>Config.LostSightTolerance then self:Finish(unit,now,"TargetHidden",true) end
  return
 end
 local stopped=speed<=Config.StopSpeedKmh*ScooterConfig.StudsPerKmH
 local path=car:Path()
 if state=="PURSUIT" and stopped and distance<=Config.InterventionDistance
  and path and not path.edge.intersection and not next(car.reservations) then
  unit.slowSince=now;self:Transition(unit,"APPROACHING",now,"TargetSlowing");state="APPROACHING"
 end
 if state=="APPROACHING" or state=="STOPPING" then
  if not stopped or distance>Config.InterventionDistance then
   unit.slowSince=nil;car.hold=false;self:Transition(unit,"PURSUIT",now,"TargetFleeing");return
  end
  car.hold=true
  if state=="APPROACHING" and now-(unit.slowSince or now)>=Config.StopConfirmation and car.speed<0.5 then
   self:Transition(unit,"STOPPING",now,"VehicleStopped")
  elseif state=="STOPPING" and now-unit.machine.since>=0.4 then
   self:Transition(unit,"OFFICER_EXITING",now,"OfficerExit")
  end
 elseif state=="OFFICER_EXITING" then
  if not stopped or distance>Config.InterventionDistance*1.5 then self:Finish(unit,now,"TargetFleeing",true);return end
  if not unit.officer.outside then unit.officer:Exit(self.officers,now) end
  if unit.officer.outside and not unit.officer.exitStarted then self:Transition(unit,"ARRESTING",now,"OfficerApproaching")
  elseif now-unit.machine.since>Config.OfficerExitTimeout then self:Finish(unit,now,"ExitObstructed",false) end
 elseif state=="ARRESTING" then
  if not stopped or distance>Config.InterventionDistance*1.5 then self:Finish(unit,now,"TargetFleeing",true);return end
  if now-unit.machine.since>Config.OfficerApproachTimeout then self:Finish(unit,now,"OfficerTimeout",false);return end
  local valid,reason=self.arrests:Validate(unit.target :: Player,unit,unit.character :: Model,unit.officer.model,car.vehicle.model)
  if valid then
   unit.officer.humanoid:MoveTo(unit.officer.root.Position)
   unit.sequenceSince=unit.sequenceSince or now
   if now-(unit.sequenceSince :: number)>=Config.ArrestSequenceDuration then
    local arrested,result=self.arrests:Try(unit.target :: Player,unit,unit.character :: Model,unit.officer.model,car.vehicle.model,now)
    if arrested then self:Finish(unit,now,"Arrested",false) else unit.sequenceSince=nil;car.vehicle.model:SetAttribute("ArrestFailure",result) end
   end
  else
   unit.sequenceSince=nil;car.vehicle.model:SetAttribute("ArrestFailure",reason)
   if visible then unit.officer:Navigate(root.Position,now) end
  end
 end
end
function Police.UpdateUnit(self: Service, unit: Unit, now: number)
 local car=unit.car;local state=unit.machine.state
 if not unit.officer.model.Parent or not unit.officer.root.Parent or unit.officer.humanoid.Health<=0 then car:Fail("OfficerRemoved");return end
 local player=unit.target
 if player then
  local root=characterRoot(unit.character)
  if player.Parent~=Players or player.Character~=unit.character or not root then self:Finish(unit,now,"TargetRemoved",false)
  elseif Combat.IsInSafeZone(root.Position) then self:Finish(unit,now,"SafeZone",false)
  else
   local riding=Rules.Read(player)
   local visible=Rules.Visible(car.vehicle.model,car.vehicle.root.CFrame,unit.character :: Model,if riding then riding.model else nil)
   if not visible and unit.officer.outside then
    visible=Rules.Visible(unit.officer.model,unit.officer.root.CFrame,unit.character :: Model,if riding then riding.model else nil)
   end
   if visible then
    unit.speed=if riding then riding.speedKmh else 0;unit.wheelie=riding~=nil and riding.wheelie
   end
   self.pursuits:Observe(player,unit,if visible then root.Position else nil,now)
   local memory=self.pursuits.memories[player]
   local expired=if memory then Pursuits.Expired(memory,car.vehicle.root.Position,now) else "AuthorityLost"
   if expired then self:Finish(unit,now,expired,false)
   elseif state~="RETURNING" and state~="RECOVERING" then
    local velocity=if riding then riding.root.AssemblyLinearVelocity else root.AssemblyLinearVelocity
    local speed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
    if state=="PURSUIT" and now>=unit.nextRoute then
     unit.nextRoute=now+Config.RouteInterval
     local goal=memory.position-car.vehicle.root.CFrame.LookVector*Config.FollowDistance
     local gap=car:SetDestination(goal)
     if gap==math.huge then car:Patrol() end
    end
    self:Intervene(unit,root,speed,visible,now)
   end
  end
 end
 state=unit.machine.state
 if state=="RETURNING" then
  if unit.officer.outside then
   car.hold=true
   local door=unit.officer.door
   if door then
    unit.officer:Navigate(door,now)
    if (unit.officer.root.Position-door).Magnitude<Config.OfficerWaypointTolerance+1 then unit.officer:Board() end
   end
   if now-unit.machine.since>Config.OfficerApproachTimeout then car:Fail("OfficerReturnTimeout") end
  elseif now-unit.machine.since>=Config.ReturnDuration then
   car.hold=false
   if unit.resume and unit.target then self:Transition(unit,"PURSUIT",now,"ResumedPursuit");unit.nextRoute=0
   else
    car.driving.maxSpeed=Config.PatrolSpeed;car.driving.edgeSpeedMultiplier=1;car:Patrol()
    self:Transition(unit,"PATROL",now,"Returned")
   end
  end
 elseif state=="RECOVERING" then
  if car.traveled-unit.recoveryStart>4 then
   self:Transition(unit,if unit.target then "PURSUIT" else "PATROL",now,"RouteRecovered");unit.nextRoute=0
  elseif now-unit.machine.since>=Config.RecoveryTimeout then
   unit.recoveries+=1
   if unit.recoveries>=Config.MaxRecoveryAttempts then car:Fail("PoliceStuck")
   else unit.machine.since=now;car:Patrol() end
  end
 elseif not car.hold and car.blockedTime>=Config.StuckTimeout then
  unit.recoveryStart=car.traveled;unit.recoveries=0;car:Patrol()
  self:Transition(unit,"RECOVERING",now,"BlockedRoute")
 end
 unit.officer:Animate(now,unit.sequenceSince~=nil)
 Adapter.Signals(car.vehicle.model,unit.target~=nil,now)
 if Debug.Enabled(self.context.root) then
  Debug.Write(car.vehicle.model,{ObservedUserId=if unit.observed then unit.observed.UserId else 0,
   TargetUserId=if unit.target then unit.target.UserId else 0,Violation=unit.violation,
   ObservedSpeedKmh=unit.speed,ObservedWheelie=unit.wheelie,Route=table.concat(car.route,","),
   RouteTarget=tostring(car.targetPoint),RecoveryAttempts=unit.recoveries})
 end
end
function Police.Update(self: Service, now: number)
 if self.destroyed then return end
 self.now=now;self.arrests:Update(now)
 if now<self.nextScan then return end
 self.nextScan=now+1/Config.ObservationRate
 local players=Players:GetPlayers();local budget=Config.MaxScansPerTick;local ordered: {Unit}={}
 for _,unit in self.units do table.insert(ordered,unit) end
 local count=#ordered;local initialCount=count
 local desired=Spawner.Target()
 for offset=1,initialCount do
  local unit=ordered[(self.scanOffset+offset-1)%initialCount+1]
  if count>desired and unit.machine.state=="PATROL" then unit.car:Fail("NightReduction");count-=1 end
  if unit.car.remove or not unit.car.vehicle.model.Parent then continue end
  local ok,err=pcall(function()
   if budget>0 and (unit.machine.state=="PATROL" or unit.machine.state=="OBSERVING") then
    local allocation=math.min(budget,math.max(1,math.floor(Config.MaxScansPerTick/math.max(1,count))))
    budget-=allocation-self:Observe(unit,players,now,allocation)
   end
   self:UpdateUnit(unit,now)
  end)
  if not ok then warn("[Police] unit error: "..tostring(err));unit.car:Fail("PoliceError") end
 end
 self.scanOffset=if initialCount>0 then (self.scanOffset+math.min(Config.MaxScansPerTick,initialCount))%initialCount else 0
 if count<desired and self.officerTemplate and #self.templates>0 and #players>0 and now>=self.nextSpawn then
  self.nextSpawn=now+Config.SpawnInterval;self.templateIndex=self.templateIndex%#self.templates+1
  local car=Spawner.Spawn(self.context.nextId(),self.templates[self.templateIndex],self.context.network,
   self.context.sensor,self.context.cars,self.context.parent,self.context.random)
  if car then
   local officerOk,officer=pcall(Officer.new,self.officerTemplate,car.vehicle.model)
   if not officerOk then car.vehicle.model:Destroy();warn("[Police] officer spawn failed: "..tostring(officer));return end
   local unit: Unit={car=car,officer=officer,machine=Machine.new(now),observed=nil,evidence=nil,target=nil,
    character=nil,nextRoute=0,slowSince=nil,sequenceSince=nil,resume=false,recoveries=0,recoveryStart=0,
    speed=0,wheelie=false,violation="",scanCursor=0}
   self.units[car.id]=unit;table.insert(self.context.cars,car)
   Debug.Write(car.vehicle.model,{PoliceState="PATROL",PoliceReason="Spawned"})
  end
 end
 self.context.root:SetAttribute("PoliceVehicleCount",count)
end
function Police.Removing(self: Service, car: Controller.Vehicle, now: number)
 local unit=self.units[car.id];if not unit then return end
 if unit.target then Debug.Signal(unit.target,nil);self.pursuits:Release(unit.target,unit) end
 self.arrests:ReleaseOwner(unit);unit.officer:Destroy();self.units[car.id]=nil
 self.nextSpawn=math.max(self.nextSpawn,now+Config.RespawnCooldown)
end
function Police.Destroy(self: Service)
 if self.destroyed then return end
 self.destroyed=true;self.arrests:Destroy()
 for _,connection in self.connections do connection:Disconnect() end;table.clear(self.connections)
 for _,unit in self.units do self:Removing(unit.car,0) end
 for _,template in self.templates do template:Destroy() end;table.clear(self.templates)
 if self.officerTemplate then self.officerTemplate:Destroy();self.officerTemplate=nil end
 self.context.root:SetAttribute("PoliceVehicleCount",0)
end
return Police
