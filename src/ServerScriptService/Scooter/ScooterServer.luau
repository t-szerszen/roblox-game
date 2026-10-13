--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local ScooterInput = require(script.Parent.ScooterInput)
local ScooterInventory = require(script.Parent.ScooterInventory)
local ScooterRig = require(script.Parent.ScooterRig)
local ScooterCollision = require(script.Parent.ScooterCollision)
local ScooterBrakeLight = require(script.Parent.ScooterBrakeLight)
local ScooterHeadlight = require(script.Parent.ScooterHeadlight)
local ScooterTerrain = require(script.Parent.ScooterTerrain)
local ScooterScrape = require(script.Parent.ScooterScrape)
local ScooterImpact = require(script.Parent.ScooterImpact)
local Cosmetics = require(script.Parent.ScooterCosmetics)
local PlayerDataService = require(script.Parent.Parent.Activity.PlayerDataService)
local ScooterEffects = require(script.Parent.ScooterEffects)
local UpgradeService = require(script.Parent.ScooterUpgradeService)
local UpgradeVisuals = require(script.Parent.ScooterUpgradeVisuals)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local CombatService = require(script.Parent.Parent.Combat.CombatService)

type Connection = RBXScriptConnection
type ScooterRecord = {
	model: Model,
	effects: ScooterEffects.Effects,
	owner: Player,
	seat: VehicleSeat,
	root: BasePart,
	deckCollider: BasePart,
	smoke: ParticleEmitter,
	upright: AlignOrientation,
	roadBalance: AlignOrientation,
	input: ScooterInput.State,
	tuning: ScooterConfig.Tuning,
	driveMode: string,
	lastModeChangeAt: number,
	lastLightChangeAt: number,
	driveForce: VectorForce,
	frontDriveForce: VectorForce,
	upgradeVisuals: any,
	ridePrompt: ProximityPrompt,
	raycastParams: RaycastParams,
	frontSuspensionPoint: Attachment,
	rearSuspensionPoint: Attachment,
	frontWheelRadius: number,
	backWheelRadius: number,
	wheelBase: number,
	rig: ScooterRig.Rig,
	brakeLight: ScooterBrakeLight.Controller?,
	headlight: ScooterHeadlight.Controller?,
	terrain: ScooterTerrain.Controller,
	scrape: ScooterScrape.Controller,
	impact: ScooterImpact.Tracker,
	additionalMass: number,
	connections: { Connection },
	lastTrickAt: number,
	lastWheelieAt: number,
	throttle: number,
	driveEffort: number,
	brakeEffort: number,
	steering: number,
	turnSteering: number,
	yawRate: number,
	steeringHold: number,
	steeringLean: number,
	wheelieActive: boolean,
	desiredForward: Vector3,
	groundUp: Vector3,
	wheeliePitch: number,
	fallen: boolean,
	fallenAt: number,
	crashToken: number,
	displaySpeedKmh: number,
	speedKmh: number,
	frontGrounded: boolean,
	rearGrounded: boolean,
	burnoutActive: boolean,
	rider: Humanoid?,
	riderConnections: { Connection },
	riderInventoryCleanup: (() -> ())?,
	riderCollisionStates: { [BasePart]: boolean },
	cleaning: boolean,
}

local function applyUpgrades(record: ScooterRecord)
 local name = record.model:GetAttribute("ScooterModel")
 if typeof(name) ~= "string" then return end
 local stats, base = UpgradeService.Calculate(record.owner,name)
 if not stats or not base then return end
 record.tuning = {maxSpeed=stats.SpeedKmh,acceleration=stats.Acceleration,
  turnTorque=base.turnTorque,wheelieTorque=base.wheelieTorque,speedTier=base.speedTier}
 local m=record.model
 m:SetAttribute("SportMaxSpeedKmh",stats.SpeedKmh)
 m:SetAttribute("MaxSpeedKmh",ScooterConfig.GetDriveModeMaxSpeed(stats.SpeedKmh,record.driveMode))
 m:SetAttribute("Acceleration",stats.Acceleration)
 m:SetAttribute("StartBonusPercent",stats.StartBonusPercent)
 m:SetAttribute("WeightRemovedKg",stats.WeightRemovedKg)
 m:SetAttribute("AddedPowerWatts",stats.AddedPowerWatts)
 m:SetAttribute("BrakeForce",stats.BrakeForce)
 m:SetAttribute("WheelieMaxAngle",stats.WheelieAngle)
 m:SetAttribute("UpgradeDualMotor",stats.DualMotor)
 m:SetAttribute("UpgradeDisplayRemoved",stats.DisplayRemoved)
 m:SetAttribute("UpgradeSparksDisabled",stats.SparksDisabled)
 if stats.DisplayRemoved and record.headlight then
  record.headlight.SetActive(false) m:SetAttribute("HeadlightEnabled",false)
 end
 record.upgradeVisuals.Apply(UpgradeService.Equipped(record.owner,name))
end

local ROAD_UP_FRAME = CFrame.Angles(0, 0, math.pi / 2)
local ScooterServer = {}

local recordsByPlayer: { [Player]: ScooterRecord } = {}
local recordsByModel: { [Model]: ScooterRecord } = {}
local lastSpawnByPlayer: { [Player]: number } = {}
local remotesFolder: Folder
local requestSpawnRemote: RemoteEvent
local trickRemote: RemoteEvent
local driveInputRemote: RemoteEvent
local toggleDriveModeRemote: RemoteEvent
local toggleHeadlightRemote: RemoteEvent
local connections: { Connection } = {}
local started = false
local mountLocks: { [Player]: {} } = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = remotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local function setAttributeIfChanged(instance: Instance, name: string, value: boolean | number | string)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function findAttachment(parent: Instance, name: string): Attachment?
	local instance = parent:FindFirstChild(name, true)
	return if instance and instance:IsA("Attachment") then instance else nil
end

