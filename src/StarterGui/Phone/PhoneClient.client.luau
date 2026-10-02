--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

type Connection = RBXScriptConnection
type Maid = {
	tasks: { Connection | Instance },
	Give: (self: Maid, task: Connection | Instance) -> (),
	Clean: (self: Maid) -> (),
}

local function newMaid(): Maid
	local maid = {}
	maid.tasks = {}

	function maid:Give(task: Connection | Instance)
		table.insert(self.tasks, task)
	end

	function maid:Clean()
		for _, task in ipairs(self.tasks) do
			if typeof(task) == "RBXScriptConnection" then
				task:Disconnect()
			elseif typeof(task) == "Instance" then
				task:Destroy()
			end
		end
		table.clear(self.tasks)
	end

	return maid :: Maid
end

type DailyState = { id: string, progress: number, target: number }
type GangMemberState = { userId: number, displayName: string, isLeader: boolean }
type GangCandidateState = { userId: number, displayName: string }
type GangState = {
	canCreate: boolean,
	gangId: string?,
	gangName: string?,
	gangColor: Color3?,
	isLeader: boolean,
	members: { GangMemberState },
	maxMembers: number,
	invite: { gangName: string, inviterName: string, expiresAt: number }?,
	candidates: { GangCandidateState },
}
type PhoneState = {
	passiveEnabled: boolean,
	passiveAvailable: boolean,
	gangName: string?,
	gang: GangState,
	delivery: { active: boolean, destination: string, distance: number },
	daily: { DailyState },
	ownedScooters: { string },
	loginStreak: number,
	loginReward: number,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName):WaitForChild(PhoneConfig.RequestFunctionName) :: RemoteFunction
local stateChanged = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName):WaitForChild(PhoneConfig.StateChangedEventName) :: RemoteEvent

local emptyState: PhoneState = {
	passiveEnabled = false,
	passiveAvailable = true,
	gangName = nil,
	gang = {
		canCreate = false,
		gangId = nil,
		gangName = nil,
		gangColor = nil,
		isLeader = false,
		members = {},
		maxMembers = 1,
		invite = nil,
		candidates = {},
	},
	delivery = { active = false, destination = "", distance = 0 },
	daily = {},
	ownedScooters = {},
	loginStreak = 0,
	loginReward = 0,
}
local state = emptyState
local currentPage = "Home"
local busy = false
local pageMaid = newMaid()
local globalMaid = newMaid()

local function createGradient(parent: Instance, c1: Color3, c2: Color3): UIGradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2)
	})
	grad.Rotation = 45
	grad.Parent = parent
	return grad
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local item = Instance.new("UIStroke")
	item.Color = color
	item.Thickness = thickness
	item.Parent = parent
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	item.Text = text
	item.TextColor3 = color
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Center
	item.Parent = parent
	return item
end

local function makeButton(parent: Instance, text: string, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.AutoButtonColor = true
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = Color3.fromRGB(255, 255, 255)
	item.TextSize = 14
	item.Parent = parent
	corner(item, 10)
	return item
end

local gui = Instance.new("ScreenGui")
gui.Name = "PhoneGui"
gui.DisplayOrder = 15
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Toggle event: fired by the ActionHUD to open/close the phone
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "TogglePhone"
toggleEvent.Parent = gui
gui:SetAttribute("PhoneOpen", false)

local phone = Instance.new("Frame")
phone.Name = "Phone"
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -18, 1, 30)
phone.Size = UDim2.fromOffset(250, 530)
phone.BackgroundColor3 = Color3.fromRGB(20, 20, 22) -- Titanium body
phone.Visible = false
phone.ClipsDescendants = false
phone.Parent = gui
corner(phone, 28)
stroke(phone, Color3.fromRGB(26, 26, 26), 3)

local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 250 / 530
aspect.Parent = phone

local phoneScale = Instance.new("UIScale")
phoneScale.Scale = 0.75
phoneScale.Parent = phone

