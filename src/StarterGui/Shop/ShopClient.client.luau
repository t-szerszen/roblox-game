--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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
	function maid:Give(task: Connection | Instance) table.insert(self.tasks, task) end
	function maid:Clean()
		for _, task in ipairs(self.tasks) do
			if typeof(task) == "RBXScriptConnection" then task:Disconnect()
			elseif typeof(task) == "Instance" then task:Destroy() end
		end
		table.clear(self.tasks)
	end
	return maid :: Maid
end

type Product = ShopConfig.Product
type ShopState = {
	coins: number,
	coinSystemReady: boolean,
	owned: { [string]: boolean },
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild(ShopConfig.RemoteFolderName):WaitForChild(ShopConfig.RequestFunctionName) :: RemoteFunction

local COLORS = {
	backdrop = Color3.fromRGB(5, 5, 8),
	panel = Color3.fromRGB(16, 18, 22),
	panelRaised = Color3.fromRGB(24, 27, 34),
	card = Color3.fromRGB(28, 31, 38),
	muted = Color3.fromRGB(140, 150, 160),
	text = Color3.fromRGB(250, 250, 255),
	coin = Color3.fromRGB(255, 190, 40),
	robux = Color3.fromRGB(0, 220, 180),
	danger = Color3.fromRGB(240, 60, 60),
}

local currentTab = "Coins"
local currentState: ShopState = { coins = 0, coinSystemReady = false, owned = {} }
local busy = false
local shopMaid = newMaid()
local globalMaid = newMaid()
local isShopOpen = false

local function formatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1 %2")
		formatted = replaced
		if count == 0 then return formatted end
	end
end

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = thickness
	value.Parent = parent
	return value
end

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

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = font
	value.Text = text
	value.TextColor3 = color
	value.TextSize = size
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

-- Shared Action HUD logic
local hudGui = playerGui:FindFirstChild("ActionHUD")
if not hudGui then
	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "ActionHUD"
	hudGui.DisplayOrder = 100
	hudGui.ResetOnSpawn = false
	hudGui.IgnoreGuiInset = true
	hudGui.Parent = playerGui
	
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Position = UDim2.new(0, 16, 0, 60)
	container.Size = UDim2.fromOffset(150, 300)
	container.BackgroundTransparency = 1
	container.Parent = hudGui
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
end
local hudContainer = hudGui:WaitForChild("Container")

-- HUD Shop Button
local shopBtn = Instance.new("TextButton")
shopBtn.Name = "ShopBtn"
shopBtn.Size = UDim2.fromOffset(120, 44)
shopBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shopBtn.AutoButtonColor = false
shopBtn.Text = ""
shopBtn.LayoutOrder = 1
shopBtn.Parent = hudContainer
corner(shopBtn, 12)
local shopBtnGradient = createGradient(shopBtn, Color3.fromRGB(24, 26, 32), Color3.fromRGB(16, 18, 22))
local shopBtnStroke = stroke(shopBtn, COLORS.coin, 1.5)
shopBtnStroke.Transparency = 0.5

local shopBtnIcon = label(shopBtn, "SKLEP", 14, COLORS.text, Enum.Font.GothamBold)
shopBtnIcon.Position = UDim2.fromOffset(14, 0)
shopBtnIcon.Size = UDim2.new(1, -50, 1, 0)

local shopBadge = Instance.new("Frame")
shopBadge.Size = UDim2.fromOffset(26, 26)
shopBadge.AnchorPoint = Vector2.new(1, 0.5)
shopBadge.Position = UDim2.new(1, -8, 0.5, 0)
shopBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shopBadge.Parent = shopBtn
corner(shopBadge, 6)
createGradient(shopBadge, Color3.fromRGB(50, 50, 55), Color3.fromRGB(30, 30, 35))
local shopBadgeLabel = label(shopBadge, "B", 14, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
shopBadgeLabel.Size = UDim2.new(1, 0, 1, 0)
shopBadgeLabel.TextXAlignment = Enum.TextXAlignment.Center

globalMaid:Give(shopBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		TweenService:Create(shopBtn, TweenInfo.new(0.2), {Size = UDim2.fromOffset(126, 46)}):Play()
		TweenService:Create(shopBtnStroke, TweenInfo.new(0.2), {Transparency = 0.1}):Play()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		TweenService:Create(shopBtn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(116, 42)}):Play()
	end
end))
globalMaid:Give(shopBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		TweenService:Create(shopBtn, TweenInfo.new(0.2), {Size = UDim2.fromOffset(120, 44)}):Play()
		TweenService:Create(shopBtnStroke, TweenInfo.new(0.2), {Transparency = if isShopOpen then 0.1 else 0.5}):Play()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		TweenService:Create(shopBtn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(126, 46)}):Play()
	end
