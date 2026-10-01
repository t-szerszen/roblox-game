--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ActivityConfig = require(ReplicatedStorage.Shared.Activity.ActivityConfig)

type BoardDefinition = {
	id: string,
	title: string,
	attribute: string,
	store: OrderedDataStore,
	formatTime: boolean,
}

local LeaderboardService = {}
local definitions: { BoardDefinition } = {
	{
		id = "RaceWins",
		title = "WYGRANE WYSCIGI 1V1",
		attribute = "RaceWins",
		store = DataStoreService:GetOrderedDataStore("GlobalRaceWins_v1"),
		formatTime = false,
	},
	{
		id = "LongestBurnout",
		title = "NAJDLUZSZY BURNOUT",
		attribute = "LongestBurnout",
		store = DataStoreService:GetOrderedDataStore("GlobalBurnoutMs_v1"),
		formatTime = true,
	},
	{
		id = "LongestWheelie",
		title = "NAJDLUZSZE WHEELIE",
		attribute = "LongestWheelie",
		store = DataStoreService:GetOrderedDataStore("GlobalWheelieMs_v1"),
		formatTime = true,
	},
	{
		id = "Deliveries",
		title = "NAJWIECEJ DOSTAW",
		attribute = "Deliveries",
		store = DataStoreService:GetOrderedDataStore("GlobalDeliveries_v1"),
		formatTime = false,
	},
}

local boards: { [string]: TextLabel } = {}
local publishedValues: { [string]: number } = {}
local started = false

local function spawnCFrame(): CFrame
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			return descendant.CFrame
		end
	end
	return CFrame.new(0, 5, 0)
end

local function createBoards()
	local old = Workspace:FindFirstChild("GlobalLeaderboards")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GlobalLeaderboards"
	folder.Parent = Workspace
	local base = spawnCFrame() * CFrame.new(0, 5, 18) * CFrame.Angles(0, math.pi, 0)
	for index, definition in definitions do
		local part = Instance.new("Part")
		part.Name = definition.id
		part.Anchored = true
		part.CanCollide = true
		part.Size = Vector3.new(8, 7, 0.5)
		part.CFrame = base * CFrame.new((index - 2.5) * 8.5, 0, 0)
		part.Color = Color3.fromRGB(24, 28, 34)
		part.Material = Enum.Material.Metal
		part.Parent = folder

		local surface = Instance.new("SurfaceGui")
		surface.Name = "BoardGui"
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 45
		surface.Parent = part
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
		text.BorderSizePixel = 0
		text.Font = Enum.Font.GothamMedium
		text.Text = definition.title .. "\n\nLadowanie..."
		text.TextColor3 = Color3.fromRGB(240, 242, 245)
		text.TextSize = 18
		text.TextWrapped = true
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.Parent = surface
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 18)
		padding.PaddingLeft = UDim.new(0, 14)
		padding.PaddingRight = UDim.new(0, 14)
		padding.Parent = text
		boards[definition.id] = text
	end
end

local function encodedValue(definition: BoardDefinition, value: number): number
	return if definition.formatTime then math.floor(value * 1_000) else math.floor(value)
end

local function displayValue(definition: BoardDefinition, value: number): string
	return if definition.formatTime then string.format("%.1f s", value / 1_000) else tostring(math.floor(value))
end

local function publishPlayer(player: Player)
	for _, definition in definitions do
		local value = player:GetAttribute(definition.attribute)
		if typeof(value) == "number" and value > 0 then
			local encoded = encodedValue(definition, value)
			local cacheKey = string.format("%d:%s", player.UserId, definition.id)
			if publishedValues[cacheKey] == encoded then
				continue
			end
			local success, message = pcall(function()
				definition.store:SetAsync(tostring(player.UserId), encoded)
			end)
			if not success then
				warn(string.format("LeaderboardService: failed to publish %s: %s", definition.id, tostring(message)))
			else
				publishedValues[cacheKey] = encoded
			end
		end
	end
end

local function userName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return if success then name else string.format("Gracz %d", userId)
end

local function refreshBoard(definition: BoardDefinition)
	local label = boards[definition.id]
	if not label then
		return
	end
	local success, pages = pcall(function()
		return definition.store:GetSortedAsync(false, ActivityConfig.LeaderboardEntries)
	end)
	if not success then
		label.Text = definition.title .. "\n\nRanking chwilowo niedostepny"
		return
	end
	local lines = { definition.title, "" }
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(lines, string.format("%d. %s   %s", rank, userName(userId), displayValue(definition, entry.value)))
		end
	end
	if #lines == 2 then
		table.insert(lines, "Brak wynikow")
	end
	label.Text = table.concat(lines, "\n")
end

function LeaderboardService.Start()
	if started then
		return
	end
	started = true
	createBoards()
	Players.PlayerRemoving:Connect(publishPlayer)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				publishPlayer(player)
			end
			for _, definition in definitions do
				refreshBoard(definition)
			end
			task.wait(ActivityConfig.LeaderboardRefreshInterval)
		end
	end)
end

return LeaderboardService
