--!strict
--[[
	ShopClient — "Juicy" cartoony shop UI inspired by top-grossing Roblox
	simulators (Pet Sim 99 / Blade Ball / Arm Wrestle Simulator).

	Visual Framework:
	  • Chunky rounded framing with thick dark strokes for a tactile toy look
	  • UIGradient backgrounds (electric blue → deep navy)
	  • 3D extruded "SKLEP" header with shadow offset
	  • "Candy buttons" — stacked lighter-top / darker-bottom frames for depth
	  • Pulsing glowing UIStroke on featured items (KuKirin G4)

	Architecture:
	  • All purchases go through ShopRemotes/ShopRequest RemoteFunction
	    (server-authoritative — client never validates balances)
	  • Memory: every connection, tween, and spawned Instance is tracked via
	    a lightweight Maid; everything is cleaned on close/destroy
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

type Product = ShopConfig.Product
type TabId = ShopConfig.TabId
type ShopState = {
	coins: number,
	coinSystemReady: boolean,
	owned: { [string]: boolean },
}

-- ─── Maid ──────────────────────────────────────────────────────────────
type MaidTask = RBXScriptConnection | Instance | Tween
type Maid = {
	tasks: { MaidTask },
	Give: (self: Maid, task: MaidTask) -> (),
	Clean: (self: Maid) -> (),
}

local function newMaid(): Maid
	local m: any = {}
	m.tasks = {}
	function m:Give(task: MaidTask)
		table.insert(self.tasks, task)
	end
	function m:Clean()
		for _, task in self.tasks do
			if typeof(task) == "RBXScriptConnection" then
				(task :: RBXScriptConnection):Disconnect()
			elseif typeof(task) == "Instance" then
				(task :: Instance):Destroy()
			end
			-- Tweens are garbage-collected; no explicit cleanup needed
		end
		table.clear(self.tasks)
	end
	return m :: Maid
end

-- ─── Constants ─────────────────────────────────────────────────────────
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild(ShopConfig.RemoteFolderName)
	:WaitForChild(ShopConfig.RequestFunctionName) :: RemoteFunction

-- "Juicy" color palette — chunky toy aesthetic
local C = {
	-- Modal gradient (electric blue → deep navy)
	gradientTop     = Color3.fromRGB(42, 165, 255),
	gradientBottom  = Color3.fromRGB(14, 46, 98),
	-- Outer frame stroke (dark navy, thick)
	frameStroke     = Color3.fromRGB(30, 74, 122),
	-- Inner content panel
	innerBg         = Color3.fromRGB(230, 240, 252),
	innerStroke     = Color3.fromRGB(170, 200, 235),
	-- Header
	headerGrad1     = Color3.fromRGB(42, 165, 255),
	headerGrad2     = Color3.fromRGB(22, 100, 200),
	headerText      = Color3.fromRGB(255, 255, 255),
	headerShadow    = Color3.fromRGB(14, 46, 98),
	-- Sidebar
	sidebarBg       = Color3.fromRGB(32, 42, 62),
	sidebarTabIdle  = Color3.fromRGB(48, 58, 82),
	sidebarTabText  = Color3.fromRGB(170, 185, 210),
	-- Cards
	cardBg          = Color3.fromRGB(255, 255, 255),
	cardStroke      = Color3.fromRGB(210, 220, 238),
	cardText        = Color3.fromRGB(25, 35, 50),
	cardMuted       = Color3.fromRGB(110, 125, 145),
	-- Candy buttons — coins
	coinBtnTop      = Color3.fromRGB(255, 210, 50),
	coinBtnTopLight = Color3.fromRGB(255, 230, 100),
	coinBtnBevel    = Color3.fromRGB(200, 140, 15),
	coinBtnStroke   = Color3.fromRGB(160, 105, 10),
	-- Candy buttons — robux
	robuxBtnTop     = Color3.fromRGB(70, 215, 100),
	robuxBtnTopLight = Color3.fromRGB(110, 240, 140),
	robuxBtnBevel   = Color3.fromRGB(30, 140, 55),
	robuxBtnStroke  = Color3.fromRGB(20, 100, 40),
	-- Free / owned
	freeBtnTop      = Color3.fromRGB(90, 215, 255),
	freeBtnBevel    = Color3.fromRGB(40, 140, 180),
	ownedBtnTop     = Color3.fromRGB(170, 185, 200),
	ownedBtnBevel   = Color3.fromRGB(130, 145, 160),
	-- Close button
	closeBg         = Color3.fromRGB(235, 55, 50),
	closeBgLight    = Color3.fromRGB(255, 90, 80),
	closeBevel      = Color3.fromRGB(160, 28, 22),
	closeStroke     = Color3.fromRGB(120, 20, 15),
	-- Featured badge
	badgeBg         = Color3.fromRGB(255, 70, 70),
	-- Coin display
	coinGold        = Color3.fromRGB(255, 210, 50),
	-- General
	white           = Color3.fromRGB(255, 255, 255),
	dark            = Color3.fromRGB(20, 25, 35),
}

-- ─── State ─────────────────────────────────────────────────────────────
local currentTab: TabId = "Hulajnogi"
local currentState: ShopState = { coins = 0, coinSystemReady = false, owned = {} }
local busy = false
local cardMaid = newMaid()
local globalMaid = newMaid()

-- ─── UI Builder Helpers ────────────────────────────────────────────────

local function formatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1 %2")
		formatted = replaced
		if count == 0 then return formatted end
	end
end

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

local function uiPadding(parent: Instance, t: number, b: number, l: number, r: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r)
	p.Parent = parent
	return p
end

local function gradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2) })
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = font or Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextSize = size
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = parent
	return lbl
