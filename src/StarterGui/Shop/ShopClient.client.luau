--!strict
--[[
	ShopClient — Vibrant cartoony shop UI inspired by top-grossing Roblox
	simulators (Pet Sim 99 / Blade Ball / Arm Wrestle Simulator).

	Architecture:
	  • All purchases go through the existing ShopRemotes/ShopRequest
	    RemoteFunction (server-authoritative).
	  • Memory: every connection, tween, and UI element is tracked and
	    cleaned up via a lightweight Maid on close/destroy.
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
type Maid = {
	tasks: { RBXScriptConnection | Instance | Tween },
	Give: (self: Maid, task: RBXScriptConnection | Instance | Tween) -> (),
	Clean: (self: Maid) -> (),
}
local function newMaid(): Maid
	local m: any = {}
	m.tasks = {}
	function m:Give(task: RBXScriptConnection | Instance | Tween)
		table.insert(self.tasks, task)
	end
	function m:Clean()
		for _, task in self.tasks do
			if typeof(task) == "RBXScriptConnection" then
				task:Disconnect()
			elseif typeof(task) == "Instance" then
				task:Destroy()
			end
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

-- Vibrant color palette
local C = {
	-- Outer frame
	frameBg    = Color3.fromRGB(56, 182, 255),   -- electric sky blue
	frameStroke = Color3.fromRGB(30, 74, 122),    -- dark navy stroke
	-- Inner panel
	innerBg     = Color3.fromRGB(234, 244, 255),  -- soft pastel blue-white
	innerStroke = Color3.fromRGB(180, 210, 240),
	-- Header
	headerGrad1 = Color3.fromRGB(56, 182, 255),
	headerGrad2 = Color3.fromRGB(30, 120, 200),
	headerText  = Color3.fromRGB(255, 255, 255),
	-- Sidebar
	sidebarBg   = Color3.fromRGB(40, 50, 70),
	-- Cards
	cardBg      = Color3.fromRGB(255, 255, 255),
	cardStroke  = Color3.fromRGB(220, 228, 240),
	cardText    = Color3.fromRGB(30, 40, 55),
	cardMuted   = Color3.fromRGB(120, 130, 150),
	-- Buttons
	coinBtn     = Color3.fromRGB(255, 200, 40),
	coinBtnBevel = Color3.fromRGB(200, 140, 15),
	robuxBtn    = Color3.fromRGB(50, 200, 100),
	robuxBtnBevel = Color3.fromRGB(25, 140, 60),
	freeBtn     = Color3.fromRGB(100, 220, 255),
	ownedBtn    = Color3.fromRGB(180, 190, 200),
	-- Close
	closeBg     = Color3.fromRGB(235, 60, 55),
	closeStroke = Color3.fromRGB(160, 30, 25),
	-- Badge
	badgeBg     = Color3.fromRGB(255, 80, 80),
	-- Coin display
	coinGold    = Color3.fromRGB(255, 210, 50),
	-- Text
	white       = Color3.fromRGB(255, 255, 255),
	dark        = Color3.fromRGB(25, 30, 40),
}

-- ─── State ─────────────────────────────────────────────────────────────
local currentTab: TabId = "Hulajnogi"
local currentState: ShopState = { coins = 0, coinSystemReady = false, owned = {} }
local busy = false
local cardMaid = newMaid()
local globalMaid = newMaid()

-- ─── Helpers ───────────────────────────────────────────────────────────

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

local function padding(parent: Instance, t: number, b: number, l: number, r: number): UIPadding
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
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = parent
	return lbl
end

local function gradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2) })
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Tactile click tween: scale down on press, bounce back on release
local function addClickFeel(button: GuiButton, maid: Maid)
	maid:Give(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local t = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				Size = UDim2.new(button.Size.X.Scale * 0.92, math.floor(button.Size.X.Offset * 0.92),
					button.Size.Y.Scale * 0.92, math.floor(button.Size.Y.Offset * 0.92)),
			})
			t:Play()
		end
	end))
	maid:Give(button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local t = TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
				Size = button.Size,
			})
			t:Play()
		end
	end))
