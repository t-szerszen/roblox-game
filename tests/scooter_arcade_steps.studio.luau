-- Paste into the Server Command Bar in a fresh Studio Play session.
-- Temporary geometry and input automation live outside Workspace.Map; stop Play afterward.
assert(game.RunService:IsStudio() and game.RunService:IsRunning(), "Run in Studio Play")
assert(not workspace:FindFirstChild("_ScooterArcadeStepsQA"), "Use a fresh Play session")
local player = assert(game.Players:GetPlayers()[1])
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "_ScooterArcadeStepsQA", workspace
local floor = Instance.new("Part")
floor.Name, floor.Anchored, floor.Size = "Floor", true, Vector3.new(2000, 1, 2000)
floor.CFrame, floor.Parent = CFrame.new(6000, 999.5, 6000), folder
local curb = Instance.new("Part")
curb.Name, curb.Anchored, curb.Size = "Curb", true, Vector3.new(500, 1, 80)
curb.CFrame, curb.Parent = CFrame.new(6000, 1000, 6600), folder
local drive = Instance.new("LocalScript")
drive.Name = "_ArcadeStepsDriveQA"
drive.Source = [=[
local client = game.Players.LocalPlayer.PlayerScripts:WaitForChild("ScooterClient", 5)
if client then client:Destroy() end
local remote = game.ReplicatedStorage.Remotes.ScooterRemotes.DriveInput
local elapsed = 0
local connection = game.RunService.Heartbeat:Connect(function(dt)
 elapsed += dt
 if elapsed < .06 then return end
 elapsed = 0
 remote:FireServer(script:GetAttribute("Throttle") == true, script:GetAttribute("Brake") == true,
  script:GetAttribute("Steering") or 0, script:GetAttribute("Wheelie") == true)
end)
script.Destroying:Connect(function() connection:Disconnect() end)
]=]
drive.Parent = player.PlayerGui
local runner = Instance.new("Script")
runner.Name = "_ArcadeStepsNativeQA"
runner.Source = [==[
local player = game.Players:GetPlayers()[1]
local server = require(game.ServerScriptService.Scooter.ScooterServer)
local folder = workspace._ScooterArcadeStepsQA
local drive = player.PlayerGui._ArcadeStepsDriveQA
local results = {}
local ok, problem = xpcall(function()
 for _, case in {
  {name="rest_1", height=1, angle=0, gap=0},
  {name="rolling_1", height=1, angle=0, gap=120},
  {name="rest_2_5", height=2.5, angle=0, gap=0},
  {name="rolling_2_5", height=2.5, angle=0, gap=120},
  {name="oblique_1", height=1, angle=45, gap=0},
  {name="glancing_1", height=1, angle=89, gap=0},
  {name="reverse_1", height=1, angle=45, gap=0, reverse=true},
  {name="reverse_glancing_2_4", height=2.4, angle=89, gap=0, reverse=true},
  {name="coasting_1", height=1, angle=0, gap=120, coast=true},
  {name="rounded_1", height=1, angle=0, gap=0, rounded=true},
  {name="descending_1", height=1, angle=0, gap=0, descending=true},
  {name="descending_2_5", height=2.5, angle=0, gap=0, descending=true},
  {name="wall_3", height=3, angle=0, gap=0},
 } do
  drive:SetAttribute("Throttle",false); drive:SetAttribute("Brake",false)
  folder.Curb.CFrame = CFrame.new(6000,1000,6600)
  local model = server.SpawnForPlayer(player)
  model:PivotTo(CFrame.new(6000,1003,6000) * model.PrimaryPart.CFrame.Rotation)
  local h = player.Character:FindFirstChildOfClass("Humanoid")
  player.Character:PivotTo(model.DriverSeat.CFrame + Vector3.yAxis * 3)
  local deadline=os.clock()+4
  repeat model.DriverSeat:Sit(h); task.wait(.25) until model.DriverSeat.Occupant==h or os.clock()>deadline
  assert(model.DriverSeat.Occupant==h,"Mount failed")
  task.wait(1.5)
  local root=model.PrimaryPart
  local forward=Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z).Unit
  local travel=if case.reverse then -forward else forward
  local inward=CFrame.Angles(0,math.rad(case.angle),0):VectorToWorldSpace(travel)
  local lead=if case.reverse then model.BackWheelCollider else model.FrontWheelCollider
  local face=lead.Position+inward*(lead.Size.X*.5+.015)+travel*case.gap
  face=Vector3.new(face.X,1000,face.Z)
  folder.Curb.Size=Vector3.new(500,case.height,80)
  folder.Curb.Shape=Enum.PartType.Block
  local center=face+inward*(if case.descending then -40 else 40)+Vector3.yAxis*case.height*.5
  folder.Curb.CFrame=CFrame.lookAt(center,center-inward)
  if case.rounded then
   folder.Curb.Shape=Enum.PartType.Cylinder
   folder.Curb.Size=Vector3.new(500,case.height*2,6)
   folder.Curb.CFrame=CFrame.lookAt(face+inward*3,face+inward*3-inward)
  end
  if case.descending then
   model:PivotTo(model:GetPivot()+Vector3.yAxis*case.height)
   task.wait(1.5)
  end
  drive:SetAttribute(if case.reverse then "Brake" else "Throttle",true)
  local started=os.clock()
  local crossed,active=false,false
  local maxPitch,maxHeightError,maxCompression=0,0,0
  local jointRanges={}
  local springRanges={}
  local maxSuspensionTravel,maxSpringTravel=0,0
  local entrySpeed,minSpeed=0,math.huge
  local crossedAt=nil
  local coastReleased=false
  while os.clock()-started<12 do
   local arcade=model:GetAttribute("ArcadeStepActive")==true
   local speed=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
   if case.coast and arcade and not coastReleased then
    coastReleased=true; drive:SetAttribute("Throttle",false)
   end
   if arcade then
    if not active then entrySpeed=speed end
    active=true
    minSpeed=math.min(minSpeed,speed)
    maxPitch=math.max(maxPitch,math.abs(math.deg(math.asin(root.CFrame.LookVector.Y))))
    maxHeightError=math.max(maxHeightError,math.abs(root.AssemblyLinearVelocity.Y))
   end
   if active then
    maxPitch=math.max(maxPitch,math.abs(math.deg(math.asin(root.CFrame.LookVector.Y))))
    maxHeightError=math.max(maxHeightError,math.abs(root.AssemblyLinearVelocity.Y))
   end
   for _,joint in model:GetDescendants() do
    if joint:IsA("HingeConstraint") and joint.Name:find("PivotHinge_",1,true) then
     maxCompression=math.max(maxCompression,math.abs(joint.CurrentAngle-(joint:GetAttribute("SuspensionRestAngle") or 0)))
     local range=jointRanges[joint] or {joint.CurrentAngle,joint.CurrentAngle}
     jointRanges[joint]=range
     range[1],range[2]=math.min(range[1],joint.CurrentAngle),math.max(range[2],joint.CurrentAngle)
     maxSuspensionTravel=math.max(maxSuspensionTravel,range[2]-range[1])
    elseif joint:IsA("SpringConstraint") then
     local range=springRanges[joint] or {joint.CurrentLength,joint.CurrentLength}
     springRanges[joint]=range
     range[1],range[2]=math.min(range[1],joint.CurrentLength),math.max(range[2],joint.CurrentLength)
     maxSpringTravel=math.max(maxSpringTravel,range[2]-range[1])
    end
   end
   if (model.FrontWheelCollider.Position-face):Dot(inward)>1.2
    and (model.BackWheelCollider.Position-face):Dot(inward)>1.2 then
    crossed=true
    crossedAt=crossedAt or os.clock()
    if not arcade and os.clock()-crossedAt>1 then break end
   end
   if model:GetAttribute("Fallen") or not model.DriverSeat.Occupant then break end
   task.wait(.025)
  end
  drive:SetAttribute("Throttle",false); drive:SetAttribute("Brake",false)
  local masks=0
  for _,item in model:GetDescendants() do if item.Name=="ArcadeStepCollision" then masks+=1 end end
  local passed=if case.height>2.5 then not active and not crossed
   else crossed and active and model.DriverSeat.Occupant==h and not model:GetAttribute("Fallen")
    and maxPitch<2 and masks==0 and maxSuspensionTravel>2 and maxSpringTravel>.02
  table.insert(results,{name=case.name,passed=passed,crossed=crossed,active=active,
   mounted=model.DriverSeat.Occupant==h,fallen=model:GetAttribute("Fallen"),maxPitch=maxPitch,
   maxVerticalVelocity=maxHeightError,maxSuspensionAngle=maxCompression,entrySpeed=entrySpeed,
   suspensionTravelDegrees=maxSuspensionTravel,springTravel=maxSpringTravel,
   minimumCrossingSpeed=if minSpeed==math.huge then 0 else minSpeed,remainingCollisionMasks=masks})
  folder:SetAttribute("Results",game.HttpService:JSONEncode(results))
  folder:SetAttribute("CompletedCases",#results)
  task.wait(.25)
 end
end,debug.traceback)
drive:SetAttribute("Throttle",false); drive:SetAttribute("Brake",false)
local passed=ok
for _,result in results do passed=passed and result.passed end
folder:SetAttribute("Passed",passed)
folder:SetAttribute("Finished",true)
if not ok then folder:SetAttribute("Error",problem) end
]==]
runner.Parent = game.ServerScriptService