end

-- ─── Animation System ──────────────────────────────────────────────────

-- Centralized tween factory — all animations go through here so easing
-- is consistent and tweens can be tracked by the Maid.
local function tweenTo(instance: Instance, duration: number, properties: { [string]: any }, easing: Enum.EasingStyle?, direction: Enum.EasingDirection?, maid: Maid?): Tween
	local info = TweenInfo.new(
		duration,
		easing or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(instance, info, properties)
	if maid then
		maid:Give(t)
	end
	t:Play()
	return t
end

-- Hover: scale card up to 1.05 + highlight stroke
local function addHoverScale(card: Frame, strokeRef: UIStroke?, accentColor: Color3, isFeatured: boolean, maid: Maid)
	maid:Give(card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			tweenTo(card, 0.18, { Size = UDim2.new(1.05, 0, 1.05, 0) }, Enum.EasingStyle.Quad, nil, maid)
			if strokeRef then
				tweenTo(strokeRef, 0.18, {
					Color = accentColor,
					Thickness = if isFeatured then 5 else 3,
					Transparency = 0,
				}, nil, nil, maid)
			end
		end
	end))
	maid:Give(card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			tweenTo(card, 0.22, { Size = UDim2.new(1, 0, 1, 0) }, Enum.EasingStyle.Quad, nil, maid)
			if strokeRef then
				if isFeatured then
					tweenTo(strokeRef, 0.25, {
						Color = accentColor,
						Thickness = 3,
						Transparency = 0.2,
					}, nil, nil, maid)
				else
					tweenTo(strokeRef, 0.25, {
						Color = C.cardStroke,
						Thickness = 2,
						Transparency = 0,
					}, nil, nil, maid)
				end
			end
		end
	end))
end

-- Tactile press: scale down to 0.92 on MouseButton1Down, bounce back on release
local function addClickFeel(button: GuiButton, maid: Maid)
	local baseSize = button.Size
	maid:Give(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tweenTo(button, 0.08, {
				Size = UDim2.new(
					baseSize.X.Scale * 0.92, math.floor(baseSize.X.Offset * 0.92),
					baseSize.Y.Scale * 0.92, math.floor(baseSize.Y.Offset * 0.92)
				),
			}, Enum.EasingStyle.Quad, nil, maid)
		end
	end))
	maid:Give(button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tweenTo(button, 0.2, { Size = baseSize }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, maid)
		end
	end))
end

-- ─── Server Communication ──────────────────────────────────────────────

local function callServer(action: string, itemId: string?): (boolean, string, ShopState, number?)
	local ok, success, message, state, productId = pcall(function()
		return request:InvokeServer(action, itemId)
	end)
	if not ok or typeof(success) ~= "boolean" then
		return false, "Brak polaczenia ze sklepem.", currentState, nil
	end
	return success, if typeof(message) == "string" then message else "",
		if typeof(state) == "table" then state :: ShopState else currentState,
		if typeof(productId) == "number" then productId else nil
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║                        ROOT GUI STRUCTURE                           ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ─── HUD Button ────────────────────────────────────────────────────────
local shopBtn = Instance.new("TextButton")
shopBtn.Name = "ShopBtn"
shopBtn.Position = UDim2.new(0, 144, 0, 72)
shopBtn.Size = UDim2.fromOffset(120, 44)
shopBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shopBtn.AutoButtonColor = false
shopBtn.Text = ""
shopBtn.Parent = gui
corner(shopBtn, 12)
gradient(shopBtn, Color3.fromRGB(24, 26, 32), Color3.fromRGB(16, 18, 22), 45)
local shopBtnStroke = uiStroke(shopBtn, Color3.fromRGB(255, 180, 0), 1.5)
shopBtnStroke.Transparency = 0.5

local shopBtnIcon = Instance.new("TextLabel")
shopBtnIcon.BackgroundTransparency = 1
shopBtnIcon.Font = Enum.Font.GothamBold
shopBtnIcon.Text = "SKLEP"
shopBtnIcon.TextColor3 = Color3.fromRGB(250, 250, 255)
shopBtnIcon.TextSize = 14
shopBtnIcon.Position = UDim2.fromOffset(14, 0)
shopBtnIcon.Size = UDim2.new(1, -50, 1, 0)
shopBtnIcon.TextXAlignment = Enum.TextXAlignment.Left
shopBtnIcon.Parent = shopBtn

local shopBadge = Instance.new("Frame")
shopBadge.Size = UDim2.fromOffset(26, 26)
shopBadge.AnchorPoint = Vector2.new(1, 0.5)
shopBadge.Position = UDim2.new(1, -8, 0.5, 0)
shopBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shopBadge.Parent = shopBtn
corner(shopBadge, 6)
gradient(shopBadge, Color3.fromRGB(50, 50, 55), Color3.fromRGB(30, 30, 35), 45)

