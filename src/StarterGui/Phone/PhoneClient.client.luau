--!strict
--[[
	PhoneClient — Polished smartphone UI framework (GDD Module 8)

	Architecture:
	  • Builds entire UI programmatically — no Studio tree required.
	  • ScreenGui "PhoneGui" (DisplayOrder 200) for phone + apps.
	  • HUD button "PhoneBtn" lives inside a separate ScreenGui "PhoneHUD" (DisplayOrder 100).
	  • All tweens / connections tracked via Maid for leak-free cleanup.
	  • Server comms via PhoneRemotes/PhoneRequest RemoteFunction.
	  • App icon Image fields are EMPTY — asset IDs will be injected later.
]]

-- ═══════════════════════════════════════════════════════════════════════
-- SERVICES & DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

-- ═══════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════

type Connection = RBXScriptConnection
type Maid = {
	tasks: { Connection | Instance | Tween },
	Give: (self: Maid, task: Connection | Instance | Tween) -> (),
	Clean: (self: Maid) -> (),
}

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

type AppDef = {
	id: string,
	name: string,
	c1: Color3,
	c2: Color3,
}

-- ═══════════════════════════════════════════════════════════════════════
-- MAID — lightweight connection / instance cleanup
-- ═══════════════════════════════════════════════════════════════════════

local function newMaid(): Maid
	local maid = {} :: any
	maid.tasks = {}

	function maid:Give(task: Connection | Instance | Tween)
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

-- ═══════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName)
	:WaitForChild(PhoneConfig.RequestFunctionName) :: RemoteFunction
local stateChanged = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName)
	:WaitForChild(PhoneConfig.StateChangedEventName) :: RemoteEvent

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

local state: PhoneState = emptyState
local currentPage = "Home"
local isPhoneOpen = false
local busy = false

local pageMaid = newMaid()
local globalMaid = newMaid()

-- ═══════════════════════════════════════════════════════════════════════
-- DESIGN TOKENS — compact urban-cyberpunk phone
-- ═══════════════════════════════════════════════════════════════════════

-- Dimensions (absolute pixel sizes used with UIAspectRatioConstraint)
local PHONE_WIDTH = 260
local PHONE_HEIGHT = 540
local PHONE_ASPECT = PHONE_WIDTH / PHONE_HEIGHT  -- ~0.48
local BODY_RADIUS = 30     -- heavy rounded corners for titanium chassis
local SCREEN_INSET = 6     -- bezel between body edge and display
local SCREEN_RADIUS = 26
local APP_ICON_SIZE = 56
local APP_CORNER = 16      -- squircle radius

-- Colors
local COL = {
	-- Titanium body
	bodyFrame  = Color3.fromRGB(18, 18, 20),
	bodyStroke = Color3.fromRGB(42, 42, 48),

	-- Wallpaper gradient (deep navy → electric purple)
	wallTop    = Color3.fromRGB(8, 12, 28),
	wallBot    = Color3.fromRGB(55, 18, 88),

	-- Dynamic Island
	island     = Color3.fromRGB(0, 0, 0),
	islandCam  = Color3.fromRGB(12, 14, 22),

	-- Status bar / text
	white      = Color3.fromRGB(255, 255, 255),
	muted      = Color3.fromRGB(160, 160, 170),
	dimmed     = Color3.fromRGB(100, 100, 108),

	-- App view background
	appBg      = Color3.fromRGB(18, 20, 26),

	-- Info rows
	rowBg      = Color3.fromRGB(28, 30, 38),

	-- Toast
	toastBg    = Color3.fromRGB(16, 16, 18),
	toastError = Color3.fromRGB(200, 45, 45),

	-- HUD button
	hudBg1     = Color3.fromRGB(24, 26, 32),
	hudBg2     = Color3.fromRGB(16, 18, 22),
	hudStroke  = Color3.fromRGB(0, 180, 255),
	hudBadgeBg1 = Color3.fromRGB(50, 50, 55),
	hudBadgeBg2 = Color3.fromRGB(30, 30, 35),

	-- Home indicator bar
	homeBar    = Color3.fromRGB(200, 200, 210),
}

