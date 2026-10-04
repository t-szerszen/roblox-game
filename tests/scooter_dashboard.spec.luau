local start = testCount
local Dashboard = loadModule("ReplicatedStorage/Shared/Scooter/ScooterDashboard")
local DashboardConfig = loadModule("ReplicatedStorage/Shared/Scooter/ScooterDashboardConfig")
check(Dashboard.FormatSpeed(0) == "0", "Stationary display has no leading zeroes")
check(Dashboard.FormatSpeed(47.6) == "48", "Display rounds authoritative km/h")
check(Dashboard.FormatSpeed(105) == "105", "Three-digit speeds fit")
check(Dashboard.FormatSpeed(1000) == "999", "Display bounds unusually large speeds")
check(Dashboard.FormatSpeed(-10) == "0", "Negative malformed speed is bounded")
for _, value in { "55", {}, 0 / 0, math.huge, -math.huge } do
	check(Dashboard.FormatSpeed(value) == "-", "Malformed or unavailable state cannot become a false speed")
end
check(Dashboard.FormatSpeed(nil) == "-", "Late speed replication displays unavailable state")

local scooter = make(nil, "Model", "DashboardTest")
local screen = make(scooter, "Part", "DisplaySurface")
local gui = make(screen, "SurfaceGui", "DashboardGui")
local brake = make(gui, "TextLabel", "Brake")
local mode = make(gui, "TextLabel", "Mode")
gui.CanvasSize = { X = 1000, Y = 400 }
check(Dashboard.Bind(scooter, screen) == nil, "Binding waits for the whole screen to replicate")
for index = 1, 3 do
	local digit = make(gui, "Frame", "Digit" .. index)
	digit.Size = baseEnvironment.UDim2.new(0, 112, 0, 212)
	digit.Position = baseEnvironment.UDim2.new(0, 0, 0, 91)
	for _, name in { "A", "B", "C", "D", "E", "F", "G" } do make(digit, "Frame", name) end
end
local controller = assert(Dashboard.Bind(scooter, screen))
check(gui.Digit3.G.BackgroundTransparency == 0 and not gui.Digit1.Visible,
	"Missing server state displays a single dash")
scooter:SetAttribute("SpeedKmh", 47)
check(not gui.Digit1.Visible and gui.Digit2.Visible and gui.Digit3.Visible, "Speed occupies two digits")
check(gui.Digit2.Position.X.Scale == 0.5 and gui.Digit2.Position.X.Offset == -122
	and gui.Digit3.Position.X.Offset == 10, "Two digits are centered as one readable number")
check(gui.Digit2.A.BackgroundTransparency == DashboardConfig.SegmentOffTransparency
	and gui.Digit2.F.BackgroundTransparency == 0 and gui.Digit2.G.BackgroundTransparency == 0,
	"Authoritative speed updates the segment pattern")
scooter:SetAttribute("BrakeActive", true)
check(brake.TextTransparency == 0, "Server brake attribute lights the red indicator")
scooter:SetAttribute("BrakeActive", false)
check(brake.TextTransparency == DashboardConfig.BrakeOffTransparency, "Brake release dims the indicator")
scooter:SetAttribute("DriveMode", "ECO")
check(mode.Text == "ECO" and mode.TextColor3 == DashboardConfig.EcoColor, "The dashboard renders the server's ECO mode")
scooter:SetAttribute("DriveMode", "SPORT")
check(mode.Text == "SPORT" and mode.TextColor3 == DashboardConfig.SportColor, "The dashboard renders the server's SPORT mode")
scooter:SetAttribute("SpeedKmh", 0)
check(not gui.Digit2.Visible and gui.Digit3.Visible and gui.Digit3.G.BackgroundTransparency > 0,
	"Stopping shows zero without a flickering middle segment")
check(gui.Digit3.Position.X.Offset == -56, "Single-digit zero stays at the center")

local destination = make(nil, "Part", "PresentationScreen")
local presentation = assert(Dashboard.CreatePresentation(scooter, screen, destination))
local copy = destination.DashboardGui
check(not gui.Enabled and copy.Enabled, "Presentation suppresses the original screen to avoid double rendering")
scooter:SetAttribute("SpeedKmh", 105)
check(copy.Digit1.Visible and copy.Digit1.A.BackgroundTransparency > 0,
	"Prediction presentation is bound to the real scooter state")
check(copy.Digit1.Position.X.Offset == -188 and copy.Digit3.Position.X.Offset == 76,
	"Three digits remain centered and fit without shrinking")