local shopBadgeLabel = Instance.new("TextLabel")
shopBadgeLabel.BackgroundTransparency = 1
shopBadgeLabel.Font = Enum.Font.GothamBold
shopBadgeLabel.Text = "B"
shopBadgeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
shopBadgeLabel.TextSize = 14
shopBadgeLabel.Size = UDim2.new(1, 0, 1, 0)
shopBadgeLabel.Parent = shopBadge

-- Toggle event
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "ToggleShop"
toggleEvent.Parent = gui
gui:SetAttribute("ShopOpen", false)

-- Overlay (dims background)
local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Visible = false
overlay.Parent = gui

-- ─── Main Window (outer frame — gradient blue background) ──────────────

local window = Instance.new("Frame")
window.Name = "ShopWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.88, 0, 0.82, 0)
window.BackgroundColor3 = C.gradientTop -- base; gradient overrides
window.ClipsDescendants = true
window.Parent = overlay
corner(window, 20)
uiStroke(window, C.frameStroke, 5)
gradient(window, C.gradientTop, C.gradientBottom, 90) -- electric blue → deep navy

local windowConstraint = Instance.new("UISizeConstraint")
windowConstraint.MinSize = Vector2.new(420, 440)
windowConstraint.MaxSize = Vector2.new(980, 660)
windowConstraint.Parent = window

-- Inner content panel (soft pastel)
local inner = Instance.new("Frame")
inner.Name = "Inner"
inner.AnchorPoint = Vector2.new(0.5, 0.5)
inner.Position = UDim2.fromScale(0.5, 0.5)
inner.Size = UDim2.new(1, -18, 1, -18)
inner.BackgroundColor3 = C.innerBg
inner.ClipsDescendants = true
inner.Parent = window
corner(inner, 16)
uiStroke(inner, C.innerStroke, 2)

-- ═══════════════════════════════════════════════════════════════════════
-- HEADER — 3D extruded "SKLEP" title
-- ═══════════════════════════════════════════════════════════════════════

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = C.headerGrad1
header.BorderSizePixel = 0
header.Parent = inner
corner(header, 0)
gradient(header, C.headerGrad1, C.headerGrad2, 0)

-- Title icon placeholder (empty — user will supply asset ID)
local titleIcon = Instance.new("ImageLabel")
titleIcon.Name = "TitleIcon"
titleIcon.BackgroundTransparency = 1
titleIcon.Position = UDim2.fromOffset(18, 14)
titleIcon.Size = UDim2.fromOffset(36, 36)
titleIcon.Image = "" -- EMPTY: user provides Asset ID
titleIcon.ScaleType = Enum.ScaleType.Fit
titleIcon.Parent = header

-- Title 3D Extrusion: bottom shadow layer (offset +3px Y)
local titleShadow = makeLabel(header, "SKLEP", 28, C.headerShadow, Enum.Font.GothamBlack)
titleShadow.Name = "TitleShadow"
titleShadow.Position = UDim2.fromOffset(62, 3)
titleShadow.Size = UDim2.new(0.45, 0, 1, 0)
titleShadow.TextYAlignment = Enum.TextYAlignment.Center
titleShadow.ZIndex = 1
local titleShadowStroke = Instance.new("UIStroke")
titleShadowStroke.Color = C.headerShadow
titleShadowStroke.Thickness = 2.5
titleShadowStroke.Parent = titleShadow

-- Title: top layer (white, bold, with stroke)
local titleLabel = makeLabel(header, "SKLEP", 28, C.headerText, Enum.Font.GothamBlack)
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(62, 0)
titleLabel.Size = UDim2.new(0.45, 0, 1, 0)
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.ZIndex = 2
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(18, 55, 105)
titleStroke.Thickness = 2
titleStroke.Parent = titleLabel

-- Coin balance display (header right)
local balanceFrame = Instance.new("Frame")
balanceFrame.Name = "Balance"
balanceFrame.AnchorPoint = Vector2.new(1, 0.5)
balanceFrame.Position = UDim2.new(1, -66, 0.5, 0)
balanceFrame.Size = UDim2.fromOffset(170, 36)
balanceFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
balanceFrame.BackgroundTransparency = 0.45
balanceFrame.Parent = header
corner(balanceFrame, 14)
uiStroke(balanceFrame, Color3.fromRGB(255, 200, 40), 1.5, 0.3)

-- Coin icon in balance bar (empty — user provides asset)
local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.BackgroundTransparency = 1
coinIcon.Position = UDim2.fromOffset(8, 5)
coinIcon.Size = UDim2.fromOffset(26, 26)
coinIcon.Image = "" -- EMPTY: user provides Asset ID
coinIcon.ScaleType = Enum.ScaleType.Fit
coinIcon.Parent = balanceFrame

local balanceLabel = makeLabel(balanceFrame, "0", 16, C.coinGold, Enum.Font.GothamBlack)
balanceLabel.Name = "BalanceText"
balanceLabel.Position = UDim2.fromOffset(38, 0)
balanceLabel.Size = UDim2.new(1, -46, 1, 0)
balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
balanceLabel.TextYAlignment = Enum.TextYAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════
-- CLOSE BUTTON — chunky circular red "X" with dark bevel
-- ═══════════════════════════════════════════════════════════════════════

-- Bottom bevel layer (dark red, offset +4px Y)
local closeBevel = Instance.new("Frame")
closeBevel.Name = "CloseBevel"
closeBevel.AnchorPoint = Vector2.new(1, 0.5)
closeBevel.Position = UDim2.new(1, -10, 0.5, 4)
closeBevel.Size = UDim2.fromOffset(46, 46)
closeBevel.BackgroundColor3 = C.closeBevel
closeBevel.ZIndex = 4
closeBevel.Parent = header
corner(closeBevel, 23)

