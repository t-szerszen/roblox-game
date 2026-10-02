--!strict
--[[
	ActionHUD — Unified top-left HUD buttons for Shop and Phone toggles.
	Vibrant, juicy, 3D toy-like buttons matching the cartoony Roblox
	simulator aesthetic (Pet Sim 99 / Blade Ball style).

	Communication:
	  • Fires BindableEvents inside ShopGui/PhoneGui created by their
	    respective client scripts.
	  • Reads ShopOpen / PhoneOpen attributes to track active state.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- ─── Maid ──────────────────────────────────────────────────────────────
type Maid = {
	tasks: { RBXScriptConnection | Instance },
	Give: (self: Maid, task: RBXScriptConnection | Instance) -> (),
	Clean: (self: Maid) -> (),
}
local function newMaid(): Maid
	local m: any = {}
	m.tasks = {}
	function m:Give(task: RBXScriptConnection | Instance)
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

local maid = newMaid()

-- ─── UI Helpers ────────────────────────────────────────────────────────

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function uiStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function makeGradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2),
	})
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- ─── Root GUI ──────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "ActionHUD"
gui.DisplayOrder = 25
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Container: top-left, below native Roblox topbar
local container = Instance.new("Frame")
container.Name = "HUDContainer"
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.new(0, 16, 0, 58)
container.Size = UDim2.fromOffset(110, 76)
container.BackgroundTransparency = 1
container.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.Parent = container

-- ─── Button builder ────────────────────────────────────────────────────

type HUDButtonConfig = {
	name: string,
	label: string,
	icon: string,
	keybind: string,
	gradColor1: Color3,
	gradColor2: Color3,
	strokeColor: Color3,
	bevelColor: Color3,
	order: number,
}

local function createHUDButton(config: HUDButtonConfig): (Frame, TextButton, UIStroke)
	-- Fixed size layout wrapper (prevents UIListLayout reflow on hover)
	local layoutWrapper = Instance.new("Frame")
	layoutWrapper.Name = config.name .. "Layout"
	layoutWrapper.Size = UDim2.fromOffset(100, 34)
	layoutWrapper.BackgroundTransparency = 1
	layoutWrapper.LayoutOrder = config.order
	layoutWrapper.Parent = container

	-- Anim wrapper: tween target for hover/press (centered inside layout wrapper)
	local wrapper = Instance.new("Frame")
	wrapper.Name = "AnimWrapper"
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.Position = UDim2.new(0.5, 0, 0.5, 0)
	wrapper.Size = UDim2.new(1, 0, 1, 0)
	wrapper.BackgroundTransparency = 1
	wrapper.Parent = layoutWrapper

	-- Bottom bevel shadow (exactly 2px visible at the bottom)
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.AnchorPoint = Vector2.new(0.5, 0)
	bevel.Position = UDim2.new(0.5, 0, 0, 0)
	bevel.Size = UDim2.new(1, 0, 1, 0)
	bevel.BackgroundColor3 = config.bevelColor
	bevel.ZIndex = 1
	bevel.Parent = wrapper
	corner(bevel, 11)

	-- Main button (2px shorter than bevel)
	local button = Instance.new("TextButton")
	button.Name = config.name
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 0)
	button.Size = UDim2.new(1, 0, 1, -2)
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBlack
	button.Text = ""
	button.ZIndex = 2
	button.Parent = wrapper
	corner(button, 11)
	makeGradient(button, config.gradColor1, config.gradColor2, 90)
	local btnStroke = uiStroke(button, config.strokeColor, 2)

	-- Icon + Label
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Text = config.icon
	iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.TextSize = 14
	iconLabel.Position = UDim2.fromOffset(8, 0)
	iconLabel.Size = UDim2.new(0, 20, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.TextYAlignment = Enum.TextYAlignment.Center
	iconLabel.ZIndex = 3
	iconLabel.Parent = button

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBlack
	textLabel.Text = config.label
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextSize = 11
	textLabel.Position = UDim2.fromOffset(26, 0)
	textLabel.Size = UDim2.new(1, -50, 1, 0)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.ZIndex = 3
	textLabel.Parent = button

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = config.strokeColor
	textStroke.Thickness = 1
	textStroke.Parent = textLabel

	-- Keybind badge (vertically centered)
	local badge = Instance.new("Frame")
	badge.Name = "KeyBadge"
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -5, 0.5, 0)
	badge.Size = UDim2.fromOffset(20, 14)
	badge.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	badge.BackgroundTransparency = 0.2
	badge.ZIndex = 4
	badge.Parent = button
	corner(badge, 5)

	local badgeText = Instance.new("TextLabel")
	badgeText.BackgroundTransparency = 1
	badgeText.Font = Enum.Font.GothamBold
	badgeText.Text = config.keybind
	badgeText.TextColor3 = Color3.fromRGB(220, 225, 235)
	badgeText.TextSize = 8
	badgeText.Size = UDim2.new(1, 0, 1, 0)
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	badgeText.TextYAlignment = Enum.TextYAlignment.Center
	badgeText.ZIndex = 5
	badgeText.Parent = badge

	return wrapper, button, btnStroke