local function createAttachment(root: BasePart, name: string, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	attachment.Parent = root
	return attachment
end

local function assignNetworkOwner(root: BasePart, owner: Player?)
	local canSet, reason = root:CanSetNetworkOwnership()
	if not canSet then
		warn(string.format("ScooterServer: cannot assign network ownership: %s", reason))
		return
	end
	root:SetNetworkOwner(owner)
end

local function assignScooterNetworkOwner(model: Model)
	local seen: { [BasePart]: boolean } = {}
	for _, instance in model:GetDescendants() do
		if instance:IsA("BasePart") then
			local assembly = instance.AssemblyRootPart
			if assembly and not seen[assembly] then
				seen[assembly] = true
				assignNetworkOwner(assembly, nil)
			end
		end
	end
end

local function createScooter(owner: Player, modelName: string, templateName: string?): Model
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	local template = if templates then templates:FindFirstChild(templateName or ScooterConfig.TemplateName) else nil
	assert(template, "Missing ServerStorage.ScooterModels.scooter; run DevScooterAssembler.AssembleFromSelection() on the new rig")
	local model = ScooterRig.Prepare(template)

	model.Name = string.format("%s Scooter", owner.Name)
	model:SetAttribute("ScooterModel", modelName)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("BurnoutActive", false)
	model:SetAttribute("BrakeActive", false)
	model:SetAttribute("StopLightActive", false)
	model:SetAttribute("HeadlightEnabled", false)
	model:SetAttribute("WheelieActive", false)
	model:SetAttribute("RiderMounted", false)
	model:SetAttribute("Fallen", false)
	model:SetAttribute("SteeringAngle", 0)
	model:SetAttribute("Steering", 0)
	model:SetAttribute("SteeringInput", 0)
	model:SetAttribute("SpeedKmh", 0)
	model:SetAttribute("ThrottleInput", 0)
	model:SetAttribute("FrontGrounded", false)
	model:SetAttribute("RearGrounded", false)
	model:SetAttribute("DeckGrounded", false)
	model:SetAttribute("ForwardSpeed", 0)
	model:SetAttribute("DriveState", "Idle")
	return model
end

local function sanitizeScooterPhysics(model: Model, root: BasePart, seat: VehicleSeat, smoke: ParticleEmitter)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = descendant:GetAttribute("RuntimeCollisionProxy") == true
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	root.Massless = false
	root.Transparency = 1
	root.RootPriority = 127
	seat.Transparency = 1
	seat.HeadsUpDisplay = false
	seat.Disabled = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	smoke.Enabled = false
	smoke.LightEmission = 0
	smoke.Rate = ScooterConfig.BurnoutSmokeRate
	smoke.Lifetime = ScooterConfig.BurnoutSmokeLifetime
end

local function alignRiderToDeck(record: ScooterRecord, humanoid: Humanoid)
	local character = humanoid.Parent
	local humanoidRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local riderTarget = findAttachment(record.model, "RiderRootAttachment")
	local seatWeld = record.seat:FindFirstChild("SeatWeld")
	if
		not humanoidRoot
		or not humanoidRoot:IsA("BasePart")
		or not riderTarget
		or not seatWeld
		or not seatWeld:IsA("Weld")
	then
		return
	end

	local root = record.root
	local standingHeight: number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local torso = if character then character:FindFirstChild("Torso") else nil
		local leg = if character then character:FindFirstChild("Left Leg") else nil
		standingHeight = if torso and torso:IsA("BasePart") and leg and leg:IsA("BasePart")
			then torso.Size.Y * 0.5 + leg.Size.Y
			else 3
	else
		standingHeight = humanoid.HipHeight + humanoidRoot.Size.Y * 0.5
	end
	local poseOffset = Vector3.new(0, standingHeight, 0)
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		poseOffset = Vector3.new(0, standingHeight - humanoid.HipHeight * ScooterConfig.BaseRidingPose.CrouchHipHeightFraction,
			-ScooterConfig.BaseRidingPose.RootForwardOffset)
	end
	local desiredRootPosition = riderTarget.WorldPosition + (if humanoid.RigType == Enum.HumanoidRigType.R15
		then root.CFrame:VectorToWorldSpace(poseOffset) else poseOffset)
	local desiredRootCFrame = CFrame.new(desiredRootPosition) * root.CFrame.Rotation
	local weldedPart = seatWeld.Part1
	if not weldedPart then
		return
	end
	local weldedPartOffset = humanoidRoot.CFrame:ToObjectSpace(weldedPart.CFrame)
	local desiredWeldedPartCFrame = desiredRootCFrame * weldedPartOffset
	seatWeld.C0 = record.seat.CFrame:ToObjectSpace(desiredWeldedPartCFrame) * seatWeld.C1
end

local function restoreRiderCollisions(record: ScooterRecord)
	for part, canCollide in record.riderCollisionStates do
		if part.Parent ~= nil then
			part.CanCollide = canCollide
		end
	end
	table.clear(record.riderCollisionStates)
end

local function releaseRider(record: ScooterRecord)
	if record.riderInventoryCleanup then
		record.riderInventoryCleanup()
		record.riderInventoryCleanup = nil
	end
	for _, connection in record.riderConnections do
		connection:Disconnect()
	end
	table.clear(record.riderConnections)
	restoreRiderCollisions(record)
	local rider = record.rider
	record.rider = nil
	if rider then
		-- Assembly separation may finish after Occupant changes. Listen for that split
		-- instead of leaving the character server-owned when a single deferred check misses it.
		task.defer(function()
			local character = rider.Parent
			local characterRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if not characterRoot or not characterRoot:IsA("BasePart") then return end
			local pendingConnections: { Connection } = {}
			local finished = false
			local function finish()
				finished = true
				for _, connection in pendingConnections do connection:Disconnect() end
				table.clear(pendingConnections)
			end
			local function tryRestore()
				if finished then return end
				if rider.Parent == nil or characterRoot.Parent == nil or record.rider == rider
					or (rider.SeatPart ~= nil and rider.SeatPart ~= record.seat)
				then
					finish()
				elseif rider.SeatPart == nil and characterRoot.AssemblyRootPart ~= record.root
					and characterRoot:CanSetNetworkOwnership()
				then
					characterRoot:SetNetworkOwnershipAuto()
					finish()
				end
			end
			table.insert(pendingConnections, characterRoot:GetPropertyChangedSignal("AssemblyRootPart"):Connect(tryRestore))
			table.insert(pendingConnections, rider:GetPropertyChangedSignal("SeatPart"):Connect(tryRestore))
			table.insert(pendingConnections, characterRoot.Destroying:Connect(finish))
			tryRestore()
			task.delay(1, function()
				tryRestore()
				finish()
			end)
		end)
	end
end

local function suppressRiderCollisions(record: ScooterRecord, humanoid: Humanoid)
	restoreRiderCollisions(record)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			record.riderCollisionStates[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end
end

local function resetControls(record: ScooterRecord)
	record.roadBalance.Enabled = false
	record.terrain.Update(nil, 0, record.raycastParams)
	record.scrape.Update(false, 0, 0, record.raycastParams)
	ScooterInput.Reset(record.input)
	record.throttle = 0
	record.driveEffort = 0
	record.brakeEffort = 0
	record.steering = 0
	record.turnSteering = 0
	record.yawRate = 0
	record.steeringHold = 0
	local reversing = record.seat.Occupant ~= nil and not record.fallen
		and record.root.AssemblyLinearVelocity:Dot(record.root.CFrame.LookVector) < -ScooterConfig.StopSpeed
	if record.brakeLight then record.brakeLight.SetActive(reversing) end
	setAttributeIfChanged(record.model, "BrakeActive", false)
	setAttributeIfChanged(record.model, "StopLightActive", reversing)
	record.wheelieActive = false
	record.burnoutActive = false
	record.smoke.Enabled = false
	record.rig.backHinge.ActuatorType = Enum.ActuatorType.None
	record.rig.steering.TargetAngle = 0
	record.driveForce.Force = Vector3.zero
	record.frontDriveForce.Force = Vector3.zero
	record.model:SetAttribute("ThrottleInput", 0)
	record.model:SetAttribute("Steering", 0)
	record.model:SetAttribute("SteeringInput", 0)
	record.model:SetAttribute("WheelieActive", false)
	record.model:SetAttribute("WheeliePhysical", false)
	record.model:SetAttribute("BurnoutActive", false)
end

local function dismount(record: ScooterRecord)
 local rider=record.seat.Occupant
 resetControls(record)
 if rider then rider.Sit=false end
 -- This exact seat weld is owned by the scooter; suspension and rider rigs survive.
 local seatWeld=record.seat:FindFirstChild("SeatWeld")
 if seatWeld and seatWeld:IsA("Weld") then seatWeld:Destroy() end
end

local function cleanupRecord(record: ScooterRecord)
	if record.cleaning then
		return
	end

	record.cleaning = true
	if record.brakeLight then record.brakeLight.Destroy() end
	if record.headlight then record.headlight.Destroy() end
	record.terrain.Destroy()
	record.scrape.Destroy()
	if record.rider then
		record.rider.Sit = false
	end
	releaseRider(record)
	record.model:SetAttribute("BurnoutActive", false)
	record.model:SetAttribute("WheelieActive", false)
	setAttributeIfChanged(record.model, "BrakeActive", false)
	for _, connection in ipairs(record.connections) do
		connection:Disconnect()
	end
	record.connections = {}
	recordsByPlayer[record.owner] = nil
	recordsByModel[record.model] = nil
	if record.model.Parent then
		record.model:Destroy()
	end
end

local function getScooterSpawnPivot(model: Model, player: Player): CFrame
	local characterRoot = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	local reference = if characterRoot and characterRoot:IsA("BasePart") then characterRoot.Position else nil
	local selected: SpawnLocation? = nil
	local nearestDistance = math.huge
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			local distance = if reference then (descendant.Position - reference).Magnitude else 0
			if not selected or distance < nearestDistance then
				selected, nearestDistance = descendant, distance
			end
		end
	end
	if selected then
		-- Multiple authored spawns must not send the scooter to a different part of the map.
		local lift = ScooterCollision.GetSpawnLift(model, selected.CFrame.Rotation)
		local heightAboveSpawn = selected.Size.Y * 0.5
			+ math.max(2.5, lift + ScooterConfig.SpawnGroundClearance)
		return selected.CFrame * CFrame.new(8, heightAboveSpawn, 0)
	end

	warn("ScooterServer: no enabled SpawnLocation found; using the world origin")
	return CFrame.new(0, math.max(5, ScooterCollision.GetSpawnLift(model, CFrame.identity)
		+ ScooterConfig.SpawnGroundClearance), 0)
end

local function playerOwnsModel(player: Player, modelName: string): boolean
	local product = ShopConfig.GetScooterProduct(modelName)
	return product ~= nil and PlayerDataService.OwnsScooter(player,modelName)
end

local function spawnForPlayer(player: Player, requestedModel: string?, templateName: string?): Model
	local modelName = requestedModel or ScooterConfig.DefaultModel
	assert(player.Parent == Players and playerOwnsModel(player, modelName), "Cannot spawn an unowned scooter")
	-- Validate the replacement before removing a player's working scooter.
	local scooter = createScooter(player, modelName, templateName)
	local oldRecord = recordsByPlayer[player]
	if oldRecord then cleanupRecord(oldRecord) end
	scooter:PivotTo(getScooterSpawnPivot(scooter, player))
	scooter.Parent = getOrCreateFolder(Workspace, ScooterConfig.ScooterFolderName)

	local root = scooter.PrimaryPart
	local seat = scooter:FindFirstChild("DriverSeat")
	local smoke = scooter:FindFirstChild("BurnoutSmoke", true)
	assert(root ~= nil, "Scooter requires a PrimaryPart")
	assert(seat and seat:IsA("VehicleSeat"), "Scooter requires DriverSeat")
	assert(smoke and smoke:IsA("ParticleEmitter"), "Scooter requires BurnoutSmoke")
	root.Size = Vector3.new(math.min(root.Size.X, 1.6), math.min(root.Size.Y, 0.24), math.min(root.Size.Z, 1.5))
	sanitizeScooterPhysics(scooter, root, seat, smoke)
	local rig = ScooterRig.Inspect(scooter)
	local contacts = ScooterCollision.Configure(scooter)
	local frontSuspensionPoint = rig.frontPoint
	local rearSuspensionPoint = rig.backPoint
	local additionalMass = 0
	for _, instance in scooter:GetDescendants() do
		if instance:IsA("BasePart") and instance ~= root and not instance.Massless then
			additionalMass += instance:GetMass()
		end
	end

	local existingDriveAttachment = root:FindFirstChild("ScooterDriveAttachment")
	local driveAttachment: Attachment
	if existingDriveAttachment and existingDriveAttachment:IsA("Attachment") then
		driveAttachment = existingDriveAttachment
	else
		driveAttachment = Instance.new("Attachment")
		driveAttachment.Name = "ScooterDriveAttachment"
		driveAttachment.Parent = root
	end

	local driveForce = Instance.new("VectorForce")
	driveForce.Name = "ScooterDriveForce"
	driveForce.Attachment0 = driveAttachment
	driveForce.RelativeTo = Enum.ActuatorRelativeTo.World
	driveForce.ApplyAtCenterOfMass = true
	driveForce.Force = Vector3.zero
	driveForce.Parent = root
	local frontDriveForce = driveForce:Clone()
	frontDriveForce.Name = "UpgradeFrontDriveForce"
	frontDriveForce.Attachment0 = rig.frontPoint
	frontDriveForce.Parent = rig.frontAxle

	local upright = Instance.new("AlignOrientation")
	upright.Name = "ScooterUpright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = driveAttachment
	upright.AlignType = Enum.AlignType.AllAxes
	upright.RigidityEnabled = false
	upright.Responsiveness = ScooterConfig.UprightResponsiveness
	upright.MaxAngularVelocity = 8
	upright.CFrame = root.CFrame.Rotation
	upright.Parent = root
	local roadAttachment = Instance.new("Attachment")
	roadAttachment.Name = "ScooterRoadUp"
	roadAttachment.CFrame = ROAD_UP_FRAME
	roadAttachment.Parent = root
	local roadBalance = Instance.new("AlignOrientation")
	roadBalance.Name = "ScooterRoadBalance"
	roadBalance.Mode = Enum.OrientationAlignmentMode.OneAttachment
	roadBalance.AlignType = Enum.AlignType.PrimaryAxisParallel
	roadBalance.Attachment0 = roadAttachment
	roadBalance.RigidityEnabled = true
	roadBalance.Enabled = false
	roadBalance.Parent = root
	local smokeAttachment = findAttachment(scooter, "RearWheelAttachment")
		or createAttachment(rig.backAxle, "RearWheelAttachment", Vector3.zero)
	smokeAttachment.Parent = rig.backAxle
	smokeAttachment.Position = rig.backAxle.CFrame:PointToObjectSpace(rearSuspensionPoint.WorldPosition)
	smoke.Parent = smokeAttachment
	smoke.Color = ColorSequence.new(Color3.new(1, 1, 1))
	-- Base tuning keeps the MVP independent of garage/profile availability.
	local tuning = ScooterConfig.GetTuning(modelName,0)
	assert(tuning, "Unknown scooter model")
	upright.MaxTorque = tuning.turnTorque * (root.AssemblyMass + additionalMass)
	scooter:SetAttribute("UprightSupportMass", root.AssemblyMass + additionalMass)
	scooter:SetAttribute("SpeedUpgradeTier", tuning.speedTier)
	scooter:SetAttribute("MaxSpeedKmh", tuning.maxSpeed)
	scooter:SetAttribute("DriveMode", ScooterConfig.DriveModes.Default)
	scooter:SetAttribute("Acceleration", tuning.acceleration)

	local ridePrompt = Instance.new("ProximityPrompt")
	ridePrompt.Name = "RidePrompt"
	ridePrompt.ActionText = "Ride"
	ridePrompt.ObjectText = modelName
	ridePrompt.KeyboardKeyCode = Enum.KeyCode.E
	ridePrompt.HoldDuration = 0
	ridePrompt.MaxActivationDistance = ScooterConfig.RidePromptDistance
	ridePrompt.RequiresLineOfSight = false
	ridePrompt.Parent = root

	assignScooterNetworkOwner(scooter)
	if root.AssemblyMass == math.huge then
		warn(string.format("ScooterServer: %s scooter assembly contains an anchored part", player.Name))
	end
	local lookVector = root.CFrame.LookVector
	local desiredForward = Vector3.new(lookVector.X, 0, lookVector.Z)
	if desiredForward.Magnitude < 0.01 then
		desiredForward = -Vector3.zAxis
	else
		desiredForward = desiredForward.Unit
	end

	local visualEffects=ScooterEffects.Create(scooter,root,rearSuspensionPoint,smoke)
	ScooterEffects.Apply(visualEffects,Cosmetics.GetVisuals(player,modelName))
	Cosmetics.ApplyPaint(player,scooter)
	local record: ScooterRecord = {
		model = scooter, effects = visualEffects,
		owner = player,
		seat = seat,
		root = root,
		deckCollider = scooter:FindFirstChild("DeckCollider") :: BasePart,
		smoke = smoke,
		upright = upright,
		roadBalance = roadBalance,
		input = ScooterInput.New(),
		tuning = tuning,
		driveMode = ScooterConfig.DriveModes.Default,
		lastModeChangeAt = -math.huge,
		lastLightChangeAt = -math.huge,
		driveForce = driveForce,
		frontDriveForce = frontDriveForce,
		upgradeVisuals = UpgradeVisuals.Create(scooter),
		ridePrompt = ridePrompt,
		raycastParams = RaycastParams.new(),
		frontSuspensionPoint = frontSuspensionPoint,
		rearSuspensionPoint = rearSuspensionPoint,
		frontWheelRadius = contacts.frontRadius,
		backWheelRadius = contacts.backRadius,
		wheelBase = (rig.frontPoint.WorldPosition - rig.backPoint.WorldPosition).Magnitude,
		rig = rig,
		brakeLight = ScooterBrakeLight.Create(scooter),
		headlight = ScooterHeadlight.Create(scooter),
		terrain = ScooterTerrain.Create({
			{ part = rig.frontWheel, point = rig.frontWheel:FindFirstChild("WheelCenter") :: Attachment, radius = contacts.frontRadius },
			{ part = rig.backWheel, point = rig.backWheel:FindFirstChild("WheelCenter") :: Attachment, radius = contacts.backRadius },
		}, root, { root, rig.stick, rig.frontAxle, rig.backAxle, rig.frontWheel, rig.backWheel }),
		scrape = ScooterScrape.Create(scooter, root, rearSuspensionPoint),
		impact = ScooterImpact.New(),
		additionalMass = additionalMass,
		connections = {},
		lastTrickAt = -math.huge,
		lastWheelieAt = -math.huge,
		throttle = 0,
		driveEffort = 0,
		brakeEffort = 0,
		steering = 0,
		turnSteering = 0,
		yawRate = 0,
		steeringHold = 0,
		steeringLean = 0,
		wheelieActive = false,
		desiredForward = desiredForward,
		groundUp = Vector3.yAxis,
		wheeliePitch = 0,
		fallen = false,
		fallenAt = 0,
		crashToken = 0,
		displaySpeedKmh = 0,
		speedKmh = 0,
		frontGrounded = false,
		rearGrounded = false,
		burnoutActive = false,
		rider = nil,
		riderConnections = {},
		riderCollisionStates = {},
		cleaning = false,
	}
	record.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	record.raycastParams.RespectCanCollide = true
	record.raycastParams.FilterDescendantsInstances = { scooter }
	recordsByPlayer[player] = record
	recordsByModel[scooter] = record
	applyUpgrades(record)
	table.insert(record.connections,player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if not record.cleaning then applyUpgrades(record) end
	end))
	table.insert(record.connections,scooter.Destroying:Connect(record.upgradeVisuals.Destroy))

	table.insert(
		record.connections,
		scooter.Destroying:Connect(function()
			cleanupRecord(record)
		end)
	)
	table.insert(
		record.connections,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			releaseRider(record)
			resetControls(record)
			if occupant and (occupant.Parent ~= player.Character or occupant.Health <= 0 or mountLocks[player] ~= nil) then
				occupant.Sit = false
				local seatWeld = seat:FindFirstChild("SeatWeld")
				if seatWeld then seatWeld:Destroy() end
				occupant = nil
			end
			record.model:SetAttribute("RiderMounted", occupant ~= nil)
			if occupant ~= nil and root.Parent ~= nil then
				local mountedRider = occupant
				record.rider = mountedRider
				record.riderInventoryCleanup = ScooterInventory.Lock(mountedRider)
				local character = mountedRider.Parent
				record.raycastParams.FilterDescendantsInstances = if character
					then { scooter, character }
					else { scooter }
				assignScooterNetworkOwner(scooter)
				suppressRiderCollisions(record, mountedRider)
				table.insert(record.riderConnections, mountedRider.Died:Connect(function()
					resetControls(record)
					mountedRider.Sit = false
				end))
				if character then
					table.insert(record.riderConnections, character.DescendantAdded:Connect(function(descendant: Instance)
						if descendant:IsA("BasePart") then
							record.riderCollisionStates[descendant] = descendant.CanCollide
							descendant.CanCollide = false
						end
					end))
				end
				task.defer(function()
					if not record.cleaning and seat.Occupant == mountedRider then
						assignScooterNetworkOwner(scooter)
						alignRiderToDeck(record, mountedRider)
					end
				end)
			else
				record.raycastParams.FilterDescendantsInstances = { scooter }
				assignScooterNetworkOwner(scooter)
				restoreRiderCollisions(record)
			end
			ridePrompt.Enabled = occupant == nil and not seat.Disabled
		end)
	)
	table.insert(
		record.connections,
		ridePrompt.Triggered:Connect(function(triggeringPlayer: Player)
			if triggeringPlayer ~= player or seat.Occupant ~= nil or seat.Disabled or mountLocks[player] ~= nil then
				return
			end

			local character = triggeringPlayer.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local humanoidRootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if not humanoid or humanoid.Health <= 0 or not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
				return
			end
			local stunnedUntil = triggeringPlayer:GetAttribute("StunnedUntil")
			if humanoid.SeatPart ~= nil or (typeof(stunnedUntil) == "number" and stunnedUntil > Workspace:GetServerTimeNow()) then
				return
			end
			if (humanoidRootPart.Position - root.Position).Magnitude > ScooterConfig.RidePromptDistance + 2 then
				return
			end

			ridePrompt.Enabled = false
			seat:Sit(humanoid)
		end)
	)
	table.insert(record.connections, player.CharacterRemoving:Connect(function()
		cleanupRecord(record)
	end))

	return scooter
