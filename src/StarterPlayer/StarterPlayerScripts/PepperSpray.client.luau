--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PepperSprayConfig"))
local Particles = require(ReplicatedStorage.Shared:WaitForChild("PepperSprayParticles"))
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PepperSpray")
local request = remotes:WaitForChild("Use") :: RemoteEvent
local effects = remotes:WaitForChild("Effects") :: RemoteEvent
local connections: {RBXScriptConnection} = {}
local characterConnections: {RBXScriptConnection} = {}
local toolConnections: {RBXScriptConnection} = {}
local visuals: {[BasePart]: () -> ()} = {}
local equippedTool: Tool? = nil
local currentCharacter: Model? = nil
local gripTween: Tween? = nil
local gripTool: Tool? = nil
local savedGrip: CFrame? = nil
local active = true
local hitGeneration = 0
local blur: BlurEffect? = nil
local tint: ColorCorrectionEffect? = nil
local localNextRequest = 0
local actionName = "PepperSprayUse"
local hudGeneration = 0

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "PepperSprayUI", false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Name = "UseHint"
label.AnchorPoint = Vector2.new(.5, 1)
label.Position, label.Size = UDim2.new(.5, 0, 1, -90), UDim2.fromOffset(310, 38)
label.BackgroundColor3 = Color3.fromRGB(25, 29, 34)
label.BackgroundTransparency = .15
label.TextColor3 = Color3.fromRGB(245, 220, 166)
label.Font, label.TextSize = Enum.Font.GothamMedium, 14
label.Visible = false
label.Parent = gui
local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 10) corner.Parent = label

local function refreshHUD()
 hudGeneration += 1
 local generation = hudGeneration
 task.spawn(function()
  while active and equippedTool and generation == hudGeneration do
   local nextTime = player:GetAttribute("PepperSprayNextUse")
   local remaining = typeof(nextTime) == "number" and math.max(0, nextTime - workspace:GetServerTimeNow()) or 0
   label.Text = remaining > 0 and string.format("GAZ • odnowienie %.1f s", remaining) or "GAZ • kliknij / F / przycisk użycia"
   if remaining <= 0 then break end
   task.wait(.1)
  end
 end)
end

local function disconnect(list: {RBXScriptConnection})
 for _,connection in list do connection:Disconnect() end
 table.clear(list)
end
local function clearHit()
 hitGeneration += 1
 if blur then blur:Destroy() blur = nil end
 if tint then tint:Destroy() tint = nil end
end
local function clearGesture()
 if gripTween then gripTween:Cancel() gripTween = nil end
 if gripTool and gripTool.Parent and savedGrip then gripTool.Grip = savedGrip end
 gripTool, savedGrip = nil, nil
end
local function sprayGesture(tool: Tool)
 if tool ~= equippedTool then return end
 clearGesture()
 gripTool, savedGrip = tool, tool.Grip
 local original = tool.Grip
 gripTween = TweenService:Create(tool, TweenInfo.new(.09), {Grip = original * CFrame.Angles(math.rad(-8), 0, 0)})
 gripTween:Play()
 task.delay(.18, function()
  if gripTool ~= tool or not tool.Parent then return end
  gripTween = TweenService:Create(tool, TweenInfo.new(.16), {Grip = original})
  gripTween:Play()
  task.delay(.17, function() if gripTool == tool then clearGesture() end end)
 end)
end
local function use()
 local tool, character = equippedTool, player.Character
 if not tool or tool.Parent ~= character or not character or character:GetAttribute("PepperSprayStunned") then return end
 local now = workspace:GetServerTimeNow()
 local serverNext = player:GetAttribute("PepperSprayNextUse")
 if now < localNextRequest or (typeof(serverNext) == "number" and now < serverNext) then return end
 local camera = workspace.CurrentCamera
 if not camera then return end
 localNextRequest = now + Config.RequestInterval
 request:FireServer(camera.CFrame.LookVector)
end
local function unequip()
 hudGeneration += 1
 clearGesture()
 disconnect(toolConnections)
 equippedTool = nil
 label.Visible = false
 ContextActionService:UnbindAction(actionName)
end
local function equip(tool: Tool)
 if tool.Name ~= Config.ToolName or tool:GetAttribute(Config.ToolAttribute) ~= true then return end
 unequip()
 equippedTool = tool
 label.Visible = true
 refreshHUD()
 table.insert(toolConnections, tool.Activated:Connect(use))
 table.insert(toolConnections, tool.Unequipped:Connect(unequip))
 table.insert(toolConnections, tool.Destroying:Connect(unequip))
 ContextActionService:BindAction(actionName, function(_, inputState)
  if inputState == Enum.UserInputState.Begin then use() end
  return Enum.ContextActionResult.Sink
 end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
 ContextActionService:SetTitle(actionName, "GAZ")
 ContextActionService:SetPosition(actionName, UDim2.fromScale(.78, .65))
end
local function bindCharacter(character: Model)
 disconnect(characterConnections)
 unequip()
 clearHit()
 currentCharacter = character
 table.insert(characterConnections, character.ChildAdded:Connect(function(child)
  if child:IsA("Tool") then equip(child) end
 end))
 table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
  if child == equippedTool then unequip() end
 end))
 table.insert(characterConnections, character:GetAttributeChangedSignal("PepperSprayStunned"):Connect(function()
  if not character:GetAttribute("PepperSprayStunned") then
   local humanoid = character:FindFirstChildOfClass("Humanoid")
   if humanoid and humanoid.Health > 0 and not humanoid.PlatformStand then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
  end
 end))
 task.spawn(function()
  local humanoid = character:WaitForChild("Humanoid", 10)
  if not active or currentCharacter ~= character or not humanoid or not humanoid:IsA("Humanoid") then return end
  table.insert(characterConnections, humanoid.Died:Connect(clearHit))
 end)
 for _,child in character:GetChildren() do if child:IsA("Tool") then equip(child) end end