-- Top face (bright red)
local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -10, 0.5, 0)
closeButton.Size = UDim2.fromOffset(46, 46)
closeButton.BackgroundColor3 = C.closeBg
closeButton.Font = Enum.Font.GothamBlack
closeButton.Text = "✕"
closeButton.TextColor3 = C.white
closeButton.TextSize = 22
closeButton.AutoButtonColor = false
closeButton.ZIndex = 5
closeButton.Parent = header
corner(closeButton, 23)
uiStroke(closeButton, C.closeStroke, 3)
gradient(closeButton, C.closeBgLight, C.closeBg, 90)

-- ═══════════════════════════════════════════════════════════════════════
-- BODY — Sidebar + Products ScrollingFrame
-- ═══════════════════════════════════════════════════════════════════════

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, 64)
body.Size = UDim2.new(1, 0, 1, -64)
body.BackgroundTransparency = 1
body.Parent = inner

-- ─── Sidebar ───────────────────────────────────────────────────────────

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 136, 1, 0)
sidebar.BackgroundColor3 = C.sidebarBg
sidebar.BorderSizePixel = 0
sidebar.Parent = body
corner(sidebar, 0)

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.FillDirection = Enum.FillDirection.Vertical
sidebarLayout.Padding = UDim.new(0, 7)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Parent = sidebar

uiPadding(sidebar, 12, 12, 8, 8)

-- ─── Products area (right of sidebar) ──────────────────────────────────

local productsArea = Instance.new("Frame")
productsArea.Name = "ProductsArea"
productsArea.Position = UDim2.new(0, 136, 0, 0)
productsArea.Size = UDim2.new(1, -136, 1, 0)
productsArea.BackgroundTransparency = 1
productsArea.Parent = body

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Products"
scroll.Size = UDim2.new(1, -16, 1, -16)
scroll.Position = UDim2.fromOffset(8, 8)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 175, 210)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = productsArea

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding = UDim2.fromOffset(12, 12)
gridLayout.CellSize = UDim2.new(0.5, -6, 0, 215)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = scroll

-- Status bar at bottom
local statusLabel = makeLabel(inner, "", 12, C.cardMuted, Enum.Font.GothamMedium)
statusLabel.Name = "StatusLabel"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -4)
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextWrapped = true
statusLabel.ZIndex = 10

-- ═══════════════════════════════════════════════════════════════════════
-- SIDEBAR TAB BUTTONS
-- ═══════════════════════════════════════════════════════════════════════

local tabAccents: { [TabId]: Color3 } = {}
local tabButtons: { [TabId]: TextButton } = {}
local tabIndicators: { [TabId]: Frame } = {}

for i, tabData in ShopConfig.Tabs do
	tabAccents[tabData.id] = tabData.accentColor

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = tabData.id
	tabBtn.LayoutOrder = i
	tabBtn.Size = UDim2.new(1, 0, 0, 44)
	tabBtn.BackgroundColor3 = C.sidebarTabIdle
	tabBtn.Font = Enum.Font.GothamBold
	tabBtn.Text = string.format("%s  %s", tabData.icon, tabData.label)
	tabBtn.TextColor3 = C.sidebarTabText
	tabBtn.TextSize = 13
	tabBtn.AutoButtonColor = false
	tabBtn.Parent = sidebar
	corner(tabBtn, 14)
	uiStroke(tabBtn, Color3.fromRGB(60, 72, 100), 2)

	-- Tab icon placeholder (empty — user provides asset)
	local tabIcon = Instance.new("ImageLabel")
	tabIcon.Name = "TabIcon"
	tabIcon.BackgroundTransparency = 1
	tabIcon.AnchorPoint = Vector2.new(0, 0.5)
	tabIcon.Position = UDim2.new(0, 6, 0.5, 0)
	tabIcon.Size = UDim2.fromOffset(22, 22)
	tabIcon.Image = "" -- EMPTY: user provides Asset ID
	tabIcon.ScaleType = Enum.ScaleType.Fit
	tabIcon.Visible = false -- hidden until user sets an image
	tabIcon.Parent = tabBtn

	-- Active indicator bar (left edge accent strip)
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.new(0, 4, 0.55, 0)
	indicator.AnchorPoint = Vector2.new(0, 0.5)
	indicator.Position = UDim2.new(0, 3, 0.5, 0)
	indicator.BackgroundColor3 = tabData.accentColor
	indicator.Visible = false
	indicator.Parent = tabBtn
	corner(indicator, 2)

	tabButtons[tabData.id] = tabBtn
	tabIndicators[tabData.id] = indicator
	addClickFeel(tabBtn, globalMaid)
end

-- ═══════════════════════════════════════════════════════════════════════
-- "KODY" (Codes) TAB — text box + redeem
-- ═══════════════════════════════════════════════════════════════════════

local kodyPlaceholder: Frame? = nil