-- App gradient palettes (GDD Module 8)
local APPS: { AppDef } = {
	{ id = "Scooters",   name = "Hulajnoga", c1 = Color3.fromRGB(0, 210, 245),   c2 = Color3.fromRGB(0, 130, 190)   },
	{ id = "Delivery",   name = "Kurier",    c1 = Color3.fromRGB(255, 175, 45),   c2 = Color3.fromRGB(235, 95, 0)    },
	{ id = "Gang",       name = "Gang",      c1 = Color3.fromRGB(195, 35, 65),    c2 = Color3.fromRGB(115, 18, 95)   },
	{ id = "Daily",      name = "Misje",     c1 = Color3.fromRGB(40, 230, 110),   c2 = Color3.fromRGB(8, 155, 55)    },
	{ id = "Protection", name = "Ochrona",   c1 = Color3.fromRGB(75, 115, 155),   c2 = Color3.fromRGB(35, 65, 95)    },
}

-- ═══════════════════════════════════════════════════════════════════════
-- UI BUILDER HELPERS
-- ═══════════════════════════════════════════════════════════════════════

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function uiStroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2) })
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function uiPadding(parent: Instance, t: number, b: number, l: number, r: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r)
	p.Parent = parent
	return p
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = font or Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextSize = size
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = parent
	return lbl
end

local function makeButton(parent: Instance, text: string, color: Color3): TextButton
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = color
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.Text = text
	btn.TextColor3 = COL.white
	btn.TextSize = 14
	btn.Parent = parent
	corner(btn, 10)
	return btn
end

-- ═══════════════════════════════════════════════════════════════════════
-- ANIMATION SYSTEM — centralized tween factory
-- ═══════════════════════════════════════════════════════════════════════

local function tweenTo(
	instance: Instance,
	duration: number,
	properties: { [string]: any },
	easing: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	maid: Maid?
): Tween
	local info = TweenInfo.new(
		duration,
		easing or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(instance, info, properties)
	if maid then maid:Give(t) end
	t:Play()
	return t
end

-- ═══════════════════════════════════════════════════════════════════════
-- SCREEN GUI CONTAINERS
-- ═══════════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "PhoneGui"
gui.DisplayOrder = 200
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "PhoneHUD"
hudGui.DisplayOrder = 100
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.Parent = playerGui

-- ═══════════════════════════════════════════════════════════════════════
-- HUD BUTTON — top-left "TELEFON [M]" pill
-- ═══════════════════════════════════════════════════════════════════════

local openButton = Instance.new("TextButton")
openButton.Name = "PhoneBtn"
openButton.Position = UDim2.new(0, 16, 0, 72)
openButton.Size = UDim2.fromOffset(120, 44)
openButton.BackgroundColor3 = COL.white
openButton.AutoButtonColor = false
openButton.Text = ""
openButton.Parent = hudGui
corner(openButton, 12)
gradient(openButton, COL.hudBg1, COL.hudBg2, 45)
local openBtnStroke = uiStroke(openButton, COL.hudStroke, 1.5, 0.5)

local openBtnLabel = makeLabel(openButton, "TELEFON", 14, Color3.fromRGB(250, 250, 255), Enum.Font.GothamBold)
openBtnLabel.Position = UDim2.fromOffset(14, 0)
openBtnLabel.Size = UDim2.new(1, -50, 1, 0)
openBtnLabel.TextXAlignment = Enum.TextXAlignment.Left

local phoneBadge = Instance.new("Frame")
phoneBadge.Size = UDim2.fromOffset(26, 26)
phoneBadge.AnchorPoint = Vector2.new(1, 0.5)
phoneBadge.Position = UDim2.new(1, -8, 0.5, 0)
phoneBadge.BackgroundColor3 = COL.white
phoneBadge.Parent = openButton
corner(phoneBadge, 6)
gradient(phoneBadge, COL.hudBadgeBg1, COL.hudBadgeBg2, 45)
local phoneBadgeLabel = makeLabel(phoneBadge, "M", 14, COL.white, Enum.Font.GothamBold)
phoneBadgeLabel.Size = UDim2.new(1, 0, 1, 0)

-- HUD hover / press micro-interactions
globalMaid:Give(openButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(openButton, 0.2, { Size = UDim2.fromOffset(126, 46) })
		tweenTo(openBtnStroke, 0.2, { Transparency = 0.1 })
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tweenTo(openButton, 0.08, { Size = UDim2.fromOffset(116, 42) })
	end
end))
globalMaid:Give(openButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(openButton, 0.2, { Size = UDim2.fromOffset(120, 44) })
		tweenTo(openBtnStroke, 0.2, { Transparency = if isPhoneOpen then 0.1 else 0.5 })
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tweenTo(openButton, 0.15, { Size = UDim2.fromOffset(126, 46) }, Enum.EasingStyle.Back)
	end
end))

