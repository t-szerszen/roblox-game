--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Style = require(ReplicatedStorage.Shared.Phone.PhoneTheme)
local Components = require(script.Parent.PhoneComponents)
local Layout = require(ReplicatedStorage.Shared.UI.Layout)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Types = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
local Apps = require(ReplicatedStorage.Shared.Phone.PhoneApps)
local AppsView = require(script.Parent.PhoneAppsView)

export type Actions = AppsView.Actions & {
	Navigate: (Types.Page) -> (), Back: () -> (), Close: () -> (), Toggle: () -> (), Refresh: () -> (),
}
local PhoneView = {}

function PhoneView.new(gui: ScreenGui, hudGui: ScreenGui, owner: Scope.Scope, actions: Actions)
	local safe = Components.Frame(gui, "SafeArea")
	safe.Size = UDim2.fromScale(1, 1)
	safe.BackgroundTransparency = 1
	local shadow = Components.Frame(safe, "Shadow", Color3.new(0, 0, 0))
	shadow.AnchorPoint = Vector2.new(1, 1)
	shadow.Position = UDim2.new(1, -Theme.Phone.Margin + 8, 1, -Theme.Phone.Margin + 12)
	shadow.BackgroundTransparency = 0.6
	shadow.Visible = false
	Components.Corner(shadow, Style.BodyRadius + 6)
	local window = Instance.new("CanvasGroup")
	window.Name = "Phone"
	window.AnchorPoint = Vector2.new(1, 1)
	window.Position = UDim2.new(1, -Theme.Phone.Margin, 1, -Theme.Phone.Margin)
	window.BackgroundColor3 = Style.Body
	window.BorderSizePixel = 0
	window.Visible = false
	window.SelectionGroup = true
	window.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	window.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	window.Parent = safe
	Components.Corner(window, Style.BodyRadius)
	local edge = Components.Stroke(window, Style.Border, 0.3)
	edge.Thickness = 2.5
	local screen = Components.Frame(window, "Screen", Style.White)
	screen.Position = UDim2.fromOffset(Style.ScreenInset, Style.ScreenInset)
	screen.Size = UDim2.new(1, -Style.ScreenInset * 2, 1, -Style.ScreenInset * 2)
	Components.Corner(screen, Style.ScreenRadius)
	Components.Gradient(screen, Style.WallpaperTop, Style.WallpaperBottom, 170)
	local appBackground = Components.Frame(screen, "AppBackground", Style.AppBackground)
	appBackground.Size = UDim2.fromScale(1, 1)
	appBackground.Visible = false
	Components.Corner(appBackground, Style.ScreenRadius)
	Components.Gradient(appBackground, Style.AppBackground, Style.AppBackgroundBottom, 180)
	local island = Components.Frame(screen, "DynamicIsland", Color3.new(0, 0, 0))
	island.Size = UDim2.fromOffset(86, 24)
	island.AnchorPoint = Vector2.new(0.5, 0)
	island.Position = UDim2.new(0.5, 0, 0, 10)
	Components.Corner(island, 12)
	local camera = Components.Frame(island, "CameraLens", Color3.fromRGB(12, 14, 22))
	camera.AnchorPoint = Vector2.new(1, 0.5)
	camera.Position = UDim2.new(1, -6, 0.5, 0)
	camera.Size = UDim2.fromOffset(8, 8)
	Components.Corner(camera, 4)
	local lens = Components.Frame(camera, "Shimmer", Color3.fromRGB(30, 35, 55))
	lens.Position = UDim2.fromOffset(2, 2)
	lens.Size = UDim2.fromOffset(4, 4)
	Components.Corner(lens, 2)
	local clock = Components.Label(screen, "", 11)
	clock.Font = Enum.Font.GothamBold
	clock.Position = UDim2.fromOffset(16, 12)
	clock.Size = UDim2.fromOffset(44, 16)
	local status = Components.Label(screen, "⚡ 100%", 9)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -16, 0, 13)
	status.Size = UDim2.fromOffset(50, 16)
	status.TextXAlignment = Enum.TextXAlignment.Right
	local back = Components.Button(screen, "‹", owner, actions.Back)
	back.Name = "Back"
	back.TextSize = 26
	back.Size = UDim2.fromOffset(Theme.TouchTarget, Theme.TouchTarget)
	back.Position = UDim2.fromOffset(12, 40)
	back.BackgroundTransparency = 1
	local backStroke = back:FindFirstChildOfClass("UIStroke")
	if backStroke then backStroke.Enabled = false end
	local title = Components.Label(screen, "Smartfon", 18)
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.fromOffset(64, 40)
	title.Size = UDim2.new(1, -128, 0, 44)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local close = Components.Button(screen, "×", owner, actions.Close)
	close.Name = "Close"
	close.TextSize = 22
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 40)
	close.Size = UDim2.fromOffset(Theme.TouchTarget, Theme.TouchTarget)
	close.BackgroundTransparency = 1
	local closeStroke = close:FindFirstChildOfClass("UIStroke")
	if closeStroke then closeStroke.Enabled = false end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 96)
	scroll.Size = UDim2.new(1, -32, 1, -164)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Style.Dimmed
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Selectable = false
	scroll.Parent = screen
	local home = Components.Button(screen, "", owner, function() actions.Navigate("Home") end)
	home.Name = "Home"
	home.AnchorPoint = Vector2.new(0.5, 1)
	home.Position = UDim2.new(0.5, 0, 1, -2)
	home.Size = UDim2.fromOffset(120, Theme.TouchTarget)
	home.BackgroundTransparency = 1
	local homeStroke = home:FindFirstChildOfClass("UIStroke")
	if homeStroke then homeStroke.Enabled = false end
	local indicator = Components.Frame(home, "Indicator", Style.HomeBar)
	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Position = UDim2.new(0.5, 0, 1, -4)
	indicator.Size = UDim2.fromOffset(90, 4)
	indicator.BackgroundTransparency = 0.3
	Components.Corner(indicator, 2)
	local hud = Components.Button(hudGui, "", owner, actions.Toggle)
	hud.Name = "PhoneBtn"
	hud.Position = UDim2.fromOffset(16, 72)
	hud.Size = UDim2.fromOffset(120, Theme.TouchTarget)
	hud.BackgroundColor3 = Style.White
	Components.Gradient(hud, Color3.fromRGB(24, 26, 32), Color3.fromRGB(16, 18, 22), 45)
	local hudStroke = hud:FindFirstChildOfClass("UIStroke")
	if hudStroke then hudStroke.Color = Style.Accent; hudStroke.Thickness = 1.5 end
	local hudLabel = Components.Label(hud, "TELEFON", 14)
	hudLabel.Font = Enum.Font.GothamBold
	hudLabel.Position = UDim2.fromOffset(14, 0)
	hudLabel.Size = UDim2.new(1, -50, 1, 0)
	local badge = Components.Frame(hud, "KeyBadge", Style.White)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -8, 0.5, 0)
	badge.Size = UDim2.fromOffset(26, 26)
	Components.Corner(badge, 6)
	Components.Gradient(badge, Color3.fromRGB(50, 50, 55), Color3.fromRGB(30, 30, 35), 45)
	local badgeLabel = Components.Label(badge, "M", 14)
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.TextXAlignment = Enum.TextXAlignment.Center
	badgeLabel.Size = UDim2.fromScale(1, 1)
	local pageScope: Scope.Scope? = nil
	local currentPage: Types.Page = "Home"
	local firstApp: TextButton? = nil
	local grid: UIGridLayout? = nil
	local open = false
	local tween: Tween? = nil
	local timer: thread? = nil
	local function stopTransition()
		if tween then tween:Cancel(); tween = nil end
		if timer then
			if coroutine.status(timer) ~= "dead" then task.cancel(timer) end
			timer = nil
		end
	end
	owner:Give(function() stopTransition(); if pageScope then pageScope:Clean() end end)
	local function layout()
		local input = UserInputService.PreferredInput.Name
		local width, height = Layout.PhoneWindow(safe.AbsoluteSize.X, safe.AbsoluteSize.Y, input)
		window.Size = UDim2.fromOffset(width, height)
		shadow.Size = UDim2.fromOffset(width + 16, height + 16)
		badge.Visible = input ~= "Touch"
		badgeLabel.Text = if input == "Gamepad" then "X" else "M"
		if grid then
			local available = math.max(1, width - Style.ScreenInset * 2 - Theme.Phone.Padding * 2 - 8)
			local columns = math.clamp(math.floor((available + Theme.Spacing) / (Style.IconSize + Theme.Spacing)), 1, 3)
			grid.CellSize = UDim2.fromOffset(math.floor((available - (columns - 1) * Theme.Spacing) / columns), Theme.Phone.IconHeight)
		end
	end
	owner:Give(safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	owner:Give(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(layout))
	layout()
	local function setInteractive()
		for _, object in window:GetDescendants() do
			if object:IsA("TextButton") then
				local enabled = open and object:GetAttribute("Enabled") == true
				object.Interactable = open
				object.Active = enabled
				object.Selectable = enabled
			elseif object:IsA("TextBox") then
				object.TextEditable = open
				object.Selectable = open
			end
		end
	end
	local function setBusy(busy: boolean, ready: boolean)
		for _, object in scroll:GetDescendants() do
			if object:IsA("TextButton") and object:GetAttribute("PhoneAction") then
				Components.SetEnabled(object, ready and not busy and object:GetAttribute("Available") == true)
			end
		end
		setInteractive()
	end
	local function render(page: Types.Page, state: Types.State, draft: string, busy: boolean, ready: boolean)
		local changedPage = currentPage ~= page
		local selectedPath: { string } = {}
		local selected = GuiService.SelectedObject
		if not changedPage and selected and selected:IsDescendantOf(scroll) then
			local ancestor: Instance? = selected
			while ancestor and ancestor ~= scroll do
				table.insert(selectedPath, 1, ancestor.Name)
				ancestor = ancestor.Parent
			end
		end
		local position = if currentPage == page then scroll.CanvasPosition else Vector2.zero
		if pageScope then pageScope:Clean() end
		local nextScope = Scope.new()
		pageScope = nextScope
		currentPage = page
		grid = nil
		firstApp = nil
		local content = Components.Frame(scroll, "Page")
		content.BackgroundTransparency = 1
		content.Size = UDim2.fromScale(1, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
		nextScope:Give(content)
		title.Visible = page ~= "Home"
		back.Visible = page ~= "Home"
		appBackground.Visible = page ~= "Home"
		scroll.Position = UDim2.fromOffset(16, if page == "Home" then 64 else 96)
		scroll.Size = UDim2.new(1, -32, 1, if page == "Home" then -132 else -164)
		Components.SetEnabled(back, page ~= "Home")
		Components.SetEnabled(home, page ~= "Home")
		back.BackgroundTransparency = 1
		home.BackgroundTransparency = 1
		if page == "Home" then
			local nextGrid = Instance.new("UIGridLayout")
			nextGrid.SortOrder = Enum.SortOrder.LayoutOrder
			nextGrid.CellPadding = UDim2.fromOffset(Theme.Spacing, Theme.Spacing)
			nextGrid.Parent = content
			grid = nextGrid
			for index, app in Apps do
				local container = Components.Frame(content, app.id)
				container.BackgroundTransparency = 1
				container.LayoutOrder = index
				local button = Components.Button(container, "", nextScope, function() actions.Navigate(app.id) end)
				button.Name = "Icon"
				button.BackgroundColor3 = Style.White
				button.AnchorPoint = Vector2.new(0.5, 0)
				button.Position = UDim2.fromScale(0.5, 0)
				button.Size = UDim2.fromOffset(Style.IconSize, Style.IconSize)
				local corner = button:FindFirstChildOfClass("UICorner")
				if corner then corner.CornerRadius = UDim.new(0, 16) end
				local stroke = button:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Enabled = false end
				local palettes: { [string]: { Top: Color3, Bottom: Color3 } } = Style.Apps
				local palette = palettes[app.id]
				Components.Gradient(button, palette.Top, palette.Bottom, 135)
				local sheen = Components.Frame(button, "Sheen", Style.White)
				sheen.Size = UDim2.fromScale(1, 0.45)
				sheen.BackgroundTransparency = 0.85
				Components.Corner(sheen, 16)
				if not firstApp then firstApp = button end
				if app.imageId and app.imageId ~= "" then
					local icon = Instance.new("ImageLabel")
					icon.BackgroundTransparency = 1
					icon.Image = app.imageId
					icon.ScaleType = Enum.ScaleType.Fit
					icon.Size = UDim2.fromOffset(36, 36)
					icon.Position = UDim2.new(0.5, -18, 0, 12)
					icon.Parent = button
				end
				local label = Components.Label(container, app.label, 11)
				label.Size = UDim2.new(1, -4, 0, 24)
				label.Position = UDim2.fromOffset(2, 56)
				label.TextXAlignment = Enum.TextXAlignment.Center
			end
		else
			for _, app in Apps do if app.id == page then title.Text = app.label end end
			local list = Instance.new("UIListLayout")
			list.Padding = UDim.new(0, Theme.Spacing)
			list.SortOrder = Enum.SortOrder.LayoutOrder
			list.Parent = content
			if ready then
				AppsView.Render(content, nextScope, page, state, draft, actions)
			else
				local status = Components.Label(content, if busy then "Wczytywanie…" else "Nie udało się wczytać danych.", 14, true)
				status.Size = UDim2.new(1, -8, 0, 56)
				status.TextWrapped = true
				status.LayoutOrder = 1
				local retry = Components.Button(content, "Spróbuj ponownie", nextScope, actions.Refresh)
				retry.Name = "Retry"
				retry.LayoutOrder = 2
				retry.Size = UDim2.new(1, -8, 0, Theme.TouchTarget)
				Components.SetEnabled(retry, not busy)
			end
		end
		setBusy(busy, ready)
		layout()
		scroll.CanvasPosition = position
		if open and changedPage then
			stopTransition()
			window.GroupTransparency = 0.12
			local nextTween = TweenService:Create(window, TweenInfo.new(Theme.Motion.Short), { GroupTransparency = 0 })
			tween = nextTween
			nextTween:Play()
		end
		local restored: Instance? = scroll
		for _, name in selectedPath do restored = if restored then restored:FindFirstChild(name) else nil end
		return if #selectedPath > 0 and restored and restored:IsA("GuiObject") and restored.Selectable then restored else nil
	end
	local function setOpen(value: boolean)
		open = value
		stopTransition()
		setInteractive()
		if value then
			if not window.Visible then window.GroupTransparency = 1 end
			window.Visible = true
			shadow.Visible = true
			clock.Text = os.date("%H:%M")
		end
		local nextTween = TweenService:Create(window, TweenInfo.new(Theme.Motion.Panel), { GroupTransparency = if value then 0 else 1 })
		tween = nextTween
		nextTween:Play()
		if not value then
			timer = task.delay(Theme.Motion.Panel, function()
				timer = nil
				if not open then window.Visible = false; shadow.Visible = false end
			end)
		end
	end
	return {
		Window = window, Scroll = scroll, HUD = hud, Back = back, Close = close,
		Render = render, SetBusy = setBusy, SetOpen = setOpen,
		DefaultSelection = function(): GuiObject return if currentPage == "Home" and firstApp then firstApp else back end,
		UpdateClock = function() clock.Text = os.date("%H:%M") end,
	}
end

export type View = typeof(PhoneView.new(...))
return PhoneView
