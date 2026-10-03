--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = require(ReplicatedStorage.Shared.UI.Components)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Style = require(ReplicatedStorage.Shared.Phone.PhoneTheme)
local Components = {}

Components.SetEnabled = Shared.SetEnabled
Components.Corner = Shared.Corner

function Components.Gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function Components.Stroke(parent: Instance, color: Color3?, transparency: number?): UIStroke
	return Shared.Stroke(parent, color or Style.Border, transparency)
end

function Components.Frame(parent: Instance, name: string, color: Color3?): Frame
	return Shared.Frame(parent, name, color or Style.Row)
end

function Components.Label(parent: Instance, text: string, size: number?, muted: boolean?): TextLabel
	local label = Shared.Label(parent, text, size, muted)
	label.TextColor3 = if muted then Style.Muted else Style.White
	label.Font = Enum.Font.GothamMedium
	return label
end

function Components.Button(parent: Instance, text: string, scope: Scope.Scope, onClick: () -> (), primary: boolean?, accent: Color3?): TextButton
	-- Keep activation guards, event cleanup and controller focus from shared buttons.
	local button = Shared.Button(parent, text, scope, onClick, primary)
	button.BackgroundColor3 = if primary then accent or Style.Accent else Style.Raised
	button.TextColor3 = Style.White
	button.Font = Enum.Font.GothamBold
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = Style.Border end
	return button
end

return Components
