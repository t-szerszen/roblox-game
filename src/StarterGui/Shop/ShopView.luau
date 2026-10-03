--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UI = require(ReplicatedStorage.Shared.UI.Components)
local Layout = require(ReplicatedStorage.Shared.UI.Layout)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
type Product = ShopConfig.Product
type TabId = ShopConfig.TabId
type State = { coins: number, coinSystemReady: boolean, owned: { [string]: boolean } }
type Actions = {
	Toggle: () -> (), Close: () -> (), Tab: (TabId) -> (),
	Purchase: (Product) -> (), Confirm: () -> (), Cancel: () -> (), Refresh: () -> (),
}
type Card = { product: Product, button: TextButton }
local ShopView = {}

function ShopView.new(gui: ScreenGui, owner: Scope.Scope, actions: Actions)
	local cardsScope = Scope.new()
	owner:Give(function() cardsScope:Clean() end)
	local cards: { Card } = {}
	local tabs: { [string]: TextButton } = {}
	local hud = UI.Button(gui, "Sklep  ·  B", owner, actions.Toggle)
	hud.Name = "ShopBtn"
	hud.Position = UDim2.fromOffset(144, 72)
	hud.Size = UDim2.fromOffset(120, Theme.TouchTarget)
	local overlay = UI.Frame(gui, "Overlay")
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = Theme.Shop.BackdropTransparency
	backdrop.ZIndex = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.Modal = true
	backdrop.Parent = overlay
	owner:Give(backdrop.Activated:Connect(actions.Close))
	local window = Instance.new("CanvasGroup")
	window.Name = "ShopWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.BackgroundColor3 = Theme.Shop.WindowBottom
	window.ZIndex = 2
	window.BorderSizePixel = 0
	window.Active = true
	window.SelectionGroup = true
	window.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	window.Parent = overlay
	UI.Corner(window, 20)
	UI.Stroke(window, Theme.Shop.Border, 0.15)
	-- A gradient on CanvasGroup tints its flattened contents, including text
	-- and ViewportFrames. Keep the decoration on its own background surface.
	local background = UI.Frame(window, "Background", Color3.new(1, 1, 1))
	background.Size = UDim2.fromScale(1, 1)
	background.ZIndex = 0
	UI.Corner(background, 20)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Theme.Shop.WindowTop, Theme.Shop.WindowBottom)
	gradient.Rotation = 110
	gradient.Parent = background
	local title = UI.Label(window, "Sklep", 26)
	title.Font = Theme.StrongFont
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(0.45, 0, 0, 40)
	local balance = UI.Label(window, "— Coins", 14, true)
	balance.Name = "Balance"
	balance.AnchorPoint = Vector2.new(1, 0)
	balance.Position = UDim2.new(1, -80, 0, 16)
	balance.Size = UDim2.new(0.45, -24, 0, 40)
	balance.TextXAlignment = Enum.TextXAlignment.Right
	local close = UI.Button(window, "×", owner, actions.Close)
	close.Name = "Close"
	close.TextSize = 26
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 14)
	close.Size = UDim2.fromOffset(Theme.TouchTarget, Theme.TouchTarget)
	local navigation = UI.Frame(window, "Navigation")
	navigation.BackgroundTransparency = 1
	navigation.Position = UDim2.fromOffset(16, 72)
	navigation.Size = UDim2.new(1, -32, 0, Theme.TouchTarget)
	for index, tab in ShopConfig.Tabs do
		local button = UI.Button(navigation, tab.label, owner, function() actions.Tab(tab.id) end)
		button.Name = tab.id
		button.Position = UDim2.new((index - 1) / #ShopConfig.Tabs, 0, 0, 0)
		button.Size = UDim2.new(1 / #ShopConfig.Tabs, -8, 1, 0)
		tabs[tab.id] = button
	end
	local section = UI.Label(window, "Hulajnogi", 14, true)
	section.Position = UDim2.fromOffset(20, 130)
	section.Size = UDim2.new(1, -160, 0, 28)
	local refresh = UI.Button(window, "Odśwież", owner, actions.Refresh)
	refresh.Name = "Refresh"
	refresh.AnchorPoint = Vector2.new(1, 0)
	refresh.Position = UDim2.new(1, -16, 0, 122)
	refresh.Size = UDim2.fromOffset(100, Theme.TouchTarget)
	refresh.TextSize = 12
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Products"
	scroll.Position = UDim2.fromOffset(16, 176)
	scroll.Size = UDim2.new(1, -32, 1, -192)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.Colors.Border
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = window
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(Theme.Spacing, Theme.Spacing)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	owner:Give(grid)
	local function layout()
		local inset = GuiService:GetGuiInset()
		-- Keep the transitional HUD aligned with the existing phone HUD, which
		-- ignores the top inset; the modal itself uses Roblox's safe content area.
		hud.Position = UDim2.fromOffset(144, math.max(12, 72 - inset.Y))
		local width, height = Layout.ShopWindow(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
		window.Size = UDim2.fromOffset(width, height)
		local _, cellWidth = Layout.ProductGrid(math.max(1, scroll.AbsoluteSize.X - 12))
		grid.CellSize = UDim2.fromOffset(cellWidth, Theme.Shop.CardHeight)
	end
	owner:Give(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	owner:Give(scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	owner:Give(GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout))
	layout()
	local confirmOverlay = UI.Frame(overlay, "ConfirmationOverlay", Color3.new(0, 0, 0))
	confirmOverlay.Size = UDim2.fromScale(1, 1)
	confirmOverlay.BackgroundTransparency = 0.35
	confirmOverlay.Active = true
	confirmOverlay.Visible = false
	confirmOverlay.ZIndex = 3
	local dialog = UI.Frame(confirmOverlay, "Confirmation", Theme.Shop.CardBackground)
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.new(1, -48, 0, 246)
	dialog.SelectionGroup = true
	dialog.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	dialog.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	dialog.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	dialog.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	UI.Corner(dialog, 18)
	UI.Stroke(dialog, Theme.Shop.Border, 0)
	local dialogLimit = Instance.new("UISizeConstraint")
	dialogLimit.MaxSize = Vector2.new(440, 246)
	dialogLimit.Parent = dialog
	local confirmTitle = UI.Label(dialog, "Potwierdź zakup", 22)
	confirmTitle.Position = UDim2.fromOffset(20, 16)
	confirmTitle.Size = UDim2.new(1, -40, 0, 30)
	local details = UI.Label(dialog, "", 15)
	details.Name = "Details"
	details.Position = UDim2.fromOffset(20, 60)
	details.Size = UDim2.new(1, -40, 0, 104)
	details.TextWrapped = true
	details.TextYAlignment = Enum.TextYAlignment.Top
	local cancel = UI.Button(dialog, "Anuluj", owner, actions.Cancel)
	cancel.Name = "Cancel"
	cancel.Position = UDim2.new(0, 20, 1, -64)
	cancel.Size = UDim2.new(0.5, -26, 0, Theme.TouchTarget)
	local confirm = UI.Button(dialog, "Kup", owner, actions.Confirm, true)
	confirm.Name = "Buy"
	confirm.Position = UDim2.new(0.5, 6, 1, -64)
	confirm.Size = UDim2.new(0.5, -26, 0, Theme.TouchTarget)
	return {
		Overlay = overlay, Window = window, Scroll = scroll, HUD = hud,
		Tabs = tabs, CancelButton = cancel, Dialog = confirmOverlay,
		SetConfirmation = function(product: Product?, coins: number)
			confirmOverlay.Visible = product ~= nil
			if product then
				details.Text = string.format("%s\n\nCena: %s Coins\nSaldo po zakupie: %s Coins", product.name,
					Layout.FormatCoins(product.price), Layout.FormatCoins(math.max(0, coins - product.price)))
			end
		end,
		Render = function(tabId: TabId, mountPreview: (Frame, string, Scope.Scope) -> ())
			cardsScope:Clean()
			cardsScope = Scope.new()
			table.clear(cards)
			section.Text = tabId
			scroll.CanvasPosition = Vector2.zero
			for id, button in tabs do
				button.BackgroundColor3 = if id == tabId then Theme.Colors.Accent else Theme.Colors.Raised
				button.TextColor3 = if id == tabId then Theme.Colors.AccentText else Theme.Colors.Text
			end
			grid.Parent = if tabId == "Kody" then nil else scroll
			if tabId == "Kody" then
				local empty = UI.Frame(scroll, "Codes", Theme.Shop.CardBackground)
				empty.Size = UDim2.new(1, -12, 0, 156)
				UI.Corner(empty)
				cardsScope:Give(empty)
				local heading = UI.Label(empty, "Kody promocyjne", 20)
				heading.Position = UDim2.fromOffset(20, 20)
				heading.Size = UDim2.new(1, -40, 0, 30)
				local notice = UI.Label(empty, "Wpisywanie kodów będzie dostępne wkrótce.", 14, true)
				notice.Position = UDim2.fromOffset(20, 60)
				notice.Size = UDim2.new(1, -40, 0, 60)
				notice.TextWrapped = true
				return
			end
			for index, product in ShopConfig.GetProductsByTab(tabId) do
				local card = UI.Frame(scroll, product.id, Theme.Shop.CardBackground)
				card.LayoutOrder = index
				UI.Corner(card)
				UI.Stroke(card, Theme.Shop.Border, 0.4)
				cardsScope:Give(card)
				local art = UI.Frame(card, "Artwork", Theme.Shop.PreviewBackground)
				art.Position = UDim2.fromOffset(10, 10)
				art.Size = UDim2.new(1, -20, 0, 132)
				UI.Corner(art, 10)
				if product.previewKey then mountPreview(art, product.previewKey, cardsScope)
				elseif product.imageId and product.imageId ~= "" then
					local image = Instance.new("ImageLabel")
					image.Name = "ProductImage"
					image.BackgroundTransparency = 1
					image.Size = UDim2.new(1, -20, 1, -20)
					image.Position = UDim2.fromOffset(10, 10)
					image.Image = product.imageId
					image.ScaleType = Enum.ScaleType.Fit
					image.Parent = art
				else
					local placeholder = UI.Label(art, "PREMIUM", 14, true)
					placeholder.Size = UDim2.fromScale(1, 1)
					placeholder.TextXAlignment = Enum.TextXAlignment.Center
				end
				local name = UI.Label(card, product.name, 17)
				name.Font = Theme.StrongFont
				name.Position = UDim2.fromOffset(14, 152)
				name.Size = UDim2.new(1, -28, 0, 26)
				name.TextTruncate = Enum.TextTruncate.AtEnd
				local description = UI.Label(card, product.description, 12, true)
				description.Position = UDim2.fromOffset(14, 180)
				description.Size = UDim2.new(1, -28, 0, 32)
				description.TextWrapped = true
				local specs = UI.Label(card, if product.speed then string.format("%d km/h", product.speed) else "Odblokowanie na stałe", 12, true)
				specs.Position = UDim2.fromOffset(14, 216)
				specs.Size = UDim2.new(1, -28, 0, 18)
				local buy = UI.Button(card, "", cardsScope, function() actions.Purchase(product) end, true)
				buy.Name = "Purchase"
				buy.Position = UDim2.fromOffset(12, 242)
				buy.Size = UDim2.new(1, -24, 0, Theme.TouchTarget)
				table.insert(cards, { product = product, button = buy })
			end
			layout()
		end,
		Update = function(state: State, busy: boolean)
			balance.Text = if state.coinSystemReady then Layout.FormatCoins(state.coins) .. " Coins" else "— Coins"
			UI.SetEnabled(refresh, not busy)
			for _, card in cards do
				local product = card.product
				local owned = state.owned[product.id] == true
				local unavailable = product.currency == "Robux" and (product.productId or 0) <= 0
				local insufficient = product.currency == "Coins" and state.coins < product.price
				card.button.Text = if owned then "Posiadasz" elseif unavailable then "Premium · Wkrótce"
					elseif product.currency == "Coins" and not state.coinSystemReady then "Dane niedostępne"
					elseif insufficient then "Brakuje " .. Layout.FormatCoins(product.price - state.coins) .. " Coins"
					else Layout.FormatCoins(product.price) .. " " .. product.currency
				local available = not busy and not owned and not unavailable and not insufficient
					and (product.currency ~= "Coins" or state.coinSystemReady)
				UI.SetEnabled(card.button, available)
				card.button.BackgroundColor3 = if available then Theme.Colors.Accent else Theme.Shop.DisabledBackground
				card.button.TextColor3 = if available then Theme.Colors.AccentText else Theme.Colors.Muted
				-- Ownership/price messages must stay readable even without an action.
				card.button.TextTransparency = 0
				card.button.BackgroundTransparency = 0
			end
		end,
	}
end

export type View = typeof(ShopView.new(nil :: any, nil :: any, nil :: any))
return ShopView
