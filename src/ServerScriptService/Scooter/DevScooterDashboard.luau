--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterDashboardConfig)

local DevScooterDashboard = {}

local function assertEditMode()
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play before creating or mounting the dashboard")
end

local function getScreen(model: Model): BasePart
	local screen = model:FindFirstChild(Config.ScreenName)
	assert(screen and screen:IsA("BasePart"), "Dashboard requires " .. Config.ScreenName)
	return screen
end

local function weldHousing(model: Model, screen: BasePart)
	model.PrimaryPart = screen
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= screen then
			local existing = part:FindFirstChild("DashboardInternalWeld")
			if existing then
				assert(existing:IsA("WeldConstraint") and existing.Part0 == screen and existing.Part1 == part,
					"DashboardInternalWeld must join the display to its housing")
			else
				local weld = Instance.new("WeldConstraint")
				weld.Name = "DashboardInternalWeld"
				weld.Part0 = screen
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
end

function DevScooterDashboard.Create(): Model
	assertEditMode()
	local template = ReplicatedStorage:FindFirstChild(Config.TemplateName)
	assert(template and template:IsA("Model"), "Sync the dashboard template through Rojo first")
	local model = template:Clone()
	model.Name = Config.ModelName
	local screen = getScreen(model)
	weldHousing(model, screen)
	local camera = workspace.CurrentCamera
	if camera then
		local position = camera.CFrame.Position + camera.CFrame.LookVector * 6
		model:PivotTo(CFrame.lookAt(position, camera.CFrame.Position))
	end
	model.Parent = workspace
	Selection:Set({ model })
	print("Dashboard created. Position the whole Model, then select it and the complete scooter and run MountSelection().")
	return model
end

function DevScooterDashboard.MountSelection(): Model
	assertEditMode()
	local selected = Selection:Get()
	assert(#selected == 2, "Select the dashboard Model and the complete scooter Folder/Model")
	local dashboard: Model? = nil
	local scooter: Instance? = nil
	for _, instance in selected do
		if instance:IsA("Model") and instance.Name == Config.ModelName then
			dashboard = instance
		elseif instance:IsA("Model") or instance:IsA("Folder") then
			scooter = instance
		end
	end
	assert(dashboard and scooter, "Select one ScooterDashboard and one complete scooter")
	assert(not dashboard:IsDescendantOf(scooter), "This dashboard is already mounted")
	assert(not scooter:FindFirstChild(Config.ModelName), "The scooter already has a dashboard; retain or move it before mounting another")
	local handleBar = scooter:FindFirstChild("HandleBar")
	assert(handleBar and handleBar:IsA("BasePart"), "The selected scooter requires HandleBar")
	local screen = getScreen(dashboard)
	assert(screen:FindFirstChild(Config.GuiName), "Dashboard GUI is missing")
	weldHousing(dashboard, screen)
	for _, part in dashboard:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part:SetAttribute(Config.DecorationAttribute, true)
		end
	end
	-- Preserve the placement chosen in Studio and weld to the steering assembly.
	local mount = Instance.new("WeldConstraint")
	mount.Name = "ScooterDashboardMount"
	mount.Part0 = handleBar
	mount.Part1 = screen
	mount.Parent = screen
	dashboard.Parent = scooter
	for _, part in dashboard:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = false end
	end
	Selection:Set({ dashboard })
	print("Dashboard mounted to HandleBar. Save the place; install the authored scooter if this is not the installed template.")
	return dashboard
end

function DevScooterDashboard.UpdateSelection(): SurfaceGui
	assertEditMode()
	local selected = Selection:Get()
	assert(#selected == 1, "Select a dashboard Model or the complete scooter containing it")
	local dashboard = if selected[1].Name == Config.ModelName then selected[1] else selected[1]:FindFirstChild(Config.ModelName)
	assert(dashboard and dashboard:IsA("Model"), "The selection must contain ScooterDashboard")
	local screen = getScreen(dashboard)
	local template = ReplicatedStorage:FindFirstChild(Config.TemplateName)
	assert(template and template:IsA("Model"), "Sync the latest dashboard template through Rojo first")
	local source = getScreen(template):FindFirstChild(Config.GuiName)
	assert(source and source:IsA("SurfaceGui"), "Template GUI is missing")
	local previous = screen:FindFirstChild(Config.GuiName)
	assert(not previous or previous:IsA("SurfaceGui"), "DashboardGui must be a SurfaceGui")
	local replacement = source:Clone()
	local backups = ServerStorage:FindFirstChild("ScooterDashboardBackups")
	assert(not backups or backups:IsA("Folder"), "ScooterDashboardBackups must be a Folder")
	if previous and previous:IsA("SurfaceGui") then
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "ScooterDashboardBackups"
			backups.Parent = ServerStorage
		end
		previous.Enabled = false
		previous.Name = Config.GuiName .. "_" .. HttpService:GenerateGUID(false)
		previous.Parent = backups
	end
	replacement.Parent = screen
	Selection:Set({ dashboard })
	print("Dashboard screen updated; placement, scale and welds retained. Previous GUI is in ServerStorage.ScooterDashboardBackups.")
	return replacement
end

return DevScooterDashboard