end))

-- Shop Main UI
local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = COLORS.backdrop
overlay.BackgroundTransparency = 0.3
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Visible = false
overlay.Parent = gui

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.85, 0, 0.8, 0)
window.BackgroundColor3 = COLORS.panel
window.ClipsDescendants = true
window.Parent = overlay
corner(window, 16)
stroke(window, Color3.fromRGB(40, 45, 55), 1)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(380, 500)
sizeConstraint.MaxSize = Vector2.new(1100, 750)
sizeConstraint.Parent = window

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 80)
header.BackgroundTransparency = 1
header.Parent = window

local title = label(header, "MARKETPLACE", 28, COLORS.text, Enum.Font.GothamBlack)
title.Position = UDim2.fromOffset(24, 16)
title.Size = UDim2.new(0.5, 0, 0, 32)

local subtitle = label(header, "Kupuj pojazdy, bronie i ulepszenia", 14, COLORS.muted, Enum.Font.GothamMedium)
subtitle.Position = UDim2.fromOffset(24, 48)
subtitle.Size = UDim2.new(0.5, 0, 0, 20)

local balanceFrame = Instance.new("Frame")
balanceFrame.AnchorPoint = Vector2.new(1, 0.5)
balanceFrame.Position = UDim2.new(1, -64, 0.5, 0)
balanceFrame.Size = UDim2.fromOffset(160, 40)
balanceFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
balanceFrame.Parent = header
corner(balanceFrame, 8)
createGradient(balanceFrame, Color3.fromRGB(45, 40, 20), Color3.fromRGB(25, 22, 10))
local balanceLabel = label(balanceFrame, "0", 18, COLORS.coin, Enum.Font.GothamBold)
balanceLabel.Position = UDim2.fromOffset(16, 0)
balanceLabel.Size = UDim2.new(1, -26, 1, 0)
balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
local coinIcon = label(balanceFrame, "$", 18, COLORS.coin, Enum.Font.GothamBlack)
coinIcon.Size = UDim2.fromOffset(20, 40)
coinIcon.Position = UDim2.new(1, 0, 0, 0)
coinIcon.AnchorPoint = Vector2.new(1, 0)
coinIcon.TextXAlignment = Enum.TextXAlignment.Center

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -16, 0.5, 0)
closeButton.Size = UDim2.fromOffset(36, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(35, 40, 48)
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.text
closeButton.TextSize = 14
closeButton.Parent = header
corner(closeButton, 18)

local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.Position = UDim2.fromOffset(24, 90)
tabs.Size = UDim2.new(1, -48, 0, 44)
tabs.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
tabs.Parent = window
corner(tabs, 10)

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabs

local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingTop = UDim.new(0, 6)
tabPadding.PaddingBottom = UDim.new(0, 6)
tabPadding.PaddingLeft = UDim.new(0, 6)
tabPadding.PaddingRight = UDim.new(0, 6)
tabPadding.Parent = tabs

local function makeTab(name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0.33, 0, 1, 0)
	button.BackgroundColor3 = COLORS.panelRaised
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextSize = 14
	button.AutoButtonColor = false
	button.Parent = tabs
	corner(button, 8)
	return button
end

local coinsTab = makeTab("Coins", "HULAJNOGI")
local robuxTab = makeTab("Robux", "PREMIUM")
local boostsTab = makeTab("Boosts", "DOPALACZE")

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Products"
scroll.Position = UDim2.fromOffset(24, 150)
scroll.Size = UDim2.new(1, -48, 1, -170)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = COLORS.muted
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = window

local grid = Instance.new("UIGridLayout")
grid.CellPadding = UDim2.fromOffset(16, 16)
grid.CellSize = UDim2.new(0.5, -8, 0, 140)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local status = label(window, "", 13, COLORS.muted, Enum.Font.GothamMedium)
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -6)
status.Size = UDim2.new(1, -48, 0, 24)
status.TextXAlignment = Enum.TextXAlignment.Center