-- ═══════════════════════════════════════════════════════════════════════
-- PHONE BODY — dark titanium chassis
-- ═══════════════════════════════════════════════════════════════════════

local phone = Instance.new("Frame")
phone.Name = "Phone"
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -24, 1, 80)  -- starts off-screen (below)
phone.Size = UDim2.fromOffset(PHONE_WIDTH, PHONE_HEIGHT)
phone.BackgroundColor3 = COL.bodyFrame
phone.Visible = false
phone.ClipsDescendants = false
phone.Parent = gui
corner(phone, BODY_RADIUS)

-- Titanium edge highlight — subtle outer stroke
uiStroke(phone, COL.bodyStroke, 2.5, 0.3)

-- Drop shadow (a larger dark frame behind the phone)
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 0, 0.5, 4)
shadow.Size = UDim2.new(1, 16, 1, 16)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.6
shadow.ZIndex = -1
shadow.Parent = phone
corner(shadow, BODY_RADIUS + 6)

-- Aspect ratio lock — keeps vertical smartphone shape
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = PHONE_ASPECT
aspect.AspectType = Enum.AspectType.ScaleWithParentSize
aspect.Parent = phone

-- ═══════════════════════════════════════════════════════════════════════
-- SCREEN — inner display area with wallpaper
-- ═══════════════════════════════════════════════════════════════════════

local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.AnchorPoint = Vector2.new(0.5, 0.5)
screen.Position = UDim2.new(0.5, 0, 0.5, 0)
screen.Size = UDim2.new(1, -(SCREEN_INSET * 2), 1, -(SCREEN_INSET * 2))
screen.BackgroundColor3 = COL.white
screen.ClipsDescendants = true
screen.Parent = phone
corner(screen, SCREEN_RADIUS)

-- Moody cyberpunk wallpaper gradient
gradient(screen, COL.wallTop, COL.wallBot, 170)

-- ═══════════════════════════════════════════════════════════════════════
-- DYNAMIC ISLAND (pill notch)
-- ═══════════════════════════════════════════════════════════════════════

local dynamicIsland = Instance.new("Frame")
dynamicIsland.Name = "DynamicIsland"
dynamicIsland.Size = UDim2.fromOffset(86, 24)
dynamicIsland.AnchorPoint = Vector2.new(0.5, 0)
dynamicIsland.Position = UDim2.new(0.5, 0, 0, 10)
dynamicIsland.BackgroundColor3 = COL.island
dynamicIsland.ZIndex = 100
dynamicIsland.Parent = screen
corner(dynamicIsland, 12)

-- Camera lens dot
local islandCamera = Instance.new("Frame")
islandCamera.Name = "CameraLens"
islandCamera.Size = UDim2.fromOffset(8, 8)
islandCamera.AnchorPoint = Vector2.new(0, 0.5)
islandCamera.Position = UDim2.new(1, -14, 0.5, 0)
islandCamera.BackgroundColor3 = COL.islandCam
islandCamera.ZIndex = 101
islandCamera.Parent = dynamicIsland
corner(islandCamera, 4)

-- Inner lens shimmer
local lensInner = Instance.new("Frame")
lensInner.Size = UDim2.fromOffset(4, 4)
lensInner.AnchorPoint = Vector2.new(0.5, 0.5)
lensInner.Position = UDim2.fromScale(0.5, 0.5)
lensInner.BackgroundColor3 = Color3.fromRGB(30, 35, 55)
lensInner.ZIndex = 102
lensInner.Parent = islandCamera
corner(lensInner, 2)