end

local function callServer(action: string, itemId: string?): (boolean, string, ShopState, number?)
	local ok, success, message, state, productId = pcall(function()
		return request:InvokeServer(action, itemId)
	end)
	if not ok or typeof(success) ~= "boolean" or typeof(state) ~= "table" then
		return false, "Brak polaczenia ze sklepem.", currentState, nil
	end
	return success, if typeof(message) == "string" then message else "",
		state :: ShopState, if typeof(productId) == "number" then productId else nil
end

-- ─── Root GUI ──────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Toggle event: fired by the ActionHUD to open/close the shop
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

-- ─── Main Window (outer frame = bright blue border) ────────────────────

local window = Instance.new("Frame")
window.Name = "ShopWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.88, 0, 0.82, 0)
window.BackgroundColor3 = C.frameBg
window.ClipsDescendants = true
window.Parent = overlay
corner(window, 22)
uiStroke(window, C.frameStroke, 4)

local windowConstraint = Instance.new("UISizeConstraint")
windowConstraint.MinSize = Vector2.new(400, 420)
windowConstraint.MaxSize = Vector2.new(960, 640)
windowConstraint.Parent = window

-- Inner content panel (cream/light pastel)
local inner = Instance.new("Frame")
inner.Name = "Inner"
inner.AnchorPoint = Vector2.new(0.5, 0.5)
inner.Position = UDim2.new(0.5, 0, 0.5, 0)
inner.Size = UDim2.new(1, -16, 1, -16)
inner.BackgroundColor3 = C.innerBg
inner.ClipsDescendants = true
inner.Parent = window
corner(inner, 16)
uiStroke(inner, C.innerStroke, 2)

-- ─── Header ────────────────────────────────────────────────────────────

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 62)
header.BackgroundColor3 = C.headerGrad1
header.BorderSizePixel = 0
header.Parent = inner
corner(header, 0)
gradient(header, C.headerGrad1, C.headerGrad2, 0)

-- Title with icon (Top Layer)
local titleLabel = makeLabel(header, "🛍️  SKLEP", 26, C.headerText, Enum.Font.GothamBlack)
titleLabel.Position = UDim2.fromOffset(20, -2)
titleLabel.Size = UDim2.new(0.5, 0, 1, 0)
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.ZIndex = 2
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(20, 60, 110)
titleStroke.Thickness = 2
titleStroke.Parent = titleLabel

-- Title 3D Extrusion (Bottom Layer)
local titleShadow = makeLabel(header, "🛍️  SKLEP", 26, Color3.fromRGB(20, 60, 110), Enum.Font.GothamBlack)
titleShadow.Position = UDim2.fromOffset(20, 2)
titleShadow.Size = UDim2.new(0.5, 0, 1, 0)
titleShadow.TextYAlignment = Enum.TextYAlignment.Center
titleShadow.ZIndex = 1
local titleShadowStroke = Instance.new("UIStroke")
titleShadowStroke.Color = Color3.fromRGB(20, 60, 110)
titleShadowStroke.Thickness = 2
titleShadowStroke.Parent = titleShadow

-- Coin balance display
local balanceFrame = Instance.new("Frame")
balanceFrame.Name = "Balance"
balanceFrame.AnchorPoint = Vector2.new(1, 0.5)
balanceFrame.Position = UDim2.new(1, -60, 0.5, 0)
balanceFrame.Size = UDim2.fromOffset(170, 34)
balanceFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
balanceFrame.BackgroundTransparency = 0.5
balanceFrame.Parent = header
corner(balanceFrame, 12)

local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.BackgroundTransparency = 1
coinIcon.Position = UDim2.fromOffset(10, 5)
coinIcon.Size = UDim2.fromOffset(24, 24)
coinIcon.Image = "rbxassetid://0" -- TODO: Wstaw asset ID ikony coina
coinIcon.Parent = balanceFrame

local balanceLabel = makeLabel(balanceFrame, "0", 15, C.coinGold, Enum.Font.GothamBlack)
balanceLabel.Position = UDim2.fromOffset(36, 0)
balanceLabel.Size = UDim2.new(1, -42, 1, 0)
balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
balanceLabel.TextYAlignment = Enum.TextYAlignment.Center