local function renderKodyTab()
	local container = Instance.new("Frame")
	container.Name = "KodyContainer"
	container.Size = UDim2.new(1, 0, 0, 170)
	container.BackgroundColor3 = C.cardBg
	container.Parent = scroll
	corner(container, 16)
	uiStroke(container, C.cardStroke, 2)
	uiPadding(container, 16, 16, 16, 16)

	local icon = makeLabel(container, "🎁", 44, C.dark, Enum.Font.GothamBold)
	icon.Size = UDim2.new(1, 0, 0, 52)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.TextYAlignment = Enum.TextYAlignment.Center
	icon.Position = UDim2.fromOffset(0, 6)

	local desc = makeLabel(container, "Wpisz kod promocyjny aby odebrac nagrode!", 13, C.cardMuted, Enum.Font.GothamMedium)
	desc.Size = UDim2.new(1, 0, 0, 20)
	desc.Position = UDim2.fromOffset(0, 62)
	desc.TextXAlignment = Enum.TextXAlignment.Center

	local inputBox = Instance.new("TextBox")
	inputBox.Position = UDim2.new(0, 0, 0, 92)
	inputBox.Size = UDim2.new(1, -86, 0, 38)
	inputBox.BackgroundColor3 = Color3.fromRGB(240, 244, 252)
	inputBox.Font = Enum.Font.GothamBold
	inputBox.PlaceholderText = "Wpisz kod..."
	inputBox.Text = ""
	inputBox.TextColor3 = C.dark
	inputBox.TextSize = 14
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = container
	corner(inputBox, 12)
	uiStroke(inputBox, C.innerStroke, 1.5)

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.AnchorPoint = Vector2.new(1, 0)
	redeemBtn.Position = UDim2.new(1, 0, 0, 92)
	redeemBtn.Size = UDim2.fromOffset(78, 38)
	redeemBtn.BackgroundColor3 = Color3.fromRGB(56, 182, 255)
	redeemBtn.Font = Enum.Font.GothamBlack
	redeemBtn.Text = "UZYJ"
	redeemBtn.TextColor3 = C.white
	redeemBtn.TextSize = 13
	redeemBtn.AutoButtonColor = false
	redeemBtn.Parent = container
	corner(redeemBtn, 12)
	uiStroke(redeemBtn, Color3.fromRGB(28, 95, 170), 2.5)
	addClickFeel(redeemBtn, cardMaid)

	kodyPlaceholder = container
end

-- ═══════════════════════════════════════════════════════════════════════
-- CANDY BUTTON BUILDER — stacked 3D purchase buttons
-- ═══════════════════════════════════════════════════════════════════════