local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.AnchorPoint = Vector2.new(0.5, 0.5)
screen.Position = UDim2.new(0.5, 0, 0.5, 0)
screen.Size = UDim2.new(1, -12, 1, -12)
screen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
screen.ClipsDescendants = true
screen.Parent = phone
corner(screen, 26)

local wallpaper = createGradient(screen, Color3.fromRGB(10, 14, 23), Color3.fromRGB(60, 20, 90))

-- Top Bar / Status
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundTransparency = 1
topBar.ZIndex = 100
topBar.Parent = screen

local clock = makeLabel(topBar, "12:00", 12, Color3.fromRGB(255, 255, 255), true)
clock.Position = UDim2.new(0, 18, 0, 12)
clock.Size = UDim2.fromOffset(40, 20)

local statusIcons = makeLabel(topBar, "LTE", 10, Color3.fromRGB(255, 255, 255), true)
statusIcons.AnchorPoint = Vector2.new(1, 0.5)
statusIcons.Position = UDim2.new(1, -42, 0, 22)
statusIcons.Size = UDim2.fromOffset(40, 20)
statusIcons.TextXAlignment = Enum.TextXAlignment.Right

local batteryBody = Instance.new("Frame")
batteryBody.Size = UDim2.fromOffset(18, 10)
batteryBody.AnchorPoint = Vector2.new(1, 0.5)
batteryBody.Position = UDim2.new(1, -18, 0, 22)
batteryBody.BackgroundTransparency = 1
batteryBody.Parent = topBar
corner(batteryBody, 3)
stroke(batteryBody, Color3.fromRGB(255, 255, 255), 1.5)

local batteryFill = Instance.new("Frame")
batteryFill.Size = UDim2.new(1, -4, 1, -4)
batteryFill.Position = UDim2.fromOffset(2, 2)
batteryFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
batteryFill.Parent = batteryBody
corner(batteryFill, 1)

local batteryTip = Instance.new("Frame")
batteryTip.Size = UDim2.fromOffset(2, 4)
batteryTip.Position = UDim2.new(1, 1, 0.5, 0)
batteryTip.AnchorPoint = Vector2.new(0, 0.5)
batteryTip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
batteryTip.Parent = batteryBody
corner(batteryTip, 1)

local dynamicIsland = Instance.new("Frame")
dynamicIsland.Size = UDim2.fromOffset(90, 26)
dynamicIsland.Position = UDim2.new(0.5, 0, 0, 10)
dynamicIsland.AnchorPoint = Vector2.new(0.5, 0)
dynamicIsland.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dynamicIsland.ZIndex = 100
dynamicIsland.Parent = screen
corner(dynamicIsland, 13)

local islandCamera = Instance.new("Frame")
islandCamera.Size = UDim2.fromOffset(10, 10)
islandCamera.Position = UDim2.new(1, -16, 0.5, 0)
islandCamera.AnchorPoint = Vector2.new(0, 0.5)
islandCamera.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
islandCamera.ZIndex = 101
islandCamera.Parent = dynamicIsland
corner(islandCamera, 5)

-- Home Screen View
local homeScreen = Instance.new("Frame")
homeScreen.Name = "HomeScreen"
homeScreen.Size = UDim2.new(1, 0, 1, 0)
homeScreen.BackgroundTransparency = 1
homeScreen.Parent = screen

local appGrid = Instance.new("Frame")
appGrid.Size = UDim2.new(1, -28, 1, -110)
appGrid.Position = UDim2.new(0, 14, 0, 52)
appGrid.BackgroundTransparency = 1
appGrid.Parent = homeScreen

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding = UDim2.fromOffset(14, 16)
gridLayout.CellSize = UDim2.fromOffset(64, 86)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = appGrid

-- App View
local appView = Instance.new("Frame")
appView.Name = "AppView"
appView.Size = UDim2.new(1, 0, 1, 0)
appView.Position = UDim2.new(1, 0, 0, 0) -- Slide in from right
appView.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
appView.Visible = false
appView.ZIndex = 10
appView.Parent = screen

