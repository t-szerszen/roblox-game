--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local BasePose = require(ReplicatedStorage.Shared.Scooter.ScooterBasePose)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)

type Rider = { humanoid: Humanoid, rig: BasePose.Rig, animator: Animator?, originalLod: boolean }
local scope = Scope.new()
local models: { [Model]: Scope.Scope } = {}
local active: { [Model]: Rider } = {}
local folderScope: Scope.Scope? = nil
local watchedFolder: Instance? = nil

local function release(model: Model)
	local rider = active[model]
	active[model] = nil
	if rider then
		BasePose.Restore(rider.rig)
		if rider.animator and rider.animator.Parent then rider.animator.PreferLodEnabled = rider.originalLod end
	end
end

local function watchModel(instance: Instance)
	if not instance:IsA("Model") or models[instance] then return end
	local model = instance
	local seat: VehicleSeat? = nil
	local modelScope = Scope.new()
	models[model] = modelScope
	local riderScope: Scope.Scope? = nil
	local function refresh()
		local currentSeat = seat
		if not currentSeat then return end
		if riderScope then riderScope:Clean(); riderScope = nil end
		release(model)
		local humanoid = currentSeat.Occupant
		local character = if humanoid then humanoid.Parent else nil
		if not humanoid or humanoid.Health <= 0 or not character or not character:IsA("Model") then return end
		local mountedScope = Scope.new()
		riderScope = mountedScope
		local function bind()
			if active[model] or currentSeat.Occupant ~= humanoid then return end
			local rig = BasePose.Bind(character)
			if rig then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				active[model] = { humanoid = humanoid, rig = rig, animator = animator,
					originalLod = if animator then animator.PreferLodEnabled else true }
			end
		end
		-- Character joints may replicate after Occupant; retry on actual arrivals.
		mountedScope:Give(character.DescendantAdded:Connect(bind))
		mountedScope:Give(humanoid.Died:Connect(function() release(model) end))
		mountedScope:Give(character.Destroying:Connect(function() release(model) end))
		bind()
		-- Attachment offsets may finish replicating without adding another descendant.
		local bindingAlive = true
		mountedScope:Give(function() bindingAlive = false end)
		task.spawn(function()
			local deadline = os.clock() + 20
			while bindingAlive and not active[model] and currentSeat.Occupant == humanoid and os.clock() < deadline do
				task.wait(0.1)
				if bindingAlive then bind() end
			end
		end)
	end
	modelScope:Give(function()
		models[model] = nil
		if riderScope then riderScope:Clean(); riderScope = nil end
		release(model)
	end)
	local function attachSeat(candidate: Instance)
		if seat or candidate.Name ~= "DriverSeat" or not candidate:IsA("VehicleSeat") then return end
		seat = candidate
		modelScope:Give(candidate:GetPropertyChangedSignal("Occupant"):Connect(refresh))
		refresh()
	end
	-- Streaming may deliver the Model before its seat. Register its lifetime now
	-- and attach when the existing descendant arrives, rather than missing it forever.
	modelScope:Give(model.ChildAdded:Connect(attachSeat))
	modelScope:Give(model.Destroying:Connect(function() modelScope:Clean() end))
	modelScope:Give(model.AncestryChanged:Connect(function()
		if model.Parent ~= watchedFolder then modelScope:Clean() end
	end))
	local existingSeat = model:FindFirstChild("DriverSeat")
	if existingSeat then attachSeat(existingSeat) end
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
scope:Give(RunService.PreSimulation:Connect(function(deltaTime: number)
	for model, rider in active do
		local seat = model:FindFirstChild("DriverSeat")
		-- Occupant can arrive before Humanoid.SeatPart on the observing client.
		-- Use the same seat signal that established this binding.
		if rider.humanoid.Health <= 0 or not seat or not seat:IsA("VehicleSeat")
			or seat.Occupant ~= rider.humanoid or not model.Parent then
			release(model)
		else
			local camera = Workspace.CurrentCamera
			local animationDistance = Config.RiderAnimationDistance or 150
			local nearby = not camera or (camera.CFrame.Position - rider.rig.rootPart.Position).Magnitude <= animationDistance
			if rider.animator and rider.animator.Parent then
				local preferLod = rider.originalLod and not nearby
				if rider.animator.PreferLodEnabled ~= preferLod then rider.animator.PreferLodEnabled = preferLod end
			end
			-- A throttled remote Animator may retain its previous limb matrices even
			-- when Transform was set. Full fidelity is bounded to nearby mounted rigs.
			if nearby or not rider.originalLod or (rider.animator and not rider.animator.EvaluationThrottled) then
				BasePose.Update(rider.rig, model, deltaTime)
			end
		end
	end
end))
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
local folder = Workspace:FindFirstChild(Config.ScooterFolderName)
if folder then watchFolder(folder) end
