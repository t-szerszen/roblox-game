--!strict

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Scope = require(script.Parent.Scope)
type Scope = Scope.Scope

local Components = {}

function Components.Corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Radius)
	corner.Parent = parent
end

function Components.Stroke(parent: Instance, color: Color3?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Border
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Components.Frame(parent: Instance, name: string, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color or Theme.Colors.Surface
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function Components.Label(parent: Instance, text: string, size: number?, muted: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.Text = text
	label.TextSize = size or 14
	label.TextColor3 = if muted then Theme.Colors.Muted else Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

function Components.Button(parent: Instance, text: string, scope: Scope, onClick: () -> (), primary: boolean?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.BackgroundColor3 = if primary then Theme.Colors.Accent else Theme.Colors.Raised
	button.BorderSizePixel = 0
	button.TextColor3 = if primary then Theme.Colors.AccentText else Theme.Colors.Text
	button.Font = Theme.StrongFont
	button.TextSize = 14
	button.Text = text
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(120, Theme.TouchTarget)
	button:SetAttribute("Enabled", true)
	button.Parent = parent
	Components.Corner(button, 10)
	local stroke = Components.Stroke(button)
	local selection = Instance.new("Frame")
	selection.Size = UDim2.new(1, 6, 1, 6)
	selection.Position = UDim2.fromOffset(-3, -3)
	selection.BackgroundTransparency = 1
	Components.Corner(selection, 12)
	local focusStroke = Components.Stroke(selection, Theme.Colors.Accent, 0)
	focusStroke.Thickness = 2
	button.SelectionImageObject = selection
	scope:Give(selection)
	local hovered = false
	local selected = false
	local tween: Tween? = nil
	local function update()
		if tween then tween:Cancel() end
		local nextTween = TweenService:Create(stroke, TweenInfo.new(Theme.Motion.Short), {
			Transparency = if button.Active and (hovered or selected) then 0 else 0.6,
		})
		tween = nextTween
		nextTween:Play()
	end
	scope:Give(function() if tween then tween:Cancel() end end)
	scope:Give(button.MouseEnter:Connect(function() hovered = true; update() end))
	scope:Give(button.MouseLeave:Connect(function() hovered = false; update() end))
	scope:Give(button.SelectionGained:Connect(function() selected = true; update() end))
	scope:Give(button.SelectionLost:Connect(function() selected = false; update() end))
	scope:Give(button.Activated:Connect(function()
		if button:GetAttribute("Enabled") == true then onClick() end
	end))
	return button
end

function Components.SetEnabled(button: TextButton, enabled: boolean)
	button:SetAttribute("Enabled", enabled)
	button.Active = enabled
	button.Selectable = enabled
	button.BackgroundTransparency = if enabled then 0 else 0.45
	button.TextTransparency = if enabled then 0 else 0.35
end

return Components