local function callServer(action: string, itemId: string?): (boolean, string, ShopState, number?)
	local ok, success, message, state, productId = pcall(function()
		return request:InvokeServer(action, itemId)
	end)
	if not ok or typeof(success) ~= "boolean" or typeof(state) ~= "table" then
		return false, "Brak polaczenia ze sklepem.", currentState, nil
	end
	return success, if typeof(message) == "string" then message else "", state :: ShopState, if typeof(productId) == "number" then productId else nil
end

local renderProducts: () -> ()

local function setStatus(message: string, isError: boolean)
	status.Text = message
	status.TextColor3 = if isError then COLORS.danger else COLORS.robux
end

local function purchase(product: Product)
	if busy then return end
	busy = true
	setStatus("Sprawdzanie...", false)

	task.spawn(function()
		local action = if product.currency == "Coins" then "PurchaseCoins" else "PrepareRobux"
		local success, message, state, productId = callServer(action, product.id)
		currentState = state
		balanceLabel.Text = formatNumber(state.coins)
		if success and product.currency == "Robux" and productId then
			MarketplaceService:PromptGamePassPurchase(player, productId)
			setStatus("Potwierdz zakup w nowym oknie.", false)
		else
			setStatus(message, not success)
		end
		busy = false
		renderProducts()
	end)
end

local function createProductCard(product: Product, order: number)
	local card = Instance.new("Frame")
	card.Name = product.id
	card.LayoutOrder = order
	card.BackgroundColor3 = COLORS.card
	card.Parent = scroll
	corner(card, 12)
	stroke(card, Color3.fromRGB(60, 65, 75), 0)

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 6, 1, 0)
	accent.BackgroundColor3 = product.accent
	accent.BorderSizePixel = 0
	accent.Parent = card
	corner(accent, 4)

	local name = label(card, product.name, 18, COLORS.text, Enum.Font.GothamBlack)
	name.Position = UDim2.fromOffset(24, 16)
	name.Size = UDim2.new(1, -48, 0, 24)
	
	local speedStat = label(card, if product.currency == "Coins" then "Szybkosc: Zalezna od modelu" else product.description, 13, COLORS.muted, Enum.Font.Gotham)
	speedStat.Position = UDim2.fromOffset(24, 44)
	speedStat.Size = UDim2.new(1, -48, 0, 36)
	speedStat.TextWrapped = true
	speedStat.TextYAlignment = Enum.TextYAlignment.Top

	local owned = currentState.owned[product.id] == true
	local unavailable = product.currency == "Robux" and (product.productId or 0) <= 0
	local actionBtn = Instance.new("TextButton")
	actionBtn.AnchorPoint = Vector2.new(0, 1)
	actionBtn.Position = UDim2.new(0, 24, 1, -16)
	actionBtn.Size = UDim2.new(1, -48, 0, 38)
	actionBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	actionBtn.AutoButtonColor = not owned and not unavailable
	actionBtn.Font = Enum.Font.GothamBlack
	actionBtn.TextColor3 = if owned or unavailable then COLORS.muted else Color3.fromRGB(20, 20, 20)
	actionBtn.TextSize = 15
	actionBtn.Text = if owned then "POSIADASZ" else if unavailable then string.format("%s R$ (Wkrotce)", formatNumber(product.price)) else string.format("KUP | %s %s", formatNumber(product.price), if product.currency == "Coins" then "COINS" else "R$")
	actionBtn.Parent = card
	corner(actionBtn, 8)
	
	local btnColor1 = if owned or unavailable then Color3.fromRGB(45, 50, 60) else product.accent
	local btnColor2 = if owned or unavailable then Color3.fromRGB(35, 40, 50) else Color3.fromRGB(product.accent.R*255 * 0.7, product.accent.G*255 * 0.7, product.accent.B*255 * 0.7)
	createGradient(actionBtn, btnColor1, btnColor2)

	if not owned and not unavailable then
		shopMaid:Give(actionBtn.Activated:Connect(function() purchase(product) end))
	end
