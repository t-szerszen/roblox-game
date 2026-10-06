--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PosterQuestConfig"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PosterQuest")
local action = remotes:WaitForChild("Action") :: RemoteFunction
local changed = remotes:WaitForChild("Changed") :: RemoteEvent
local connections: {RBXScriptConnection} = {}
local state = {status = "idle", count = 0, completed = {} :: {[string]: boolean}}

local gui = Instance.new("ScreenGui")
gui.Name = "DzordzPosterQuest"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "QuestCard"
card.AnchorPoint = Vector2.new(1, 0)
card.Position = UDim2.new(1, -20, 0, 80)
card.Size = UDim2.fromOffset(300, 286)
card.BackgroundColor3 = Color3.fromRGB(21, 30, 43)
card.BackgroundTransparency = 0.06
card.BorderSizePixel = 0
card.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = card
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(79, 104, 134)
stroke.Transparency = 0.25
stroke.Parent = card
local scale = Instance.new("UIScale")
scale.Parent = card

local function label(name: string, value: string, position: Vector2, size: Vector2, fontSize: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Position = UDim2.fromOffset(position.X, position.Y)
	text.Size = UDim2.fromOffset(size.X, size.Y)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.Text = value
	text.TextSize = fontSize
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.Parent = card
	return text
end

local white = Color3.fromRGB(240, 246, 255)
local muted = Color3.fromRGB(167, 185, 205)
local blue = Color3.fromRGB(103, 181, 248)
local green = Color3.fromRGB(112, 225, 167)
local header = label("Status", "ZADANIE • POLICJA", Vector2.new(18, 14), Vector2.new(220, 22), 12, blue)
header.Font = Enum.Font.GothamBold
local counter = label("Counter", "0/3", Vector2.new(249, 13), Vector2.new(38, 24), 17, white)
counter.TextXAlignment = Enum.TextXAlignment.Center
counter.Font = Enum.Font.GothamBold

local thumbnail = Instance.new("ImageLabel")
thumbnail.Name = "PosterPreview"
thumbnail.Position = UDim2.fromOffset(18, 49)
thumbnail.Size = UDim2.fromOffset(50, 90)
thumbnail.BackgroundTransparency = 1
thumbnail.Image = Config.PosterImage
thumbnail.Parent = card
local imageCorner = Instance.new("UICorner")
imageCorner.CornerRadius = UDim.new(0, 4)
imageCorner.Parent = thumbnail

local title = label("Title", "Dzordz\nAutomatowicz", Vector2.new(82, 51), Vector2.new(200, 53), 20, white)
title.Font = Enum.Font.GothamBold
label("Description", "Poszukiwany • rozwieś plakaty", Vector2.new(82, 110), Vector2.new(195, 31), 12, muted)
local instruction = label("Instruction", "Odwiedź 3 przystanki.", Vector2.new(18, 151), Vector2.new(264, 22), 13, muted)

local track = Instance.new("Frame")
track.Name = "ProgressTrack"
track.Position = UDim2.fromOffset(18, 179)
track.Size = UDim2.fromOffset(264, 5)
track.BackgroundColor3 = Color3.fromRGB(44, 57, 75)
track.BorderSizePixel = 0
track.Parent = card
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track
local fill = Instance.new("Frame")
fill.Name = "ProgressFill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = blue
fill.BorderSizePixel = 0
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local rows: {[string]: TextLabel} = {}
for index, stopName in Config.StopNames do
	rows[stopName] = label(stopName, "○  Przystanek " .. index, Vector2.new(18, 196 + (index - 1) * 26), Vector2.new(264, 24), 14, muted)
end

local function applySpot(spot: Instance)
	if not spot:IsA("BasePart") then return end
	local id = spot:GetAttribute("SpotId")
	if typeof(id) ~= "string" or not rows[id] then return end
	local completed = state.completed[id] == true
	local surface = spot:FindFirstChild("PosterSurface")
	local prompt = spot:FindFirstChild("HangPoster")
	-- Visuals belong to this player; the server owns the completion record.
	spot.Transparency = if completed then 0 else 1
	if surface and surface:IsA("SurfaceGui") then surface.Enabled = completed end
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = state.status == "active" and not completed
	end
end

local function receive(newState: any)
	if typeof(newState) ~= "table" or typeof(newState.status) ~= "string"
		or typeof(newState.count) ~= "number" or typeof(newState.completed) ~= "table" then
		return
	end
	state.status = newState.status
	state.count = math.clamp(newState.count, 0, #Config.StopNames)
	state.completed = newState.completed
	gui.Enabled = state.status ~= "idle"
	counter.Text = tostring(state.count) .. "/" .. #Config.StopNames
	local done = state.status == "completed"
	header.Text = if done then "✓ Zaliczone" else "ZADANIE • POLICJA"
	header.TextColor3 = if done then green else blue
	instruction.Text = if done then "Wszystkie plakaty rozwieszone." else "Odwiedź 3 przystanki."
	fill.Size = UDim2.fromScale(state.count / #Config.StopNames, 1)
	fill.BackgroundColor3 = if done then green else blue
	stroke.Color = if done then green else Color3.fromRGB(79, 104, 134)
	for index, id in Config.StopNames do
		local completed = state.completed[id] == true
		rows[id].Text = (if completed then "✓  " else "○  ") .. "Przystanek " .. index
		rows[id].TextColor3 = if completed then green else muted
	end
	for _, spot in CollectionService:GetTagged(Config.SpotTag) do applySpot(spot) end
end

local function resize()
	local camera = workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(camera.ViewportSize.X / 900, 0.8, 1)
	end
end
resize()
local camera = workspace.CurrentCamera
if camera then
	table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize))
end
table.insert(connections, changed.OnClientEvent:Connect(receive))
table.insert(connections, CollectionService:GetInstanceAddedSignal(Config.SpotTag):Connect(applySpot))
for _, spot in CollectionService:GetTagged(Config.SpotTag) do applySpot(spot) end
task.spawn(function()
	local ok, result = pcall(function() return action:InvokeServer("state") end)
	if ok and result and result.ok then receive(result.state) end
end)

script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	gui:Destroy()
end)