-- ═══════════════════════════════════════════════════════════════════════
-- STATUS BAR — clock + wifi / battery
-- ═══════════════════════════════════════════════════════════════════════

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 38)
topBar.BackgroundTransparency = 1
topBar.ZIndex = 99
topBar.Parent = screen

local clock = makeLabel(topBar, "12:00", 11, COL.white, Enum.Font.GothamBold)
clock.Position = UDim2.new(0, 16, 0, 12)
clock.Size = UDim2.fromOffset(36, 16)
clock.TextXAlignment = Enum.TextXAlignment.Left

local statusIcons = makeLabel(topBar, "⚡ 100%", 9, COL.white, Enum.Font.GothamMedium)
statusIcons.AnchorPoint = Vector2.new(1, 0)
statusIcons.Position = UDim2.new(1, -16, 0, 13)
statusIcons.Size = UDim2.fromOffset(50, 16)
statusIcons.TextXAlignment = Enum.TextXAlignment.Right

-- ═══════════════════════════════════════════════════════════════════════
-- HOME SCREEN — app grid (3 per row)
-- ═══════════════════════════════════════════════════════════════════════

local homeScreen = Instance.new("Frame")
homeScreen.Name = "HomeScreen"
homeScreen.Size = UDim2.new(1, 0, 1, 0)
homeScreen.BackgroundTransparency = 1
homeScreen.Parent = screen

local appGrid = Instance.new("Frame")
appGrid.Name = "AppGrid"
appGrid.Size = UDim2.new(1, -32, 0, 230)  -- enough for 2 rows
appGrid.AnchorPoint = Vector2.new(0.5, 0)
appGrid.Position = UDim2.new(0.5, 0, 0, 64)
appGrid.BackgroundTransparency = 1
appGrid.Parent = homeScreen

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding = UDim2.fromOffset(16, 16)
gridLayout.CellSize = UDim2.fromOffset(APP_ICON_SIZE, APP_ICON_SIZE + 22) -- icon + label
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.FillDirectionMaxCells = 3  -- EXACTLY 3 per row
gridLayout.Parent = appGrid

-- ═══════════════════════════════════════════════════════════════════════
-- APP VIEW — slides in from the right when an app is opened
-- ═══════════════════════════════════════════════════════════════════════

local appView = Instance.new("Frame")
appView.Name = "AppView"
appView.Size = UDim2.new(1, 0, 1, 0)
appView.Position = UDim2.new(1, 0, 0, 0)
appView.BackgroundColor3 = COL.appBg
appView.Visible = false
appView.ZIndex = 10
appView.Parent = screen

-- Subtle top-to-bottom gradient in app view
gradient(appView, COL.appBg, Color3.fromRGB(12, 14, 20), 180)

local appContent = Instance.new("ScrollingFrame")
appContent.Name = "Content"
appContent.Size = UDim2.new(1, 0, 1, -80)
appContent.Position = UDim2.new(0, 0, 0, 40)
appContent.BackgroundTransparency = 1
appContent.BorderSizePixel = 0
appContent.ScrollBarThickness = 2
appContent.ScrollBarImageColor3 = COL.dimmed
appContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
appContent.CanvasSize = UDim2.new()
appContent.ZIndex = 10
appContent.Parent = appView
uiPadding(appContent, 16, 16, 16, 16)

local appTitle = makeLabel(appView, "App", 20, COL.white, Enum.Font.GothamBold)
appTitle.Position = UDim2.fromOffset(16, 52)
appTitle.Size = UDim2.new(1, -32, 0, 26)
appTitle.TextXAlignment = Enum.TextXAlignment.Left
appTitle.ZIndex = 10

-- ═══════════════════════════════════════════════════════════════════════
-- HOME INDICATOR BAR — swipe home gesture target
-- ═══════════════════════════════════════════════════════════════════════