-- Close button graphic
local closeButton = Instance.new("ImageButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -12, 0.5, 0)
closeButton.Size = UDim2.fromOffset(48, 48)
closeButton.BackgroundTransparency = 1
closeButton.Image = "rbxassetid://0" -- TODO: Wstaw asset ID przycisku zamykania
closeButton.ZIndex = 5
closeButton.Parent = header

-- ─── Layout: Sidebar + Products ────────────────────────────────────────

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, 62)
body.Size = UDim2.new(1, 0, 1, -62)
body.BackgroundTransparency = 1
body.Parent = inner

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 130, 1, 0)
sidebar.BackgroundColor3 = C.sidebarBg
sidebar.BorderSizePixel = 0
sidebar.Parent = body
corner(sidebar, 0)

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.FillDirection = Enum.FillDirection.Vertical
sidebarLayout.Padding = UDim.new(0, 6)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Parent = sidebar

padding(sidebar, 10, 10, 8, 8)

-- Products area (right of sidebar)
local productsArea = Instance.new("Frame")
productsArea.Name = "ProductsArea"
productsArea.Position = UDim2.new(0, 130, 0, 0)
productsArea.Size = UDim2.new(1, -130, 1, 0)
productsArea.BackgroundTransparency = 1
productsArea.Parent = body

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Products"
scroll.Size = UDim2.new(1, -16, 1, -16)
scroll.Position = UDim2.fromOffset(8, 8)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(160, 180, 210)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = productsArea

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding = UDim2.fromOffset(10, 10)
gridLayout.CellSize = UDim2.new(0.5, -5, 0, 180)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = scroll

-- Status bar at bottom
local statusLabel = makeLabel(inner, "", 12, C.cardMuted, Enum.Font.GothamMedium)
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -4)
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextWrapped = true
statusLabel.ZIndex = 10

-- ─── Tab buttons ───────────────────────────────────────────────────────

local tabAccents: { [TabId]: Color3 } = {}
local tabButtons: { [TabId]: TextButton } = {}
local tabIndicators: { [TabId]: Frame } = {}

for i, tabData in ShopConfig.Tabs do
	tabAccents[tabData.id] = tabData.accentColor

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = tabData.id
	tabBtn.LayoutOrder = i
	tabBtn.Size = UDim2.new(1, 0, 0, 42)
	tabBtn.BackgroundColor3 = Color3.fromRGB(55, 65, 90)
	tabBtn.Font = Enum.Font.GothamBold
	tabBtn.Text = string.format("%s  %s", tabData.icon, tabData.label)
	tabBtn.TextColor3 = Color3.fromRGB(180, 190, 210)
	tabBtn.TextSize = 13
	tabBtn.AutoButtonColor = false
	tabBtn.Parent = sidebar
	corner(tabBtn, 10)

	-- Active indicator bar (left edge)
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.new(0, 4, 0.6, 0)
	indicator.AnchorPoint = Vector2.new(0, 0.5)
	indicator.Position = UDim2.new(0, 2, 0.5, 0)
	indicator.BackgroundColor3 = tabData.accentColor
	indicator.Visible = false
	indicator.Parent = tabBtn
	corner(indicator, 2)

	tabButtons[tabData.id] = tabBtn
	tabIndicators[tabData.id] = indicator
	addClickFeel(tabBtn, globalMaid)
end

-- ─── Kody (codes) placeholder ──────────────────────────────────────────

local kodyPlaceholder: Frame? = nil

