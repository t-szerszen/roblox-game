--!strict

local Config = require(script.Parent.ScooterDashboardConfig)
local Scope = require(script.Parent.Parent.UI.Scope)

export type Controller = { Destroy: () -> () }
type Digit = { frame: Frame, segments: { [string]: Frame }, y: UDim }

local masks = { "ABCDEF", "BC", "ABDEG", "ABCDG", "BCFG", "ACDFG", "ACDEFG", "ABC", "ABCDEFG", "ABCDFG" }
local segmentNames = { "A", "B", "C", "D", "E", "F", "G" }
local ScooterDashboard = {}

-- Server attributes already use the game's km/h scale, including reverse travel.
function ScooterDashboard.FormatSpeed(value: unknown): string
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return "-" end
	return tostring(math.clamp(math.floor(math.max(0, value) + 0.5), 0, Config.MaxDisplaySpeed))
end

function ScooterDashboard.Bind(scooter: Model, screen: BasePart): Controller?
	local gui = screen:FindFirstChild(Config.GuiName)
	if not gui or not gui:IsA("SurfaceGui") then return nil end
	local brake = gui:FindFirstChild("Brake")
	local modeLabel = gui:FindFirstChild("Mode")
	if not brake or not brake:IsA("TextLabel") then return nil end
	local digits: { Digit } = {}
	for index = 1, 3 do
		local frame = gui:FindFirstChild("Digit" .. index)
		if not frame or not frame:IsA("Frame") then return nil end
		local segments: { [string]: Frame } = {}
		for _, name in segmentNames do
			local segment = frame:FindFirstChild(name)
			if not segment or not segment:IsA("Frame") then return nil end
			segments[name] = segment
		end
		table.insert(digits, { frame = frame, segments = segments, y = frame.Position.Y })
	end
	local scope = Scope.new()
	local function updateSpeed()
		local text = ScooterDashboard.FormatSpeed(scooter:GetAttribute(Config.SpeedAttribute))
		local digitWidth = digits[1].frame.Size.X.Offset
		local stride = digitWidth + Config.DigitGapPixels
		local textWidth = #text * digitWidth + (#text - 1) * Config.DigitGapPixels
		for index, digit in digits do
			local textIndex = index - (3 - #text)
			local character = if textIndex > 0 then string.sub(text, textIndex, textIndex) else ""
			digit.frame.Visible = character ~= ""
			-- Center the visible number, including single and three-digit speeds.
			digit.frame.Position = UDim2.new(0.5, -textWidth / 2 + (textIndex - 1) * stride, digit.y.Scale, digit.y.Offset)
			local number = tonumber(character)
			local mask = if number then masks[number + 1] else if character == "-" then "G" else ""
			for name, segment in digit.segments do
				segment.BackgroundTransparency = if string.find(mask, name, 1, true)
					then Config.SegmentOnTransparency else Config.SegmentOffTransparency
			end
		end
	end
	local function updateBrake()
		brake.TextTransparency = if scooter:GetAttribute(Config.BrakeAttribute) == true
			then Config.BrakeOnTransparency else Config.BrakeOffTransparency
	end
	local function updateMode()
		if not modeLabel or not modeLabel:IsA("TextLabel") then return end
		local mode = scooter:GetAttribute(Config.DriveModeAttribute)
		modeLabel.Text = if mode == "ECO" or mode == "SPORT" then mode else "-"
		modeLabel.TextColor3 = if mode == "ECO" then Config.EcoColor else Config.SportColor
	end
	-- No per-frame UI work or extra remotes; observers use the same replicated data.
	scope:Give(scooter:GetAttributeChangedSignal(Config.SpeedAttribute):Connect(updateSpeed))
	scope:Give(scooter:GetAttributeChangedSignal(Config.BrakeAttribute):Connect(updateBrake))
	scope:Give(scooter:GetAttributeChangedSignal(Config.DriveModeAttribute):Connect(updateMode))
	scope:Give(scooter.Destroying:Connect(function() scope:Clean() end))
	scope:Give(screen.Destroying:Connect(function() scope:Clean() end))
	scope:Give(gui.Destroying:Connect(function() scope:Clean() end))
	updateSpeed()
	updateBrake()
	updateMode()
	return { Destroy = function() scope:Clean() end }
end

function ScooterDashboard.CreatePresentation(scooter: Model, source: BasePart, destination: BasePart): Controller?
	local gui = source:FindFirstChild(Config.GuiName)
	if not gui or not gui:IsA("SurfaceGui") then return nil end
	-- Keep scripts and other gameplay objects out of the visual prediction model.
	for _, child in gui:GetDescendants() do
		if not child:IsA("GuiObject") and not child:IsA("UIComponent") then return nil end
	end
	local copy = gui:Clone()
	copy.Adornee = destination
	copy.Parent = destination
	local binding = ScooterDashboard.Bind(scooter, destination)
	if not binding then copy:Destroy(); return nil end
	local originalEnabled = gui.Enabled
	-- SurfaceGui remains visible on a transparent part, so hiding the source
	-- mesh alone would leave a second screen behind the moving presentation.
	gui.Enabled = false
	local scope = Scope.new()
	scope:Give(copy)
	scope:Give(binding.Destroy)
	scope:Give(function()
		if gui.Parent then gui.Enabled = originalEnabled end
	end)
	scope:Give(gui.Destroying:Connect(function() scope:Clean() end))
	scope:Give(destination.Destroying:Connect(function() scope:Clean() end))
	return { Destroy = function() scope:Clean() end }
end

return ScooterDashboard