end


local function setBurnout(record: ScooterRecord, active: boolean)
	if record.burnoutActive == active then
		return
	end

	record.burnoutActive = active
	setAttributeIfChanged(record.model, "BurnoutActive", active)
	record.smoke.Enabled = active
	local motor = record.rig.backHinge
	motor.ActuatorType = if active then Enum.ActuatorType.Motor else Enum.ActuatorType.None
	if active then
		-- Motor torque must overcome tire contact under the entire articulated/rider load.
		local axis = record.rig.backHinge.Attachment0
		local rotationSign = if axis and axis.WorldAxis:Dot(record.root.CFrame.RightVector) < 0 then 1 else -1
		if axis and axis.Parent == record.rig.backWheel then rotationSign = -rotationSign end
		motor.AngularVelocity = rotationSign * ScooterConfig.BurnoutWheelAngularSpeed
		motor.MotorMaxTorque = math.max(ScooterConfig.BurnoutMotorTorque,
			(record.root.AssemblyMass + record.additionalMass) * Workspace.Gravity * record.backWheelRadius
				* ScooterConfig.BurnoutMotorForceScale)
		motor.MotorMaxAcceleration = ScooterConfig.BurnoutMotorAcceleration
	else
		motor.AngularVelocity = 0
	end
end

local function playerOwnsOccupiedScooter(player: Player, record: ScooterRecord): boolean
	local occupant = record.seat.Occupant
	if not occupant or occupant.Health <= 0 or record.owner ~= player or player.Parent ~= Players or mountLocks[player] ~= nil then
		return false
	end
	local stunnedUntil = player:GetAttribute("StunnedUntil")
	if typeof(stunnedUntil) == "number" and stunnedUntil > Workspace:GetServerTimeNow() then
		return false
	end

	local character = occupant.Parent
	return character == player.Character