local appContent = Instance.new("ScrollingFrame")
appContent.Name = "Content"
appContent.Size = UDim2.new(1, 0, 1, -80)
appContent.Position = UDim2.new(0, 0, 0, 40)
appContent.BackgroundTransparency = 1
appContent.BorderSizePixel = 0
appContent.ScrollBarThickness = 2
appContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
appContent.CanvasSize = UDim2.new()
appContent.ZIndex = 10
appContent.Parent = appView

local appPadding = Instance.new("UIPadding")
appPadding.PaddingTop = UDim.new(0, 16)
appPadding.PaddingBottom = UDim.new(0, 16)
appPadding.PaddingLeft = UDim.new(0, 16)
appPadding.PaddingRight = UDim.new(0, 16)
appPadding.Parent = appContent

local appTitle = makeLabel(appView, "App", 22, Color3.fromRGB(255, 255, 255), true)
appTitle.Position = UDim2.fromOffset(16, 46)
appTitle.Size = UDim2.new(1, -32, 0, 30)
appTitle.TextXAlignment = Enum.TextXAlignment.Left
appTitle.ZIndex = 10

-- Home Indicator
local homeBar = Instance.new("TextButton")
homeBar.Text = ""
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.Position = UDim2.new(0.5, 0, 1, -8)
homeBar.Size = UDim2.fromOffset(100, 4)
homeBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
homeBar.ZIndex = 110
homeBar.Parent = screen
corner(homeBar, 2)

local toast = makeLabel(screen, "", 12, Color3.fromRGB(255, 255, 255), true)
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -30)
toast.Size = UDim2.new(1, -32, 0, 40)
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
toast.BackgroundTransparency = 0.1
toast.ZIndex = 105
toast.Visible = false
corner(toast, 12)

local function updateClock()
	clock.Text = os.date("%H:%M")
end

local function showToast(message: string, isError: boolean)
	toast.Text = message
	toast.BackgroundColor3 = if isError then Color3.fromRGB(200, 50, 50) else Color3.fromRGB(20, 20, 20)
	toast.Visible = message ~= ""
	local shownMessage = message
	task.delay(2.5, function()
		if toast.Text == shownMessage then
			toast.Visible = false
		end
	end)
end

local function callServer(action: string, payload: unknown): (boolean, string, PhoneState)
	local ok, success, message, newState = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	if not ok or typeof(success) ~= "boolean" or typeof(newState) ~= "table" then
		return false, "Blad polaczenia.", state
	end
	return success, if typeof(message) == "string" then message else "", newState :: PhoneState
end

local function verticalLayout(parent: Instance, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function infoRow(parent: Instance, titleText: string, detail: string, accent: Color3): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 70)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	row.Parent = parent
	corner(row, 12)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	corner(stripe, 2)

	local titleLabel = makeLabel(row, titleText, 14, Color3.fromRGB(255, 255, 255), true)
	titleLabel.Position = UDim2.fromOffset(16, 12)
	titleLabel.Size = UDim2.new(1, -32, 0, 20)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local detailLabel = makeLabel(row, detail, 12, Color3.fromRGB(160, 160, 165))
	detailLabel.Position = UDim2.fromOffset(16, 36)
	detailLabel.Size = UDim2.new(1, -32, 0, 20)
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextWrapped = true
	return row
end

local renderApp: (appId: string) -> ()

local function runAction(action: string, payload: unknown)
	if busy then return end
	busy = true
	task.spawn(function()
		local success, message, newState = callServer(action, payload)
		state = newState
		busy = false
		showToast(message, not success)
		renderApp(currentPage)
	end)
end

local function openApp(appId: string)
	if currentPage == appId then return end
	currentPage = appId
	renderApp(appId)
	appView.Position = UDim2.new(1, 0, 0, 0)
	appView.Visible = true
	TweenService:Create(appView, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0)
	}):Play()
	TweenService:Create(homeScreen, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(-0.2, 0, 0, 0),
		GroupTransparency = 1
	}):Play()
end

local function goHome()
	if currentPage == "Home" then return end
	currentPage = "Home"
	TweenService:Create(appView, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, 0, 0, 0)
	}):Play()
	TweenService:Create(homeScreen, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
		GroupTransparency = 0
	}):Play()
	task.delay(0.3, function()
		if currentPage == "Home" then
			appView.Visible = false
		end
	end)
