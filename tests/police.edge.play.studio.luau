--!strict
-- Temporary server Script, one-player Studio Play only. Injects authorized
-- interventions to isolate removal/respawn/restart cleanup with real instances.
-- Repositions the test character, respawns it and restarts the NPC traffic fleet.
local Manager=require(game.ServerScriptService.Traffic.TrafficManager)
local Machine=require(game.ServerScriptService.Police.PoliceStateMachine)
local Scooter=require(game.ServerScriptService.Scooter.ScooterServer)
local Http=game:GetService("HttpService")
local world=workspace.TrafficSystem
local player=game.Players:GetPlayers()[1]
local report: any={checks=0}
local function check(value: boolean,message: string) assert(value,message);report.checks+=1 end
local function waitFor(test: ()->boolean,timeout: number)
 local deadline=os.clock()+timeout
 while not test() and os.clock()<deadline do task.wait(0.1) end
 check(test(),"Timed out waiting for native state")
end
local ok,errorMessage=pcall(function()
 local service=assert(Manager.GetPoliceService())
 local function begin()
  waitFor(function()
   local protection=player:GetAttribute("InvulnerableUntil")
   return typeof(protection)~="number" or protection<=workspace:GetServerTimeNow()
  end,5)
  service.nextSpawn=service.now
  waitFor(function() return next(service.units)~=nil end,30)
  local unit=select(2,next(service.units));local car=unit.car
  check(not next(car.reservations),"Fixture must not relocate a reserved car")
  car.hold=true
  waitFor(function() return car.speed<0.1 end,4)
  if not unit.officer.outside then check(unit.officer:Exit(service.officers,service.now),"Supported real-road officer exit") end
  waitFor(function() return unit.officer.exitStarted==nil end,3)
  unit.machine=Machine.new(service.now)
  for _,state in {"OBSERVING","PURSUIT","APPROACHING","STOPPING","OFFICER_EXITING","ARRESTING"} do unit.machine:Transition(state,service.now,"CleanupFixture") end
  player:SetAttribute("PoliceReleaseUntil",nil)
  local root=unit.officer.root
  player.Character:PivotTo(CFrame.new(root.Position+Vector3.new(0,4,2)))
  player.Character.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
  check(service.pursuits:Claim(player,unit,player.Character.HumanoidRootPart.Position,service.now),"Fixture claims unique pursuit")
  unit.target=player;unit.character=player.Character
  check(not service.arrests:Validate(player,unit,player.Character,unit.officer.model,Instance.new("Model")),"Wrong actor vehicle rejected")
  local accepted,reason=service.arrests:Try(player,unit,player.Character,unit.officer.model,car.vehicle.model,service.now)
  check(accepted,"Real player accepts authorized detention: "..reason)
  service:Finish(unit,service.now,"Arrested",false)
  waitFor(function() return player.Character.HumanoidRootPart.Anchored end,2)
  return unit
 end
 report.stage="OfficerRemoval"
 local unit=begin();unit.officer.model:Destroy()
 waitFor(function() return player:GetAttribute("PoliceState")==nil end,2)
 check(not player.Character.HumanoidRootPart.Anchored,"Officer deletion restores character")
 check(service.arrests.holds[player]==nil,"Officer deletion clears hold record")
 waitFor(function() return service.units[unit.car.id]==nil end,2)
 report.officerRemoval=true
 report.stage="VehicleRemoval"
 unit=begin();unit.car.vehicle.model:Destroy()
 waitFor(function() return player:GetAttribute("PoliceState")==nil end,2)
 check(not player.Character.HumanoidRootPart.Anchored,"Car deletion restores character")
 check(service.nextSpawn>=service.now,"Respawn throttle survives car deletion")
 waitFor(function() return service.units[unit.car.id]==nil end,2)
 report.vehicleRemoval=true
 report.stage="Respawn"
 unit=begin()
 local previousCharacter=player.Character
 player:LoadCharacterAsync()
 waitFor(function() return player.Character~=nil and player.Character~=previousCharacter and player.Character:FindFirstChild("HumanoidRootPart")~=nil and player:GetAttribute("PoliceState")==nil and service.arrests.holds[player]==nil end,5)
 check(player:GetAttribute("PoliceState")==nil and service.arrests.holds[player]==nil,"Real respawn clears detention")
 local owner={};check(Scooter.LockMount(player,owner),"Respawn removes mount lock");Scooter.ReleaseMount(player,owner)
 report.respawn=true
 report.stage="Restart"
 local map=workspace.Map;local descendants=#map:GetDescendants()
 local retained=Instance.new("Model");retained.Name="__RetainedAuthoringFixture";retained.Parent=world.ActiveVehicles
 Manager.Stop();check(service.destroyed and next(service.units)==nil,"Stop disposes controllers")
 check(Manager.Start(),"Traffic restarts")
 check(Manager.Start(),"Repeated start remains safe")
 local previous=assert(Manager.GetPoliceService())
 local modules=Instance.new("Folder");modules.Name="__FreshTrafficManager";modules.Parent=game.ServerScriptService
 for _,v in game.ServerScriptService.Traffic:GetChildren() do if v:IsA("ModuleScript") then v:Clone().Parent=modules end end
 local fresh=require(modules.TrafficManager)
 check(fresh.Start(),"Fresh require context starts safely")
 waitFor(function() return previous.destroyed end,3)
 check(Manager.GetPoliceService()==nil,"Fresh manager lease stops the old Heartbeat/controller")
 fresh.Stop();modules:Destroy()
 check(Manager.Start(),"Normal manager resumes after fresh-context restart")
 report.freshContextRestart=true
 task.wait(6)
 local restarted=assert(Manager.GetPoliceService());local count=0
 for _ in restarted.units do count+=1 end
 check(count<=2,"Repeated start preserves police budget")
 check(retained.Parent==world.ActiveVehicles,"Authoring content is retained")
 check(workspace.Map==map and #map:GetDescendants()==descendants,"Restart leaves authored map intact")
 local owned=0;for _,v in world.ActiveVehicles:GetChildren() do if v:GetAttribute("NPCVehicle")==true then owned+=1 end end
 check(owned<=12,"Shared civilian/police fleet stays bounded")
 retained:Destroy();report.restart=true;report.activeUnits=count;report.activeVehicles=owned
end)
report.ok=ok;report.error=if ok then nil else tostring(errorMessage)
world:SetAttribute("PoliceEdgeReport",Http:JSONEncode(report))
print("[PoliceTest] "..Http:JSONEncode(report))