end

local function crashRider(record: ScooterRecord)
	local humanoid = record.seat.Occupant
	if not humanoid then
		return
	end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end

	record.crashToken += 1
	local crashToken = record.crashToken

	record.seat.Disabled = true
	record.ridePrompt.Enabled = false
	resetControls(record)
	CombatService.StunPlayer(record.owner, ScooterConfig.CrashStunDuration)
	humanoid.Sit = false
	local seatWeld = record.seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		local sideDirection = if math.random() < 0.5 then -1 else 1
		local ejectVelocity = Vector3.yAxis * ScooterConfig.CrashEjectUpVelocity
			+ record.root.CFrame.RightVector * ScooterConfig.CrashEjectSideVelocity * sideDirection
		humanoidRootPart:ApplyImpulse(ejectVelocity * humanoidRootPart.AssemblyMass)
	end

	task.delay(ScooterConfig.CrashStunDuration, function()
		if record.cleaning or record.crashToken ~= crashToken then
			return
		end
		if record.seat.Parent then
			record.seat.Disabled = false
			record.ridePrompt.Enabled = record.seat.Occupant == nil
		end
	end)
end

local function probeGround(
	record: ScooterRecord,
	point: Attachment
): (RaycastResult?, boolean)
	local root = record.root
	if root.CFrame.UpVector.Y < 0.25 then
		return nil, false
	end

	-- A world-down probe keeps the rear contact valid at steep wheelie angles.
	-- The spherical wheel proxies carry the assembly; there is no fake spring
	-- force: authored SpringConstraints provide the suspension travel.
	local lift = ScooterConfig.SuspensionProbeLift
	local origin = point.WorldPosition + Vector3.yAxis * lift
	local radius = if point == record.frontSuspensionPoint then record.frontWheelRadius else record.backWheelRadius
	local rayLength = radius + ScooterConfig.GroundProbeTolerance + ScooterConfig.MaxStepHeight
	local result = Workspace:Raycast(
		origin,
		-Vector3.yAxis * (lift + rayLength),
		record.raycastParams
	)
	if not result or result.Normal.Y < ScooterConfig.GroundMinNormalY then
		-- Read a raised cap when the lower origin lies inside its side, while
		-- preferring the nearby floor when riding beneath an overhead platform.
		result = Workspace:Raycast(origin + Vector3.yAxis * ScooterConfig.MaxStepHeight,
			-Vector3.yAxis * (lift + rayLength + ScooterConfig.MaxStepHeight), record.raycastParams)
	end
	if not result or result.Normal.Y < ScooterConfig.GroundMinNormalY then return nil, false end
	-- A lower surface may inform chassis pitch without authorizing airborne drive.
	local separation = point.WorldPosition.Y - result.Position.Y
	return result, separation >= -ScooterConfig.StepTraction.HeightTolerance
		and separation - radius <= ScooterConfig.GroundProbeTolerance