presentation.Destroy()
presentation.Destroy()
check(copy.destroyed and not gui.destroyed, "Disposal destroys only the presentation GUI")
check(gui.Enabled, "Presentation cleanup restores authored screen visibility")
local automatic = assert(Dashboard.CreatePresentation(scooter, screen, destination))
destination:Destroy()
check(gui.Enabled, "Destroying a presentation destination restores the source GUI automatically")
automatic.Destroy()
local injection = make(gui, "LocalScript", "UnexpectedScript")
check(Dashboard.CreatePresentation(scooter, screen, destination) == nil,
	"Presentation never admits scripts from an authored GUI")
injection:Destroy()

controller.Destroy()
controller.Destroy()
scooter:SetAttribute("BrakeActive", true)
scooter:SetAttribute("SpeedKmh", 2)
check(brake.TextTransparency == DashboardConfig.BrakeOffTransparency and gui.Digit1.Visible,
	"Disposed bindings no longer update the screen")
local replacement = assert(Dashboard.Bind(scooter, screen))
screen:Destroy()
scooter:SetAttribute("BrakeActive", false)
check(brake.TextTransparency == 0, "Destroyed screen disconnects attribute callbacks")
replacement.Destroy()

-- Exercise actual mounting code without altering the existing scooter fixture.
local configModule = make(services.ReplicatedStorage.Shared.Scooter, "ModuleScript", "ScooterDashboardConfig")
configModule._values._path = "ReplicatedStorage/Shared/Scooter/ScooterDashboardConfig"
local Developer = loadModule("ServerScriptService/Scooter/DevScooterDashboard")
local target = make(nil, "Model", "scooter")
local handleBar = make(target, "MeshPart", "HandleBar")
local dashboard = make(nil, "Model", "ScooterDashboard")
local mountScreen = make(dashboard, "Part", "DisplaySurface")
make(mountScreen, "SurfaceGui", "DashboardGui")
local housing = make(dashboard, "Part", "Housing")
housing.Anchored = true
local pose = housing.CFrame
local previousGetSelection = services.Selection.Get
services.Selection.Get = function() return services.Selection.selected end
services.Selection.selected = { dashboard, target }
Developer.MountSelection()
check(dashboard.Parent == target and not housing.Anchored and housing.Massless and not housing.CanCollide,
	"Mounting preserves the steering physics and adds no collisions or mass")
check(housing.CFrame == pose and mountScreen.ScooterDashboardMount.Part0 == handleBar,
	"Mounting retains Studio placement and welds to HandleBar")
check(housing.DashboardInternalWeld.Part0 == mountScreen,
	"Imported housing receives internal welds before it is unanchored")
local unprepared = source:Clone()
unprepared:SetAttribute("ArticulatedScooter", nil)
local optional = make(unprepared, "Part", "OptionalDecoration")
optional:SetAttribute("ScooterDecoration", true)
local prepared = Rig.Prepare(unprepared)
check(prepared.OptionalDecoration.Massless and not prepared.OptionalDecoration.CanCollide,
	"Rig installation retains the decorative part's massless contract")
do
local template = make(services.ReplicatedStorage, "Model", DashboardConfig.TemplateName)
local templateScreen = make(template, "Part", DashboardConfig.ScreenName)
local updatedGui = make(templateScreen, "SurfaceGui", DashboardConfig.GuiName)
local templateMode = make(updatedGui, "TextLabel", "Mode")
templateMode.Text = "SPORT"
local oldGui = mountScreen.DashboardGui
local oldMount = mountScreen.ScooterDashboardMount
services.Selection.selected = { target }
local updated = Developer.UpdateSelection()
check(updated.Parent == mountScreen and updated.Mode.Text == "SPORT",
	"Updating an existing dashboard installs the new GUI without replacing the model")
check(oldGui.Parent == services.ServerStorage.ScooterDashboardBackups and not oldGui.Enabled,
	"Updating retains the previous GUI in backups")
check(housing.CFrame == pose and mountScreen.ScooterDashboardMount == oldMount,
	"Screen updates preserve authored placement and steering welds")
template.Parent = nil
local beforeFailure = mountScreen.DashboardGui
check(not pcall(Developer.UpdateSelection) and mountScreen.DashboardGui == beforeFailure,
	"A missing template cannot overwrite an existing dashboard")
end
local another = make(nil, "Model", "ScooterDashboard")
make(another, "Part", "DisplaySurface")
services.Selection.selected = { another, target }
check(not pcall(Developer.MountSelection) and another.Parent == nil,
	"A duplicate dashboard cannot replace existing work")
services.Selection.selected = { dashboard, target }
local isRunning = services.RunService.IsRunning
services.RunService.IsRunning = function() return true end
check(not pcall(Developer.MountSelection), "Developer mounting is forbidden during Play")
services.RunService.IsRunning = isRunning
services.Selection.Get = previousGetSelection
print(string.format("PASS: %d dashboard lifecycle and mounting assertions", testCount - start))
