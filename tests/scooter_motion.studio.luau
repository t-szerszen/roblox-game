-- Paste into the Server Command Bar in a fresh one-player Studio Play session.
-- Inspect Workspace._ScooterCurbPerfResults on the CLIENT. Stop Play afterward.
-- Keep the Client viewport foreground: background throttling invalidates motion sampling.
assert(game.RunService:IsStudio() and game.RunService:IsRunning())
local p=assert(game.Players:GetPlayers()[1])
local f=Instance.new("Folder") f.Name="_ScooterPerformanceQA" f.Parent=workspace
local floor=Instance.new("Part") floor.Name="Floor" floor.Anchored=true floor.Size=Vector3.new(2000,1,2000) floor.CFrame=CFrame.new(6000,999.5,6000) floor.Parent=f
local c=Instance.new("LocalScript") c.Name="_ScooterCurbPerfClient" c.Enabled=false
c.Source=[==[
local p=game.Players.LocalPlayer local m=workspace.Scooters:GetChildren()[1] local root=m.PrimaryPart
local controls=p.PlayerScripts:FindFirstChild("ScooterClient") if controls then controls:Destroy() end
local remote=game.ReplicatedStorage.Remotes.ScooterRemotes.DriveInput
local f=Instance.new("Folder") f.Name="_ScooterCurbPerfResults" f.Parent=workspace
local elapsed=0 local bins={} local last=os.clock() local prev=root.Position
local con=game.RunService.PreRender:Connect(function()
 local now=os.clock() local dt=now-last last=now
 local delta=(root.Position-prev).Magnitude prev=root.Position
 local speed=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
 if speed>40 then
  local label=if m:GetAttribute("ArcadeStepActive")==true then "active" else "native"
  local b=bins[label] or {n=0,stale=0,time=0,maxDelta=0,totalDelta=0,maxStepRatio=0} bins[label]=b
  b.maxStepRatio=math.max(b.maxStepRatio,delta/(speed*math.max(dt,.001)))
  b.n+=1 b.time+=dt b.totalDelta+=delta b.maxDelta=math.max(b.maxDelta,delta)
  if delta<.0001 then b.stale+=1 end
 end
end)
local heartbeat=game.RunService.Heartbeat:Connect(function(dt)elapsed+=dt if elapsed>.06 then elapsed=0 remote:FireServer(true,false,0,false)end end)
task.wait(9)
heartbeat:Disconnect() con:Disconnect() remote:FireServer(false,false,0,false)
f:SetAttribute("Results",game.HttpService:JSONEncode(bins))
local active=bins.active
f:SetAttribute("Passed",active~=nil and active.n>=10 and active.stale/active.n<.1 and active.maxStepRatio<2.5)
f:SetAttribute("Finished",true)
]==] c.Parent=p.PlayerGui
local s=Instance.new("Script") s.Name="_ScooterCurbPerf"
s.Source=[====[local p=game.Players:GetPlayers()[1]
local server=require(game.ServerScriptService.Scooter.ScooterServer)
workspace._ScooterPerformanceQA.Floor.Size=Vector3.new(2000,1,2000)
local m=server.SpawnForPlayer(p) m:PivotTo(CFrame.new(6000,1003,6000)*m.PrimaryPart.CFrame.Rotation)
local h=p.Character:FindFirstChildOfClass("Humanoid")
p.Character:PivotTo(m.DriverSeat.CFrame+Vector3.yAxis*3)
local deadline=os.clock()+5 repeat m.DriverSeat:Sit(h) task.wait(.2) until m.DriverSeat.Occupant==h or os.clock()>deadline
assert(m.DriverSeat.Occupant==h,"mount") task.wait(1)
local forward=Vector3.new(m.PrimaryPart.CFrame.LookVector.X,0,m.PrimaryPart.CFrame.LookVector.Z).Unit
local center=m.FrontWheelCollider.Position+forward*420
center=Vector3.new(center.X,1000.5,center.Z)
local curb=Instance.new("Part") curb.Name="PerfCurb" curb.Size=Vector3.new(500,1,600) curb.Anchored=true curb.CFrame=CFrame.lookAt(center,center-forward) curb.Parent=workspace._ScooterPerformanceQA

p.PlayerGui._ScooterCurbPerfClient.Enabled=true
]====] s.Parent=game.ServerScriptService
return "curb performance fixture running"
