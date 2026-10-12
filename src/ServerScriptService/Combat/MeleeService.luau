--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Combat.MeleeConfig)
local Ragdoll = require(script.Parent.Parent.PepperSpray.Ragdoll)
local Service = {}
type Pair = { count: number, recent: {number} }
type Swing = { character: Model, tool: Tool, index: number, started: number, ready: number, busy: boolean }
local pairsByPlayer: {[Player]: {[Player]: Pair}} = {}
local swings: {[Player]: Swing} = {}
local knockReady: {[Player]: number} = {}
local playerConnections: {[Player]: {RBXScriptConnection}} = {}
local characterConnections: {[Player]: {RBXScriptConnection}} = {}
local connections: {RBXScriptConnection} = {}
local combat: any
local effects: RemoteEvent
local started = false

local function disconnect(list: {RBXScriptConnection}?)
	if list then for _, c in list do c:Disconnect() end end
end
local function clear(player: Player)
	swings[player] = nil
	knockReady[player] = nil
	pairsByPlayer[player] = nil
	for _, targets in pairsByPlayer do targets[player] = nil end
	disconnect(characterConnections[player])
	characterConnections[player] = nil
end
local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
local function equipped(character: Model): Tool?
	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") and tool.Name == Config.ToolName and tool:GetAttribute(Config.ToolAttribute) == true then return tool end
	end
	return nil
end
local function eligible(player: Player, character: Model, tool: Tool): boolean
	local h = character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	local stun = player:GetAttribute("StunnedUntil")
	return player.Parent == Players and player.Character == character and tool.Parent == character
		and h ~= nil and h.Health > 0 and not h.Sit and not h.PlatformStand
		and root ~= nil and not root.Anchored and character:GetAttribute("PepperSprayStunned") ~= true
		and player:GetAttribute("PoliceState") ~= "ARRESTED"
		and player:GetAttribute("PassiveMode") ~= true
		and not (typeof(stun) == "number" and stun > workspace:GetServerTimeNow())
end
local function broadcast(character: Model, event: string, ...: any)
	local root = rootOf(character)
	if not root then return end
	for _, observer in Players:GetPlayers() do
		local other = rootOf(observer.Character)
		if other and (other.Position - root.Position).Magnitude <= Config.VisualDistance then
			effects:FireClient(observer, event, character, ...)
		end
	end
end
local function hit(attacker: Player, target: Player, index: number)
	if not combat.CanDamage(attacker, target) then return end
	local character = target.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not h or h.Health <= 0 then return end
	local targets = pairsByPlayer[attacker]
	if not targets then targets = {} pairsByPlayer[attacker] = targets end
	local pair = targets[target]
	if not pair then pair = { count = 0, recent = {} } targets[target] = pair end
	local now = workspace:GetServerTimeNow()
	pair.count += 1
	while #pair.recent > 0 and now - pair.recent[1] > Config.KnockWindow do table.remove(pair.recent, 1) end
	table.insert(pair.recent, now)
	combat.MarkMeleeCombat(attacker, target)
	broadcast(character, "Hit", Config.Swings[index].Heavy)
	-- Pair counters cannot share ordinary per-hit HP damage: otherwise several attackers could kill before anyone reaches eight.
	if pair.count >= Config.KillHits then
		h.Health = 0
		return
	end
	if #pair.recent >= Config.KnockHits and now >= (knockReady[target] or 0) and Ragdoll.Start(character, Config.KnockDuration) then
		pair.recent = {}
		local deadline = now + Config.KnockDuration
		knockReady[target] = deadline + Config.RecoveryGrace
		target:SetAttribute("StunnedUntil", deadline)
		character:SetAttribute("MeleeDownUntil", deadline)
		broadcast(character, "Fall")
		effects:FireClient(target, "Knock", character, deadline)
		task.delay(Config.KnockDuration, function()
			if target.Character ~= character then return end
			character:SetAttribute("MeleeDownUntil", nil)
			if target:GetAttribute("StunnedUntil") == deadline then target:SetAttribute("StunnedUntil", nil) end
		end)
	end