end

renderProducts = function()
	shopMaid:Clean()
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	local products = if currentTab == "Coins" then ShopConfig.CoinProducts elseif currentTab == "Robux" then ShopConfig.RobuxProducts else {}
	for index, product in products do
		createProductCard(product, index)
	end
	
	if #products == 0 then
		local noItems = label(scroll, "Wkrotce dostepne!", 18, COLORS.muted, Enum.Font.GothamBold)
		noItems.Size = UDim2.new(1, 0, 1, 0)
		noItems.TextXAlignment = Enum.TextXAlignment.Center
	end

	coinsTab.BackgroundColor3 = if currentTab == "Coins" then COLORS.coin else COLORS.panelRaised
	coinsTab.TextColor3 = if currentTab == "Coins" then Color3.fromRGB(20, 20, 20) else COLORS.muted
	robuxTab.BackgroundColor3 = if currentTab == "Robux" then COLORS.robux else COLORS.panelRaised
	robuxTab.TextColor3 = if currentTab == "Robux" then Color3.fromRGB(20, 20, 20) else COLORS.muted
	boostsTab.BackgroundColor3 = if currentTab == "Boosts" then Color3.fromRGB(150, 80, 255) else COLORS.panelRaised
	boostsTab.TextColor3 = if currentTab == "Boosts" then Color3.fromRGB(255, 255, 255) else COLORS.muted
end

local function setOpen(open: boolean)
	isShopOpen = open
	if open then
		overlay.Visible = true
		window.Size = UDim2.new(0.85, 0, 0.75, 0)
		window.GroupTransparency = 1
		TweenService:Create(window, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.85, 0, 0.8, 0),
			GroupTransparency = 0
		}):Play()
		TweenService:Create(shopBtnStroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
		task.spawn(function()
			local success, message, state = callServer("GetState", nil)
			currentState = state
			balanceLabel.Text = formatNumber(state.coins)
			if not success then setStatus(message, true) else setStatus("", false) end
			renderProducts()
		end)
	else
		TweenService:Create(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0.85, 0, 0.75, 0),
			GroupTransparency = 1
		}):Play()
		TweenService:Create(shopBtnStroke, TweenInfo.new(0.2), {Transparency = 0.5}):Play()
		task.delay(0.2, function()
			if not isShopOpen then overlay.Visible = false end
		end)
	end
end

globalMaid:Give(shopBtn.Activated:Connect(function() setOpen(not isShopOpen) end))
globalMaid:Give(closeButton.Activated:Connect(function() setOpen(false) end))
globalMaid:Give(overlay.Activated:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then setOpen(false) end
end))
window.InputBegan:Connect(function() end)
globalMaid:Give(coinsTab.Activated:Connect(function() currentTab = "Coins"; renderProducts() end))
globalMaid:Give(robuxTab.Activated:Connect(function() currentTab = "Robux"; renderProducts() end))
globalMaid:Give(boostsTab.Activated:Connect(function() currentTab = "Boosts"; renderProducts() end))

globalMaid:Give(UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		setOpen(not isShopOpen)
	elseif input.KeyCode == Enum.KeyCode.Escape and isShopOpen then
		setOpen(false)
	end
end))

local function updateGrid()
	local compact = window.AbsoluteSize.X < 700
	grid.CellSize = if compact then UDim2.new(1, 0, 0, 140) else UDim2.new(0.5, -8, 0, 140)
	title.TextSize = if compact then 22 else 28
	title.Size = if compact then UDim2.new(1, -120, 0, 26) else UDim2.new(0.5, 0, 0, 32)
	subtitle.Visible = not compact
end

window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGrid)
updateGrid()
renderProducts()

script.Destroying:Connect(function()
	shopMaid:Clean()
	globalMaid:Clean()
	gui:Destroy()
end)
