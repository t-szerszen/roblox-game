-- Paste into the Server Command Bar in a fresh one-player Studio Play session.
-- CLIENT results: Workspace._ScooterHandlingResults. Stop Play after completion.
assert(game.RunService:IsStudio() and game.RunService:IsRunning())
local player = assert(game.Players:GetPlayers()[1])
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "_ScooterHandlingQA", workspace
local floor = Instance.new("Part")
floor.Name, floor.Anchored, floor.Size = "Floor", true, Vector3.new(2000, 1, 2000)
floor.CFrame, floor.Parent = CFrame.new(6000, 999.5, 6000), folder
local client = Instance.new("LocalScript")
client.Name, client.Enabled = "_ScooterHandlingClient", false
client.Source = [==[
local player = game.Players.LocalPlayer
local controls = player.PlayerScripts:FindFirstChild("ScooterClient")
if controls then controls:Destroy() end
local model = workspace.Scooters:GetChildren()[1]
local root = model.PrimaryPart
local results = Instance.new("Folder")
results.Name, results.Parent = "_ScooterHandlingResults", workspace
local remote = game.ReplicatedStorage.Remotes.ScooterRemotes.DriveInput
local steering, elapsed = 0, 0
local heartbeat = game.RunService.Heartbeat:Connect(function(dt)
 elapsed += dt
 if elapsed >= .06 then elapsed = 0; remote:FireServer(true, false, steering, false) end
end)
local samples, previous = {}, {}
local phase = "straight"
game.RunService:BindToRenderStep("ScooterHandlingQA",Enum.RenderPriority.Last.Value+1,function(dt)
 local b = samples[phase] or {frames=0, maxWheelShift=0, maxWheelSpinStep=0, visibleCopies=0, maxYaw=0}
 samples[phase] = b; b.frames += 1
 b.maxYaw = math.max(b.maxYaw, math.abs(root.AssemblyAngularVelocity.Y))
 local visuals = workspace:FindFirstChild("_ScooterRideVisuals")
 if visuals then
  local visible = 0
  for _, part in visuals:GetChildren() do
   if part:IsA("BasePart") and part.Transparency < 1 then
    visible += 1
    if part.Name:find("AnimatedWheel", 1, true) then
     local frame = root.CFrame:ToObjectSpace(part.CFrame)
     if previous[part] then
      b.maxWheelShift = math.max(b.maxWheelShift, (frame.Position-previous[part].Position).Magnitude)
      local _, angle = previous[part]:ToObjectSpace(frame):ToAxisAngle()
      b.maxWheelSpinStep = math.max(b.maxWheelSpinStep, math.abs(angle))
     end
     previous[part] = frame
    end
   end
  end
  b.visibleCopies = math.max(b.visibleCopies, visible)
 end
end)
task.wait(2)
for _, step in {{"left",1},{"reverse",-1},{"neutral",0}} do
 phase, steering = step[1], step[2]; task.wait(2)
end
heartbeat:Disconnect(); remote:FireServer(false,false,0,false)
task.wait(.5)
game.RunService:UnbindFromRenderStep("ScooterHandlingQA")
local passed = model:GetAttribute("RiderMounted")==true and model:GetAttribute("Fallen")~=true
 and math.abs(root.AssemblyAngularVelocity.Y)<.1
local phases = 0
for _, b in samples do
 phases += 1
 passed = passed and b.frames>=10 and b.visibleCopies==4 and b.maxWheelShift<.1
end
passed = passed and phases==4
results:SetAttribute("Results",game.HttpService:JSONEncode(samples))
results:SetAttribute("Passed",passed)
results:SetAttribute("NeutralYaw",root.AssemblyAngularVelocity.Y)
results:SetAttribute("Finished",true)
]==]
client.Parent = player.PlayerGui
local runner = Instance.new("Script")
runner.Name = "_ScooterHandlingNativeQA"
runner.Source = [==[
local player = game.Players:GetPlayers()[1]
local server = require(game.ServerScriptService.Scooter.ScooterServer)
local model = server.SpawnForPlayer(player)
model:PivotTo(CFrame.new(6000,1003,6000)*model.PrimaryPart.CFrame.Rotation)
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
player.Character:PivotTo(model.DriverSeat.CFrame+Vector3.yAxis*3)
local deadline = os.clock()+5
repeat model.DriverSeat:Sit(humanoid); task.wait(.2) until model.DriverSeat.Occupant==humanoid or os.clock()>deadline
assert(model.DriverSeat.Occupant==humanoid,"Mount failed")
task.wait(1)
player.PlayerGui._ScooterHandlingClient.Enabled=true
]==]
runner.Parent = game.ServerScriptService
