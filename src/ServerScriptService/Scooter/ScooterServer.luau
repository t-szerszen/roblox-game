--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local ScooterInput = require(script.Parent.ScooterInput)
local ScooterRig = require(script.Parent.ScooterRig)
local ScooterCollision = require(script.Parent.ScooterCollision)
local ScooterBrakeLight = require(script.Parent.ScooterBrakeLight)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local CombatService = require(script.Parent.Parent.Combat.CombatService)

type Connection = RBXScriptConnection
type ScooterRecord = {
	model: Model,
	owner: Player,
	seat: VehicleSeat,
	root: BasePart,
	smoke: ParticleEmitter,
	upright: AlignOrientation,
	input: ScooterInput.State,
	tuning: ScooterConfig.Tuning,
	driveForce: VectorForce,
	ridePrompt: ProximityPrompt,
	raycastParams: RaycastParams,
	frontSuspensionPoint: Attachment,
	rearSuspensionPoint: Attachment,
	frontWheelRadius: number,
	backWheelRadius: number,
	wheelBase: number,
	rig: ScooterRig.Rig,
	brakeLight: ScooterBrakeLight.Controller?,
	additionalMass: number,
	connections: { Connection },
	lastTrickAt: number,
	lastWheelieAt: number,
	throttle: number,
	steering: number,
	steeringLean: number,
	wheelieActive: boolean,
	desiredForward: Vector3,
	groundUp: Vector3,
	wheeliePitch: number,
	fallen: boolean,
	fallenAt: number,
	lastStepAt: number,
	crashToken: number,
	displaySpeedKmh: number,
	frontGrounded: boolean,
	rearGrounded: boolean,
	burnoutActive: boolean,
	rider: Humanoid?,
	riderConnections: { Connection },
	riderCollisionStates: { [BasePart]: boolean },
	cleaning: boolean,
}

local ScooterServer = {}

local recordsByPlayer: { [Player]: ScooterRecord } = {}
local recordsByModel: { [Model]: ScooterRecord } = {}
local lastSpawnByPlayer: { [Player]: number } = {}
local remotesFolder: Folder
local requestSpawnRemote: RemoteEvent
local trickRemote: RemoteEvent
local driveInputRemote: RemoteEvent
local connections: { Connection } = {}
local started = false

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

local function createScooter(owner: Player, modelName: string): Model
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	local template = if templates then templates:FindFirstChild(ScooterConfig.TemplateName) else nil
	assert(template, "Missing ServerStorage.ScooterModels.scooter; run DevScooterAssembler.AssembleFromSelection() on the new rig")
	local model = ScooterRig.Prepare(template)

	model.Name = string.format("%s Scooter", owner.Name)
	model:SetAttribute("ScooterModel", modelName)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("BurnoutActive", false)
	model:SetAttribute("BrakeActive", false)
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
	local leftFoot = findAttachment(record.model, "LeftFootPlant")
	local rightFoot = findAttachment(record.model, "RightFootPlant")
	local seatWeld = record.seat:FindFirstChild("SeatWeld")
	if
		not humanoidRoot
		or not humanoidRoot:IsA("BasePart")
		or not riderTarget
		or not leftFoot
		or not rightFoot
		or not seatWeld
		or not seatWeld:IsA("Weld")
	then
		return
	end

	local root = record.root
	local footCenter = (leftFoot.WorldPosition + rightFoot.WorldPosition) * 0.5
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
	local desiredRootPosition = Vector3.new(riderTarget.WorldPosition.X, footCenter.Y + standingHeight, riderTarget.WorldPosition.Z)
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
	ScooterInput.Reset(record.input)
	record.throttle = 0
	record.steering = 0
	if record.brakeLight then record.brakeLight.SetActive(false) end
	setAttributeIfChanged(record.model, "BrakeActive", false)
	record.wheelieActive = false
	record.burnoutActive = false
	record.smoke.Enabled = false
	record.rig.backHinge.ActuatorType = Enum.ActuatorType.None
	record.rig.steering.TargetAngle = 0
	record.driveForce.Force = Vector3.zero
	record.model:SetAttribute("ThrottleInput", 0)
	record.model:SetAttribute("Steering", 0)
	record.model:SetAttribute("SteeringInput", 0)
	record.model:SetAttribute("WheelieActive", false)
	record.model:SetAttribute("BurnoutActive", false)
end