local function renderKodyTab()
	-- Codes tab: just a text box + redeem button
	local container = Instance.new("Frame")
	container.Name = "KodyContainer"
	container.Size = UDim2.new(1, 0, 0, 160)
	container.BackgroundColor3 = C.cardBg
	container.Parent = scroll
	corner(container, 14)
	uiStroke(container, C.cardStroke, 2)
	padding(container, 16, 16, 16, 16)

	local icon = makeLabel(container, "🎁", 40, C.dark, Enum.Font.GothamBold)
	icon.Size = UDim2.new(1, 0, 0, 50)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.TextYAlignment = Enum.TextYAlignment.Center
	icon.Position = UDim2.fromOffset(0, 8)

	local desc = makeLabel(container, "Wpisz kod promocyjny aby odebrac nagrode!", 13, C.cardMuted, Enum.Font.GothamMedium)
	desc.Size = UDim2.new(1, 0, 0, 20)
	desc.Position = UDim2.fromOffset(0, 62)
	desc.TextXAlignment = Enum.TextXAlignment.Center

	local inputBox = Instance.new("TextBox")
	inputBox.Position = UDim2.new(0, 0, 0, 90)
	inputBox.Size = UDim2.new(1, -80, 0, 36)
	inputBox.BackgroundColor3 = Color3.fromRGB(240, 244, 250)
	inputBox.Font = Enum.Font.GothamBold
	inputBox.PlaceholderText = "Wpisz kod..."
	inputBox.Text = ""
	inputBox.TextColor3 = C.dark
	inputBox.TextSize = 14
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = container
	corner(inputBox, 10)
	uiStroke(inputBox, C.innerStroke, 1)

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.AnchorPoint = Vector2.new(1, 0)
	redeemBtn.Position = UDim2.new(1, 0, 0, 90)
	redeemBtn.Size = UDim2.fromOffset(72, 36)
	redeemBtn.BackgroundColor3 = Color3.fromRGB(56, 182, 255)
	redeemBtn.Font = Enum.Font.GothamBlack
	redeemBtn.Text = "UZYJ"
	redeemBtn.TextColor3 = C.white
	redeemBtn.TextSize = 13
	redeemBtn.Parent = container
	corner(redeemBtn, 10)
	uiStroke(redeemBtn, Color3.fromRGB(30, 100, 170), 2)
	addClickFeel(redeemBtn, cardMaid)

	kodyPlaceholder = container
end

