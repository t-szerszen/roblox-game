-- Run after Rojo sync in the Command Bar (Edit, Server or Client).
-- All test objects remain outside the DataModel; the authored game is untouched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Dashboard = require(ReplicatedStorage.Shared.Scooter.ScooterDashboard)
local model = Instance.new("Model")
local screen = Instance.new("Part")
screen.Name = "DisplaySurface"
screen.Parent = model
local gui = Instance.new("SurfaceGui")
gui.Name = "DashboardGui"
gui.Parent = screen
local brake = Instance.new("TextLabel")
brake.Name = "Brake"
brake.Parent = gui
local mode = Instance.new("TextLabel")
mode.Name = "Mode"
mode.Parent = gui
for index = 1, 3 do
	local digit = Instance.new("Frame")
	digit.Name = "Digit" .. index
	digit.Parent = gui
	for _, name in { "A", "B", "C", "D", "E", "F", "G" } do
		local segment = Instance.new("Frame")
		segment.Name = name
		segment.Parent = digit
	end
end
local copyScreen = Instance.new("Part")
local ok, result = xpcall(function()
	local binding = assert(Dashboard.Bind(model, screen))
	model:SetAttribute("SpeedKmh", 47)
	model:SetAttribute("BrakeActive", true)
	model:SetAttribute("DriveMode", "ECO")
	task.wait()
	assert(gui.Digit2.F.BackgroundTransparency == 0 and gui.Digit2.A.BackgroundTransparency > 0)
	assert(brake.TextTransparency == 0)
	assert(mode.Text == "ECO")
	local left = gui.Digit2.Position.X.Scale * gui.CanvasSize.X + gui.Digit2.Position.X.Offset
	local right = gui.Digit3.Position.X.Scale * gui.CanvasSize.X + gui.Digit3.Position.X.Offset + gui.Digit3.Size.X.Offset
	assert(math.abs((left + right) / 2 - gui.CanvasSize.X / 2) < 0.01)
	local presentation = assert(Dashboard.CreatePresentation(model, screen, copyScreen))
	assert(not gui.Enabled and copyScreen.DashboardGui.Enabled)
	model:SetAttribute("SpeedKmh", 105)
	model:SetAttribute("DriveMode", "SPORT")
	task.wait()
	assert(copyScreen.DashboardGui.Digit1.Visible)
	assert(copyScreen.DashboardGui.Mode.Text == "SPORT")
	presentation.Destroy()
	presentation.Destroy()
	assert(copyScreen:FindFirstChild("DashboardGui") == nil)
	assert(gui.Enabled)
	binding.Destroy()
	model:SetAttribute("BrakeActive", false)
	task.wait()
	assert(brake.TextTransparency == 0)
	return "PASS: Roblox Instance dashboard centering, speed, brake, modes, presentation and cleanup"
end, debug.traceback)
copyScreen:Destroy()
model:Destroy()
if not ok then error(result) end
print(result)
return result