end

-- ─── Create buttons ────────────────────────────────────────────────────

local shopWrapper, shopBtn, shopStroke = createHUDButton({
	name = "ShopHUD",
	label = "SKLEP",
	icon = "🛒",
	keybind = "B",
	gradColor1 = Color3.fromRGB(255, 208, 0),
	gradColor2 = Color3.fromRGB(255, 145, 0),
	strokeColor = Color3.fromRGB(168, 91, 0),
	bevelColor = Color3.fromRGB(140, 75, 0),
	order = 1,
})

local phoneWrapper, phoneBtn, phoneStroke = createHUDButton({
	name = "PhoneHUD",
	label = "TELEFON",
	icon = "📱",
	keybind = "M",
	gradColor1 = Color3.fromRGB(0, 229, 255),
	gradColor2 = Color3.fromRGB(0, 136, 255),
	strokeColor = Color3.fromRGB(0, 68, 136),
	bevelColor = Color3.fromRGB(0, 55, 110),
	order = 2,
})

-- ─── Micro-Interactions ────────────────────────────────────────────────
-- Tween the WRAPPER (offset-based) to avoid Scale multiplication bugs.

local TWEEN_HOVER   = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_PRESS   = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_RELEASE = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function addInteractions(wrapper: Frame, button: TextButton, btnStroke: UIStroke)
	local hovering = false

	maid:Give(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hovering = true
			TweenService:Create(wrapper, TWEEN_HOVER, {
				Size = UDim2.new(1.05, 0, 1.05, 0),
			}):Play()
			TweenService:Create(btnStroke, TWEEN_HOVER, {
				Transparency = 0.3,
				Thickness = 3.5,
			}):Play()
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(wrapper, TWEEN_PRESS, {
				Size = UDim2.new(0.94, 0, 0.94, 0),
			}):Play()
		end
	end))

	maid:Give(button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hovering = false
			TweenService:Create(wrapper, TWEEN_RELEASE, {
				Size = UDim2.new(1, 0, 1, 0),
			}):Play()
			TweenService:Create(btnStroke, TWEEN_HOVER, {
				Transparency = 0,
				Thickness = 2.5,
			}):Play()
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(wrapper, TWEEN_RELEASE, {
				Size = UDim2.new(if hovering then 1.05 else 1, 0, if hovering then 1.05 else 1, 0),
			}):Play()
		end
	end))
end

addInteractions(shopWrapper, shopBtn, shopStroke)
addInteractions(phoneWrapper, phoneBtn, phoneStroke)

-- ─── Target GUI References ────────────────────────────────────────────

-- Wait for ShopGui and PhoneGui to be created by their respective scripts
local shopGui: ScreenGui? = nil
local phoneGui: ScreenGui? = nil
local shopToggle: BindableEvent? = nil
local phoneToggle: BindableEvent? = nil

