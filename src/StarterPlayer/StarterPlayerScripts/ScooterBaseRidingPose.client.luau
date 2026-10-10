--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local BasePose = require(ReplicatedStorage.Shared.Scooter.ScooterBasePose)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)

type Rider = { humanoid: Humanoid, rig: BasePose.Rig }
local scope = Scope.new()
local models: { [Model]: Scope.Scope } = {}
local active: { [Model]: Rider } = {}
local folderScope: Scope.Scope? = nil
local watchedFolder: Instance? = nil

local function release(model: Model)
	local rider = active[model]
	active[model] = nil
	if rider then BasePose.Restore(rider.rig) end
end

local function watchModel(instance: Instance)
	if not instance:IsA("Model") or models[instance] then return end
	local model = instance
	local seat = model:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") then return end
	local modelScope = Scope.new()
	models[model] = modelScope
	local riderScope: Scope.Scope? = nil
	local function refresh()
		if riderScope then riderScope:Clean(); riderScope = nil end
		release(model)
		local humanoid = seat.Occupant
		local character = if humanoid then humanoid.Parent else nil
		if not humanoid or humanoid.Health <= 0 or not character or not character:IsA("Model") then return end
		local mountedScope = Scope.new()
		riderScope = mountedScope
		local function bind()
			if active[model] or seat.Occupant ~= humanoid then return end
			local rig = BasePose.Bind(character)
			if rig then active[model] = { humanoid = humanoid, rig = rig } end
		end
		-- Character joints may replicate after Occupant; retry on actual arrivals.
		mountedScope:Give(character.DescendantAdded:Connect(bind))
		mountedScope:Give(humanoid.Died:Connect(function() release(model) end))
		mountedScope:Give(character.Destroying:Connect(function() release(model) end))
		bind()
	end
	modelScope:Give(function()
		models[model] = nil
		if riderScope then riderScope:Clean(); riderScope = nil end
		release(model)
	end)
	modelScope:Give(seat:GetPropertyChangedSignal("Occupant"):Connect(refresh))
	modelScope:Give(model.Destroying:Connect(function() modelScope:Clean() end))
	modelScope:Give(model.AncestryChanged:Connect(function()
		if model.Parent ~= watchedFolder then modelScope:Clean() end
	end))
	refresh()
end

local function clearFolder()
	if folderScope then folderScope:Clean(); folderScope = nil end
	watchedFolder = nil
	for _, modelScope in models do modelScope:Clean() end
end

local function watchFolder(folder: Instance)
	if folder.Name ~= Config.ScooterFolderName or folder == watchedFolder then return end
	clearFolder()
	watchedFolder = folder
	local nextScope = Scope.new()
	folderScope = nextScope
	nextScope:Give(folder.ChildAdded:Connect(watchModel))
	nextScope:Give(folder.AncestryChanged:Connect(function()
		if folder.Parent ~= Workspace then clearFolder() end
	end))
	for _, model in folder:GetChildren() do watchModel(model) end
end

scope:Give(clearFolder)
scope:Give(Workspace.ChildAdded:Connect(watchFolder))
-- Animate evaluates first; a single final pose pass prevents sitting/mood tracks
-- from folding the rider's limbs. Each client poses every rider it can see.
scope:Give(RunService.PreSimulation:Connect(function()
	for model, rider in active do
		local seat = model:FindFirstChild("DriverSeat")
		-- Occupant can arrive before Humanoid.SeatPart on the observing client.
		-- Use the same seat signal that established this binding.
		if rider.humanoid.Health <= 0 or not seat or not seat:IsA("VehicleSeat")
			or seat.Occupant ~= rider.humanoid or not model.Parent then
			release(model)
		else
			BasePose.Update(rider.rig, model)
		end
	end
end))
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
local folder = Workspace:FindFirstChild(Config.ScooterFolderName)
if folder then watchFolder(folder) end