end

local apps = {
	{ id = "Scooters", name = "Hulajnoga", c1 = Color3.fromRGB(0, 220, 255), c2 = Color3.fromRGB(0, 140, 200), icon = "K" },
	{ id = "Delivery", name = "Kurier", c1 = Color3.fromRGB(255, 180, 50), c2 = Color3.fromRGB(240, 100, 0), icon = "D" },
	{ id = "Gang", name = "Gang", c1 = Color3.fromRGB(200, 40, 70), c2 = Color3.fromRGB(120, 20, 100), icon = "G" },
	{ id = "Daily", name = "Misje", c1 = Color3.fromRGB(50, 240, 120), c2 = Color3.fromRGB(10, 160, 60), icon = "M" },
	{ id = "Protection", name = "Ochrona", c1 = Color3.fromRGB(80, 120, 160), c2 = Color3.fromRGB(40, 70, 100), icon = "O" },
}

local function renderHomeGrid()
	for _, child in appGrid:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end
	for index, app in apps do
		local container = Instance.new("Frame")
		container.BackgroundTransparency = 1
		container.LayoutOrder = index
		container.Parent = appGrid

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(64, 64)
		btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Parent = container
		corner(btn, 16)
		createGradient(btn, app.c1, app.c2)

		local glyph = makeLabel(btn, app.icon, 28, Color3.fromRGB(255, 255, 255), true)
		glyph.Size = UDim2.new(1, 0, 1, 0)
		
		local label = makeLabel(container, app.name, 12, Color3.fromRGB(240, 240, 240))
		label.Position = UDim2.new(0, -10, 0, 68)
		label.Size = UDim2.new(1, 20, 0, 16)
		
		globalMaid:Give(btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(btn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(4, 4)}):Play()
			end
		end))
		globalMaid:Give(btn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(btn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(64, 64), Position = UDim2.new()}):Play()
			end
		end))
		globalMaid:Give(btn.Activated:Connect(function()
			openApp(app.id)
		end))
	end
end

local function clearAppContent()
	pageMaid:Clean()
	for _, child in appContent:GetChildren() do
		if not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	appContent.CanvasPosition = Vector2.zero
end

local function renderScooters()
	appTitle.Text = "Hulajnoga"
	local owned: { [string]: boolean } = {}
	for _, name in state.ownedScooters do owned[name] = true end
	for _, product in ShopConfig.CoinProducts do
		local isOwned = owned[product.name] == true
		local row = infoRow(appContent, product.name, product.description, if isOwned then Color3.fromRGB(0, 200, 255) else Color3.fromRGB(80, 80, 80))
		row.Size = UDim2.new(1, 0, 0, 80)
		local action = makeButton(row, if isOwned then "PRZYWOLAJ" else "ZABLOKOWANA", if isOwned then Color3.fromRGB(0, 140, 200) else Color3.fromRGB(60, 60, 60))
		action.AnchorPoint = Vector2.new(1, 1)
		action.Position = UDim2.new(1, -12, 1, -12)
		action.Size = UDim2.fromOffset(90, 26)
		action.TextSize = 10
		if isOwned then
			pageMaid:Give(action.Activated:Connect(function()
				runAction("SpawnScooter", product.name)
			end))
		end
	end
end

local function renderDelivery()
	appTitle.Text = "Kurier"
	if state.delivery.active then
		infoRow(appContent, "Cel Dostawy", state.delivery.destination, Color3.fromRGB(255, 160, 0))
		infoRow(appContent, "Dystans", string.format("%d studow", math.floor(state.delivery.distance)), Color3.fromRGB(200, 100, 0))
	else
		infoRow(appContent, "Brak zlecenia", "Znajdz punkt odbioru na mapie.", Color3.fromRGB(255, 160, 0))
	end
end