-- ─── Product card builder ──────────────────────────────────────────────

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

	-- Layout cell for Grid (prevents reflow during tween)
	local cellWrapper = Instance.new("Frame")
	cellWrapper.Name = product.id .. "_Cell"
	cellWrapper.LayoutOrder = order
	cellWrapper.BackgroundTransparency = 1
	cellWrapper.Parent = scroll

	-- Card frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = C.cardBg
	card.Parent = cellWrapper
	corner(card, 14)

	-- Featured items get a glowing animated stroke
	if isFeatured then
		local glow = uiStroke(card, product.accent, 3)
		glow.Transparency = 0.2
		-- Pulse glow
		local glowTween = TweenService:Create(glow, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Transparency = 0.7,
		})
		glowTween:Play()
		cardMaid:Give(glow)
	else
		uiStroke(card, C.cardStroke, 1.5)
	end

	-- Top accent gradient bar
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(1, 0, 0, 6)
	accentBar.BackgroundColor3 = product.accent
	accentBar.BorderSizePixel = 0
	accentBar.Parent = card
	-- Top corners only
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 14)
	accentCorner.Parent = accentBar

	-- Product name
	local nameLabel = makeLabel(card, product.name, 14, C.cardText, Enum.Font.GothamBlack)
	nameLabel.Position = UDim2.fromOffset(14, 16)
	nameLabel.Size = UDim2.new(1, -28, 0, 20)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	-- Description
	local descLabel = makeLabel(card, product.description, 11, C.cardMuted, Enum.Font.GothamMedium)
	descLabel.Position = UDim2.fromOffset(14, 38)
	descLabel.Size = UDim2.new(1, -28, 0, 16)
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd

	-- Speed badge for scooters
	if product.speed then
		local speedBadge = Instance.new("Frame")
		speedBadge.AnchorPoint = Vector2.new(1, 0)
		speedBadge.Position = UDim2.new(1, -12, 0, 56)
		speedBadge.Size = UDim2.fromOffset(80, 24)
		speedBadge.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
		speedBadge.Parent = card
		corner(speedBadge, 8)
		uiStroke(speedBadge, product.accent, 1.5)

		local speedText = makeLabel(speedBadge, string.format("⚡ %d km/h", product.speed), 11, product.accent, Enum.Font.GothamBlack)
		speedText.Size = UDim2.new(1, 0, 1, 0)
		speedText.TextXAlignment = Enum.TextXAlignment.Center
		speedText.TextYAlignment = Enum.TextYAlignment.Center
	end

	-- Featured badge ("POLECANE")
	if isFeatured then
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0, 38, 0, 6)
		badge.Size = UDim2.fromOffset(80, 20)
		badge.BackgroundColor3 = C.badgeBg
		badge.Rotation = -8
		badge.ZIndex = 5
		badge.Parent = card
		corner(badge, 6)

		local badgeText = makeLabel(badge, "⭐ POLECANE", 9, C.white, Enum.Font.GothamBlack)
		badgeText.Size = UDim2.new(1, 0, 1, 0)
		badgeText.TextXAlignment = Enum.TextXAlignment.Center
		badgeText.TextYAlignment = Enum.TextYAlignment.Center
		badgeText.ZIndex = 5
	end

	-- Product graphic (e.g. KuKirin)
	local productGraphic = Instance.new("ImageLabel")
	productGraphic.Name = "ProductGraphic"
	productGraphic.Position = UDim2.fromOffset(14, 50)
	productGraphic.Size = UDim2.fromOffset(60, 60)
	productGraphic.BackgroundTransparency = 1
	productGraphic.Image = product.imageId or "rbxassetid://0" -- TODO: Wstaw asset ID grafiki produktu
	productGraphic.Parent = card

	-- Action / Buy button (Baked Graphic)
	local actionBtn = Instance.new("ImageButton")
	actionBtn.AnchorPoint = Vector2.new(0.5, 1)
	actionBtn.Position = UDim2.new(0.5, 0, 1, -12)
	actionBtn.Size = UDim2.new(1, -24, 0, 42)
	actionBtn.BackgroundTransparency = 1
	actionBtn.Parent = card

	if owned then
		actionBtn.Image = "rbxassetid://0" -- TODO: Wstaw asset ID przycisku POSIADASZ
	elseif isFree then
		actionBtn.Image = "rbxassetid://0" -- TODO: Wstaw asset ID przycisku DARMOWA
	elseif unavailable then
		actionBtn.Image = "rbxassetid://0" -- TODO: Wstaw asset ID przycisku WKROTCE
	elseif product.currency == "Robux" then
		actionBtn.Image = product.buttonImageId or "rbxassetid://0" -- TODO: Wstaw asset ID wygenerowanego przycisku z ceną ROBUX
	else
		actionBtn.Image = product.buttonImageId or "rbxassetid://0" -- TODO: Wstaw asset ID wygenerowanego przycisku z ceną COINS
	end

	if not owned and not unavailable then
		local hoveringBtn = false
		cardMaid:Give(actionBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				hoveringBtn = true
				TweenService:Create(actionBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
					Size = UDim2.new(1, -20, 0, 46),
				}):Play()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- Press down effect
				TweenService:Create(actionBtn, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
					Size = UDim2.new(1, -28, 0, 38),
				}):Play()
			end
		end))
		cardMaid:Give(actionBtn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				hoveringBtn = false
				TweenService:Create(actionBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
					Size = UDim2.new(1, -24, 0, 42),
				}):Play()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- Bounce back
				local tSize = if hoveringBtn then UDim2.new(1, -20, 0, 46) else UDim2.new(1, -24, 0, 42)
				TweenService:Create(actionBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
					Size = tSize,
				}):Play()
			end
		end))
		cardMaid:Give(actionBtn.Activated:Connect(function()
			purchase(product)
		end))
	end

	-- Hover effect: subtle glow + scale card to 1.05
	local cardStrokeRef = card:FindFirstChildWhichIsA("UIStroke")
	cardMaid:Give(card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(1.05, 0, 1.05, 0)
			}):Play()
			if cardStrokeRef then
				TweenService:Create(cardStrokeRef, TweenInfo.new(0.2), {
					Color = product.accent,
					Thickness = if isFeatured then 4 else 2.5,
					Transparency = 0.1,
				}):Play()
			end
		end
	end))
	cardMaid:Give(card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(1, 0, 1, 0)
			}):Play()
			if cardStrokeRef and not isFeatured then
				TweenService:Create(cardStrokeRef, TweenInfo.new(0.25), {
					Color = C.cardStroke,
					Thickness = 1.5,
					Transparency = 0,
				}):Play()
			elseif cardStrokeRef and isFeatured then
				TweenService:Create(cardStrokeRef, TweenInfo.new(0.25), {
					Color = product.accent,
					Thickness = 3,
					Transparency = 0.2,
				}):Play()
			end
		end
	end))