local function cleanupRecord(record: ScooterRecord)
	if record.cleaning then
		return
	end

	record.cleaning = true
	if record.brakeLight then record.brakeLight.Destroy() end
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

local function getScooterSpawnPivot(model: Model): CFrame
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			-- A larger imported rig must not start with its wheel contacts below the road.
			local lift = ScooterCollision.GetSpawnLift(model, descendant.CFrame.Rotation)
			local heightAboveSpawn = descendant.Size.Y * 0.5
				+ math.max(2.5, lift + ScooterConfig.SpawnGroundClearance)
			return descendant.CFrame * CFrame.new(8, heightAboveSpawn, 0)
		end
	end

	warn("ScooterServer: no enabled SpawnLocation found; using the world origin")
	return CFrame.new(0, math.max(5, ScooterCollision.GetSpawnLift(model, CFrame.identity)
		+ ScooterConfig.SpawnGroundClearance), 0)
end

local function playerOwnsModel(player: Player, modelName: string): boolean
	local product = ShopConfig.GetScooterProduct(modelName)
	return product ~= nil and (product.price == 0 or (product.stat ~= nil and player:GetAttribute(product.stat) == true))
end

local function spawnForPlayer(player: Player, requestedModel: string?): Model
	local modelName = requestedModel or ScooterConfig.DefaultModel
	assert(player.Parent == Players and playerOwnsModel(player, modelName), "Cannot spawn an unowned scooter")
	-- Validate the replacement before removing a player's working scooter.
	local scooter = createScooter(player, modelName)
	local oldRecord = recordsByPlayer[player]
	if oldRecord then cleanupRecord(oldRecord) end
	scooter:PivotTo(getScooterSpawnPivot(scooter))
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

	local upright = Instance.new("AlignOrientation")
	upright.Name = "ScooterUpright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = driveAttachment
	upright.RigidityEnabled = false
	upright.Responsiveness = ScooterConfig.UprightResponsiveness
	upright.MaxAngularVelocity = 8
	upright.CFrame = root.CFrame.Rotation
	upright.Parent = root
	local smokeAttachment = findAttachment(scooter, "RearWheelAttachment")
		or createAttachment(rig.backAxle, "RearWheelAttachment", Vector3.zero)
	smokeAttachment.Parent = rig.backAxle
	smokeAttachment.Position = rig.backAxle.CFrame:PointToObjectSpace(rearSuspensionPoint.WorldPosition)
	smoke.Parent = smokeAttachment
	smoke.Color = ColorSequence.new(Color3.new(1, 1, 1))
	-- Base tuning keeps the MVP independent of garage/profile availability.
	local tuning = ScooterConfig.GetTuning(modelName, 0)
	assert(tuning, "Unknown scooter model")
	upright.MaxTorque = tuning.turnTorque * (root.AssemblyMass + additionalMass)
	scooter:SetAttribute("UprightSupportMass", root.AssemblyMass + additionalMass)
	scooter:SetAttribute("SpeedUpgradeTier", tuning.speedTier)
	scooter:SetAttribute("MaxSpeedKmh", tuning.maxSpeed)
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

	local record: ScooterRecord = {
		model = scooter,
		owner = player,
		seat = seat,
		root = root,
		smoke = smoke,
		upright = upright,
		input = ScooterInput.New(),
		tuning = tuning,
		driveForce = driveForce,
		ridePrompt = ridePrompt,
		raycastParams = RaycastParams.new(),
		frontSuspensionPoint = frontSuspensionPoint,
		rearSuspensionPoint = rearSuspensionPoint,
		frontWheelRadius = contacts.frontRadius,
		backWheelRadius = contacts.backRadius,
		wheelBase = (rig.frontPoint.WorldPosition - rig.backPoint.WorldPosition).Magnitude,
		rig = rig,
		brakeLight = ScooterBrakeLight.Create(scooter),
		additionalMass = additionalMass,
		connections = {},
		lastTrickAt = -math.huge,
		lastWheelieAt = -math.huge,
		throttle = 0,
		steering = 0,
		steeringLean = 0,
		wheelieActive = false,
		desiredForward = desiredForward,
		groundUp = Vector3.yAxis,
		wheeliePitch = 0,
		fallen = false,
		fallenAt = 0,
		lastStepAt = 0,
		crashToken = 0,
		displaySpeedKmh = 0,
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
			if occupant and (occupant.Parent ~= player.Character or occupant.Health <= 0) then
				occupant.Sit = false
				local seatWeld = seat:FindFirstChild("SeatWeld")
				if seatWeld then seatWeld:Destroy() end
				occupant = nil
			end
			record.model:SetAttribute("RiderMounted", occupant ~= nil)
			if occupant ~= nil and root.Parent ~= nil then
				local mountedRider = occupant
				record.rider = mountedRider
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
			if triggeringPlayer ~= player or seat.Occupant ~= nil or seat.Disabled then
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
	if not occupant or occupant.Health <= 0 or record.owner ~= player or player.Parent ~= Players then
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
	local origin = point.WorldPosition + Vector3.yAxis * ScooterConfig.SuspensionProbeLift
	local radius = if point == record.frontSuspensionPoint then record.frontWheelRadius else record.backWheelRadius
	local rayLength = radius + ScooterConfig.GroundProbeTolerance
	local result = Workspace:Raycast(
		origin,
		-Vector3.yAxis * (ScooterConfig.SuspensionProbeLift + rayLength),
		record.raycastParams
	)
	if not result or result.Normal.Y < ScooterConfig.GroundMinNormalY then
		return nil, false
	end
	return result, true
end

local function tryStepAssist(record: ScooterRecord, directionSign: number)
	if os.clock() - record.lastStepAt < ScooterConfig.StepCooldown then
		return
	end

	local root = record.root
	local up = root.CFrame.UpVector
	local travelDirection = record.desiredForward * directionSign
	local leadingPoint = if directionSign > 0
		then record.frontSuspensionPoint
		else record.rearSuspensionPoint
	local leadingCenter = if leadingPoint then leadingPoint.WorldPosition
		else root.Position + travelDirection * (ScooterConfig.WheelBase * 0.5)
	local radius = if directionSign > 0 then record.frontWheelRadius else record.backWheelRadius
	local lowOrigin = leadingCenter - up * math.max(0, radius - ScooterConfig.StepProbeHeight)
	local probe = travelDirection * ScooterConfig.StepProbeDistance
	local lowHit = Workspace:Raycast(lowOrigin, probe, record.raycastParams)
	if not lowHit then
		return
	end

	local highOrigin = lowOrigin + up * (ScooterConfig.MaxStepHeight + 0.1)
	if Workspace:Raycast(highOrigin, probe, record.raycastParams) then
		return
	end

	-- Measure the obstacle instead of applying the same kick to road paint and curbs.
	-- The sample sits just past the hit face so narrow raised markings are not skipped.
	local wheelBottom = leadingCenter - up * radius
	local topOrigin = lowHit.Position + travelDirection * 0.05
		+ up * (ScooterConfig.MaxStepHeight + 0.1)
	local topHit = Workspace:Raycast(
		topOrigin,
		-up * (ScooterConfig.MaxStepHeight + 0.2),
		record.raycastParams
	)
	if not topHit then
		return
	end
	local stepHeight = (topHit.Position - wheelBottom):Dot(up)
	if stepHeight <= 0 or stepHeight > ScooterConfig.MaxStepHeight then
		return
	end

	record.lastStepAt = os.clock()
	local targetUpVelocity = math.clamp(
		math.sqrt(2 * Workspace.Gravity * stepHeight) * ScooterConfig.StepVelocityScale,
		ScooterConfig.StepMinUpVelocity,
		ScooterConfig.StepMaxUpVelocity
	)
	local currentUpVelocity = root.AssemblyLinearVelocity:Dot(up)
	local velocityChange = up * math.max(0, targetUpVelocity - currentUpVelocity)
		+ travelDirection * ScooterConfig.StepForwardVelocity
	root:ApplyImpulse(velocityChange * root.AssemblyMass)
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

function ScooterServer.SpawnForPlayer(player: Player, modelName: string?): Model
	return spawnForPlayer(player, modelName)
end

function ScooterServer.RequestSpawnForPlayer(player: Player, modelName: string): (boolean, string)
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
	local success, problem = pcall(spawnForPlayer, player, modelName)
	if not success then
		warn("ScooterServer: " .. tostring(problem))
		return false, "Brak poprawnego nowego modelu hulajnogi."
	end
	return true, "Hulajnoga czeka przy spawnie."
end

function ScooterServer.Start()
	if started then return end
	started = true
	getOrCreateFolder(Workspace, ScooterConfig.ScooterFolderName)
	remotesFolder = getOrCreateFolder(getOrCreateFolder(ReplicatedStorage, "Remotes"), ScooterConfig.RemoteFolderName)
	requestSpawnRemote = getOrCreateRemote("RequestSpawn")
	trickRemote = getOrCreateRemote("TrickState")
	driveInputRemote = getOrCreateRemote("DriveInput")
	local pausedGarage = remotesFolder:FindFirstChild("GarageRequest")
	if pausedGarage and pausedGarage:IsA("RemoteFunction") then
		pausedGarage.OnServerInvoke = function(_player: Player)
			return false, "Unavailable", nil
		end
	end

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

	table.insert(connections, trickRemote.OnServerEvent:Connect(function(player: Player, trickName: unknown, active: unknown)
		if (trickName ~= "Burnout" and trickName ~= "Dismount") or typeof(active) ~= "boolean" then return end
		local record = recordsByPlayer[player]
		if not record or not playerOwnsOccupiedScooter(player, record) then return end
		if trickName == "Dismount" then
			if active then
				local rider = record.seat.Occupant
				resetControls(record)
				if rider then rider.Sit = false end
				local seatWeld = record.seat:FindFirstChild("SeatWeld")
				if seatWeld then seatWeld:Destroy() end
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
			local maxSpeed = tuning.maxSpeed * ScooterConfig.StudsPerKmH
			local frontHit, frontGrounded = probeGround(record, record.frontSuspensionPoint)
			local rearHit, rearGrounded = probeGround(record, record.rearSuspensionPoint)
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
			end
			local groundAlpha = 1 - math.exp(-ScooterConfig.GroundNormalSmoothSpeed * math.min(deltaTime, 0.1))
			local blendedGroundUp = record.groundUp:Lerp(targetGroundUp, groundAlpha)
			record.groundUp = if blendedGroundUp.Magnitude > 0.01 then blendedGroundUp.Unit else Vector3.yAxis
			local groundUp = record.groundUp
			local flatHeading = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			local actualHeading = if flatHeading.Magnitude > 0.01 then flatHeading.Unit else record.desiredForward
			local headingSpeed = flatVelocity:Dot(actualHeading)
			local motionAlongScooter = math.abs(headingSpeed)
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
			local effectiveSteering = if frontGrounded or rearGrounded
				then ScooterPhysics.GetEffectiveSteering(record.steering, headingSpeed, canBurnout)
				else 0
			setAttributeIfChanged(record.model, "SteeringInput", math.round(record.steering * 100) / 100)
			local servo = record.rig.steering
			local reversedAttachments = servo.Attachment0 ~= nil and servo.Attachment0.Parent == record.rig.stick
			local targetAngle = ScooterPhysics.GetServoSteering(effectiveSteering,
				reversedAttachments, servo.LimitsEnabled, servo.LowerAngle, servo.UpperAngle)
			servo.TargetAngle = targetAngle
			local anglePrecision = ScooterConfig.SteeringAnglePrecisionDegrees
			local measuredAngle = math.round(servo.CurrentAngle / anglePrecision) * anglePrecision
			local measuredSteerAngle = math.rad(measuredAngle) / ScooterConfig.SteeringServoSign
				* (if reversedAttachments then -1 else 1)
			effectiveSteering = math.clamp(measuredSteerAngle / ScooterConfig.MaxHandlebarAngle, -1, 1)
			setAttributeIfChanged(record.model, "Steering", math.round(effectiveSteering * 100) / 100)
			setAttributeIfChanged(record.model, "SteeringAngle", measuredSteerAngle)
			local turnSteering = if frontGrounded or rearGrounded
				then (if canBurnout then effectiveSteering else ScooterPhysics.GetTurnSteering(effectiveSteering, headingSpeed))
				else 0
			local desired = ScooterPhysics.AdvanceForward(
				record.desiredForward,
				turnSteering,
				headingSpeed,
				deltaTime,
				record.wheelBase,
				canBurnout
			)
			record.desiredForward = if math.abs(headingSpeed) < ScooterConfig.MinSteeringSpeed and not canBurnout then actualHeading
				else ScooterPhysics.ClampForwardLead(actualHeading, desired,
					ScooterPhysics.GetYawRate(turnSteering, headingSpeed, record.wheelBase, canBurnout))

			local driveForward = ScooterPhysics.ProjectOntoPlane(record.desiredForward, groundUp)
			if driveForward.Magnitude < 0.01 then
				driveForward = record.desiredForward
			else
				driveForward = driveForward.Unit
			end
			local forwardSpeed = velocity:Dot(driveForward)
			setAttributeIfChanged(record.model, "ForwardSpeed", math.floor(forwardSpeed * 2 + 0.5) / 2)
			local driveState = "Idle"
			if record.fallen then
				driveState = "Fallen"
			elseif not (frontGrounded or rearGrounded) then
				driveState = "Airborne"
			elseif record.throttle > 0 then
				driveState = "Forward"
			elseif record.throttle < 0 then
				driveState = "Reverse"
			end
			setAttributeIfChanged(record.model, "DriveState", driveState)

			local grounded = frontGrounded or rearGrounded
			if record.fallen or not occupied then
				applyParkingDamping(record, deltaTime)
			end
			record.driveForce.Force = ScooterPhysics.ComputeDriveForce({
				velocity = velocity,
				forward = driveForward,
				groundUp = groundUp,
				gravity = Workspace.Gravity,
				mass = root.AssemblyMass + record.additionalMass,
				maxSpeed = maxSpeed,
				acceleration = tuning.acceleration,
				throttleHeld = input.throttleHeld,
				brakeHeld = input.brakeHeld,
				burnout = record.burnoutActive,
				grounded = grounded,
				fallen = record.fallen,
				deltaTime = deltaTime,
			})
			local stepDirection = 0
			local leadingWheelGrounded = false
			if input.throttleHeld and not input.brakeHeld then
				stepDirection = 1
				leadingWheelGrounded = frontGrounded
			elseif input.brakeHeld and not input.throttleHeld and forwardSpeed <= ScooterConfig.StopSpeed then
				stepDirection = -1
				leadingWheelGrounded = rearGrounded
			end
			if occupied and leadingWheelGrounded and not record.fallen and stepDirection ~= 0 then
				tryStepAssist(record, stepDirection)
			end

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
						deltaTime
					)
				end
				if record.wheeliePitch <= 0 and frontGrounded then
					record.wheelieActive = false
				end
			elseif not record.fallen then
				record.wheeliePitch = ScooterPhysics.AdvanceWheeliePitch(record.wheeliePitch, 0, forwardSpeed, deltaTime)
			end
			setAttributeIfChanged(record.model, "WheelieActive", record.wheelieActive and not record.fallen)

			local actualPitch = math.asin(math.clamp(root.CFrame.LookVector.Y, -1, 1))
			if not record.fallen
				and record.wheelieActive
				and (record.wheeliePitch >= ScooterConfig.WheelieFallAngle or actualPitch >= ScooterConfig.WheelieFallAngle)
			then
				record.fallen = true
				record.wheelieActive = false
				record.fallenAt = now
				record.upright.Enabled = false
				record.model:SetAttribute("Fallen", true)
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

			local brakeActive = occupied and not record.fallen and input.brakeHeld
			if record.brakeLight then record.brakeLight.SetActive(brakeActive) end
			setAttributeIfChanged(record.model, "BrakeActive", brakeActive)
			-- Only roll a supported chassis; wheelie keeps its existing pitch balance.
			local targetLean = if occupied and frontGrounded and rearGrounded
				and not record.wheelieActive and not record.fallen and not canBurnout
				then ScooterPhysics.GetSteeringLean(turnSteering, headingSpeed, Workspace.Gravity, record.wheelBase)
				else 0
			record.steeringLean = ScooterPhysics.SmoothSteeringLean(record.steeringLean, targetLean, deltaTime)

			if not record.fallen then
				local target = CFrame.lookAt(Vector3.zero, driveForward, groundUp)
					* CFrame.Angles(record.wheeliePitch, 0, record.steeringLean)
				-- Hinges connect several massive assemblies; Root contains only the chassis mass.
				record.upright.MaxTorque = tuning.turnTorque * (root.AssemblyMass + record.additionalMass)
				setAttributeIfChanged(record.model, "UprightSupportMass", root.AssemblyMass + record.additionalMass)
				record.upright.CFrame = target
			end
		end
	end))
end

function ScooterServer.Stop()
	if not started then return end
	started = false
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)

	for _, record in recordsByPlayer do cleanupRecord(record) end
	table.clear(lastSpawnByPlayer)
end

return ScooterServer
