--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

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
	backdrop = Color3.fromRGB(8, 10, 13),
	panel = Color3.fromRGB(20, 23, 28),
	panelRaised = Color3.fromRGB(29, 33, 39),
	card = Color3.fromRGB(35, 39, 46),
	muted = Color3.fromRGB(151, 158, 169),
	text = Color3.fromRGB(245, 247, 250),
	coin = Color3.fromRGB(241, 196, 43),
	robux = Color3.fromRGB(65, 202, 129),
	danger = Color3.fromRGB(235, 101, 91),
}

local currentTab = "Coins"
local currentState: ShopState = { coins = 0, coinSystemReady = false, owned = {} }
local busy = false
local connections: { RBXScriptConnection } = {}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number?)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Transparency = transparency or 0
	value.Thickness = 1
	value.Parent = parent
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

local function formatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1 %2")
		formatted = replaced
		if count == 0 then
			return formatted
		end
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenShop"
openButton.AnchorPoint = Vector2.new(1, 0.5)
openButton.Position = UDim2.new(1, -24, 0.5, 0)
openButton.Size = UDim2.fromOffset(112, 44)
openButton.BackgroundColor3 = COLORS.panelRaised
openButton.Font = Enum.Font.GothamBold
openButton.Text = "SKLEP"
openButton.TextColor3 = COLORS.text
openButton.TextSize = 14
openButton.AutoButtonColor = false
openButton.Parent = gui
corner(openButton, 8)
stroke(openButton, Color3.fromRGB(70, 76, 86), 0.25)

local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = COLORS.backdrop
overlay.BackgroundTransparency = 0.2
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Visible = false
overlay.Parent = gui

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.86, 0, 0.82, 0)
window.BackgroundColor3 = COLORS.panel
window.ClipsDescendants = true
window.Parent = overlay
corner(window, 8)
stroke(window, Color3.fromRGB(74, 80, 91), 0.25)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(320, 400)
sizeConstraint.MaxSize = Vector2.new(1040, 720)
sizeConstraint.Parent = window

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 74)
header.BackgroundColor3 = COLORS.panelRaised
header.BorderSizePixel = 0
header.Parent = window

local title = label(header, "SKLEP", 24, COLORS.text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(22, 13)
title.Size = UDim2.new(0.5, 0, 0, 28)

local subtitle = label(header, "Hulajnogi i dodatki", 12, COLORS.muted, Enum.Font.Gotham)
subtitle.Position = UDim2.fromOffset(23, 42)
subtitle.Size = UDim2.new(0.5, 0, 0, 18)

local balance = label(header, "0 COINS", 14, COLORS.coin, Enum.Font.GothamBold)
balance.AnchorPoint = Vector2.new(1, 0.5)
balance.Position = UDim2.new(1, -70, 0.5, 0)
balance.Size = UDim2.fromOffset(180, 30)
balance.TextXAlignment = Enum.TextXAlignment.Right

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -16, 0.5, 0)
closeButton.Size = UDim2.fromOffset(36, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(46, 51, 59)
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.text
closeButton.TextSize = 14
closeButton.Parent = header
corner(closeButton, 6)

local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.Position = UDim2.fromOffset(18, 90)
tabs.Size = UDim2.new(1, -36, 0, 42)
tabs.BackgroundColor3 = Color3.fromRGB(14, 17, 21)
tabs.Parent = window
corner(tabs, 7)

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
tabLayout.Padding = UDim.new(0, 5)
tabLayout.Parent = tabs

local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingTop = UDim.new(0, 4)
tabPadding.PaddingBottom = UDim.new(0, 4)
tabPadding.PaddingLeft = UDim.new(0, 4)
tabPadding.PaddingRight = UDim.new(0, 4)
tabPadding.Parent = tabs

local function makeTab(name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0.5, -3, 1, 0)
	button.BackgroundColor3 = COLORS.panelRaised
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextSize = 13
	button.AutoButtonColor = false
	button.Parent = tabs
	corner(button, 6)
	return button
end

local coinsTab = makeTab("Coins", "COINY")
local robuxTab = makeTab("Robux", "ROBUX")

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Products"
scroll.Position = UDim2.fromOffset(18, 148)
scroll.Size = UDim2.new(1, -36, 1, -196)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = Color3.fromRGB(95, 102, 112)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = window

local grid = Instance.new("UIGridLayout")
grid.CellPadding = UDim2.fromOffset(12, 12)
grid.CellSize = UDim2.new(0.5, -6, 0, 156)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local status = label(window, "", 12, COLORS.muted, Enum.Font.GothamMedium)
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -12)
status.Size = UDim2.new(1, -36, 0, 24)
status.TextXAlignment = Enum.TextXAlignment.Center
status.TextWrapped = true

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
	if busy then
		return
	end
	busy = true
	setStatus("Sprawdzanie zakupu...", false)

	task.spawn(function()
		local action = if product.currency == "Coins" then "PurchaseCoins" else "PrepareRobux"
		local success, message, state, productId = callServer(action, product.id)
		currentState = state
		balance.Text = string.format("%s COINS", formatNumber(state.coins))
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
	local card = Instance.new("Frame")
	card.Name = product.id
	card.LayoutOrder = order
	card.BackgroundColor3 = COLORS.card
	card.Parent = scroll
	corner(card, 7)
	stroke(card, Color3.fromRGB(76, 82, 92), 0.45)

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 5, 1, 0)
	accent.BackgroundColor3 = product.accent
	accent.BorderSizePixel = 0
	accent.Parent = card

	local monogram = label(card, string.sub(product.name, 1, 1), 28, product.accent, Enum.Font.GothamBlack)
	monogram.Position = UDim2.fromOffset(20, 15)
	monogram.Size = UDim2.fromOffset(36, 36)

	local name = label(card, product.name, 16, COLORS.text, Enum.Font.GothamBold)
	name.Position = UDim2.fromOffset(60, 16)
	name.Size = UDim2.new(1, -72, 0, 24)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local description = label(card, product.description, 12, COLORS.muted, Enum.Font.Gotham)
	description.Position = UDim2.fromOffset(20, 58)
	description.Size = UDim2.new(1, -34, 0, 36)
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top

	local owned = currentState.owned[product.id] == true
	local unavailable = product.currency == "Robux" and (product.productId or 0) <= 0
	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.new(0, 20, 1, -14)
	action.Size = UDim2.new(1, -34, 0, 36)
	action.BackgroundColor3 = if owned or unavailable then Color3.fromRGB(57, 62, 70) else product.accent
	action.AutoButtonColor = not owned and not unavailable
	action.Font = Enum.Font.GothamBold
	action.TextColor3 = if owned or unavailable then COLORS.muted else Color3.fromRGB(15, 17, 20)
	action.TextSize = 12
	action.Text = if owned then "POSIADASZ" else if unavailable then string.format("%s R$ | WKROTCE", formatNumber(product.price)) else string.format("KUP | %s %s", formatNumber(product.price), if product.currency == "Coins" then "COINS" else "R$")
	action.Parent = card
	corner(action, 6)

	if not owned and not unavailable then
		table.insert(connections, action.Activated:Connect(function()
			purchase(product)
		end))
	end