local homeBar = Instance.new("TextButton")
homeBar.Name = "HomeBar"
homeBar.Text = ""
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.Position = UDim2.new(0.5, 0, 1, -6)
homeBar.Size = UDim2.fromOffset(90, 4)
homeBar.BackgroundColor3 = COL.homeBar
homeBar.BackgroundTransparency = 0.3
homeBar.ZIndex = 110
homeBar.Parent = screen
corner(homeBar, 2)

-- ═══════════════════════════════════════════════════════════════════════
-- TOAST NOTIFICATION
-- ═══════════════════════════════════════════════════════════════════════

local toast = makeLabel(screen, "", 11, COL.white, Enum.Font.GothamBold)
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -24)
toast.Size = UDim2.new(1, -24, 0, 36)
toast.BackgroundColor3 = COL.toastBg
toast.BackgroundTransparency = 0.08
toast.ZIndex = 105
toast.Visible = false
corner(toast, 12)
uiStroke(toast, Color3.fromRGB(40, 40, 50), 1, 0.4)

-- ═══════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════

local function updateClock()
	clock.Text = os.date("%H:%M")
end

local function showToast(message: string, isError: boolean)
	toast.Text = "  " .. message
	toast.BackgroundColor3 = if isError then COL.toastError else COL.toastBg
	toast.Visible = message ~= ""
	-- Slide up + fade in
	toast.Position = UDim2.new(0.5, 0, 1, -10)
	toast.TextTransparency = 1
	tweenTo(toast, 0.25, {
		Position = UDim2.new(0.5, 0, 1, -24),
		TextTransparency = 0,
	}, Enum.EasingStyle.Back)
	local captured = message
	task.delay(2.5, function()
		if toast.Text == "  " .. captured then
			tweenTo(toast, 0.2, { TextTransparency = 1 })
			task.delay(0.2, function()
				if toast.Text == "  " .. captured then toast.Visible = false end
			end)
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
	row.BackgroundColor3 = COL.rowBg
	row.Parent = parent
	corner(row, 12)

	-- Accent stripe on left edge
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 3, 1, -8)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.new(0, 0, 0.5, 0)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	corner(stripe, 2)

	local titleLabel = makeLabel(row, titleText, 13, COL.white, Enum.Font.GothamBold)
	titleLabel.Position = UDim2.fromOffset(14, 12)
	titleLabel.Size = UDim2.new(1, -28, 0, 18)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local detailLabel = makeLabel(row, detail, 11, COL.muted, Enum.Font.GothamMedium)
	detailLabel.Position = UDim2.fromOffset(14, 34)
	detailLabel.Size = UDim2.new(1, -28, 0, 18)
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextWrapped = true

	return row
end

-- ═══════════════════════════════════════════════════════════════════════
-- APP GRID — build squircle buttons for each GDD app
-- ═══════════════════════════════════════════════════════════════════════

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

	-- Slide app view in from right
	appView.Position = UDim2.new(1, 0, 0, 0)
	appView.Visible = true
	tweenTo(appView, 0.3, { Position = UDim2.new(0, 0, 0, 0) })
	-- Parallax home screen left + fade
	tweenTo(homeScreen, 0.3, {
		Position = UDim2.new(-0.15, 0, 0, 0),
		GroupTransparency = 1,
	})
end

local function goHome()
	if currentPage == "Home" then return end
	currentPage = "Home"
	tweenTo(appView, 0.3, { Position = UDim2.new(1, 0, 0, 0) })
	tweenTo(homeScreen, 0.3, {
		Position = UDim2.new(0, 0, 0, 0),
		GroupTransparency = 0,
	})
	task.delay(0.3, function()
		if currentPage == "Home" then
			appView.Visible = false
		end
	end)
end