--[[
	Creates a "candy button" with physical 3D depth:
	  ┌────────────────────────┐  ← lighter top face (text + icon)
	  │   🪙 1 000 Coins       │     UIGradient light→base
	  ├────────────────────────┤  ← darker bottom bevel (+4px offset)
	  └────────────────────────┘     solid dark color
]]
local function createCandyButton(
	parent: Instance,
	product: Product,
	owned: boolean,
	isFree: boolean,
	unavailable: boolean,
	maid: Maid
): TextButton

	local BEVEL_OFFSET = 4
	local BTN_HEIGHT = 42

	-- Determine colors based on state
	local topColor: Color3
	local topGradLight: Color3
	local bevelColor: Color3
	local strokeColor: Color3
	local btnText: string

	if owned then
		topColor = C.ownedBtnTop
		topGradLight = Color3.fromRGB(190, 200, 215)
		bevelColor = C.ownedBtnBevel
		strokeColor = Color3.fromRGB(110, 120, 135)
		btnText = "✓ POSIADASZ"
	elseif isFree then
		topColor = C.freeBtnTop
		topGradLight = Color3.fromRGB(140, 235, 255)
		bevelColor = C.freeBtnBevel
		strokeColor = Color3.fromRGB(30, 100, 135)
		btnText = "DARMOWA"
	elseif unavailable then
		topColor = C.ownedBtnTop
		topGradLight = Color3.fromRGB(190, 200, 215)
		bevelColor = C.ownedBtnBevel
		strokeColor = Color3.fromRGB(110, 120, 135)
		btnText = "WKROTCE"
	elseif product.currency == "Robux" then
		topColor = C.robuxBtnTop
		topGradLight = C.robuxBtnTopLight
		bevelColor = C.robuxBtnBevel
		strokeColor = C.robuxBtnStroke
		btnText = string.format("%s R$", formatNumber(product.price))
	else
		topColor = C.coinBtnTop
		topGradLight = C.coinBtnTopLight
		bevelColor = C.coinBtnBevel
		strokeColor = C.coinBtnStroke
		btnText = string.format("%s Coins", formatNumber(product.price))
	end

	-- Wrapper (clickable area)
	local wrapper = Instance.new("TextButton")
	wrapper.Name = "CandyBtn"
	wrapper.AnchorPoint = Vector2.new(0.5, 1)
	wrapper.Position = UDim2.new(0.5, 0, 1, -10)
	wrapper.Size = UDim2.new(1, -20, 0, BTN_HEIGHT + BEVEL_OFFSET)
	wrapper.BackgroundTransparency = 1
	wrapper.Text = ""
	wrapper.AutoButtonColor = false
	wrapper.Parent = parent

	-- Bottom bevel frame (dark, offset down)
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.AnchorPoint = Vector2.new(0.5, 1)
	bevel.Position = UDim2.new(0.5, 0, 1, 0)
	bevel.Size = UDim2.new(1, 0, 0, BTN_HEIGHT)
	bevel.BackgroundColor3 = bevelColor
	bevel.Parent = wrapper
	corner(bevel, 14)

	-- Top face frame (bright gradient)
	local topFace = Instance.new("Frame")
	topFace.Name = "TopFace"
	topFace.AnchorPoint = Vector2.new(0.5, 0)
	topFace.Position = UDim2.new(0.5, 0, 0, 0)
	topFace.Size = UDim2.new(1, 0, 0, BTN_HEIGHT)
	topFace.BackgroundColor3 = topColor
	topFace.Parent = wrapper
	corner(topFace, 14)
	uiStroke(topFace, strokeColor, 3)
	gradient(topFace, topGradLight, topColor, 90)

	-- Currency icon placeholder inside top face (empty — user provides asset)
	local currencyIcon = Instance.new("ImageLabel")
	currencyIcon.Name = "CurrencyIcon"
	currencyIcon.BackgroundTransparency = 1
	currencyIcon.AnchorPoint = Vector2.new(0, 0.5)
	currencyIcon.Position = UDim2.new(0, 12, 0.5, 0)
	currencyIcon.Size = UDim2.fromOffset(22, 22)
	currencyIcon.Image = "" -- EMPTY: user provides Coin / Premium gem Asset ID
	currencyIcon.ScaleType = Enum.ScaleType.Fit
	currencyIcon.Parent = topFace

	-- Button text (price label)
	local priceLabel = makeLabel(topFace, btnText, 15, C.white, Enum.Font.GothamBlack)
	priceLabel.Name = "PriceText"
	priceLabel.Size = UDim2.new(1, -12, 1, 0)
	priceLabel.TextXAlignment = Enum.TextXAlignment.Center
	priceLabel.TextYAlignment = Enum.TextYAlignment.Center
	-- 3D text stroke
	local priceLblStroke = Instance.new("UIStroke")
	priceLblStroke.Color = strokeColor
	priceLblStroke.Thickness = 1.5
	priceLblStroke.Parent = priceLabel

	-- Hover + press animations on the candy button wrapper
	if not owned and not unavailable then
		local baseBtnSize = wrapper.Size
		maid:Give(wrapper.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				tweenTo(wrapper, 0.15, {
					Size = UDim2.new(baseBtnSize.X.Scale, baseBtnSize.X.Offset + 4,
						baseBtnSize.Y.Scale, baseBtnSize.Y.Offset + 2),
				}, Enum.EasingStyle.Quad, nil, maid)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- Press: push top face down toward bevel (flatten the 3D)
				tweenTo(topFace, 0.06, {
					Position = UDim2.new(0.5, 0, 0, BEVEL_OFFSET),
				}, Enum.EasingStyle.Quad, nil, maid)
				tweenTo(wrapper, 0.06, {
					Size = UDim2.new(baseBtnSize.X.Scale, baseBtnSize.X.Offset - 2,
						baseBtnSize.Y.Scale, baseBtnSize.Y.Offset),
				}, Enum.EasingStyle.Quad, nil, maid)
			end
		end))
		maid:Give(wrapper.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				tweenTo(wrapper, 0.2, { Size = baseBtnSize }, Enum.EasingStyle.Quad, nil, maid)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- Release: bounce top face back up
				tweenTo(topFace, 0.2, {
					Position = UDim2.new(0.5, 0, 0, 0),
				}, Enum.EasingStyle.Back, Enum.EasingDirection.Out, maid)
				tweenTo(wrapper, 0.2, { Size = baseBtnSize }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, maid)
			end
		end))
	end

	return wrapper
end

-- ═══════════════════════════════════════════════════════════════════════
-- PRODUCT CARD BUILDER
-- ═══════════════════════════════════════════════════════════════════════

local renderProducts: () -> ()

local function setStatus(message: string, isError: boolean)
	statusLabel.Text = message
	statusLabel.TextColor3 = if isError then C.closeBg else Color3.fromRGB(40, 160, 80)
end

local function purchase(product: Product)
	if busy then return end
	busy = true
	setStatus("Sprawdzanie zakupu...", false)

	task.spawn(function()
		local action = if product.currency == "Coins" then "PurchaseCoins" else "PrepareRobux"
		local success, message, state, productId = callServer(action, product.id)
		currentState = state
		balanceLabel.Text = formatNumber(state.coins)
		if success and product.currency == "Robux" and productId then
			MarketplaceService:PromptGamePassPurchase(player, productId)
			setStatus("Potwierdz zakup w oknie Roblox.", false)
		else
			setStatus(message, not success)
		end
		busy = false
		renderProducts()
	end)
end

