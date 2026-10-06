--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterDashboardConfig)
local Dashboard = require(ReplicatedStorage.Shared.Scooter.ScooterDashboard)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)

export type Controller = { Destroy: () -> () }
local ScooterSpeedometer = {}

local function round(parent: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function label(parent: Instance, name: string, text: string, position: UDim2, size: UDim2, fontSize: number): TextLabel
	local node = Instance.new("TextLabel")
	node.Name, node.Text, node.Position, node.Size = name, text, position, size
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.BackgroundTransparency = 1
	node.Font = Enum.Font.GothamBold
	node.TextSize = fontSize
	node.TextColor3 = Color3.fromRGB(240, 242, 248)
	node.Parent = parent
	return node
end

function ScooterSpeedometer.Start(scooter: Model, playerGui: PlayerGui): Controller
	local scope = Scope.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ScooterSpeedometer"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	scope:Give(gui)
	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.AnchorPoint = Vector2.one
	dial.Position = UDim2.new(1, -24, 1, -32)
	dial.Size = UDim2.fromOffset(Config.HudDiameter, Config.HudDiameter)
	dial.BackgroundColor3 = Color3.fromRGB(13, 16, 23)
	dial.BackgroundTransparency = 0.16
	dial.Parent = gui
	round(dial, UDim.new(0.5, 0))
	local scale = Instance.new("UIScale")
	scale.Parent = dial
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(72, 80, 99)
	rim.Thickness = 2
	rim.Transparency = 0.25
	rim.Parent = dial
	for index = 0, 20 do
		local angle = math.rad(-225 + index * 13.5)
		local major = index % 2 == 0
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. index
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.425, 0.5 + math.sin(angle) * 0.425)
		tick.Size = UDim2.fromOffset(if major then 3 else 2, if major then 11 else 5)
		tick.Rotation = math.deg(angle) + 90
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = if index >= 18 then Color3.fromRGB(255, 62, 83) else Color3.fromRGB(213, 220, 233)
		tick.BackgroundTransparency = if major then 0 else 0.5
		tick.Parent = dial
		round(tick, UDim.new(1, 0))
		if major then
			local number = label(dial, "Mark" .. index, tostring(index * 5),
				UDim2.fromScale(0.5 + math.cos(angle) * 0.33, 0.5 + math.sin(angle) * 0.33),
				UDim2.fromOffset(26, 20), 13)
			if index >= 18 then number.TextColor3 = Color3.fromRGB(255, 62, 83) end
		end
	end
	local rotor = Instance.new("Frame")
	rotor.Name = "NeedleRotor"
	rotor.BackgroundTransparency = 1
	rotor.Size = UDim2.fromScale(1, 1)
	rotor.Rotation = -225
	rotor.Parent = dial
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.new(0.36, 0, 0, 3)
	needle.AnchorPoint = Vector2.new(0, 0.5)
	needle.BackgroundColor3 = Config.SportColor
	needle.BorderSizePixel = 0
	needle.Parent = rotor
	round(needle, UDim.new(1, 0))
	local hub = Instance.new("Frame")
	hub.Name = "GearHub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(40, 40)
	hub.BackgroundColor3 = Color3.fromRGB(19, 23, 31)
	hub.Parent = dial
	round(hub, UDim.new(0.5, 0))
	local gear = label(hub, "Gear", "N", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), 19)
	local speed = label(dial, "Speed", "0", UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.6, 0.22), 42)
	label(dial, "Units", "km/h", UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.4, 0.1), 11).TextColor3 = Color3.fromRGB(158, 170, 190)
	local mode = label(dial, "Mode", "SPORT", UDim2.fromScale(0.5, 0.29), UDim2.fromScale(0.5, 0.1), 11)
	local brake = label(dial, "Brake", "BRAKE", UDim2.fromScale(0.5, 0.63), UDim2.fromScale(0.45, 0.08), 11)
	brake.TextColor3 = Color3.fromRGB(255, 83, 97)
	local light = label(dial, "Headlight", "L  ŚWIATŁA", UDim2.fromScale(0.5, 1.09), UDim2.new(1, 0, 0, 20), 11)
	local target, angle = -225, -225
	local function refresh()
		local value = scooter:GetAttribute("SpeedKmh")
		speed.Text = Dashboard.FormatSpeed(value)
		local numeric = if typeof(value) == "number" and value == value then math.clamp(value, 0, Config.HudMaxSpeed) else 0
		target = -225 + 270 * numeric / Config.HudMaxSpeed
		local driveMode = scooter:GetAttribute("DriveMode")
		mode.Text = if driveMode == "ECO" then "ECO" else "SPORT"
		mode.TextColor3 = if driveMode == "ECO" then Config.EcoColor else Config.SportColor
		needle.BackgroundColor3 = mode.TextColor3
		local forward = scooter:GetAttribute("ForwardSpeed")
		gear.Text = if typeof(forward) ~= "number" or math.abs(forward) < 0.25 then "N" else if forward < 0 then "R" else "D"
		brake.Visible = scooter:GetAttribute("BrakeActive") == true
		light.TextColor3 = if scooter:GetAttribute("HeadlightEnabled") == true then Config.EcoColor else Color3.fromRGB(149, 160, 180)
	end
	for _, attribute in { "SpeedKmh", "ForwardSpeed", "BrakeActive", "DriveMode", "HeadlightEnabled" } do
		scope:Give(scooter:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	scope:Give(RunService.RenderStepped:Connect(function(deltaTime: number)
		local camera = workspace.CurrentCamera
		gui.Enabled = camera ~= nil
		if not camera or not gui.Enabled then return end
		scale.Scale = math.clamp(math.min(camera.ViewportSize.X / 1100, camera.ViewportSize.Y / 750), 0.65, 1)
		angle += (target - angle) * (1 - math.exp(-Config.HudNeedleSmoothSpeed * math.clamp(deltaTime, 0, 0.1)))
		rotor.Rotation = angle
	end))
	scope:Give(scooter.Destroying:Connect(function() scope:Clean() end))
	refresh()
	return { Destroy = function() scope:Clean() end }
end

return ScooterSpeedometer
