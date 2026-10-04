--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local DashboardConfig = require(ReplicatedStorage.Shared.Scooter.ScooterDashboardConfig)
local Dashboard = require(ReplicatedStorage.Shared.Scooter.ScooterDashboard)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)

type Binding = { screen: BasePart, controller: Dashboard.Controller }
local bindings: { [Model]: Binding } = {}
local pending: { [Model]: boolean } = {}
local scope = Scope.new()
local folderScope: Scope.Scope? = nil
local currentFolder: Instance? = nil
local destroyed = false

local function remove(scooter: Model)
	local binding = bindings[scooter]
	if binding then
		bindings[scooter] = nil
		binding.controller.Destroy()
	end
end

local function refresh(scooter: Model)
	if destroyed or scooter.Parent ~= currentFolder then remove(scooter); return end
	local dashboard = scooter:FindFirstChild(DashboardConfig.ModelName)
	local screen = if dashboard and dashboard:IsA("Model") then dashboard:FindFirstChild(DashboardConfig.ScreenName) else nil
	local existing = bindings[scooter]
	if existing then
		if screen == existing.screen then return end
		remove(scooter)
	end
	if screen and screen:IsA("BasePart") then
		local controller = Dashboard.Bind(scooter, screen)
		if controller then bindings[scooter] = { screen = screen, controller = controller } end
	end
end

local function schedule(instance: Instance)
	local scooter: Instance? = instance
	while scooter and scooter.Parent ~= currentFolder do scooter = scooter.Parent end
	if not scooter or not scooter:IsA("Model") or pending[scooter] then return end
	pending[scooter] = true
	task.defer(function()
		pending[scooter] = nil
		refresh(scooter)
	end)
end

local function detachFolder()
	if folderScope then folderScope:Clean(); folderScope = nil end
	currentFolder = nil
	for scooter in bindings do remove(scooter) end
	table.clear(pending)
end

local function attachFolder(folder: Instance)
	if destroyed or folder.Name ~= Config.ScooterFolderName or not folder:IsA("Folder") then return end
	detachFolder()
	currentFolder = folder
	local cleanup = Scope.new()
	folderScope = cleanup
	cleanup:Give(folder.ChildAdded:Connect(schedule))
	cleanup:Give(folder.ChildRemoved:Connect(function(instance)
		if instance:IsA("Model") then remove(instance) end
	end))
	-- A model may arrive before its SurfaceGui, digits and segments replicate.
	cleanup:Give(folder.DescendantAdded:Connect(schedule))
	cleanup:Give(folder.DescendantRemoving:Connect(function(instance)
		local ancestor: Instance? = instance
		while ancestor and ancestor.Parent ~= folder do ancestor = ancestor.Parent end
		if ancestor and ancestor:IsA("Model") then
			local binding = bindings[ancestor]
			if binding and (instance == binding.screen or instance:IsDescendantOf(binding.screen)) then
				remove(ancestor)
				schedule(ancestor)
			end
		end
	end))
	cleanup:Give(folder.Destroying:Connect(detachFolder))
	for _, scooter in folder:GetChildren() do schedule(scooter) end
end

scope:Give(workspace.ChildAdded:Connect(attachFolder))
scope:Give(workspace.ChildRemoved:Connect(function(instance)
	if instance == currentFolder then detachFolder() end
end))
local folder = workspace:FindFirstChild(Config.ScooterFolderName)
if folder then attachFolder(folder) end

script.Destroying:Connect(function()
	destroyed = true
	scope:Clean()
	detachFolder()
end)