local function createProductCard(product: Product, order: number)
	local owned = currentState.owned[product.id] == true
	local unavailable = product.currency == "Robux" and (product.productId or 0) <= 0
	local isFree = product.price == 0 and product.currency == "Coins"
	local isFeatured = product.featured == true

	-- Grid cell wrapper (prevents reflow during tween)
	local cellWrapper = Instance.new("Frame")
	cellWrapper.Name = product.id .. "_Cell"
	cellWrapper.LayoutOrder = order
	cellWrapper.BackgroundTransparency = 1
	cellWrapper.Parent = scroll

	-- Card frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = C.cardBg
	card.ClipsDescendants = false
	card.Parent = cellWrapper
	corner(card, 16)

	-- Stroke: featured items get pulsing glow, others get subtle border
	local cardStrokeRef: UIStroke
	if isFeatured then
		cardStrokeRef = uiStroke(card, product.accent, 3, 0.15)
		-- Pulsing glow animation on featured card stroke
		local glowTween = TweenService:Create(cardStrokeRef,
			TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.7 }
		)
		glowTween:Play()
		cardMaid:Give(cardStrokeRef)
	else
		cardStrokeRef = uiStroke(card, C.cardStroke, 2)
	end

	-- Top accent gradient bar
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(1, 0, 0, 6)
	accentBar.BackgroundColor3 = product.accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = card
	local accentBarCorner = Instance.new("UICorner")
	accentBarCorner.CornerRadius = UDim.new(0, 16)
	accentBarCorner.Parent = accentBar

	-- Featured badge ("⭐ POLECANE")
	if isFeatured then
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0, 42, 0, 6)
		badge.Size = UDim2.fromOffset(84, 21)
		badge.BackgroundColor3 = C.badgeBg
		badge.Rotation = -8
		badge.ZIndex = 6
		badge.Parent = card
		corner(badge, 6)

		local badgeText = makeLabel(badge, "⭐ POLECANE", 9, C.white, Enum.Font.GothamBlack)
		badgeText.Size = UDim2.fromScale(1, 1)
		badgeText.TextXAlignment = Enum.TextXAlignment.Center
		badgeText.TextYAlignment = Enum.TextYAlignment.Center
		badgeText.ZIndex = 6
	end

	-- Product graphic placeholder (empty — user provides Asset ID)
	local productGraphic = Instance.new("ImageLabel")
	productGraphic.Name = "ProductGraphic"
	productGraphic.AnchorPoint = Vector2.new(0.5, 0)
	productGraphic.Position = UDim2.new(0.5, 0, 0, 16)
	productGraphic.Size = UDim2.fromOffset(72, 72)
	productGraphic.BackgroundTransparency = 1
	productGraphic.Image = product.imageId or "" -- EMPTY: user provides Asset ID
	productGraphic.ScaleType = Enum.ScaleType.Fit
	productGraphic.Parent = card

	-- Product name
	local nameLabel = makeLabel(card, product.name, 14, C.cardText, Enum.Font.GothamBlack)
	nameLabel.Name = "ProductName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 0, 94)
	nameLabel.Size = UDim2.new(1, -24, 0, 20)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	-- Description
	local descLabel = makeLabel(card, product.description, 11, C.cardMuted, Enum.Font.GothamMedium)
	descLabel.Name = "Description"
	descLabel.AnchorPoint = Vector2.new(0.5, 0)
	descLabel.Position = UDim2.new(0.5, 0, 0, 114)
	descLabel.Size = UDim2.new(1, -24, 0, 16)
	descLabel.TextXAlignment = Enum.TextXAlignment.Center
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd

	-- Speed badge for scooters
	if product.speed then
		local speedBadge = Instance.new("Frame")
		speedBadge.Name = "SpeedBadge"
		speedBadge.AnchorPoint = Vector2.new(0.5, 0)
		speedBadge.Position = UDim2.new(0.5, 0, 0, 132)
		speedBadge.Size = UDim2.fromOffset(90, 24)
		speedBadge.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
		speedBadge.Parent = card
		corner(speedBadge, 8)
		uiStroke(speedBadge, product.accent, 1.5)

		local speedText = makeLabel(speedBadge, string.format("⚡ %d km/h", product.speed), 11, product.accent, Enum.Font.GothamBlack)
		speedText.Size = UDim2.fromScale(1, 1)
		speedText.TextXAlignment = Enum.TextXAlignment.Center
		speedText.TextYAlignment = Enum.TextYAlignment.Center
	end

	-- Candy purchase button
	local candyBtn = createCandyButton(card, product, owned, isFree, unavailable, cardMaid)

	-- Wire purchase action
	if not owned and not unavailable then
		cardMaid:Give(candyBtn.Activated:Connect(function()
			purchase(product)
		end))
	end

	-- Hover scale + stroke highlight on the entire card
	addHoverScale(card, cardStrokeRef, product.accent, isFeatured, cardMaid)
end

-- ═══════════════════════════════════════════════════════════════════════
-- RENDER PRODUCTS FOR ACTIVE TAB
-- ═══════════════════════════════════════════════════════════════════════

renderProducts = function()
	-- Clean up old cards
	cardMaid:Clean()
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Update tab visuals with smooth transitions
	for tabId, tabBtn in tabButtons do
		local isActive = tabId == currentTab
		local accent = tabAccents[tabId]

		tweenTo(tabBtn, 0.22, {
			BackgroundColor3 = if isActive then accent else C.sidebarTabIdle,
			TextColor3 = if isActive then C.dark else C.sidebarTabText,
		}, Enum.EasingStyle.Quad)

		local indicator = tabIndicators[tabId]
		if indicator then
			indicator.Visible = isActive
		end
	end

	-- Kody tab renders its own special UI
	if currentTab == "Kody" then
		renderKodyTab()
		return
	end

	-- Render product cards
	local products = ShopConfig.GetProductsByTab(currentTab)
	for index, product in products do
		createProductCard(product, index)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE — modal spring animation
-- ═══════════════════════════════════════════════════════════════════════