local function findTargetGuis()
	-- Shop
	local sg = playerGui:FindFirstChild("ShopGui")
	if sg and sg:IsA("ScreenGui") then
		shopGui = sg
		local ev = sg:FindFirstChild("ToggleShop")
		if ev and ev:IsA("BindableEvent") then
			shopToggle = ev
		end
	end
	-- Phone
	local pg = playerGui:FindFirstChild("PhoneGui")
	if pg and pg:IsA("ScreenGui") then
		phoneGui = pg
		local ev = pg:FindFirstChild("TogglePhone")
		if ev and ev:IsA("BindableEvent") then
			phoneToggle = ev
		end
	end
end

-- Try immediately, then retry until found
task.spawn(function()
	for _ = 1, 60 do
		findTargetGuis()
		if shopToggle and phoneToggle then break end
		task.wait(0.25)
	end
end)

-- ─── Phone active state glow ───────────────────────────────────────────

local phoneGlowActive = false
local phoneGlowTween: Tween? = nil

local function updatePhoneActiveState(isOpen: boolean)
	if isOpen and not phoneGlowActive then
		phoneGlowActive = true
		-- Pulsing glow on phone stroke when active
		phoneGlowTween = TweenService:Create(phoneStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Thickness = 5,
			Color = Color3.fromRGB(0, 255, 255),
		})
		phoneGlowTween:Play()
	elseif not isOpen and phoneGlowActive then
		phoneGlowActive = false
		if phoneGlowTween then
			phoneGlowTween:Cancel()
			phoneGlowTween = nil
		end
		TweenService:Create(phoneStroke, TweenInfo.new(0.2), {
			Thickness = 3,
			Color = Color3.fromRGB(0, 68, 136),
		}):Play()
	end
end

-- Listen for attribute changes on PhoneGui
task.spawn(function()
	-- Wait until phoneGui is resolved
	while not phoneGui do task.wait(0.5) end
	local pg = phoneGui :: ScreenGui
	maid:Give(pg:GetAttributeChangedSignal("PhoneOpen"):Connect(function()
		local isOpen = pg:GetAttribute("PhoneOpen")
		updatePhoneActiveState(isOpen == true)
	end))
	-- Sync initial state
	updatePhoneActiveState(pg:GetAttribute("PhoneOpen") == true)
end)

-- ─── Shop-open: hide HUD buttons ──────────────────────────────────────

task.spawn(function()
	while not shopGui do task.wait(0.5) end
	local sg = shopGui :: ScreenGui
	maid:Give(sg:GetAttributeChangedSignal("ShopOpen"):Connect(function()
		container.Visible = sg:GetAttribute("ShopOpen") ~= true
	end))
	container.Visible = sg:GetAttribute("ShopOpen") ~= true
end)

-- ─── Button click handlers ─────────────────────────────────────────────

maid:Give(shopBtn.Activated:Connect(function()
	findTargetGuis() -- Ensure reference is fresh
	if shopToggle then
		shopToggle:Fire()
	end
end))

maid:Give(phoneBtn.Activated:Connect(function()
	findTargetGuis()
	if phoneToggle then
		phoneToggle:Fire()
	end
end))

-- ─── Keyboard shortcuts (redundant safety — scripts also listen) ──────
-- These are here so buttons respond even if the target scripts' own
-- InputBegan listeners are suppressed (e.g., during textbox focus).

maid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		findTargetGuis()
		if shopToggle then shopToggle:Fire() end
	elseif input.KeyCode == Enum.KeyCode.M then
		findTargetGuis()
		if phoneToggle then phoneToggle:Fire() end
	end
end))

-- ─── Cleanup ───────────────────────────────────────────────────────────

script.Destroying:Connect(function()
	if phoneGlowTween then phoneGlowTween:Cancel() end
	maid:Clean()
	gui:Destroy()
end)