local function renderHomeGrid()
	-- Clean existing grid children
	for _, child in appGrid:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end

	for index, app in APPS do
		-- Container holds the icon + label
		local container = Instance.new("Frame")
		container.Name = app.id
		container.BackgroundTransparency = 1
		container.LayoutOrder = index
		container.Parent = appGrid

		-- Squircle icon button
		local btn = Instance.new("ImageButton")
		btn.Name = "Icon"
		btn.Size = UDim2.fromOffset(APP_ICON_SIZE, APP_ICON_SIZE)
		btn.BackgroundColor3 = COL.white
		btn.AutoButtonColor = false
		btn.Image = ""  -- EMPTY — asset ID injected later
		btn.ScaleType = Enum.ScaleType.Fit
		btn.Parent = container
		corner(btn, APP_CORNER)
		gradient(btn, app.c1, app.c2, 135)

		-- Subtle inner glow overlay on the top half
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		sheen.Size = UDim2.new(1, 0, 0.45, 0)
		sheen.BackgroundColor3 = COL.white
		sheen.BackgroundTransparency = 0.85
		sheen.BorderSizePixel = 0
		sheen.ZIndex = 2
		sheen.Parent = btn
		corner(sheen, APP_CORNER)

		-- Empty ImageLabel placeholder for custom icon art
		local iconImage = Instance.new("ImageLabel")
		iconImage.Name = "AppIcon"
		iconImage.Size = UDim2.new(0.6, 0, 0.6, 0)
		iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
		iconImage.Position = UDim2.fromScale(0.5, 0.5)
		iconImage.BackgroundTransparency = 1
		iconImage.Image = ""  -- EMPTY — will be set via asset ID
		iconImage.ScaleType = Enum.ScaleType.Fit
		iconImage.ZIndex = 3
		iconImage.Parent = btn

		-- App name label beneath icon
		local label = makeLabel(container, app.name, 10, Color3.fromRGB(220, 225, 235), Enum.Font.GothamMedium)
		label.Position = UDim2.new(0, -8, 0, APP_ICON_SIZE + 4)
		label.Size = UDim2.new(1, 16, 0, 14)

		-- ── Micro-interactions ──

		-- Scale wrapper for hover / press effects
		local btnScale = Instance.new("UIScale")
		btnScale.Parent = btn

		-- Hover → scale up 1.05
		globalMaid:Give(btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				tweenTo(btnScale, 0.15, { Scale = 1.05 })
			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				-- Tactile press → squish to 0.92
				tweenTo(btnScale, 0.06, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end))

		-- Release → bounce back via EasingStyle.Back
		globalMaid:Give(btn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				tweenTo(btnScale, 0.2, { Scale = 1.0 })
			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				tweenTo(btnScale, 0.25, { Scale = 1.0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end))

		-- Open app on click
		globalMaid:Give(btn.Activated:Connect(function()
			openApp(app.id)
		end))
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- APP RENDERERS — each app's inner UI
-- ═══════════════════════════════════════════════════════════════════════

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
		local row = infoRow(
			appContent,
			product.name,
			product.description,
			if isOwned then Color3.fromRGB(0, 200, 245) else Color3.fromRGB(70, 70, 75)
		)
		row.Size = UDim2.new(1, 0, 0, 80)
		local action = makeButton(
			row,
			if isOwned then "PRZYWOLAJ" else "ZABLOKOWANA",
			if isOwned then Color3.fromRGB(0, 140, 200) else Color3.fromRGB(50, 50, 55)
		)
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
		nameInput.BackgroundColor3 = Color3.fromRGB(44, 46, 54)
		nameInput.TextColor3 = COL.white
		nameInput.Font = Enum.Font.GothamMedium
		nameInput.TextSize = 13
		nameInput.PlaceholderText = "Nazwa..."
		nameInput.PlaceholderColor3 = COL.dimmed
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
	infoRow(appContent, gang.gangName or "Twoj Gang", string.format("%d/%d graczy", #gang.members, gang.maxMembers), gColor)

	for _, m in gang.members do
		local detail = if m.isLeader then "Lider" else "Czlonek"
		local row = infoRow(appContent, m.displayName, detail, if m.isLeader then gColor else Color3.fromRGB(80, 80, 85))
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
		-- Progress bar
		local fillBg = Instance.new("Frame")
		fillBg.Position = UDim2.new(0, 14, 1, -10)
		fillBg.Size = UDim2.new(1, -28, 0, 4)
		fillBg.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
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

	local c1 = if avail then (if active then Color3.fromRGB(40, 200, 100) else Color3.fromRGB(130, 130, 135)) else Color3.fromRGB(200, 40, 40)
	local txt = if active then "Ochrona Wlaczona" else "Ochrona Wylaczona"
	local det = if avail then "Blokuje udzial w PvP." else "Zablokowane dla czlonkow gangu."

	local row = infoRow(appContent, txt, det, c1)
	row.Size = UDim2.new(1, 0, 0, 100)
	local toggle = makeButton(
		row,
		if active then "WYLACZ" else "WLACZ",
		if avail then (if active then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(40, 200, 100)) else Color3.fromRGB(70, 70, 75)
	)
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 14, 1, -10)
	toggle.Size = UDim2.new(1, -28, 0, 30)
	toggle.Active = avail
	if avail then
		pageMaid:Give(toggle.Activated:Connect(function() runAction("SetPassive", not active) end))
	end
end

renderApp = function(appId: string)
	if appId == "Home" then return end
	clearAppContent()
	verticalLayout(appContent, 10)
	appTitle.Position = UDim2.fromOffset(16, 52)
	appContent.Position = UDim2.new(0, 0, 0, 88)
	appContent.Size = UDim2.new(1, 0, 1, -88)

	if appId == "Scooters" then renderScooters()
	elseif appId == "Delivery" then renderDelivery()
	elseif appId == "Gang" then renderGang()
	elseif appId == "Daily" then renderDaily()
	elseif appId == "Protection" then renderProtection()
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE — smooth slide-up from bottom
-- ═══════════════════════════════════════════════════════════════════════

local function refresh()
	task.spawn(function()
		local success, message, newState = callServer("GetState", nil)
		state = newState
		if not success then showToast(message, true) end
		if currentPage ~= "Home" then renderApp(currentPage) end
	end)
end

local function setOpen(open: boolean)
	isPhoneOpen = open
	if open then
		phone.Visible = true
		-- Start below screen edge
		phone.Position = UDim2.new(1, -24, 1, 80)
		-- Slide up with bounce
		tweenTo(phone, 0.4, {
			Position = UDim2.new(1, -24, 1, -24),
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		-- HUD button glow
		tweenTo(openBtnStroke, 0.2, { Transparency = 0 })
		refresh()
	else
		-- Slide down out of view
		tweenTo(phone, 0.25, {
			Position = UDim2.new(1, -24, 1, 80),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenTo(openBtnStroke, 0.2, { Transparency = 0.5 })
		task.delay(0.25, function()
			if not isPhoneOpen then
				phone.Visible = false
				-- Reset to home when closed
				if currentPage ~= "Home" then
					currentPage = "Home"
					appView.Visible = false
					appView.Position = UDim2.new(1, 0, 0, 0)
					homeScreen.Position = UDim2.new(0, 0, 0, 0)
					homeScreen.GroupTransparency = 0
				end
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- CONNECTIONS
-- ═══════════════════════════════════════════════════════════════════════

globalMaid:Give(openButton.Activated:Connect(function() setOpen(not isPhoneOpen) end))
globalMaid:Give(homeBar.Activated:Connect(goHome))

globalMaid:Give(UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setOpen(not isPhoneOpen)
	elseif input.KeyCode == Enum.KeyCode.Escape and isPhoneOpen then
		if currentPage ~= "Home" then goHome() else setOpen(false) end
	end
end))

globalMaid:Give(stateChanged.OnClientEvent:Connect(function()
	if phone.Visible then refresh() else showToast("Powiadomienie z gangu", false) end
end))

-- ═══════════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════════

renderHomeGrid()
updateClock()

-- Clock refresh loop
task.spawn(function()
	while gui.Parent do
		task.wait(15)
		updateClock()
	end
end)

-- ═══════════════════════════════════════════════════════════════════════
-- CLEANUP — prevent memory leaks on script destruction
-- ═══════════════════════════════════════════════════════════════════════

script.Destroying:Connect(function()
	pageMaid:Clean()
	globalMaid:Clean()
	hudGui:Destroy()
	gui:Destroy()
end)