end

renderProducts = function()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local products = if currentTab == "Coins" then ShopConfig.CoinProducts else ShopConfig.RobuxProducts
	for index, product in products do
		createProductCard(product, index)
	end

	coinsTab.BackgroundColor3 = if currentTab == "Coins" then COLORS.coin else COLORS.panelRaised
	coinsTab.TextColor3 = if currentTab == "Coins" then Color3.fromRGB(18, 20, 23) else COLORS.muted
	robuxTab.BackgroundColor3 = if currentTab == "Robux" then COLORS.robux else COLORS.panelRaised
	robuxTab.TextColor3 = if currentTab == "Robux" then Color3.fromRGB(18, 20, 23) else COLORS.muted
end

local function setOpen(open: boolean)
	overlay.Visible = open
	openButton.Visible = not open
	if open then
		window.Size = UDim2.new(0.82, 0, 0.76, 0)
		TweenService:Create(window, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.86, 0, 0.82, 0),
		}):Play()
		task.spawn(function()
			local success, message, state = callServer("GetState", nil)
			currentState = state
			balance.Text = string.format("%s COINS", formatNumber(state.coins))
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

openButton.Activated:Connect(function()
	setOpen(true)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
overlay.Activated:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setOpen(false)
	end
end)
window.InputBegan:Connect(function() end)
coinsTab.Activated:Connect(function()
	currentTab = "Coins"
	renderProducts()
end)
robuxTab.Activated:Connect(function()
	currentTab = "Robux"
	renderProducts()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		setOpen(not overlay.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and overlay.Visible then
		setOpen(false)
	end
end)

local function updateGrid()
	local compact = window.AbsoluteSize.X < 650
	grid.CellSize = if compact then UDim2.new(1, 0, 0, 156) else UDim2.new(0.5, -6, 0, 156)
	title.TextSize = if compact then 19 else 24
	title.Size = if compact then UDim2.fromOffset(110, 28) else UDim2.new(0.5, 0, 0, 28)
	subtitle.Visible = not compact
	balance.Size = if compact then UDim2.fromOffset(100, 30) else UDim2.fromOffset(180, 30)
	balance.TextSize = if compact then 11 else 14
end

window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGrid)
updateGrid()
renderProducts()

script.Destroying:Connect(function()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	gui:Destroy()
end)