end

local function showHit(character: Model, deadline: number)
 if character ~= player.Character or deadline <= workspace:GetServerTimeNow() or blur then return end
 clearHit()
 local generation = hitGeneration
 blur = Instance.new("BlurEffect")
 blur.Name, blur.Size = "PepperSprayBlur", Config.BlurSize
 blur.Parent = Lighting
 tint = Instance.new("ColorCorrectionEffect")
 tint.Name = "PepperSprayTint"
 tint.TintColor = Color3.fromRGB(255, 236, 173)
 tint.Contrast, tint.Saturation = .08, -.2
 tint.Parent = Lighting
 -- Server clock prevents late packets or repeated hits from extending the effect window.
 task.delay(math.max(0, deadline - workspace:GetServerTimeNow()), function()
  if hitGeneration == generation then clearHit() end
 end)
end

local function showSpray(tool: Tool, position: Vector3, direction: Vector3)
 local camera = workspace.CurrentCamera
 if not camera or (camera.CFrame.Position - position).Magnitude > Config.VisualDistance then return end
 sprayGesture(tool)
 local origin = tool:FindFirstChild(Config.OriginName, true)
 local sourceCharacter = tool.Parent
 local holder = Instance.new("Part")
 holder.Name, holder.Size, holder.Transparency = "PepperSprayVisual", Vector3.new(.1, .1, .1), 1
 holder.Anchored, holder.CanCollide, holder.CanTouch, holder.CanQuery = true, false, false, false
 holder.CFrame = CFrame.lookAt(position, position + direction)
 holder.Parent = workspace
 local attachment = Instance.new("Attachment") attachment.Name = "GasVisualOrigin" attachment.Parent = holder
 -- Always use the shared preset; an old Tool template must not override emission direction.
 local emitter = Particles.Create()
 emitter.Rate = Config.ParticleRate
 emitter.Speed = NumberRange.new(Config.Speed, Config.Speed)
 emitter.Parent = attachment
 local wallParams = RaycastParams.new()
 wallParams.FilterType = Enum.RaycastFilterType.Exclude
 wallParams.FilterDescendantsInstances = {tool.Parent or tool, holder}
 local wall = workspace:Raycast(position, direction * Config.Range, wallParams)
 local lifetime = math.min(Config.Range / Config.Speed, wall and math.max(.02, wall.Distance / Config.Speed) or Config.Range / Config.Speed)
 emitter.Lifetime = NumberRange.new(math.max(.02, lifetime * .75), lifetime)
 emitter.Enabled = true
 local follow: RBXScriptConnection? = nil
 local closed = false
 local function cleanup()
  if closed then return end
  closed = true
  if follow then follow:Disconnect() end
  visuals[holder] = nil
  holder:Destroy()
 end
 visuals[holder] = cleanup
 local started = os.clock()
 -- One brief connection per spray; particles keep world positions after leaving the nozzle.
 follow = RunService.RenderStepped:Connect(function()
  if not holder.Parent then cleanup() return end
  if os.clock() - started >= Config.SprayDuration or not tool.Parent or tool.Parent ~= sourceCharacter then
   emitter.Enabled = false
   if follow then follow:Disconnect() follow = nil end
   return
  end
  if origin and origin:IsA("Attachment") and origin.Parent then
   local nozzlePosition = origin.WorldPosition
   holder.CFrame = CFrame.lookAt(nozzlePosition, nozzlePosition + direction)
  end
 end)
 task.delay(Config.SprayDuration + lifetime + .15, cleanup)
end

table.insert(connections, effects.OnClientEvent:Connect(function(kind: string, ...: any)
 if kind == "Hit" then
  local character, deadline = ...
  if typeof(character) == "Instance" and character:IsA("Model") and typeof(deadline) == "number" then showHit(character, deadline) end
 elseif kind == "Spray" then
  local tool, position, direction = ...
  if typeof(tool) == "Instance" and tool:IsA("Tool") and typeof(position) == "Vector3" and typeof(direction) == "Vector3" then
   showSpray(tool, position, direction)
  end
 end
end))
table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
table.insert(connections, player.CharacterRemoving:Connect(function() currentCharacter = nil disconnect(characterConnections) unequip() clearHit() end))
if player.Character then bindCharacter(player.Character) end
table.insert(connections, player:GetAttributeChangedSignal("PepperSprayNextUse"):Connect(refreshHUD))
table.insert(connections, script.Destroying:Connect(function()
 active = false
 disconnect(connections) disconnect(characterConnections) unequip() clearHit()
 local cleanups = {} for _,cleanup in visuals do table.insert(cleanups, cleanup) end
 for _,cleanup in cleanups do cleanup() end
 gui:Destroy()
end))