end

local function probeDeckSupport(record: ScooterRecord): RaycastResult?
	if record.root.CFrame.UpVector.Y < 0.25 then return nil end
	local deck = record.deckCollider
	local lift = deck.Size.Y + ScooterConfig.GroundProbeTolerance
	local thickness = ScooterConfig.DeckSupportProbeThickness
	-- Sample the whole underside: point rays miss narrow supports as they move
	-- between sample positions, cutting drive while the deck still touches them.
	local origin = deck.CFrame * CFrame.new(0, -deck.Size.Y * 0.5 + thickness * 0.5, 0)
		+ Vector3.yAxis * lift
	local hit = Workspace:Blockcast(origin, Vector3.new(deck.Size.X, thickness, deck.Size.Z),
		-Vector3.yAxis * (lift + ScooterConfig.DeckSupportTolerance), record.raycastParams)
	if hit and hit.Normal.Y >= ScooterConfig.GroundMinNormalY
		and deck.CFrame:PointToObjectSpace(hit.Position).Y <= -deck.Size.Y * 0.5
			+ ScooterConfig.StepTraction.HeightTolerance then return hit end
	return nil
end

local function applyParkingDamping(record: ScooterRecord, deltaTime: number)
	local root = record.root
	local nearGround = Workspace:Raycast(
		root.Position + Vector3.yAxis * 0.5,
		-Vector3.yAxis * ScooterConfig.ParkingGroundProbeDistance,
		record.raycastParams
	)
	if not nearGround then
		return
	end

	-- Preserve gravity while removing the horizontal and rotational energy that can
	-- turn an unoccupied, overturned scooter into a bouncing projectile.
	local linearScale = math.exp(-ScooterConfig.ParkingLinearDamping * deltaTime)
	local angularScale = math.exp(-ScooterConfig.ParkingAngularDamping * deltaTime)
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(
		velocity.X * linearScale,
		if velocity.Y > 0 then velocity.Y * linearScale else velocity.Y,
		velocity.Z * linearScale
	)
	root.AssemblyAngularVelocity = root.AssemblyAngularVelocity * angularScale
end

function ScooterServer.RefreshUpgrades(player: Player, model: Model): boolean
 local record=recordsByModel[model]
 if not record or record.owner ~= player or record.cleaning then return false end
 applyUpgrades(record)
 return true
end

function ScooterServer.SpawnForPlayer(player: Player, modelName: string?): Model
	return spawnForPlayer(player, modelName)
end

local function requestSpawn(player: Player, modelName: string, templateName: string?): (boolean, string)
	if mountLocks[player] then return false, "Poczekaj na zakończenie zatrzymania." end
	if player.Parent ~= Players or ScooterConfig.Models[modelName] == nil or not playerOwnsModel(player, modelName) then
		return false, "Nie posiadasz tej hulajnogi."
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return false, "Poczekaj na odrodzenie postaci."
	end

	local now = os.clock()
	local lastSpawn = lastSpawnByPlayer[player]
	if lastSpawn and now - lastSpawn < ScooterConfig.SpawnCooldown then
		return false, "Hulajnoga byla przywolana przed chwila."
	end
	lastSpawnByPlayer[player] = now
	local success, problem = pcall(spawnForPlayer, player, modelName, templateName)
	if not success then
		warn("ScooterServer: " .. tostring(problem))
		return false, "Brak poprawnego nowego modelu hulajnogi."
	end
	local profile=PlayerDataService.GetProfile(player)
	if not templateName and profile and profile.selectedScooter~=modelName then PlayerDataService.SelectScooter(player,modelName) end
	return true, "Hulajnoga czeka przy spawnie."
end

function ScooterServer.RequestSpawnForPlayer(player: Player, modelName: string): (boolean, string)
	return requestSpawn(player, modelName)
end

-- Called only by the server's Studio comparison prompts, never by a RemoteEvent.
function ScooterServer.RequestStudioScaleForPlayer(player: Player, variantId: string): (boolean, string)
	if not RunService:IsStudio() then return false, "Test skali jest dostępny tylko w Studio." end
	for _, variant in ScooterConfig.StudioScaleVariants do
		if variant.Id == variantId then
			return requestSpawn(player, ScooterConfig.DefaultModel, variant.TemplateName)
		end
	end
	return false, "Nieznana skala."
end