local function setOpen(open: boolean)
	overlay.Visible = open
	gui:SetAttribute("ShopOpen", open)
	if open then
		-- Spring open: start at 0.8 scale, bounce to 1.0
		window.Size = UDim2.new(0.70, 0, 0.66, 0)
		tweenTo(window, 0.35, {
			Size = UDim2.new(0.88, 0, 0.82, 0),
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		-- Overlay fade in
		overlay.BackgroundTransparency = 1
		tweenTo(overlay, 0.25, { BackgroundTransparency = 0.35 }, Enum.EasingStyle.Quad)
		tweenTo(shopBtnStroke, 0.2, { Transparency = 0 }, Enum.EasingStyle.Quad)

		-- Fetch latest state from server
		task.spawn(function()
			local success, message, state = callServer("GetState", nil)
			currentState = state
			balanceLabel.Text = formatNumber(state.coins)
			if not state.coinSystemReady then
				setStatus("Saldo pojawi sie po podlaczeniu systemu Coinow.", false)
			elseif not success then
				setStatus(message, true)
			else
				setStatus("", false)
			end
			renderProducts()
		end)
	else
		-- Spring close
		tweenTo(window, 0.2, {
			Size = UDim2.new(0.72, 0, 0.68, 0),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenTo(overlay, 0.15, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		tweenTo(shopBtnStroke, 0.2, { Transparency = 0.5 }, Enum.EasingStyle.Quad)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- CONNECTIONS
-- ═══════════════════════════════════════════════════════════════════════

globalMaid:Give(toggleEvent.Event:Connect(function()
	setOpen(not overlay.Visible)
end))

globalMaid:Give(shopBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(shopBtn, 0.2, { Size = UDim2.fromOffset(126, 46) }, Enum.EasingStyle.Quad)
		tweenTo(shopBtnStroke, 0.2, { Transparency = 0.1 }, Enum.EasingStyle.Quad)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tweenTo(shopBtn, 0.1, { Size = UDim2.fromOffset(116, 42) }, Enum.EasingStyle.Quad)
	end
end))

globalMaid:Give(shopBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(shopBtn, 0.2, { Size = UDim2.fromOffset(120, 44) }, Enum.EasingStyle.Quad)
		tweenTo(shopBtnStroke, 0.2, { Transparency = if overlay.Visible then 0.1 else 0.5 }, Enum.EasingStyle.Quad)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tweenTo(shopBtn, 0.1, { Size = UDim2.fromOffset(126, 46) }, Enum.EasingStyle.Quad)
	end
end))

globalMaid:Give(shopBtn.Activated:Connect(function()
	setOpen(not overlay.Visible)
end))

-- Close button: tactile press + close
globalMaid:Give(closeButton.Activated:Connect(function()
	tweenTo(closeButton, 0.08, {
		Size = UDim2.fromOffset(38, 38),
	}, Enum.EasingStyle.Quad)
	task.delay(0.08, function()
		tweenTo(closeButton, 0.2, {
			Size = UDim2.fromOffset(46, 46),
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	setOpen(false)
end))

-- Close hover effect on the close button
globalMaid:Give(closeButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(closeButton, 0.12, {
			Size = UDim2.fromOffset(50, 50),
		}, Enum.EasingStyle.Quad)
	end
end))
globalMaid:Give(closeButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		tweenTo(closeButton, 0.15, {
			Size = UDim2.fromOffset(46, 46),
		}, Enum.EasingStyle.Quad)
	end
end))

-- Overlay click closes
globalMaid:Give(overlay.Activated:Connect(function()
	setOpen(false)
end))

-- Prevent click-through on window
inner.InputBegan:Connect(function() end)
window.InputBegan:Connect(function() end)

-- Tab switching
for tabId, tabBtn in tabButtons do
	globalMaid:Give(tabBtn.Activated:Connect(function()
		if currentTab == tabId then return end
		currentTab = tabId
		renderProducts()
	end))
end

-- Keyboard shortcuts
-- Escape closes shop, B key toggles shop
globalMaid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() then return end

	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not overlay.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and overlay.Visible then
		setOpen(false)
	end
end))

-- ═══════════════════════════════════════════════════════════════════════
-- RESPONSIVE LAYOUT
-- ═══════════════════════════════════════════════════════════════════════

local function updateLayout()
	local w = window.AbsoluteSize.X
	local compact = w < 580

	if compact then
		sidebar.Size = UDim2.new(0, 105, 1, 0)
		productsArea.Position = UDim2.new(0, 105, 0, 0)
		productsArea.Size = UDim2.new(1, -105, 1, 0)
		gridLayout.CellSize = UDim2.new(1, 0, 0, 200)
	else
		sidebar.Size = UDim2.new(0, 136, 1, 0)
		productsArea.Position = UDim2.new(0, 136, 0, 0)
		productsArea.Size = UDim2.new(1, -136, 1, 0)
		gridLayout.CellSize = UDim2.new(0.5, -6, 0, 215)
	end

	for _, tabBtn in tabButtons do
		tabBtn.TextSize = if compact then 11 else 13
	end
end

globalMaid:Give(window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))
updateLayout()
renderProducts()

-- ═══════════════════════════════════════════════════════════════════════
-- CLEANUP — prevent memory leaks on script destruction
-- ═══════════════════════════════════════════════════════════════════════

script.Destroying:Connect(function()
	cardMaid:Clean()
	globalMaid:Clean()
	gui:Destroy()
end)
