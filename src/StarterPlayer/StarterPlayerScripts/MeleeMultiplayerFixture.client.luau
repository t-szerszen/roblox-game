local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local folder=RS:WaitForChild("MeleeTest",30)
if not folder then return end
local p=Players.LocalPlayer
local remote=folder:WaitForChild("Command")
local observations={swings=0,seenSwings=0,blur=0,gas=false}
local function report() remote:FireServer(observations) end
RS:WaitForChild("CombatRemotes"):WaitForChild("MeleeEffects").OnClientEvent:Connect(function(event,character)
 if event=="Swing" then
  observations.seenSwings+=1
  if character==p.Character then observations.swings+=1 end
 end
 if event=="Knock" and character==p.Character then
  task.delay(.18,function()
   local blur=game.Lighting:FindFirstChild("MeleeKnockBlur")
   observations.blur=blur and blur.Size or 0 report()
  end)
 end
 report()
end)
remote.OnClientEvent:Connect(function(command)
 local c=p.Character
 if command=="Ready" then
  observations.gas=p.Backpack:FindFirstChild("gaz")~=nil or c:FindFirstChild("gaz")~=nil
  local fists=p.Backpack:FindFirstChild("Pięści") or c:FindFirstChild("Pięści")
  c.Humanoid:EquipTool(fists) report()
 elseif command=="Attack" then
  local fists=c:FindFirstChild("Pięści")
  if fists then fists:Activate() end
 end
end)