function ScooterServer.Start()
	if started then return end
	started = true
	getOrCreateFolder(Workspace, ScooterConfig.ScooterFolderName)
	remotesFolder = getOrCreateFolder(getOrCreateFolder(ReplicatedStorage, "Remotes"), ScooterConfig.RemoteFolderName)
	requestSpawnRemote = getOrCreateRemote("RequestSpawn")
	trickRemote = getOrCreateRemote("TrickState")
	driveInputRemote = getOrCreateRemote("DriveInput")
	toggleDriveModeRemote = getOrCreateRemote(ScooterConfig.DriveModes.ToggleRemoteName)
	toggleHeadlightRemote = getOrCreateRemote(ScooterConfig.Headlight.ToggleRemoteName)

	table.insert(connections, requestSpawnRemote.OnServerEvent:Connect(function(player: Player, requestedModel: unknown)
		if typeof(requestedModel) ~= "string" or #requestedModel > 64 then return end
		ScooterServer.RequestSpawnForPlayer(player, requestedModel)
	end))

	table.insert(connections, driveInputRemote.OnServerEvent:Connect(function(
		player: Player, throttleHeld: unknown, brakeHeld: unknown, steering: unknown, wheelieHeld: unknown
	)
		local record = recordsByPlayer[player]
		if not record or record.fallen or not playerOwnsOccupiedScooter(player, record) then return end
		ScooterInput.Apply(record.input, os.clock(), throttleHeld, brakeHeld, steering, wheelieHeld)
	end))

	table.insert(connections, toggleDriveModeRemote.OnServerEvent:Connect(function(player: Player, ...: unknown)
		-- The client requests one toggle, never a mode, speed or tuning value.
		if select("#", ...) ~= 0 then return end
		local record = recordsByPlayer[player]
		if not record or record.fallen or not playerOwnsOccupiedScooter(player, record) then return end
		local now = os.clock()
		if now - record.lastModeChangeAt < ScooterConfig.DriveModes.ToggleCooldown then return end
		record.lastModeChangeAt = now
		record.driveMode = if record.driveMode == "SPORT" then "ECO" else "SPORT"
		setAttributeIfChanged(record.model, "MaxSpeedKmh", ScooterConfig.GetDriveModeMaxSpeed(record.tuning.maxSpeed, record.driveMode))
		setAttributeIfChanged(record.model, "DriveMode", record.driveMode)
	end))

	table.insert(connections, toggleHeadlightRemote.OnServerEvent:Connect(function(player: Player, ...: unknown)
		if select("#", ...) ~= 0 then return end
		local record = recordsByPlayer[player]
		if not record or not record.headlight or record.model:GetAttribute("UpgradeDisplayRemoved") == true or record.fallen or not playerOwnsOccupiedScooter(player, record) then return end
		local now = os.clock()
		if now - record.lastLightChangeAt < ScooterConfig.Headlight.ToggleCooldown then return end
		record.lastLightChangeAt = now
		local enabled = record.model:GetAttribute("HeadlightEnabled") ~= true
		record.headlight.SetActive(enabled)
		setAttributeIfChanged(record.model, "HeadlightEnabled", enabled)
	end))

	table.insert(connections, trickRemote.OnServerEvent:Connect(function(player: Player, trickName: unknown, active: unknown)
		if (trickName ~= "Burnout" and trickName ~= "Dismount") or typeof(active) ~= "boolean" then return end
		local record = recordsByPlayer[player]
		if not record or not playerOwnsOccupiedScooter(player, record) then return end
		if trickName == "Dismount" then
			if active then
				dismount(record)
			end
			return
		end
		-- Releases always win; a cooldown must never leave smoke enabled.
		if not active then
			setBurnout(record, false)
			return
		end
		local now = os.clock()
		if now - record.lastTrickAt < ScooterConfig.TrickCooldown then return end
		record.lastTrickAt = now
		if record.fallen or not ScooterInput.IsFresh(record.input, now)
			or not record.input.throttleHeld or not record.input.brakeHeld
		then
			return
		end
		-- W+S in validated DriveInput is sufficient; this legacy event is only a hint.
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		local record = recordsByPlayer[player]
		if record then cleanupRecord(record) end
		lastSpawnByPlayer[player] = nil
		mountLocks[player] = nil
	end))

	table.insert(connections, RunService.PostSimulation:Connect(function()
		for _, record in recordsByPlayer do record.terrain.Stabilize() end
	end))

	table.insert(connections, RunService.PreSimulation:Connect(function(deltaTime: number)
		deltaTime = math.clamp(deltaTime, 0, 0.1)
		for _, record in pairs(recordsByPlayer) do
			local occupied = playerOwnsOccupiedScooter(record.owner, record)
			local now = os.clock()
			if not occupied or not ScooterInput.IsFresh(record.input, now) then
				resetControls(record)
			end
			local input = record.input
			record.throttle = if input.throttleHeld == input.brakeHeld then 0 else if input.throttleHeld then 1 else -1
			record.steering = ScooterPhysics.SmoothSteering(record.steering, input.steering, deltaTime)
			setAttributeIfChanged(record.model, "ThrottleInput", record.throttle)
			local tuning = record.tuning
			local root = record.root
			local velocity = root.AssemblyLinearVelocity
			local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			local speed = flatVelocity.Magnitude
			local maxSpeed = ScooterConfig.GetDriveModeMaxSpeed(tuning.maxSpeed, record.driveMode) * ScooterConfig.StudsPerKmH
			local frontHit, frontGrounded = probeGround(record, record.frontSuspensionPoint)
			local rearHit, rearGrounded = probeGround(record, record.rearSuspensionPoint)
			-- A scooter balanced on its underside still has physical support and must
			-- be able to drive off. Airborne tires alone are insufficient to decide this.
			local deckHit = if not frontGrounded and not rearGrounded then probeDeckSupport(record) else nil
			local grounded = frontGrounded or rearGrounded or deckHit ~= nil
			local arcadeStep = occupied and not record.fallen and not record.wheelieActive
				and record.model:GetAttribute("ArcadeStepActive") == true
			grounded = grounded or arcadeStep
			setAttributeIfChanged(record.model, "DeckGrounded", deckHit ~= nil)
			if record.frontGrounded ~= frontGrounded then
				record.frontGrounded = frontGrounded
				record.model:SetAttribute("FrontGrounded", frontGrounded)
			end
			if record.rearGrounded ~= rearGrounded then
				record.rearGrounded = rearGrounded
				record.model:SetAttribute("RearGrounded", rearGrounded)
			end

			local targetGroundUp = Vector3.yAxis
			if frontHit and rearHit then
				targetGroundUp = (frontHit.Normal + rearHit.Normal).Unit
			elseif frontHit then
				targetGroundUp = frontHit.Normal
			elseif rearHit then
				targetGroundUp = rearHit.Normal
			elseif deckHit then
				targetGroundUp = deckHit.Normal
			end
			if frontHit and rearHit and grounded and not record.wheelieActive and not arcadeStep then
				local axleLine = record.frontSuspensionPoint.WorldPosition - record.rearSuspensionPoint.WorldPosition
				local planarLine = Vector3.new(axleLine.X, 0, axleLine.Z)
				if planarLine.Magnitude > 0.01 then
					-- Ground heights break the flat-frame deadlock when one tire hangs over a lower road.
					local heightDifference = frontHit.Position.Y - rearHit.Position.Y
					local grade = math.clamp(heightDifference / planarLine.Magnitude,
						-math.tan(ScooterConfig.StepTraction.MaxChassisPitch), math.tan(ScooterConfig.StepTraction.MaxChassisPitch))
					targetGroundUp = (Vector3.yAxis - planarLine.Unit * grade).Unit
				end
			end
			local groundAlpha = 1 - math.exp(-ScooterConfig.GroundNormalSmoothSpeed * math.min(deltaTime, 0.1))
			if arcadeStep then targetGroundUp = Vector3.yAxis end
			local blendedGroundUp = record.groundUp:Lerp(targetGroundUp, groundAlpha)
			record.groundUp = if blendedGroundUp.Magnitude > 0.01 then blendedGroundUp.Unit else Vector3.yAxis
			local groundUp = record.groundUp
			local flatHeading = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			local actualHeading = if flatHeading.Magnitude > 0.01 then flatHeading.Unit else record.desiredForward
			local headingSpeed = flatVelocity:Dot(actualHeading)
			local motionAlongScooter = math.abs(headingSpeed)
			record.speedKmh=motionAlongScooter / ScooterConfig.StudsPerKmH
			local displaySpeedKmh = if motionAlongScooter < ScooterConfig.StopSpeed
				then 0
				else math.floor(motionAlongScooter / ScooterConfig.StudsPerKmH + 0.5)
			if displaySpeedKmh ~= record.displaySpeedKmh then
				record.displaySpeedKmh = displaySpeedKmh
				record.model:SetAttribute("SpeedKmh", displaySpeedKmh)
			end
			local canBurnout = occupied and not record.fallen and rearGrounded
				and math.abs(velocity.Y) <= ScooterConfig.MaxGroundedVerticalSpeed
				and ScooterPhysics.CanBurnout(speed, input.throttleHeld, input.brakeHeld)
			setBurnout(record, canBurnout)
			local effectiveSteering = if grounded
				then ScooterPhysics.GetEffectiveSteering(record.steering, headingSpeed, canBurnout)
				else 0
			if record.wheelieActive then effectiveSteering *= ScooterConfig.WheelieBalance.SteeringScale end
			setAttributeIfChanged(record.model, "SteeringInput", math.round(record.steering * 100) / 100)
			local servo = record.rig.steering
			local reversedAttachments = servo.Attachment0 ~= nil and servo.Attachment0.Parent == record.rig.stick
			local targetAngle = ScooterPhysics.GetServoSteering(effectiveSteering,
				reversedAttachments, servo.LimitsEnabled, servo.LowerAngle, servo.UpperAngle)
			servo.TargetAngle = targetAngle
			local wheelServo = record.rig.wheelSteering
			if wheelServo then wheelServo.TargetAngle = targetAngle end
			local anglePrecision = ScooterConfig.SteeringAnglePrecisionDegrees
			local measuredAngle = math.round(servo.CurrentAngle / anglePrecision) * anglePrecision
			local measuredSteerAngle = math.rad(measuredAngle) / ScooterConfig.SteeringServoSign
				* (if reversedAttachments then -1 else 1)
			local driveSteerAngle = if wheelServo then math.rad(wheelServo.CurrentAngle) / ScooterConfig.SteeringServoSign else measuredSteerAngle
			effectiveSteering = math.clamp(driveSteerAngle / ScooterConfig.MaxHandlebarAngle, -1, 1)
			setAttributeIfChanged(record.model, "Steering", math.round(effectiveSteering * 100) / 100)
			setAttributeIfChanged(record.model, "SteeringAngle", measuredSteerAngle)
			-- Road forces may perturb the physical servo. Neutral rider input must
			-- not turn those small errors into self-amplifying chassis yaw/lean.
			local controlledTarget = if math.abs(record.steering) < 0.01 then 0 else effectiveSteering
			record.turnSteering += (controlledTarget - record.turnSteering)
				* (1 - math.exp(-ScooterConfig.TurnSteeringResponse * deltaTime))
			local controlledSteering = record.turnSteering
			local turnSteering = if grounded
				then (if canBurnout then controlledSteering else ScooterPhysics.GetTurnSteering(controlledSteering, headingSpeed))
				else 0
			record.steeringHold = ScooterPhysics.AdvanceSteeringHold(record.steeringHold,
				if occupied and grounded and not record.fallen and not record.wheelieActive and not canBurnout
					then input.steering else 0, deltaTime)
			local requestedYawRate = ScooterPhysics.GetYawRate(turnSteering, headingSpeed, record.wheelBase, canBurnout)
			record.yawRate = ScooterPhysics.SmoothYawRate(record.yawRate, requestedYawRate, deltaTime)
			local desired = ScooterPhysics.AdvanceForward(
				record.desiredForward,
				turnSteering,
				headingSpeed,
				deltaTime,
				record.wheelBase,
				canBurnout,
				record.yawRate
			)
			record.desiredForward = if math.abs(headingSpeed) < ScooterConfig.MinSteeringSpeed and not canBurnout then actualHeading
				else ScooterPhysics.ClampForwardLead(actualHeading, desired,
					record.yawRate, record.steering, math.abs(record.steeringHold))

			local driveForward = ScooterPhysics.ProjectOntoPlane(record.desiredForward, groundUp)
			if driveForward.Magnitude < 0.01 then
				driveForward = record.desiredForward
			else
				driveForward = driveForward.Unit
			end
			local balanceForward = driveForward
			local forwardSpeed = velocity:Dot(driveForward)
			setAttributeIfChanged(record.model, "ForwardSpeed", math.floor(forwardSpeed * 2 + 0.5) / 2)
			local driveState = "Idle"
			if record.fallen then
				driveState = "Fallen"
			elseif not grounded then
				driveState = "Airborne"
			elseif record.throttle > 0 then
				driveState = "Forward"
			elseif record.throttle < 0 then
				driveState = "Reverse"
			end
			setAttributeIfChanged(record.model, "DriveState", driveState)

			if record.fallen or not occupied then
				applyParkingDamping(record, deltaTime)
			end
			local stepDirection = 0
			if input.throttleHeld and not input.brakeHeld then
				stepDirection = 1
			elseif input.brakeHeld and not input.throttleHeld
				and forwardSpeed <= ScooterConfig.DirectionChangeSpeedKmh * ScooterConfig.StudsPerKmH then
				stepDirection = -1
			end
			local tractionDirection = if occupied and not record.fallen and not record.wheelieActive and not input.wheelieQueued and stepDirection ~= 0
				then record.desiredForward * stepDirection else nil
			local stepSpeedLimit = if stepDirection < 0 then ScooterConfig.MaxReverseSpeedKmh * ScooterConfig.StudsPerKmH else maxSpeed
			local stepEntry = record.terrain.Update(tractionDirection, root.AssemblyMass + record.additionalMass,
				record.raycastParams, grounded, stepSpeedLimit,
				if occupied and grounded and not record.fallen and not record.wheelieActive
					and not input.wheelieQueued then targetGroundUp else nil)
			-- A new edge can be detected this frame, after the normal ground sample.
			if record.model:GetAttribute("ArcadeStepActive") == true then
				grounded = true
				groundUp, record.groundUp = Vector3.yAxis, Vector3.yAxis
				driveForward = ScooterPhysics.ProjectOntoPlane(record.desiredForward, groundUp).Unit
				balanceForward = driveForward
			end
			if stepEntry then
				-- Grip must agree with the verified corner assistance rather than
				-- immediately cancelling its small sideways entry at shallow angles.
				driveForward = ScooterPhysics.ProjectOntoPlane(stepEntry * stepDirection, groundUp).Unit
			end
			local handling = ScooterConfig.Handling
			local driveTarget = if occupied and input.throttleHeld and not input.brakeHeld then 1 else 0
			local brakeTarget = if occupied and input.brakeHeld then 1 else 0
			record.driveEffort += (driveTarget - record.driveEffort) * (1 - math.exp(-handling.ThrottleResponse * deltaTime))
			record.brakeEffort += (brakeTarget - record.brakeEffort) * (1 - math.exp(-handling.BrakeResponse * deltaTime))
			record.driveForce.Force = ScooterPhysics.ComputeDriveForce({
				velocity = velocity,
				forward = driveForward,
				groundUp = groundUp,
				gravity = Workspace.Gravity,
				mass = root.AssemblyMass + record.additionalMass,
				maxSpeed = maxSpeed,
				brakingDeceleration = record.model:GetAttribute("BrakeForce") or ScooterConfig.BrakingDeceleration,
				acceleration = ScooterConfig.GetDriveModeAcceleration(tuning.acceleration, record.driveMode),
				throttleStrength = record.driveEffort,
				brakeStrength = record.brakeEffort,
				throttleHeld = input.throttleHeld,
				brakeHeld = input.brakeHeld,
				burnout = record.burnoutActive,
				grounded = grounded,
				fallen = record.fallen,
				deltaTime = deltaTime,
			})

			-- Split the existing force between contacted axles without doubling it.
			local dual = record.model:GetAttribute("UpgradeDualMotor") == true
			local frontShare = if dual and frontGrounded and occupied and not record.burnoutActive and not record.fallen then (if rearGrounded then .5 else 1) else 0
			local totalForce = record.driveForce.Force
			record.frontDriveForce.Force = totalForce * frontShare
			record.driveForce.Force = totalForce * (1-frontShare)

			local wheelieTriggered = input.wheelieQueued
			input.wheelieQueued = false
			if wheelieTriggered and not record.wheelieActive and occupied and rearGrounded
				and forwardSpeed > ScooterConfig.WheelieMinSpeed and not record.fallen
				and not input.brakeHeld and now - record.lastWheelieAt >= ScooterConfig.WheelieCooldown
			then
				record.lastWheelieAt = now
				record.wheelieActive = true
				record.wheeliePitch = math.max(record.wheeliePitch, ScooterConfig.WheelieKickAngle)
			end

			if record.wheelieActive and not record.fallen then
				if forwardSpeed <= 0 or not occupied or not rearGrounded then
					record.wheelieActive = false
				else
					record.wheeliePitch = ScooterPhysics.AdvanceWheeliePitch(
						record.wheeliePitch,
						if input.brakeHeld then -1 else if input.throttleHeld then 1 else 0,
						forwardSpeed,
						deltaTime,
						record.model:GetAttribute("WheelieMaxAngle")
					)
				end
				if record.wheeliePitch <= 0 and frontGrounded then
					record.wheelieActive = false
				end
			elseif not record.fallen then
				record.wheeliePitch = ScooterPhysics.AdvanceWheeliePitch(record.wheeliePitch, 0, forwardSpeed, deltaTime, record.model:GetAttribute("WheelieMaxAngle"))
			end
			setAttributeIfChanged(record.model, "WheelieActive", record.wheelieActive and not record.fallen)

			local leadingPoint = if headingSpeed >= 0 then record.frontSuspensionPoint else record.rearSuspensionPoint
			local leadingRadius = if headingSpeed >= 0 then record.frontWheelRadius else record.backWheelRadius
			local collisionImpact = ScooterImpact.Update(record.impact, velocity, leadingPoint.WorldPosition, leadingRadius,
				record.raycastParams, occupied and not record.fallen, now, deltaTime)
			local actualPitch = math.asin(math.clamp(root.CFrame.LookVector.Y, -1, 1))
			local physicalWheelie = occupied and not record.fallen and record.wheelieActive
				and rearGrounded and not frontGrounded and headingSpeed > ScooterConfig.StopSpeed
				and actualPitch >= ScooterConfig.WheelieBalance.MinimumPhysicalAngle
			setAttributeIfChanged(record.model, "WheeliePhysical", physicalWheelie)
			local ridingState = if not occupied then "IdleOnScooter"
				else if record.wheelieActive then (if physicalWheelie then "WheelieBalance" else "WheelieStart")
				else if actualPitch > ScooterConfig.WheelieBalance.MinimumPhysicalAngle and not frontGrounded then "WheelieEnd"
				else if input.brakeHeld and headingSpeed > ScooterConfig.StopSpeed then "Braking"
				else if speed < ScooterConfig.StopSpeed then "IdleOnScooter"
				else if math.abs(turnSteering) > 0.05 then (if turnSteering < 0 then "TurningLeft" else "TurningRight")
				else if input.throttleHeld and headingSpeed < maxSpeed - ScooterConfig.StopSpeed then "Accelerating" else "NormalRide"
			setAttributeIfChanged(record.model, "RidingState", ridingState)
			if not record.fallen
				and (collisionImpact or (record.wheelieActive
					and (record.wheeliePitch >= (record.model:GetAttribute("WheelieMaxAngle") or ScooterConfig.WheelieFallAngle) or actualPitch >= (record.model:GetAttribute("WheelieMaxAngle") or ScooterConfig.WheelieFallAngle))))
			then
				record.fallen = true
				record.wheelieActive = false
				record.fallenAt = now
				record.upright.Enabled = false
				record.model:SetAttribute("Fallen", true)
				record.root:ApplyAngularImpulse(record.root.CFrame.LookVector * root.AssemblyMass * ScooterConfig.Impact.TipImpulsePerMass)
				crashRider(record)
			elseif record.fallen
				and not occupied
				and speed < 2
				and now - record.fallenAt >= ScooterConfig.WheelieRecoveryDelay
			then
				record.fallen = false
				record.wheeliePitch = 0
				record.upright.Enabled = true
				record.model:SetAttribute("Fallen", false)
			end

			record.scrape.Update(occupied and record.wheelieActive and not record.fallen and record.model:GetAttribute("UpgradeSparksDisabled") ~= true, actualPitch, speed, record.raycastParams)

			local brakeActive = occupied and not record.fallen
				and ScooterPhysics.IsBraking(forwardSpeed, input.throttleHeld, input.brakeHeld)
			local stopLightActive = occupied and not record.fallen
				and (brakeActive or input.brakeHeld or forwardSpeed < -ScooterConfig.StopSpeed)
			if record.brakeLight then record.brakeLight.SetActive(stopLightActive) end
			setAttributeIfChanged(record.model, "BrakeActive", brakeActive)
			setAttributeIfChanged(record.model, "StopLightActive", stopLightActive)
			-- Only roll a supported chassis; wheelie keeps its existing pitch balance.
			local targetLean = if occupied and frontGrounded and rearGrounded
				and not record.wheelieActive and not record.fallen and not canBurnout
				then ScooterPhysics.GetSteeringLean(turnSteering, headingSpeed, Workspace.Gravity, record.wheelBase)
				else 0
			if occupied and frontGrounded and rearGrounded and not record.wheelieActive and not record.fallen
				and not input.throttleHeld and not input.brakeHeld
				and speed <= ScooterConfig.IdleLeanSpeedKmh * ScooterConfig.StudsPerKmH then
				targetLean = ScooterConfig.IdleScooterLean
			end
			record.steeringLean = ScooterPhysics.SmoothSteeringLean(record.steeringLean, targetLean, deltaTime)

			-- Restrict collision-driven pitch/roll while keeping the previous heading controller.
			record.roadBalance.Enabled = occupied and not record.fallen and not record.wheelieActive
				and (grounded or (frontHit ~= nil and rearHit ~= nil))
			if not record.fallen then
				local target = CFrame.lookAt(Vector3.zero, balanceForward, groundUp)
					* CFrame.Angles(record.wheeliePitch, 0, record.steeringLean)
				-- Hinges connect several massive assemblies; Root contains only the chassis mass.
				record.upright.MaxTorque = tuning.turnTorque * (root.AssemblyMass + record.additionalMass)
				setAttributeIfChanged(record.model, "UprightSupportMass", root.AssemblyMass + record.additionalMass)
				record.upright.CFrame = target
				record.roadBalance.CFrame = target * ROAD_UP_FRAME
			end
		end
	end))
