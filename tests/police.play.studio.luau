--!strict
-- Run as a temporary server Script in a one-player Studio Play session.
-- This test repositions that test player/scooter and one unreserved police car
-- onto a real 1173-stud road route. It never edits Workspace.Map or saved assets.
-- Once PolicePlayStage="Ready", hold W for 5.5 seconds, then S for 1.5 seconds,
-- release inputs and wait. Read TrafficSystem.PolicePlayReport when finished.
local Http=game:GetService("HttpService")
local Manager=require(game.ServerScriptService.Traffic.TrafficManager)
local Scooter=require(game.ServerScriptService.Scooter.ScooterServer)
local Network=require(game.ServerScriptService.Traffic.RoadNetwork)
local Machine=require(game.ServerScriptService.Police.PoliceStateMachine)
local scenario=script:GetAttribute("Scenario") or "Speeding"
local report: any={states={},maxSpeedKmh=0,claimed=false,officerExited=false,arrested=false,released=false,observedWheelie=false,escapedIntervention=false,resumed=false}
local world=workspace:WaitForChild("TrafficSystem")
local CivilSpawner=require(game.ServerScriptService.Traffic.TrafficSpawner)
local originalSpawn=CivilSpawner.Spawn
local ok,errorMessage=pcall(function()
 local service=Manager.GetPoliceService()
 local deadline=os.clock()+15
 while (not service or not next(service.units)) and os.clock()<deadline do
  task.wait(0.1);service=Manager.GetPoliceService()
 end
 assert(service and next(service.units),"No live police unit")
 local player=game.Players:GetPlayers()[1];assert(player and player.Character,"A connected test player is required")
 local unit=select(2,next(service.units));local car=unit.car
 CivilSpawner.Spawn=function() return nil end
 for _,v in service.context.cars do if v.role~="Police" then v:Fail("TestFixture") end end
 Scooter.DismountForPlayer(player);task.wait(0.3)
 assert(not next(car.reservations),"Cannot relocate a reserved car")
 local node=assert(service.context.network.nodes["R_43.4_0.2_-1918.4>R_43.4_0.2_-1982.4"],"Test road missing")
 local scooter=Scooter.SpawnForPlayer(player);local root=scooter.PrimaryPart
 local seat=scooter:FindFirstChildWhichIsA("VehicleSeat",true)
 local bbox,size=scooter:GetBoundingBox();local height=root.Position.Y-(bbox.Position.Y-size.Y/2)
 local p=node.position+node.direction*35+Vector3.yAxis*(height+0.1)
 scooter:PivotTo(CFrame.lookAt(p,p+node.direction))
 for _,v in scooter:GetDescendants() do if v:IsA("BasePart") then v.AssemblyLinearVelocity=Vector3.zero;v.AssemblyAngularVelocity=Vector3.zero end end
 player.Character:PivotTo(seat.CFrame+Vector3.yAxis*2);seat:Sit(player.Character.Humanoid)
 car.route=Network.Route(service.context.network,node.id,Random.new(1));car.index=1;car.distance=0;car.traveled=0
 car.remove=false;car.exitReason=nil;car.speed=0;car.target=0;car.blockedTime=0;car.blockedSince=nil;car.managed=false;car.hold=false;car.destinationDistance=nil
 local frame=assert(service.context.sensor:Ground(node.position,node.direction,car.vehicle.bounds),"Test road does not support this car")
 car.vehicle.model:PivotTo(frame);car.lastFrame=frame;unit.machine=Machine.new(service.now)
 task.wait(0.7)
 assert(Scooter.GetRidingState(player),"Native scooter did not mount")
 world:SetAttribute("PolicePlayStage","Ready")
 local started=os.clock();local last="";local detainedUntil=0
 while os.clock()-started<60 do
  local riding=Scooter.GetRidingState(player)
  if riding then report.maxSpeedKmh=math.max(report.maxSpeedKmh,riding.speedKmh);report.observedWheelie=report.observedWheelie or riding.wheelie end
  if unit.machine.state~=last then table.insert(report.states,{state=unit.machine.state,time=os.clock()-started,reason=unit.machine.reason});last=unit.machine.state end
  report.claimed=report.claimed or service.pursuits:Owns(player,unit)
  report.officerExited=report.officerExited or unit.officer.outside
  if player:GetAttribute("PoliceState")=="ARRESTED" then
   report.arrested=true;detainedUntil=os.clock()
   report.detentionStopsRide=Scooter.GetRidingState(player)==nil
   report.detentionAnchorsCharacter=player.Character.HumanoidRootPart.Anchored
  elseif report.arrested then
   report.released=not player.Character.HumanoidRootPart.Anchored and player.Character.Humanoid.WalkSpeed>0
   local lock={};report.mountLockReleased=Scooter.LockMount(player,lock);Scooter.ReleaseMount(player,lock)
   report.pursuitReleased=service.pursuits.owners[player]==nil
   break
  end
  if scenario=="WheelieEscape" then
   if unit.machine.state=="RETURNING" and unit.resume and unit.machine.reason=="TargetFleeing" then
    report.escapedIntervention=true
    report.controlsAvailable=riding~=nil and riding.speedKmh>0 and player:GetAttribute("PoliceState")==nil
   end
   if report.escapedIntervention and unit.machine.state=="PURSUIT" then report.resumed=true;break end
  end
  if unit.target==player then world:SetAttribute("PolicePlayStage",unit.machine.state) end
  task.wait(0.1)
 end
 report.elapsed=os.clock()-started;report.lastDetainedAt=detainedUntil
 if scenario=="WheelieEscape" then
  assert(report.observedWheelie and report.claimed and unit.violation=="Wheelie","Real wheelie did not confirm pursuit")
  assert(report.escapedIntervention and report.controlsAvailable and not report.arrested and report.resumed,"Escape did not resume pursuit safely")
  return
 end
 assert(report.maxSpeedKmh>50 and report.claimed,"Real speeding did not confirm pursuit")
 assert(report.officerExited,"Officer did not physically exit")
 assert(report.arrested and report.released and report.mountLockReleased,"Detention/release failed")
end)
CivilSpawner.Spawn=originalSpawn
report.ok=ok;report.error=if ok then nil else tostring(errorMessage)
world:SetAttribute("PolicePlayStage",if ok then "Passed" else "Failed")
world:SetAttribute("PolicePlayReport",Http:JSONEncode(report))
print("[PoliceTest] "..Http:JSONEncode(report))
