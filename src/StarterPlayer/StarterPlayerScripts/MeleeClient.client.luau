--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Combat.MeleeConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local Motion = require(ReplicatedStorage.Shared.Combat.MeleeMotion)
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(CombatConfig.RemoteFolderName)
local action = remotes:WaitForChild(CombatConfig.ActionRemoteName) :: RemoteEvent
local effects = remotes:WaitForChild(Config.EffectsRemote) :: RemoteEvent
local connections: {RBXScriptConnection} = {}
local watchers: {[Player]: {RBXScriptConnection}} = {}
local characterWatchers: {[Player]: {RBXScriptConnection}} = {}
local toolConnections: {[Tool]: RBXScriptConnection} = {}
local nextInput = 0
local active = true
local blur = Instance.new("BlurEffect") blur.Name = "MeleeKnockBlur" blur.Size = 0 blur.Parent = Lighting
local tint = Instance.new("ColorCorrectionEffect") tint.Name = "MeleeKnockTint" tint.Brightness = 0 tint.Parent = Lighting
local effectToken = 0
local tweens: {Tween} = {}
local cameraTween: Tween? = nil
local cameraHumanoid: Humanoid? = nil
local cameraBase = Vector3.zero
local function disconnect(list: {RBXScriptConnection}?) if list then for _, c in list do c:Disconnect() end end end
local function tween(object: Instance, duration: number, properties: {[string]: any})
	local t = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Sine), properties)
	table.insert(tweens, t) t:Play()
end
local function resetEffects()
	effectToken += 1
	for _, t in tweens do t:Cancel() end table.clear(tweens)
	blur.Size, tint.Brightness = 0, 0
	if cameraTween then cameraTween:Cancel() cameraTween = nil end
	if cameraHumanoid and cameraHumanoid.Parent then cameraHumanoid.CameraOffset = cameraBase end
	cameraHumanoid = nil
end
local function knock(deadline: number)
	resetEffects()
	local token = effectToken
	local remaining = math.max(0, deadline - workspace:GetServerTimeNow())
	if remaining <= 0 then return end
	tween(blur, math.min(0.12, remaining), {Size=Config.BlurSize})
	tween(tint, math.min(0.12, remaining), {Brightness=-0.12})
	task.delay(math.max(0, remaining - 0.25), function()
		if active and effectToken == token then tween(blur, 0.25, {Size=0}) tween(tint, 0.25, {Brightness=0}) end
	end)
end
local function cameraKick()
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not h then return end
	if cameraTween then cameraTween:Cancel() end
	if cameraHumanoid ~= h then cameraHumanoid, cameraBase = h, h.CameraOffset end
	h.CameraOffset = cameraBase + Vector3.new(0, 0.06, 0.12)
	cameraTween = TweenService:Create(h, TweenInfo.new(0.22), {CameraOffset=cameraBase}) cameraTween:Play()
end
local function sound(character: Model, kind: string)
	local id = (Config.Sounds :: any)[kind]
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or type(id) ~= "string" or not id:match("^rbxassetid://%d+$") then return end
	local s = Instance.new("Sound") s.SoundId = id s.Volume = 0.55 s.RollOffMinDistance = 5 s.RollOffMaxDistance = Config.SoundDistance
	s.Parent = root s:Play() Debris:AddItem(s, 4)
end
local function fists(character: Model): Tool?
	for _, item in character:GetChildren() do
		if item:IsA("Tool") and item.Name == Config.ToolName and item:GetAttribute(Config.ToolAttribute) == true then return item end
	end
	return nil
end
local function hookCharacter(owner: Player, character: Model)
	disconnect(characterWatchers[owner])
	local h = character:WaitForChild("Humanoid", 10)
	if not active or owner.Character ~= character or not h or not h:IsA("Humanoid") then return end
	local knownTool: Tool? = nil
	local function refresh()
		local tool = fists(character)
		local allowed = tool ~= nil and h.Health > 0 and not h.PlatformStand and not character:GetAttribute("PepperSprayStunned")
		Motion.Stance(character, allowed)
		if owner ~= player or tool == knownTool then return end
		if knownTool and toolConnections[knownTool] then toolConnections[knownTool]:Disconnect() toolConnections[knownTool] = nil end
		knownTool = tool
		if tool then
			toolConnections[tool] = tool.Activated:Connect(function()
				if UserInputService:GetFocusedTextBox() or os.clock() < nextInput or tool.Parent ~= player.Character then return end
				nextInput = os.clock() + 0.12
				action:FireServer("Melee")
			end)
		end
	end
	local function cleanup()
		Motion.Stop(character)
		if knownTool and toolConnections[knownTool] then toolConnections[knownTool]:Disconnect() toolConnections[knownTool] = nil end
		if owner == player then resetEffects() end
	end
	characterWatchers[owner] = {
		character.ChildAdded:Connect(refresh), character.ChildRemoved:Connect(refresh),
		character:GetAttributeChangedSignal("PepperSprayStunned"):Connect(refresh),
		h:GetPropertyChangedSignal("PlatformStand"):Connect(refresh),
		h.Died:Connect(cleanup), character.Destroying:Connect(cleanup),
	}
	refresh()
end
local function hook(owner: Player)
	watchers[owner] = {
		owner.CharacterAdded:Connect(function(c) hookCharacter(owner, c) end),
		owner.CharacterRemoving:Connect(function(c)
			Motion.Stop(c) disconnect(characterWatchers[owner]) characterWatchers[owner] = nil
			for tool, connection in toolConnections do if tool:IsDescendantOf(c) then connection:Disconnect() toolConnections[tool] = nil end end
			if owner == player then
				for tool, connection in toolConnections do connection:Disconnect() toolConnections[tool] = nil end
				resetEffects()
			end
		end),
	}
	if owner.Character then task.defer(hookCharacter, owner, owner.Character) end
end
table.insert(connections, effects.OnClientEvent:Connect(function(event: string, character: Model, value: any, timestamp: any)
	if not active or typeof(character) ~= "Instance" or not character:IsA("Model") or not character.Parent then return end
	if event == "Swing" then
		Motion.Play(character, "Punch" .. tostring(value), value, workspace:GetServerTimeNow() - timestamp)
	elseif event == "Miss" then Motion.Play(character, "Miss") sound(character, "Miss")
	elseif event == "Hit" then
		Motion.Play(character, if value then "HeavyHit" else "Hit") sound(character, if value then "Heavy" else "Light")
		if value and character == player.Character then cameraKick() end
	elseif event == "Fall" then Motion.Stop(character) sound(character, "Fall")
	elseif event == "Knock" and character == player.Character then knock(value)
	end
end))
for _, owner in Players:GetPlayers() do hook(owner) end
table.insert(connections, Players.PlayerAdded:Connect(hook))
table.insert(connections, Players.PlayerRemoving:Connect(function(owner)
	disconnect(watchers[owner]) disconnect(characterWatchers[owner]) watchers[owner], characterWatchers[owner] = nil, nil
	if owner.Character then Motion.Stop(owner.Character) end
end))
script.Destroying:Connect(function()
	active = false resetEffects() Motion.StopAll()
	disconnect(connections)
	for _, list in watchers do disconnect(list) end
	for _, list in characterWatchers do disconnect(list) end
	for _, c in toolConnections do c:Disconnect() end
	blur:Destroy() tint:Destroy()
end)
