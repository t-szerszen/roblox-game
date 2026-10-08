--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DzordzQuestConfig"))
local npc = workspace:WaitForChild(Config.NpcName)
local npcRoot = npc:WaitForChild("HumanoidRootPart") :: BasePart
local bench = workspace:WaitForChild(Config.BenchName)
local bag = bench:WaitForChild(Config.BagName) :: Model
local bagRoot = bag.PrimaryPart
assert(bagRoot, "Dzordz bag requires a PrimaryPart")
local template = ReplicatedStorage:WaitForChild(Config.AssetFolder):WaitForChild("Bag") :: Model
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local folder = Instance.new("Folder")
folder.Name = "DzordzQuest"
folder.Parent = remotes
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = folder
local connections: {RBXScriptConnection} = {}
local playerConnections: {[Player]: {RBXScriptConnection}} = {}
type State = {status: string, taps: number, started: number, lastTap: number, lastRequest: number, attempt: number}
local states: {[Player]: State} = {}

local function stateFor(player: Player): State
	local state = states[player]
	if not state then
		state = {status = "idle", taps = 0, started = 0, lastTap = 0, lastRequest = -math.huge, attempt = 0}
		states[player] = state
	end
	return state
end
local function publish(player: Player, state: State)
	player:SetAttribute("DzordzQuestStatus", state.status)
	player:SetAttribute("DzordzQuestTaps", state.taps)
end
local function near(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
		and (root.Position - part.Position).Magnitude <= Config.Range
		and not humanoid.Sit
end
local function removeCarry(character: Model?)
	if not character then return end
	local item = character:FindFirstChild(Config.CarryName)
	if item then item:Destroy() end
end
local function attachCarry(player: Player, character: Model)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or stateFor(player).status ~= "carrying" then return end
	removeCarry(character)
	local carried = template:Clone()
	carried.Name = Config.CarryName
	carried:PivotTo(torso.CFrame * CFrame.new(0, -0.45, 1.05) * CFrame.Angles(0, 0, math.rad(-12)))
	for _, part in carried:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = part
			weld.Parent = part
		end
	end
	carried.Parent = character
end
local function resetPickup(player: Player, state: State)
	state.status = "seeking"
	state.taps = 0
	state.attempt += 1
	publish(player, state)
end

action.OnServerInvoke = function(player: Player, operation: any, ...: any)
	if typeof(operation) ~= "string" or select("#", ...) ~= 0 then return {ok = false} end
	if operation ~= "accept" and operation ~= "begin" and operation ~= "tap" and operation ~= "cancel" and operation ~= "deliver" then return {ok = false} end
	local state = stateFor(player)
	local now = os.clock()
	if operation == "tap" then
		if now - state.lastTap < Config.TapCooldown then return {ok = false} end
		state.lastTap = now
	else
		if now - state.lastRequest < Config.RequestCooldown then return {ok = false} end
		state.lastRequest = now
	end
	if operation == "accept" then
		if state.status ~= "idle" or not near(player, npcRoot) then return {ok = false} end
		state.status = "seeking"
		publish(player, state)
	elseif operation == "begin" then
		if state.status ~= "seeking" or not near(player, bagRoot) then return {ok = false} end
		state.status = "picking"
		state.taps = 0
		state.started = now
		state.lastTap = now
		state.attempt += 1
		local attempt = state.attempt
		publish(player, state)
		task.delay(Config.PickupWindow, function()
			if states[player] == state and state.status == "picking" and state.attempt == attempt then
				resetPickup(player, state)
			end
		end)
	elseif operation == "tap" then
		if state.status ~= "picking" then return {ok = false} end
		if now - state.started > Config.PickupWindow or not near(player, bagRoot) then
			resetPickup(player, state)
			return {ok = false}
		end
		-- Tap count and elapsed time are independently checked on the server.
		state.taps = math.min(state.taps + 1, Config.Taps)
		if state.taps == Config.Taps and now - state.started >= Config.MinPickupTime then
			state.status = "carrying"
			state.attempt += 1
			if player.Character then attachCarry(player, player.Character) end
		end
		publish(player, state)
	elseif operation == "cancel" then
		if state.status ~= "picking" then return {ok = false} end
		resetPickup(player, state)
	elseif operation == "deliver" then
		if state.status ~= "carrying" or not near(player, npcRoot) then return {ok = false} end
		state.status = "completed"
		removeCarry(player.Character)
		publish(player, state)
	end
	return {ok = true, status = state.status, taps = state.taps}
end

local function watch(player: Player)
	local owned: {RBXScriptConnection} = {}
	playerConnections[player] = owned
	table.insert(owned, player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			if character ~= player.Character or not player.Parent then return end
			attachCarry(player, character)
		end)
	end))
	table.insert(owned, player.CharacterRemoving:Connect(function(character)
		local state = states[player]
		if state and state.status == "picking" then resetPickup(player, state) end
		removeCarry(character)
	end))
end
for _, player in Players:GetPlayers() do watch(player) end
table.insert(connections, Players.PlayerAdded:Connect(watch))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
	for _, connection in playerConnections[player] or {} do connection:Disconnect() end
	playerConnections[player] = nil
end))
script.Destroying:Connect(function()
	action.OnServerInvoke = nil
	for _, connection in connections do connection:Disconnect() end
	for _, owned in playerConnections do
		for _, connection in owned do connection:Disconnect() end
	end
	table.clear(playerConnections)
	for player in states do removeCarry(player.Character) end
	table.clear(states)
	folder:Destroy()
end)