local function renderGang()
	appTitle.Text = "Gang"
	local gang = state.gang
	if gang.invite and not gang.gangId then
		local inviteRow = infoRow(appContent, gang.invite.gangName, "Zaprasza: " .. gang.invite.inviterName, Color3.fromRGB(200, 40, 100))
		inviteRow.Size = UDim2.new(1, 0, 0, 100)
		local accept = makeButton(inviteRow, "DOLACZ", Color3.fromRGB(40, 180, 60))
		accept.Position = UDim2.new(0, 12, 1, -34)
		accept.Size = UDim2.new(0.5, -16, 0, 24)
		local decline = makeButton(inviteRow, "ODRZUC", Color3.fromRGB(200, 40, 40))
		decline.Position = UDim2.new(0.5, 4, 1, -34)
		decline.Size = UDim2.new(0.5, -16, 0, 24)
		pageMaid:Give(accept.Activated:Connect(function() runAction("RespondGangInvite", true) end))
		pageMaid:Give(decline.Activated:Connect(function() runAction("RespondGangInvite", false) end))
	end
	
	if not gang.gangId then
		if not gang.canCreate then
			infoRow(appContent, "Brak Gangu", "Odblokuj prawo w sklepie by stworzyc gang.", Color3.fromRGB(150, 40, 80))
			return
		end
		local createRow = infoRow(appContent, "Zaloz Gang", "Podaj unikalna nazwe.", Color3.fromRGB(180, 30, 90))
		createRow.Size = UDim2.new(1, 0, 0, 110)
		local nameInput = Instance.new("TextBox")
		nameInput.Position = UDim2.new(0, 12, 1, -36)
		nameInput.Size = UDim2.new(1, -96, 0, 26)
		nameInput.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		nameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameInput.PlaceholderText = "Nazwa..."
		nameInput.Parent = createRow
		corner(nameInput, 6)
		local create = makeButton(createRow, "ZALOZ", Color3.fromRGB(180, 30, 90))
		create.AnchorPoint = Vector2.new(1, 0)
		create.Position = UDim2.new(1, -12, 1, -36)
		create.Size = UDim2.fromOffset(68, 26)
		pageMaid:Give(create.Activated:Connect(function() runAction("CreateGang", nameInput.Text) end))
		return
	end
	
	local gColor = gang.gangColor or Color3.fromRGB(180, 30, 90)
	infoRow(appContent, gang.gangName or "Twój Gang", string.format("%d/%d graczy", #gang.members, gang.maxMembers), gColor)
	
	for _, m in gang.members do
		local detail = if m.isLeader then "Lider" else "Czlonek"
		local row = infoRow(appContent, m.displayName, detail, if m.isLeader then gColor else Color3.fromRGB(100, 100, 100))
		if gang.isLeader and not m.isLeader then
			local kick = makeButton(row, "KICK", Color3.fromRGB(200, 40, 40))
			kick.AnchorPoint = Vector2.new(1, 0.5)
			kick.Position = UDim2.new(1, -12, 0.5, 0)
			kick.Size = UDim2.fromOffset(50, 24)
			pageMaid:Give(kick.Activated:Connect(function() runAction("KickGangMember", m.userId) end))
		end
	end
	
	if gang.isLeader and #gang.candidates > 0 and #gang.members < gang.maxMembers then
		for _, c in gang.candidates do
			local row = infoRow(appContent, c.displayName, "W poblizu", Color3.fromRGB(40, 180, 60))
			local inv = makeButton(row, "ZAPROS", Color3.fromRGB(40, 180, 60))
			inv.AnchorPoint = Vector2.new(1, 0.5)
			inv.Position = UDim2.new(1, -12, 0.5, 0)
			inv.Size = UDim2.fromOffset(60, 24)
			pageMaid:Give(inv.Activated:Connect(function() runAction("InviteGangMember", c.userId) end))
		end
	end
	
	local leave = makeButton(appContent, if gang.isLeader then "ROZWIAZ GANG" else "OPUSC GANG", Color3.fromRGB(200, 40, 40))
	leave.Size = UDim2.new(1, 0, 0, 36)
	pageMaid:Give(leave.Activated:Connect(function() runAction("LeaveGang", nil) end))
end

local function renderDaily()
	appTitle.Text = "Misje"
	infoRow(appContent, "Seria logowan", string.format("Dzien %d/7", state.loginStreak), Color3.fromRGB(240, 180, 40))
	
	local byId: { [string]: DailyState } = {}
	for _, progress in state.daily do byId[progress.id] = progress end
	
	for _, mission in PhoneConfig.DailyMissions do
		local p = byId[mission.id]
		local val = if p then p.progress else 0
		local row = infoRow(appContent, mission.name, string.format("%g / %g %s", val, mission.target, mission.unit), Color3.fromRGB(40, 200, 100))
		local fillBg = Instance.new("Frame")
		fillBg.Position = UDim2.new(0, 16, 1, -12)
		fillBg.Size = UDim2.new(1, -32, 0, 4)
		fillBg.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
		fillBg.BorderSizePixel = 0
		fillBg.Parent = row
		corner(fillBg, 2)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(math.clamp(val / mission.target, 0, 1), 1)
		fill.BackgroundColor3 = Color3.fromRGB(40, 200, 100)
		fill.BorderSizePixel = 0
		fill.Parent = fillBg
		corner(fill, 2)
	end
end

local function renderProtection()
	appTitle.Text = "Ochrona"
	local active = state.passiveEnabled
	local avail = state.passiveAvailable
	
	local c1 = if avail then (if active then Color3.fromRGB(40, 200, 100) else Color3.fromRGB(150, 150, 150)) else Color3.fromRGB(200, 40, 40)
	local txt = if active then "Ochrona Wlaczona" else "Ochrona Wylaczona"
	local det = if avail then "Blokuje udzial w PvP." else "Zablokowane dla czlonkow gangu."
	
	local row = infoRow(appContent, txt, det, c1)
	row.Size = UDim2.new(1, 0, 0, 100)
	local toggle = makeButton(row, if active then "WYLACZ" else "WLACZ", if avail then (if active then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(40, 200, 100)) else Color3.fromRGB(80, 80, 80))
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 16, 1, -10)
	toggle.Size = UDim2.new(1, -32, 0, 30)
	toggle.Active = avail
	if avail then
		pageMaid:Give(toggle.Activated:Connect(function() runAction("SetPassive", not active) end))
	end
end

renderApp = function(appId: string)
	if appId == "Home" then return end
	clearAppContent()
	verticalLayout(appContent, 12)
	appTitle.Position = UDim2.fromOffset(16, 60)
	appContent.Position = UDim2.new(0, 0, 0, 96)
	
	if appId == "Scooters" then renderScooters()
	elseif appId == "Delivery" then renderDelivery()
	elseif appId == "Gang" then renderGang()
	elseif appId == "Daily" then renderDaily()
	elseif appId == "Protection" then renderProtection()
	end
end

local function refresh()
	task.spawn(function()
		local success, message, newState = callServer("GetState", nil)
		state = newState
		if not success then showToast(message, true) end
		if currentPage ~= "Home" then renderApp(currentPage) end
	end)
end

local function setOpen(open: boolean)
	phone.Visible = open
	gui:SetAttribute("PhoneOpen", open)
	if open then
		phone.Position = UDim2.new(1, -18, 1, 30)
		TweenService:Create(phone, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -18, 1, -18)
		}):Play()
		refresh()
	end
end

globalMaid:Give(toggleEvent.Event:Connect(function()
	setOpen(not phone.Visible)
end))
globalMaid:Give(homeBar.Activated:Connect(goHome))
-- Escape navigates home or closes phone (M key toggle is handled by ActionHUD)
globalMaid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
	if input.KeyCode == Enum.KeyCode.Escape and phone.Visible then
		if currentPage ~= "Home" then goHome() else setOpen(false) end
	end
end))
globalMaid:Give(stateChanged.OnClientEvent:Connect(function()
	if phone.Visible then refresh() else showToast("Powiadomienie z gangu", false) end
end))

renderHomeGrid()
updateClock()

task.spawn(function()
	while gui.Parent do
		task.wait(15)
		updateClock()
	end
end)

script.Destroying:Connect(function()
	pageMaid:Clean()
	globalMaid:Clean()
	gui:Destroy()
end)
