--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PepperSprayConfig"))
local Ragdoll = require(script.Parent:WaitForChild("PepperSpray"):WaitForChild("Ragdoll"))
local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PepperSpray")
local request = remotes:WaitForChild("Use") :: RemoteEvent
local effects = remotes:WaitForChild("Effects") :: RemoteEvent
local connections: {RBXScriptConnection} = {}
local playerConnections: {[Player]: RBXScriptConnection} = {}
local lastRequest: {[Player]: number} = {}
local nextUse: {[Player]: number} = {}
local immunity: {[Player]: number} = {}
local active = true

local function finite(vector: Vector3): boolean
 return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
  and math.abs(vector.X) < 1e6 and math.abs(vector.Y) < 1e6 and math.abs(vector.Z) < 1e6
end
local function equipped(character: Model): Tool?
 for _,item in character:GetChildren() do
  if item:IsA("Tool") and item.Name == Config.ToolName and item:GetAttribute(Config.ToolAttribute) == true then return item end
 end
 return nil
end
local function applyHit(target: Player, character: Model)
 local now = workspace:GetServerTimeNow()
 if now < (immunity[target] or 0) then return end
 if not Ragdoll.Start(character, Config.EffectDuration) then return end
 immunity[target] = now + Config.EffectDuration + Config.RecoveryImmunity
 effects:FireClient(target, "Hit", character, now + Config.EffectDuration)
end
local function spray(player: Player, character: Model, tool: Tool, origin: Vector3, direction: Vector3)
 for _,observer in Players:GetPlayers() do
  local root = observer.Character and observer.Character:FindFirstChild("HumanoidRootPart")
  if root and root:IsA("BasePart") and (root.Position - origin).Magnitude <= Config.VisualDistance then
   effects:FireClient(observer, "Spray", tool, origin, direction)
  end
 end
 local rayParams = RaycastParams.new()
 rayParams.FilterType = Enum.RaycastFilterType.Exclude
 rayParams.FilterDescendantsInstances = {character}
 local hit: {[Player]: boolean} = {}
 local packets: {{origin: Vector3, time: number}} = {}
 local nozzle = tool:FindFirstChild(Config.OriginName, true)
 local started = os.clock()
 local duration = Config.SprayDuration + Config.Range / Config.Speed
 while active and os.clock() - started <= duration do
  if player.Character ~= character or tool.Parent ~= character or character:GetAttribute("PepperSprayStunned") then break end
  local elapsed = os.clock() - started
  if elapsed <= Config.SprayDuration and nozzle and nozzle:IsA("Attachment") then
   local root = character:FindFirstChild("HumanoidRootPart")
   if not root or not root:IsA("BasePart") or (nozzle.WorldPosition - root.Position).Magnitude > Config.MaxOriginDistance then break end
   if not workspace:Raycast(root.Position, nozzle.WorldPosition - root.Position, rayParams) then
    table.insert(packets, {origin = nozzle.WorldPosition, time = elapsed})
   end
  end
  for _,target in Players:GetPlayers() do
   if target == player or hit[target] then continue end
   local targetCharacter = target.Character
   local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
   if not targetCharacter or not humanoid or humanoid.Health <= 0 then continue end
   -- Sample body points so the cone edge can hit either rig without client-supplied targets.
   for _,name in {"Head", "UpperTorso", "Torso", "HumanoidRootPart"} do
    local sample = targetCharacter:FindFirstChild(name)
    if not sample or not sample:IsA("BasePart") then continue end
    for _,packet in packets do
     local age = elapsed - packet.time
     if age > Config.Range / Config.Speed then continue end
     local delta = sample.Position - packet.origin
     local distance = delta.Magnitude
     local front = age * Config.Speed
     if distance < .05 or distance > Config.Range or distance > front + 1.5 or distance < math.max(0, front - 3)
      or direction:Dot(delta / distance) < math.cos(math.rad(Config.ConeHalfAngle)) then continue end
     local obstacle = workspace:Raycast(packet.origin, delta, rayParams)
     if not obstacle or obstacle.Instance:IsDescendantOf(targetCharacter) then
      applyHit(target, targetCharacter)
      hit[target] = true
      break
     end
    end
    if hit[target] then break end
   end
  end
  task.wait(Config.HitInterval)
 end
end

table.insert(connections, request.OnServerEvent:Connect(function(player: Player, direction: any, ...: any)
 local now = workspace:GetServerTimeNow()
 if now - (lastRequest[player] or -math.huge) < Config.RequestInterval then return end
 lastRequest[player] = now
 if select("#", ...) ~= 0 or typeof(direction) ~= "Vector3" or not finite(direction) then return end
 if direction.Magnitude < .95 or direction.Magnitude > 1.05 or now < (nextUse[player] or 0) then return end
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
  or humanoid.Sit or humanoid.PlatformStand or character:GetAttribute("PepperSprayStunned") then return end
 local tool = equipped(character)
 local origin = tool and tool:FindFirstChild(Config.OriginName, true)
 if not tool or not tool.Enabled or not origin or not origin:IsA("Attachment") or not origin.Parent or not origin.Parent:IsA("BasePart") then return end
 if (origin.WorldPosition - root.Position).Magnitude > Config.MaxOriginDistance then return end
 direction = direction.Unit
 if root.CFrame.LookVector:Dot(direction) < math.cos(math.rad(Config.MaxAimAngle)) then return end
 -- A nozzle embedded in a wall must not emit through it.
 local rayParams = RaycastParams.new()
 rayParams.FilterType = Enum.RaycastFilterType.Exclude
 rayParams.FilterDescendantsInstances = {character}
 if workspace:Raycast(root.Position, origin.WorldPosition - root.Position, rayParams) then return end
 nextUse[player] = now + Config.Cooldown
 player:SetAttribute("PepperSprayNextUse", nextUse[player])
 task.spawn(spray, player, character, tool, origin.WorldPosition, direction)
end))

local function bind(player: Player)
 playerConnections[player] = player.CharacterRemoving:Connect(function(character)
  Ragdoll.Stop(character)
  -- Respawning clears visuals but does not bypass cooldown or protection.
 end)
end
for _,player in Players:GetPlayers() do bind(player) end
table.insert(connections, Players.PlayerAdded:Connect(bind))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
 if player.Character then Ragdoll.Stop(player.Character) end
 local connection = playerConnections[player] if connection then connection:Disconnect() end
 playerConnections[player], lastRequest[player], nextUse[player], immunity[player] = nil, nil, nil, nil
end))
table.insert(connections, script.Destroying:Connect(function()
 active = false
 Ragdoll.StopAll()
 for _,connection in connections do connection:Disconnect() end
 for _,connection in playerConnections do connection:Disconnect() end
end))
