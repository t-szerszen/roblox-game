--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PosterQuestConfig"))

type Progress = {
	status: string,
	completed: {[string]: boolean},
	count: number,
	holdStarted: {[string]: number},
	lastRequest: number,
	lastPost: number,
}

local states: {[Player]: Progress} = {}
local connections: {RBXScriptConnection} = {}
local spots: {[string]: BasePart} = {}

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
local questRemotes = Instance.new("Folder")
questRemotes.Name = "PosterQuest"
questRemotes.Parent = remotes
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = questRemotes
local changed = Instance.new("RemoteEvent")
changed.Name = "Changed"
changed.Parent = questRemotes

local function getProgress(player: Player): Progress
	local state = states[player]
	if not state then
		state = {
			status = "idle", completed = {}, count = 0,
			holdStarted = {}, lastRequest = -math.huge, lastPost = -math.huge,
		}
		states[player] = state
	end
	return state
end

local function snapshot(player: Player)
	local state = getProgress(player)
	return {
		status = state.status,
		count = state.count,
		total = #Config.StopNames,
		completed = table.clone(state.completed),
	}
end

local function publish(player: Player)
	local state = getProgress(player)
	player:SetAttribute("PosterQuestStatus", state.status)
	player:SetAttribute("PosterQuestCount", state.count)
	for _, stopName in Config.StopNames do
		player:SetAttribute("PosterQuest_" .. stopName, state.completed[stopName] == true)
	end
	changed:FireClient(player, snapshot(player))
end

local function withinRange(player: Player, position: Vector3, distance: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart")
		and humanoid ~= nil and humanoid.Health > 0
		and (root.Position - position).Magnitude <= distance
end

local function createSpot(stopName: string)
	local stop = workspace:WaitForChild(stopName, 10)
	assert(stop and stop:IsA("Model"), "Nie znaleziono przystanku: " .. stopName)
	local wall = stop:FindFirstChild(Config.WallName)
	assert(wall and wall:IsA("BasePart"), "Brak białej ścianki: " .. stopName)
	local existing = stop:FindFirstChild(Config.SpotName)
	if existing then
		existing:Destroy()
	end

	local spot = Instance.new("Part")
	spot.Name = Config.SpotName
	spot.Size = Config.PosterSize
	spot.CFrame = wall.CFrame * CFrame.new(0, 0, -(wall.Size.Z / 2 + Config.SurfaceGap))
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanTouch = false
	spot.CanQuery = false
	spot.Transparency = 1
	spot.Color = Color3.fromRGB(233, 220, 187)
	spot:SetAttribute("SpotId", stopName)
	spot.Parent = stop

	local surface = Instance.new("SurfaceGui")
	surface.Name = "PosterSurface"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(572, 1024)
	surface.LightInfluence = 0.35
	surface.Enabled = false
	surface.Parent = spot

	local poster = Instance.new("ImageLabel")
	poster.Name = "PosterImage"
	poster.Size = UDim2.fromScale(1, 1)
	poster.BackgroundTransparency = 1
	poster.Image = Config.PosterImage
	poster.ScaleType = Enum.ScaleType.Stretch
	poster.Parent = surface

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HangPoster"
	prompt.ActionText = "Rozwieś plakat"
	prompt.ObjectText = "Przystanek " .. string.sub(stopName, -1)
	prompt.HoldDuration = Config.HoldDuration
	prompt.MaxActivationDistance = Config.InteractionDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
	spots[stopName] = spot
	CollectionService:AddTag(spot, Config.SpotTag)

	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local state = getProgress(player)
		if state.status == "active" and not state.completed[stopName]
			and withinRange(player, spot.Position, Config.InteractionDistance + 0.5) then
			state.holdStarted[stopName] = os.clock()
		end
	end))

	table.insert(connections, prompt.Triggered:Connect(function(player: Player)
		local state = getProgress(player)
		local started = state.holdStarted[stopName]
		state.holdStarted[stopName] = nil
		local now = os.clock()
		-- Roblox prompt signals can be forged; eligibility, distance and hold time remain server checks.
		if not prompt.Enabled or state.status ~= "active" or state.completed[stopName]
			or not started or now - started < Config.HoldDuration - 0.15
			or now - started > Config.HoldDuration + 5
			or now - state.lastPost < Config.RequestCooldown
			or not withinRange(player, spot.Position, Config.InteractionDistance + 0.5) then
			return
		end
		state.lastPost = now
		state.completed[stopName] = true
		state.count += 1
		if state.count == #Config.StopNames then
			state.status = "completed"
		end
		publish(player)
	end))
end

for _, stopName in Config.StopNames do
	createSpot(stopName)
end

action.OnServerInvoke = function(player: Player, operation: any, ...: any)
	local state = getProgress(player)
	if select("#", ...) ~= 0 or typeof(operation) ~= "string"
		or (operation ~= "accept" and operation ~= "state") then
		return {ok = false, reason = "Nieprawidłowe żądanie."}
	end
	local now = os.clock()
	if now - state.lastRequest < Config.RequestCooldown then
		return {ok = false, reason = "Spróbuj za chwilę."}
	end
	state.lastRequest = now
	if operation == "state" then
		return {ok = true, state = snapshot(player)}
	end
	local folder = workspace:FindFirstChild(Config.NpcFolder)
	local npc = folder and folder:FindFirstChild(Config.NpcName)
	local root = npc and npc:FindFirstChild("HumanoidRootPart")
	local prompt = npc and npc:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not root or not root:IsA("BasePart") or not prompt or not prompt.Enabled
		or not withinRange(player, root.Position, Config.AcceptDistance) then
		return {ok = false, reason = "Podejdź do Szkieła, żeby przyjąć zadanie."}
	end
	if state.status == "idle" then
		state.status = "active"
		publish(player)
	end
	return {ok = true, state = snapshot(player)}
end

table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end))

script.Destroying:Connect(function()
	action.OnServerInvoke = nil
	for _, connection in connections do connection:Disconnect() end
	table.clear(states)
	questRemotes:Destroy()
end)