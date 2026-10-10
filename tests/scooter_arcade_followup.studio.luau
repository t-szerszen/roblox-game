-- Native physics regression. Start Play, switch Command Bar to Server, paste this file.
-- Uses the installed template and validated DriveInput; stop Play afterward to restore input.
-- Fixtures stay outside Workspace.Map. Results are attributes on Workspace._ScooterRemodelQA.
local STEERING_ONLY = false -- Set true to run only steering and spark checks.
assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsRunning(),"Run only in Studio Play")
assert(not workspace:FindFirstChild("_ScooterRemodelQA"),"Use a fresh Play session")
local rider=game.Players:GetPlayers()[1]
assert(rider and rider.Character and rider.Character:FindFirstChildOfClass("Humanoid")
 and rider.Character:FindFirstChild("HumanoidRootPart"),"Wait for the rider to load before starting QA")
local folder=Instance.new("Folder");folder.Name="_ScooterRemodelQA";folder.Parent=workspace; local floor=Instance.new("Part");floor.Name="Floor";floor.Anchored=true;floor.Size=Vector3.new(2000,1,2000);floor.CFrame=CFrame.new(6000,999.5,6000);floor.Parent=folder;local curb=Instance.new("Part");curb.Name="Curb";curb.Anchored=true;curb.Size=Vector3.new(500,1,80);curb.CFrame=CFrame.new(6000,1000,6600);curb.Parent=folder;local d=Instance.new("LocalScript");d.Name="_ScooterRemodelDriveQA";d.Source="local client=game.Players.LocalPlayer.PlayerScripts:WaitForChild(\"ScooterClient\",5);if client then client:Destroy() end\nlocal remote=game.ReplicatedStorage.Remotes.ScooterRemotes.DriveInput;local elapsed=0;local c=game.RunService.Heartbeat:Connect(function(dt) elapsed+=dt;if elapsed>=.06 then elapsed=0;remote:FireServer(script:GetAttribute(\"Throttle\")==true,script:GetAttribute(\"Brake\")==true,script:GetAttribute('Steering') or 0,script:GetAttribute('Wheelie')==true) end end);script.Destroying:Connect(function() c:Disconnect() end)";d.Parent=game.Players:GetPlayers()[1].PlayerGui;
local runner=Instance.new("Script")
runner.Name="_ScooterArcadeNativeQA"
runner:SetAttribute("SteeringOnly", STEERING_ONLY)
runner.Source=[==[
if not script:GetAttribute("SteeringOnly") then
do local Http=game:GetService("HttpService")
local player=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
local folder=workspace._ScooterRemodelQA
local drive=player.PlayerGui._ScooterRemodelDriveQA
local results={}
local ok,problem=xpcall(function()
 for _,case in { {name="hump_forward_rest",height=1,angle=0,gap=0,reverse=false},{name="hump_reverse_rest",height=1,angle=0,gap=0,reverse=true} } do
  drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
  folder.Curb.CFrame=CFrame.new(6000,1000,6300)
  local model=server.SpawnForPlayer(player)
  local rotation=model.PrimaryPart.CFrame.Rotation
  model:PivotTo(CFrame.new(6000,1003,6000)*rotation)
  local humanoid=player.Character:FindFirstChildOfClass("Humanoid")
  player.Character:PivotTo(model.DriverSeat.CFrame+Vector3.yAxis*3)
  local mountDeadline=os.clock()+4
  repeat
   model.DriverSeat:Sit(humanoid)
   task.wait(0.25)
  until model.DriverSeat.Occupant==humanoid or os.clock()>mountDeadline
  task.wait(2)
  local travel=Vector3.new(model.PrimaryPart.CFrame.LookVector.X,0,model.PrimaryPart.CFrame.LookVector.Z).Unit
  if case.reverse then travel=-travel end
  local inward=CFrame.Angles(0,math.rad(case.angle),0):VectorToWorldSpace(travel)
  local lead=if case.reverse then model.BackWheelCollider else model.FrontWheelCollider
  local radius=lead.Size.X*0.5
  local face=lead.Position+inward*(radius+0.015)+travel*case.gap
  face=Vector3.new(face.X,1000,face.Z)
  local center=face+inward*40+Vector3.yAxis*case.height*0.5
  folder.Curb.Shape=Enum.PartType.Cylinder;folder.Curb.Size=Vector3.new(500,2,6)
  folder.Curb.CFrame=CFrame.lookAt(face+inward*3,face+inward*3-inward)
  drive:SetAttribute(if case.reverse then "Brake" else "Throttle",true)
  local start=os.clock()
  local minSpeed=math.huge
  local maxSpeed,maxLift,maxForce=0,0,0
  local crossed=false
  while os.clock()-start<9 do
   local front=model.FrontWheelCollider
   local back=model.BackWheelCollider
   local speed=model:GetAttribute("SpeedKmh") or 0
   maxSpeed=math.max(maxSpeed,speed)
   maxLift=math.max(maxLift,model.PrimaryPart.AssemblyLinearVelocity.Y)
   for _,force in model:GetDescendants() do
    if force:IsA("VectorForce") and force.Name=="WheelStepTraction" then maxForce=math.max(maxForce,force.Force.Magnitude) end
   end
   if (front.Position-face):Dot(inward)>7 and (back.Position-face):Dot(inward)>7 then crossed=true;break end
   if model:GetAttribute("Fallen") or not model.DriverSeat.Occupant then break end
   task.wait(0.05)
  end
  drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
  table.insert(results,{name=case.name,crossed=crossed,seconds=os.clock()-start,fallen=model:GetAttribute("Fallen"),
   mounted=model.DriverSeat.Occupant~=nil,maxSpeed=maxSpeed,maxVerticalSpeed=maxLift,maxAssistForce=maxForce,
   frontHeight=model.FrontWheelCollider.Position.Y,backHeight=model.BackWheelCollider.Position.Y,
   headingChangeDegrees=math.deg(math.acos(math.clamp(Vector3.new(model.PrimaryPart.CFrame.LookVector.X,0,model.PrimaryPart.CFrame.LookVector.Z).Unit:Dot(if case.reverse then -travel else travel),-1,1)))})
  folder:SetAttribute("Results",Http:JSONEncode(results))
  folder:SetAttribute("CompletedCases",#results)
  task.wait(0.4)
 end
end,debug.traceback)
folder:SetAttribute("Finished",true)
if not ok then folder:SetAttribute("Error",problem) end
drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
 end
workspace._ScooterRemodelQA:SetAttribute("HumpResults",workspace._ScooterRemodelQA:GetAttribute("Results"))
do local Http=game:GetService("HttpService")
local player=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
local folder=workspace._ScooterRemodelQA
local drive=player.PlayerGui._ScooterRemodelDriveQA
local results={}
local ok,problem=xpcall(function()
 for _,case in {
  {name="forward_1_degree_rest_1",height=1,angle=89,gap=0,reverse=false},
  {name="reverse_1_degree_rest_1",height=1,angle=89,gap=0,reverse=true},
  {name="forward_1_degree_other_side_1",height=1,angle=-89,gap=0,reverse=false},
  {name="forward_1_degree_rolling_1",height=1,angle=89,gap=12,reverse=false},
  {name="forward_1_degree_rest_2_5",height=2.5,angle=89,gap=0,reverse=false},
  {name="reverse_1_degree_rest_2_4",height=2.4,angle=89,gap=0,reverse=true},
  {name="forward_rest_1",height=1,angle=0,gap=0,reverse=false},
  {name="forward_rolling_1",height=1,angle=0,gap=18,reverse=false},
  {name="forward_full_speed_1",height=1,angle=0,gap=140,reverse=false},
  {name="forward_45_rest_1",height=1,angle=45,gap=0,reverse=false},
  {name="reverse_45_rest_1",height=1,angle=45,gap=0,reverse=true},
  {name="forward_45_rest_2_5",height=2.5,angle=45,gap=0,reverse=false},
  {name="reverse_45_rest_2_4",height=2.4,angle=45,gap=0,reverse=true},
  {name="wall_3",height=3,angle=0,gap=0,reverse=false}
 } do
  drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
  folder.Curb.CFrame=CFrame.new(6000,1000,6300)
  local model=server.SpawnForPlayer(player)
  local rotation=model.PrimaryPart.CFrame.Rotation
  model:PivotTo(CFrame.new(6000,1003,6000)*rotation)
  local humanoid=player.Character:FindFirstChildOfClass("Humanoid")
  player.Character:PivotTo(model.DriverSeat.CFrame+Vector3.yAxis*3)
  local mountDeadline=os.clock()+4
  repeat
   model.DriverSeat:Sit(humanoid)
   task.wait(0.25)
  until model.DriverSeat.Occupant==humanoid or os.clock()>mountDeadline
  task.wait(2)
  local travel=Vector3.new(model.PrimaryPart.CFrame.LookVector.X,0,model.PrimaryPart.CFrame.LookVector.Z).Unit
  if case.reverse then travel=-travel end
  local inward=CFrame.Angles(0,math.rad(case.angle),0):VectorToWorldSpace(travel)
  local lead=if case.reverse then model.BackWheelCollider else model.FrontWheelCollider
  local radius=lead.Size.X*0.5
  local face=lead.Position+inward*(radius+0.015)+travel*case.gap
  face=Vector3.new(face.X,1000,face.Z)
  local center=face+inward*40+Vector3.yAxis*case.height*0.5
  folder.Curb.Shape=Enum.PartType.Block;folder.Curb.Size=Vector3.new(500,case.height,80)
  folder.Curb.CFrame=CFrame.lookAt(center,center-inward)
  drive:SetAttribute(if case.reverse then "Brake" else "Throttle",true)
  local start=os.clock()
  local minSpeed=math.huge
  local maxSpeed,maxLift,maxForce=0,0,0
  local crossed=false
  while os.clock()-start<9 do
   local front=model.FrontWheelCollider
   local back=model.BackWheelCollider
   local speed=model:GetAttribute("SpeedKmh") or 0
   maxSpeed=math.max(maxSpeed,speed)
   maxLift=math.max(maxLift,model.PrimaryPart.AssemblyLinearVelocity.Y)
   for _,force in model:GetDescendants() do
    if force:IsA("VectorForce") and force.Name=="WheelStepTraction" then maxForce=math.max(maxForce,force.Force.Magnitude) end
   end
   if (front.Position-face):Dot(inward)>front.Size.X*0.5 and (back.Position-face):Dot(inward)>back.Size.X*0.5
    and front.Position.Y>1000+case.height+0.65 and back.Position.Y>1000+case.height+0.8 then crossed=true;break end
   if model:GetAttribute("Fallen") or not model.DriverSeat.Occupant then break end
   task.wait(0.05)
  end
  drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
  table.insert(results,{name=case.name,crossed=crossed,seconds=os.clock()-start,fallen=model:GetAttribute("Fallen"),
   mounted=model.DriverSeat.Occupant~=nil,maxSpeed=maxSpeed,maxVerticalSpeed=maxLift,maxAssistForce=maxForce,
   frontHeight=model.FrontWheelCollider.Position.Y,backHeight=model.BackWheelCollider.Position.Y,
   headingChangeDegrees=math.deg(math.acos(math.clamp(Vector3.new(model.PrimaryPart.CFrame.LookVector.X,0,model.PrimaryPart.CFrame.LookVector.Z).Unit:Dot(if case.reverse then -travel else travel),-1,1)))})
  folder:SetAttribute("Results",Http:JSONEncode(results))
  folder:SetAttribute("CompletedCases",#results)
  task.wait(0.4)
 end
end,debug.traceback)
folder:SetAttribute("Finished",true)
if not ok then folder:SetAttribute("Error",problem) end
drive:SetAttribute("Throttle",false);drive:SetAttribute("Brake",false)
 end
workspace._ScooterRemodelQA:SetAttribute("CurbResults",workspace._ScooterRemodelQA:GetAttribute("Results"))
do
local p=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
local f=workspace._ScooterRemodelQA
local d=p.PlayerGui._ScooterRemodelDriveQA
local H=game.HttpService
local results={}
local function spawn(height, setup)
 d:SetAttribute('Throttle',false);d:SetAttribute('Brake',false);d:SetAttribute('Steering',0);d:SetAttribute('Wheelie',false)
 f.Curb.CFrame=CFrame.new(6000,1000,6600)
 local m=server.SpawnForPlayer(p)
 m:PivotTo(CFrame.new(6000,1003+(height or 0),6000)*m.PrimaryPart.CFrame.Rotation)
 if setup then setup(m) end
 local h=p.Character:FindFirstChildOfClass('Humanoid')
 p.Character:PivotTo(m.DriverSeat.CFrame+Vector3.yAxis*3)
 for _=1,16 do m.DriverSeat:Sit(h);task.wait(.25);if m.DriverSeat.Occupant==h then break end end
 return m
end
local ok,err=xpcall(function()
 for _,c in {{name='front_lower_1',height=1,frontLow=true},{name='rear_lower_1',height=1,frontLow=false},{name='front_lower_2_5',height=2.5,frontLow=true},{name='rear_lower_2_5',height=2.5,frontLow=false}} do
  local m=spawn(c.height,function(model)
   local fw,bw=model.FrontWheelCollider,model.BackWheelCollider
   local front=Vector3.new(model.PrimaryPart.CFrame.LookVector.X,0,model.PrimaryPart.CFrame.LookVector.Z).Unit
   local inward=if c.frontLow then -front else front
   local face=(fw.Position+bw.Position)*.5;face=Vector3.new(face.X,1000,face.Z)
   local center=face+inward*40+Vector3.yAxis*c.height*.5
   f.Curb.Shape=Enum.PartType.Block;f.Curb.Size=Vector3.new(500,c.height,80);f.Curb.CFrame=CFrame.lookAt(center,center-inward)
  end)
  local fw,bw=m.FrontWheelCollider,m.BackWheelCollider
  task.wait(4)
  local frontGap=fw.Position.Y-fw.Size.Y*.5-(1000+(if c.frontLow then 0 else c.height))
  local rearGap=bw.Position.Y-bw.Size.Y*.5-(1000+(if c.frontLow then c.height else 0))
  table.insert(results,{name=c.name,frontGap=frontGap,rearGap=rearGap,pitch=math.deg(math.asin(m.PrimaryPart.CFrame.LookVector.Y)),frontGrounded=m:GetAttribute('FrontGrounded'),rearGrounded=m:GetAttribute('RearGrounded'),mounted=m.DriverSeat.Occupant~=nil,fallen=m:GetAttribute('Fallen'),vertical=m.PrimaryPart.AssemblyLinearVelocity.Y})
  f:SetAttribute('SurfaceResults',H:JSONEncode(results))
 end
 for _,c in {{name='rolling_1',height=1},{name='rolling_2_5',height=2.5}} do
  local m=spawn();task.wait(2)
  d:SetAttribute('Throttle',true);task.wait(5)
  local fw,bw=m.FrontWheelCollider,m.BackWheelCollider
  local travel=Vector3.new(m.PrimaryPart.CFrame.LookVector.X,0,m.PrimaryPart.CFrame.LookVector.Z).Unit
  local face=fw.Position+travel*120;face=Vector3.new(face.X,1000,face.Z)
  local center=face+travel*40+Vector3.yAxis*c.height*.5
  f.Curb.Shape=Enum.PartType.Block;f.Curb.Size=Vector3.new(500,c.height,80);f.Curb.CFrame=CFrame.lookAt(center,center-travel)
  local springs={};for _,v in m:GetDescendants() do if v:IsA("SpringConstraint") then table.insert(springs,{part=v,min=v.CurrentLength,max=v.CurrentLength}) end end
  local t=os.clock();local entry=nil;local lowest=math.huge;local maxVertical=0;local crossed=false
  while os.clock()-t<8 do
   for _,spring in springs do spring.min=math.min(spring.min,spring.part.CurrentLength);spring.max=math.max(spring.max,spring.part.CurrentLength) end
   local distance=(fw.Position-face):Dot(travel)
   if distance>=-fw.Size.Y*.5-5 then
    local speed=m.PrimaryPart.AssemblyLinearVelocity:Dot(travel)
    entry=entry or speed;lowest=math.min(lowest,speed);maxVertical=math.max(maxVertical,m.PrimaryPart.AssemblyLinearVelocity.Y)
   end
   if (bw.Position-face):Dot(travel)>bw.Size.Y*.5+5 then crossed=true;break end
   task.wait(.02)
  end
  task.wait(.4)
  local shockTravel=0;for _,spring in springs do shockTravel=math.max(shockTravel,spring.max-spring.min) end
  table.insert(results,{shockTravel=shockTravel,settledVertical=m.PrimaryPart.AssemblyLinearVelocity.Y,name=c.name,entry=entry,minimumSpeed=lowest,retention=entry and lowest/entry,crossed=crossed,maxVertical=maxVertical,mounted=m.DriverSeat.Occupant~=nil,fallen=m:GetAttribute('Fallen')})
  f:SetAttribute('SurfaceResults',H:JSONEncode(results))
 end
end,debug.traceback)
d:SetAttribute('Throttle',false)
f:SetAttribute('SurfaceFinished',true);if not ok then f:SetAttribute('SurfaceError',err) end

end
end
do local H=game:GetService("HttpService")
local p=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
local physics=require(game.ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local config=require(game.ReplicatedStorage.Shared.ScooterConfig)
local f=workspace._ScooterRemodelQA
local d=p.PlayerGui._ScooterRemodelDriveQA
local originalBoost=config.LowSpeedTurnBoost
local originalLead=config.HeldSteering.MaxHeadingLeadAngle
local result={}
local ok,err=xpcall(function()
 for _,case in {
  {name="previous_full",boost=1.08,lead=math.rad(12),steer=1},
  {name="held_full",boost=originalBoost,steer=1},
  {name="fast_right",boost=originalBoost,steer=.2},
  {name="fast_left",boost=originalBoost,steer=-.2},
  {name="fast_tap_right",boost=originalBoost,steer=1,tap=.12},
  {name="fast_tap_left",boost=originalBoost,steer=-1,tap=.12},
 } do
  config.LowSpeedTurnBoost=case.boost
  config.HeldSteering.MaxHeadingLeadAngle=case.lead or originalLead
  d:SetAttribute("Throttle",false);d:SetAttribute("Brake",false);d:SetAttribute("Steering",0)
  f.Curb.CFrame=CFrame.new(6000,1000,6600)
  local m=server.SpawnForPlayer(p);m:PivotTo(CFrame.new(6000,1003,6000)*m.PrimaryPart.CFrame.Rotation)
  local h=p.Character:FindFirstChildOfClass("Humanoid");p.Character:PivotTo(m.DriverSeat.CFrame+Vector3.yAxis*3)
  for _=1,16 do m.DriverSeat:Sit(h);task.wait(.25);if m.DriverSeat.Occupant==h then break end end
  task.wait(2)
  d:SetAttribute("Throttle",true);task.wait(if string.find(case.name,"fast_") then 5 else 3)
  local approach=m:GetAttribute("SpeedKmh")
  d:SetAttribute("Steering",case.steer)
  local t=os.clock();local dt=0;local path,yaw,minTireBottom,maxTireBottom,maxVertical,maxAngle=0,0,math.huge,-math.huge,0,0
  while os.clock()-t<(if case.tap then 1.5 else 3) do
   if case.tap and os.clock()-t>=case.tap then d:SetAttribute("Steering",0) end
   local before=os.clock();task.wait(.05);dt=os.clock()-before
   local speed=Vector3.new(m.PrimaryPart.AssemblyLinearVelocity.X,0,m.PrimaryPart.AssemblyLinearVelocity.Z).Magnitude
   path+=speed*dt;yaw+=math.abs(m.PrimaryPart.AssemblyAngularVelocity.Y)*dt
   maxAngle=math.max(maxAngle,math.deg(math.abs(m:GetAttribute("SteeringAngle") or 0)))
   for _,wheel in {m.FrontWheelCollider,m.BackWheelCollider} do
    minTireBottom=math.min(minTireBottom,wheel.Position.Y-wheel.Size.Y*.5-1000)
    maxTireBottom=math.max(maxTireBottom,wheel.Position.Y-wheel.Size.Y*.5-1000)
   end
   maxVertical=math.max(maxVertical,math.abs(m.PrimaryPart.AssemblyLinearVelocity.Y))
  end
  d:SetAttribute("Steering",0);task.wait(1.5)
  table.insert(result,{name=case.name,releaseYaw=math.abs(m.PrimaryPart.AssemblyAngularVelocity.Y),approachKmh=approach,path=path,yawDegrees=math.deg(yaw),turnRadius=path/math.max(.001,yaw),
   minimumTireBottom=minTireBottom,maximumTireBottom=maxTireBottom,maximumVerticalSpeed=maxVertical,steerAngle=maxAngle,
   fallen=m:GetAttribute("Fallen"),mounted=m.DriverSeat.Occupant~=nil})
  f:SetAttribute("SteeringResults",H:JSONEncode(result))
 end
end,debug.traceback)
config.LowSpeedTurnBoost=originalBoost;config.HeldSteering.MaxHeadingLeadAngle=originalLead
d:SetAttribute("Throttle",false);d:SetAttribute("Steering",0)
f:SetAttribute("SteeringFinished",true);if not ok then f:SetAttribute("Error",err) end end
do local H=game:GetService("HttpService")
local p=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
local f=workspace._ScooterRemodelQA
local d=p.PlayerGui._ScooterRemodelDriveQA
local ok,err=xpcall(function()
 d:SetAttribute("Throttle",false);d:SetAttribute("Brake",false);d:SetAttribute("Steering",0);d:SetAttribute("Wheelie",false)
 f.Curb.CFrame=CFrame.new(6000,1000,6600)
 local m=server.SpawnForPlayer(p);m:PivotTo(CFrame.new(6000,1003,6000)*m.PrimaryPart.CFrame.Rotation)
 local h=p.Character:FindFirstChildOfClass("Humanoid");p.Character:PivotTo(m.DriverSeat.CFrame+Vector3.yAxis*3)
 for _=1,16 do m.DriverSeat:Sit(h);task.wait(.25);if m.DriverSeat.Occupant==h then break end end
 task.wait(2);d:SetAttribute("Throttle",true);task.wait(1.6);d:SetAttribute("Wheelie",true)
 local t=os.clock();local sparks=false;local maxPitch,firstSparkPitch,lowestSparkPitch,duration=0,nil,math.huge,0
 local sparkPoint=m:FindFirstChild("WheelieScrapePoint",true)
 while os.clock()-t<3 do
  local pitch=math.deg(math.asin(math.clamp(m.PrimaryPart.CFrame.LookVector.Y,-1,1)))
  maxPitch=math.max(maxPitch,pitch)
  if m:GetAttribute("WheelieSparksActive") then
   sparks=true;firstSparkPitch=firstSparkPitch or pitch;lowestSparkPitch=math.min(lowestSparkPitch,pitch);duration+=.02
  end
  if m:GetAttribute("Fallen") then break end
  task.wait(.02)
 end
 d:SetAttribute("Throttle",false);d:SetAttribute("Wheelie",false);task.wait(.1)
 local particles=m:FindFirstChild("WheelieSparks",true)
 local result={particleSize=particles.Size.Keypoints[1].Value,rate=particles.Rate,lifetime=particles.Lifetime.Max,enabled=sparks,firstSparkPitch=firstSparkPitch,lowestSparkPitch=lowestSparkPitch,maximumPitch=maxPitch,
  approximateSparkSeconds=duration,fallen=m:GetAttribute("Fallen"),stopped=m:GetAttribute("WheelieSparksActive")~=true,
  emitter=m:FindFirstChild("WheelieSparks",true) and m:FindFirstChild("WheelieSparks",true).Enabled}
 task.wait(2.2);server.SpawnForPlayer(p)
 result.cleaned=sparkPoint.Parent==nil
 f:SetAttribute("SparkResults",H:JSONEncode(result))
end,debug.traceback)
f:SetAttribute("SparkFinished",true);if not ok then f:SetAttribute("Error",err) end end
local f=workspace._ScooterRemodelQA
local Http=game.HttpService
local ok,problem=xpcall(function()
 assert(not f:GetAttribute("Error"),f:GetAttribute("Error"))
 if not script:GetAttribute("SteeringOnly") then
 for _,c in Http:JSONDecode(f:GetAttribute("HumpResults")) do assert(c.crossed and c.mounted and not c.fallen,c.name) end
 for _,c in Http:JSONDecode(f:GetAttribute("CurbResults")) do
  assert(c.mounted and not c.fallen,c.name)
  if c.name=="wall_3" then assert(not c.crossed and c.maxAssistForce==0,"Tall wall bypass")
  else assert(c.crossed,c.name);if string.find(c.name,"_1$") then assert(c.maxVerticalSpeed<=3.51,"Small-curb rebound") end end
 end
 assert(not f:GetAttribute("SurfaceError"),f:GetAttribute("SurfaceError"))
 for _,surface in Http:JSONDecode(f:GetAttribute("SurfaceResults")) do
  assert(surface.mounted and not surface.fallen,surface.name)
  if string.find(surface.name,"lower") then
   assert(surface.frontGrounded and surface.rearGrounded and math.abs(surface.frontGap)<.12
    and math.abs(surface.rearGap)<.12,"Suspended wheel did not meet the lower surface")
  else
   assert(surface.crossed and surface.retention>=.99,"Obstacle removed incoming speed")
   assert(surface.shockTravel>.01 and surface.settledVertical<=.1 and surface.settledVertical>=-2,"Suspension stopped moving or rebounded after climbing")
  end
 end
 end
 local turns=Http:JSONDecode(f:GetAttribute("SteeringResults"))
 assert(turns[2].turnRadius<turns[1].turnRadius*.8 and turns[2].turnRadius>turns[1].turnRadius*.45,"Held turn should improve radius without extreme sensitivity")
 for _,turn in turns do
  assert(turn.mounted and not turn.fallen,turn.name)
  assert(turn.minimumTireBottom>-.1 and turn.maximumVerticalSpeed<5,"Turn left the road or destabilized suspension")
 end
 for i=3,4 do
  assert(turns[i].approachKmh>=45 and turns[i].yawDegrees<90,"High-speed partial steering too sensitive")
  assert(turns[i].releaseYaw<.2,"Released steering did not settle")
 end
 for i=5,6 do
  assert(turns[i].approachKmh>=45 and turns[i].yawDegrees<15,"Short steering tap over-rotated the scooter")
  assert(turns[i].releaseYaw<.2,"Tap release did not settle")
 end
 local sparks=Http:JSONDecode(f:GetAttribute("SparkResults"))
 assert(sparks.enabled and sparks.stopped and sparks.cleaned,"Wheelie spark lifecycle")
 assert(sparks.particleSize>=.36 and sparks.rate>=85 and sparks.lifetime>=.4,"Larger visible spark trail")
end,debug.traceback)
f:SetAttribute("Passed",ok)
f:SetAttribute("AllFinished",true)
if not ok then f:SetAttribute("Error",problem);warn(problem) else print("Scooter arcade native QA passed. Stop Play to restore normal input.") end
]==]
runner.Parent=game.ServerScriptService
return "Native scooter QA started; wait for AllFinished/Passed attributes, then stop Play."