end

-- ─── Render products for active tab ────────────────────────────────────

renderProducts = function()
	-- Clean up old cards
	cardMaid:Clean()
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Update tab visuals
	for tabId, tabBtn in tabButtons do
		local isActive = tabId == currentTab
		local accent = tabAccents[tabId]

		TweenService:Create(tabBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			BackgroundColor3 = if isActive then accent else Color3.fromRGB(55, 65, 90),
			TextColor3 = if isActive then C.dark else Color3.fromRGB(180, 190, 210),
		}):Play()

		local indicator = tabIndicators[tabId]
		if indicator then
			indicator.Visible = isActive
		end
	end

	-- Kody tab is special
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

-- ─── Open / Close ──────────────────────────────────────────────────────

local function setOpen(open: boolean)
	overlay.Visible = open
	gui:SetAttribute("ShopOpen", open)
	if open then
		-- Spring open animation: 0.8 -> 1.05 -> 1.0
		window.Size = UDim2.new(0.7, 0, 0.65, 0)
		local t1 = TweenService:Create(window, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.88, 0, 0.82, 0),
		})
		t1:Play()

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
	end
end

-- ─── Connections ───────────────────────────────────────────────────────

globalMaid:Give(toggleEvent.Event:Connect(function()
	setOpen(not overlay.Visible)
end))

globalMaid:Give(closeButton.Activated:Connect(function()
	-- Spring close animation on close button
	local t = TweenService:Create(closeButton, TweenInfo.new(0.1), {
		Size = UDim2.fromOffset(34, 34),
	})
	t:Play()
	task.delay(0.1, function()
		TweenService:Create(closeButton, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
			Size = UDim2.fromOffset(40, 40),
		}):Play()
	end)
	setOpen(false)
end))

globalMaid:Give(overlay.Activated:Connect(function()
	setOpen(false)
end))

-- Prevent clicks on inner window from closing
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
-- Escape closes shop (B key toggle is handled by ActionHUD)
globalMaid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
	if input.KeyCode == Enum.KeyCode.Escape and overlay.Visible then
		setOpen(false)
	end
end))

-- ─── Responsive grid ──────────────────────────────────────────────────

local function updateLayout()
	local w = window.AbsoluteSize.X
	local compact = w < 580

	-- In compact mode: single column, narrower sidebar
	if compact then
		sidebar.Size = UDim2.new(0, 100, 1, 0)
		productsArea.Position = UDim2.new(0, 100, 0, 0)
		productsArea.Size = UDim2.new(1, -100, 1, 0)
		gridLayout.CellSize = UDim2.new(1, 0, 0, 170)
	else
		sidebar.Size = UDim2.new(0, 130, 1, 0)
		productsArea.Position = UDim2.new(0, 130, 0, 0)
		productsArea.Size = UDim2.new(1, -130, 1, 0)
		gridLayout.CellSize = UDim2.new(0.5, -5, 0, 180)
	end

	-- Very compact: reduce tab text size
	for _, tabBtn in tabButtons do
		tabBtn.TextSize = if compact then 11 else 13
	end
end

globalMaid:Give(window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))
updateLayout()
renderProducts()

-- ─── Cleanup ───────────────────────────────────────────────────────────

script.Destroying:Connect(function()
	cardMaid:Clean()
	globalMaid:Clean()
	gui:Destroy()
end)
