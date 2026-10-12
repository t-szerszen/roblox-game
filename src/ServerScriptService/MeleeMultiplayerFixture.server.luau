-- Temporary Studio fixture, installed only for the explicitly requested multiplayer verification.
local StudioTestService=game:GetService("StudioTestService")
local ok,args=pcall(function() return StudioTestService:GetTestArgs() end)
if not ok or args~="MeleePolish" then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local folder=Instance.new("Folder") folder.Name="MeleeTest" folder.Parent=RS
local remote=Instance.new("RemoteEvent") remote.Name="Command" remote.Parent=folder
local observations={}
local connection=remote.OnServerEvent:Connect(function(player,data)
 if type(data)=="table" then observations[player.UserId]=data end
end)
local function finish(result)
 connection:Disconnect()
 StudioTestService:EndTest(result)
end
task.delay(55,function() finish({ok=false,error="Multiplayer fixture timeout"}) end)
local success,result=pcall(function()
 local deadline=os.clock()+25
 repeat task.wait(.1) until #Players:GetPlayers()>=2 or os.clock()>deadline
 assert(#Players:GetPlayers()==2,"Expected two clients")
 local people=Players:GetPlayers()
 table.sort(people,function(a,b) return a.UserId<b.UserId end)
 local attacker,target=people[1],people[2]
 repeat task.wait(.1) until attacker.Character and target.Character and attacker.Character:FindFirstChild("HumanoidRootPart") and target.Character:FindFirstChild("HumanoidRootPart")
 local platform=Instance.new("Part") platform.Anchored=true platform.Size=Vector3.new(40,2,40)
 platform.Position=Vector3.new(300,1000,437) platform.Parent=workspace
 local a,t=attacker.Character,target.Character
 local h=t.Humanoid
 local origin=platform.Position+Vector3.new(0,5,0)
 local function position()
  a:PivotTo(CFrame.lookAt(origin,origin+Vector3.new(0,0,-3)))
  t:PivotTo(CFrame.lookAt(origin+Vector3.new(0,0,-3),origin))
  a.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
  t.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
 end
 position()
 attacker:SetAttribute("InvulnerableUntil",0) target:SetAttribute("InvulnerableUntil",0)
 attacker:SetAttribute("PassiveMode",false) target:SetAttribute("PassiveMode",false)
 task.wait(4)
 remote:FireClient(attacker,"Ready") remote:FireClient(target,"Observe")
 task.wait(.5)
 local ready=observations[attacker.UserId]
 assert(ready and ready.gas,"Gas Tool must remain in inventory")
 local function attack()
  remote:FireClient(attacker,"Attack")
  task.wait(.85)
 end
 for _=1,3 do attack() end
 remote:FireClient(attacker,"Attack") task.wait(.6)
 local down=t:GetAttribute("MeleeDownUntil")
 assert(type(down)=="number" and down>workspace:GetServerTimeNow(),"Fourth valid hit should knock target")
 assert(h.PlatformStand and h.Health==100,"Knock must not kill")
 task.wait(1.9)
 assert(not h.PlatformStand and h.WalkSpeed>0,"Target must recover")
 local targetReport=observations[target.UserId]
 assert(targetReport and targetReport.blur and targetReport.blur>0,"Only victim receives visible knock blur")
 position() task.wait(.2)
 for _=1,4 do attack() end
 assert(h.Health==0,"Eighth hit must kill")
 local attackerReport=observations[attacker.UserId]
 assert(attackerReport and attackerReport.swings>=8,"Eight server-approved swings")
 assert(attackerReport.gas,"Gas preserved")
 platform:Destroy()
 return {ok=true,attacker=attackerReport,target=observations[target.UserId],fourHitFall=true,recovered=true,eightHitDeath=true,clients=2}
end)
finish(if success then result else {ok=false,error=tostring(result),observations=observations})