end

function ScooterServer.RefreshCosmetics(player: Player)
 local record=recordsByPlayer[player]
 if not record or record.cleaning then return end
 local modelName=record.model:GetAttribute("ScooterModel")
 if typeof(modelName)~="string" then return end
 ScooterEffects.Apply(record.effects,Cosmetics.GetVisuals(player,modelName))
 Cosmetics.ApplyPaint(player,record.model)
end

export type RidingState = {model: Model, root: BasePart, speedKmh: number, maxSpeedKmh: number, wheelie: boolean, burnout: boolean, grounded: boolean}
function ScooterServer.GetRidingState(player: Player): RidingState?
 local record=recordsByPlayer[player]
 if not record or record.cleaning or not record.model.Parent or not record.root.Parent
  or record.fallen or not playerOwnsOccupiedScooter(player,record) then return nil end
 local axis=record.rig.backHinge.Attachment0
 local spin=if axis then math.abs((record.rig.backWheel.AssemblyAngularVelocity-record.root.AssemblyAngularVelocity):Dot(axis.WorldAxis))*record.backWheelRadius else 0
 local burnout=record.burnoutActive and record.rearGrounded and spin>record.root.AssemblyLinearVelocity.Magnitude+2
 return {model=record.model,root=record.root,speedKmh=record.speedKmh,
  maxSpeedKmh=ScooterConfig.GetDriveModeMaxSpeed(record.tuning.maxSpeed,record.driveMode),
  grounded=record.frontGrounded or record.rearGrounded or record.model:GetAttribute("DeckGrounded")==true,
  burnout=burnout,
  wheelie=record.wheelieActive and record.rearGrounded and not record.frontGrounded
   and math.asin(math.clamp(record.root.CFrame.LookVector.Y,-1,1))>=ScooterConfig.WheelieBalance.MinimumPhysicalAngle
   and math.abs(record.root.AssemblyLinearVelocity.Y)<=ScooterConfig.MaxGroundedVerticalSpeed}
end
function ScooterServer.LockMount(player: Player, owner: {}): boolean
 if mountLocks[player] then return false end
 mountLocks[player]=owner; return true
end
function ScooterServer.ReleaseMount(player: Player, owner: {})
 if mountLocks[player]==owner then mountLocks[player]=nil end
end
function ScooterServer.DismountForPlayer(player: Player): boolean
 local record=recordsByPlayer[player]
 if not record or record.cleaning or not record.model.Parent or record.owner~=player then return false end
 local rider=record.seat.Occupant
 if not rider or rider.Health<=0 or rider.Parent~=player.Character then return false end
 dismount(record); return true
end

function ScooterServer.Stop()
	if not started then return end
	started = false
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)

	for _, record in recordsByPlayer do cleanupRecord(record) end
	table.clear(lastSpawnByPlayer)
	table.clear(mountLocks)
end

return ScooterServer