end
local function findTarget(attacker: Player, character: Model): Player?
	local root = rootOf(character)
	if not root then return nil end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = {character}
	local candidates: {[Player]: boolean} = {}
	for _, part in workspace:GetPartBoundsInBox(root.CFrame * Config.HitboxOffset, Config.HitboxSize, overlap) do
		local ancestor: Instance? = part
		while ancestor and ancestor ~= workspace do
			if ancestor:IsA("Model") then
				local p = Players:GetPlayerFromCharacter(ancestor)
				if p then candidates[p] = true break end
			end
			ancestor = ancestor.Parent
		end
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = {character}
	local best: Player? = nil
	local nearest = Config.Range
	for target in candidates do
		local other = rootOf(target.Character)
		if target == attacker or not other or not combat.CanDamage(attacker, target) then continue end
		local offset = other.Position - root.Position
		local distance = offset.Magnitude
		if distance > nearest or distance < 0.01 or root.CFrame.LookVector:Dot(offset.Unit) < Config.FacingDot then continue end
		local origin = root.Position + Vector3.new(0, 1, 0)
		local result = workspace:Raycast(origin, other.Position - origin, ray)
		if result and not result.Instance:IsDescendantOf(target.Character :: Model) then continue end
		best, nearest = target, distance
	end
	return best
end
function Service.Attack(player: Player)
	local character = player.Character
	if not character then return end
	local tool = equipped(character)
	if not tool or not eligible(player, character, tool) then return end
	local now = workspace:GetServerTimeNow()
	local previous = swings[player]
	if previous and (previous.busy or now < previous.ready) then return end
	local index = if previous and previous.character == character and now - previous.started <= Config.ComboReset then previous.index % #Config.Swings + 1 else 1
	local config = Config.Swings[index]
	local swing: Swing = { character = character, tool = tool, index = index, started = now, ready = now + config.Cooldown, busy = true }
	swings[player] = swing
	broadcast(character, "Swing", index, now)
	task.delay(config.Windup, function()
		local deadline = swing.started + config.Windup + config.Window
		local connected = false
		repeat
			if swings[player] ~= swing then return end
			if not eligible(player, character, tool) or workspace:GetServerTimeNow() >= deadline then
				swing.busy = false
				return
			end
			local target = findTarget(player, character)
			if target then hit(player, target, index) connected = true break end
			task.wait(Config.SampleInterval)
		until workspace:GetServerTimeNow() >= deadline
		if swings[player] ~= swing then return end
		swing.busy = false
		if not connected and eligible(player, character, tool) then broadcast(character, "Miss") end
	end)
end
local function characterAdded(player: Player, character: Model)
	clear(player)
	local h = character:WaitForChild("Humanoid", 10)
	if not h or not h:IsA("Humanoid") or player.Character ~= character or player.Parent ~= Players then return end
	if not h:FindFirstChildOfClass("Animator") then Instance.new("Animator", h) end
	characterConnections[player] = {
		h.Died:Connect(function() clear(player) end),
		character.ChildRemoved:Connect(function(child)
			local current = swings[player]
			if current and current.tool == child then swings[player] = nil end
		end),
	}
end
local function hook(player: Player)
	playerConnections[player] = {
		player.CharacterAdded:Connect(function(c) characterAdded(player, c) end),
		player.CharacterRemoving:Connect(function() clear(player) end),
	}
	if player.Character then task.defer(characterAdded, player, player.Character) end
end
function Service.Start(combatService: any, remote: RemoteEvent)
	if started then return end
	started, combat, effects = true, combatService, remote
	for _, player in Players:GetPlayers() do hook(player) end
	table.insert(connections, Players.PlayerAdded:Connect(hook))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		clear(player) disconnect(playerConnections[player]) playerConnections[player] = nil
	end))
	table.insert(connections, script.Destroying:Connect(function()
		for player in playerConnections do clear(player) disconnect(playerConnections[player]) end
		table.clear(playerConnections)
		disconnect(connections)
	end))
end
return Service
