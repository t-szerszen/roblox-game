--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

type Connection = RBXScriptConnection
type ScooterRecord = {
	model: Model,
	owner: Player,
	seat: VehicleSeat,
	root: BasePart,
	smoke: ParticleEmitter,
	upright: AlignOrientation,
	driveForce: VectorForce,
	ridePrompt: ProximityPrompt,
	raycastParams: RaycastParams,
	frontSuspensionPoint: Attachment?,
	rearSuspensionPoint: Attachment?,
	wheelRadius: number,
	connections: { Connection },
	lastTrickAt: number,
	lastDriveInputAt: number,
	lastDriveRemoteAt: number,
	lastJumpAt: number,
	throttle: number,
	steering: number,
	wheelieTriggerQueued: boolean,
	wheelieActive: boolean,
	jumpQueued: boolean,
	desiredForward: Vector3,
	wheeliePitch: number,
	fallen: boolean,
	fallenAt: number,
	lastStepAt: number,
	lastGroundRecoveryAt: number,
	crashToken: number,
	displaySpeedKmh: number,
	displayFrontCompression: number,
	displayRearCompression: number,
	frontGrounded: boolean,
	rearGrounded: boolean,
	burnoutActive: boolean,
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

local function createPart(
	parent: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weld(root: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = root
end

local function createAttachment(root: BasePart, name: string, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	attachment.Parent = root
	return attachment
end

local function createWorldAttachment(root: BasePart, name: string, worldPosition: Vector3)
	if findAttachment(root, name) then
		return
	end
	createAttachment(root, name, root.CFrame:PointToObjectSpace(worldPosition))
end

local function ensureRiderAttachments(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end

	local bodyCandidate = model:FindFirstChild("ScooterBody", true) or model:FindFirstChild("Deck", true)
	local body = if bodyCandidate and bodyCandidate:IsA("BasePart") then bodyCandidate else root
	local handlebarCandidate = model:FindFirstChild("Handlebar", true)
	local handlebar = if handlebarCandidate and handlebarCandidate:IsA("BasePart") then handlebarCandidate else nil
	local forward = root.CFrame.LookVector
	local right = root.CFrame.RightVector
	local bodyHalfHeight = math.abs(body.CFrame.RightVector.Y) * body.Size.X * 0.5
		+ math.abs(body.CFrame.UpVector.Y) * body.Size.Y * 0.5
		+ math.abs(body.CFrame.LookVector.Y) * body.Size.Z * 0.5
	local deckY = body.Position.Y + bodyHalfHeight
	local handlebarPosition = if handlebar then handlebar.Position else root.Position + forward * 2.45 + Vector3.yAxis * 3.1

	createWorldAttachment(root, "RiderRootAttachment", Vector3.new(body.Position.X, deckY + 2.6, body.Position.Z) - forward * 0.25)
	createWorldAttachment(root, "LeftFootPlant", Vector3.new(body.Position.X, deckY + 0.08, body.Position.Z) + forward * 0.45 - right * 0.32)
	createWorldAttachment(root, "RightFootPlant", Vector3.new(body.Position.X, deckY + 0.08, body.Position.Z) - forward * 0.55 + right * 0.32)
	createWorldAttachment(root, "LeftHandGrip", handlebarPosition - right * 0.58)
	createWorldAttachment(root, "RightHandGrip", handlebarPosition + right * 0.58)
end

local function ensureChassisCollider(model: Model, root: BasePart): BasePart
	local existing = model:FindFirstChild("ChassisCollider")
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local leftFoot = findAttachment(model, "LeftFootPlant")
	local rightFoot = findAttachment(model, "RightFootPlant")
	local deckPosition = if leftFoot and rightFoot
		then (leftFoot.WorldPosition + rightFoot.WorldPosition) * 0.5
		else root.Position + root.CFrame.UpVector * 0.7
	local collider = Instance.new("Part")
	collider.Name = "ChassisCollider"
	collider.Size = Vector3.new(1.35, 0.2, 2.2)
	collider.CFrame = root.CFrame * CFrame.new(root.CFrame:PointToObjectSpace(deckPosition) - Vector3.yAxis * 0.05)
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanQuery = true
	collider.CanTouch = false
	collider.Massless = true
	collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 10, 10)
	collider.Parent = model
	weld(root, collider)
	return collider
end

local function createFallbackScooter(owner: Player, modelName: string): Model
	local model = Instance.new("Model")
	model.Name = string.format("%s Scooter", owner.Name)
	model:SetAttribute("ScooterModel", modelName)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("BurnoutActive", false)
	model:SetAttribute("WheelieActive", false)
	model:SetAttribute("RiderMounted", false)
	model:SetAttribute("Fallen", false)
	model:SetAttribute("Steering", 0)
	model:SetAttribute("WheelRadius", ScooterConfig.WheelRadius)
	model:SetAttribute("FrontSuspensionCompression", 0)
	model:SetAttribute("RearSuspensionCompression", 0)
	model:SetAttribute("ThrottleInput", 0)
	model:SetAttribute("FrontGrounded", false)
	model:SetAttribute("RearGrounded", false)
	model:SetAttribute("ForwardSpeed", 0)
	model:SetAttribute("DriveState", "Idle")

	local root = createPart(
		model,
		"Root",
		Vector3.new(1.6, 0.24, 1.5),
		CFrame.new(0, 2.2, 0),
		Color3.fromRGB(38, 43, 50),
		Enum.Material.Metal
	)
	root.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.1, 0, 10, 10)
	model.PrimaryPart = root

	createPart(
		model,
		"Deck",
		Vector3.new(2.4, 0.28, 5.8),
		root.CFrame * CFrame.new(0, -0.08, 0),
		Color3.fromRGB(27, 32, 39),
		Enum.Material.Metal
	)
	createPart(
		model,
		"Stem",
		Vector3.new(0.22, 3.2, 0.22),
		root.CFrame * CFrame.new(0, 1.65, -2.15) * CFrame.Angles(math.rad(-10), 0, 0),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.Metal
	)
	createPart(
		model,
		"Handlebar",
		Vector3.new(2.2, 0.18, 0.18),
		root.CFrame * CFrame.new(0, 3.1, -2.45),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.Metal
	)

	local rearWheel = createPart(
		model,
		"RearWheel",
		Vector3.new(0.42, 1.4, 1.4),
		root.CFrame * CFrame.new(0, -0.42, 2.25),
		Color3.fromRGB(12, 12, 12),
		Enum.Material.Rubber
	)
	rearWheel.Shape = Enum.PartType.Cylinder
	rearWheel.CustomPhysicalProperties = PhysicalProperties.new(0.7, ScooterConfig.WheelFriction, 0, 100, 100)
	local frontWheel = createPart(
		model,
		"FrontWheel",
		Vector3.new(0.42, 1.4, 1.4),
		root.CFrame * CFrame.new(0, -0.42, -2.25),
		Color3.fromRGB(12, 12, 12),
		Enum.Material.Rubber
	)
	frontWheel.Shape = Enum.PartType.Cylinder
	frontWheel.CustomPhysicalProperties = PhysicalProperties.new(0.7, ScooterConfig.WheelFriction, 0, 100, 100)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.9, 0.4, 1.3)
	seat.CFrame = root.CFrame * CFrame.new(0, 0.55, 0.65)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Disabled = false
	seat.CanTouch = false
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model

	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= root then
			part.CanCollide = false
			part.Massless = true
			weld(root, part)
		end
	end

	createAttachment(root, "FrontSuspensionPoint", root.CFrame:PointToObjectSpace(frontWheel.Position))
	createAttachment(root, "RearSuspensionPoint", root.CFrame:PointToObjectSpace(rearWheel.Position))
	createAttachment(root, "RiderRootAttachment", Vector3.new(0, 2.85, 0.35))
	createAttachment(root, "LeftFootPlant", Vector3.new(-0.38, 0.25, -0.45))
	createAttachment(root, "RightFootPlant", Vector3.new(0.38, 0.25, 0.65))
	createAttachment(root, "LeftHandGrip", Vector3.new(-0.72, 3.1, -2.45))
	createAttachment(root, "RightHandGrip", Vector3.new(0.72, 3.1, -2.45))

	local smokeAttachment = Instance.new("Attachment")
	smokeAttachment.Name = "BurnoutSmokeAttachment"
	smokeAttachment.Parent = rearWheel

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "BurnoutSmoke"
	smoke.Enabled = false
	smoke.LightEmission = 0
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	smoke.Lifetime = ScooterConfig.BurnoutSmokeLifetime
	smoke.Rate = ScooterConfig.BurnoutSmokeRate
	smoke.Speed = NumberRange.new(4, 8)
	smoke.SpreadAngle = Vector2.new(24, 24)
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Parent = smokeAttachment

	return model
end

local function createScooter(owner: Player, modelName: string): Model
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	local template = if templates then templates:FindFirstChild(modelName) else nil
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = createFallbackScooter(owner, modelName)
	end

	model.Name = string.format("%s Scooter", owner.Name)
	model:SetAttribute("ScooterModel", modelName)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("BurnoutActive", false)
	model:SetAttribute("WheelieActive", false)
	model:SetAttribute("RiderMounted", false)
	model:SetAttribute("Fallen", false)
	model:SetAttribute("Steering", 0)
	model:SetAttribute("SpeedKmh", 0)
	model:SetAttribute("FrontSuspensionCompression", 0)
	model:SetAttribute("RearSuspensionCompression", 0)
	model:SetAttribute("ThrottleInput", 0)
	model:SetAttribute("FrontGrounded", false)
	model:SetAttribute("RearGrounded", false)
	model:SetAttribute("ForwardSpeed", 0)
	model:SetAttribute("DriveState", "Idle")
	if typeof(model:GetAttribute("WheelRadius")) ~= "number" then
		model:SetAttribute("WheelRadius", ScooterConfig.WheelRadius)
	end
	ensureRiderAttachments(model)
	return model
end

local function sanitizeScooterPhysics(model: Model, root: BasePart, seat: VehicleSeat, smoke: ParticleEmitter)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = descendant ~= root
			if descendant:IsA("MeshPart") then
				descendant.CollisionFidelity = Enum.CollisionFidelity.Box
			end
		end
	end

	root.Massless = false
	seat.Transparency = 1
	seat.HeadsUpDisplay = false
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
	local footLocal = root.CFrame:PointToObjectSpace(footCenter)
	local riderLocal = root.CFrame:PointToObjectSpace(riderTarget.WorldPosition)
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
	local desiredLocal = Vector3.new(riderLocal.X, footLocal.Y + standingHeight, riderLocal.Z)
	local desiredRootCFrame = root.CFrame * CFrame.new(desiredLocal)
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

local function cleanupRecord(record: ScooterRecord)
	if record.cleaning then
		return
	end

	record.cleaning = true
	restoreRiderCollisions(record)
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

local function getScooterSpawnPivot(): CFrame
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			local heightAboveSpawn = descendant.Size.Y * 0.5 + 2.5
			return descendant.CFrame * CFrame.new(8, heightAboveSpawn, 0)
		end
	end

	warn("ScooterServer: no enabled SpawnLocation found; using the world origin")
	return CFrame.new(0, 5, 0)
end

local function spawnForPlayer(player: Player, requestedModel: string?): Model
	local oldRecord = recordsByPlayer[player]
	if oldRecord then
		cleanupRecord(oldRecord)
	end

	local modelName = requestedModel or ScooterConfig.DefaultModel
	if ScooterConfig.Models[modelName] == nil then
		modelName = ScooterConfig.DefaultModel
	end

	local scooter = createScooter(player, modelName)
	scooter:PivotTo(getScooterSpawnPivot())
	scooter.Parent = getOrCreateFolder(Workspace, ScooterConfig.ScooterFolderName)

	local root = scooter.PrimaryPart
	local seat = scooter:FindFirstChild("DriverSeat")
	local smoke = scooter:FindFirstChild("BurnoutSmoke", true)
	assert(root ~= nil, "Scooter requires a PrimaryPart")
	assert(seat and seat:IsA("VehicleSeat"), "Scooter requires DriverSeat")
	assert(smoke and smoke:IsA("ParticleEmitter"), "Scooter requires BurnoutSmoke")
	root.Size = Vector3.new(math.min(root.Size.X, 1.6), math.min(root.Size.Y, 0.24), math.min(root.Size.Z, 1.5))
	sanitizeScooterPhysics(scooter, root, seat, smoke)
	local chassisCollider = ensureChassisCollider(scooter, root)
	chassisCollider.Anchored = false
	chassisCollider.CanCollide = true
	chassisCollider.CanQuery = true

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
	upright.Parent = root

	local ridePrompt = Instance.new("ProximityPrompt")
	ridePrompt.Name = "RidePrompt"
	ridePrompt.ActionText = "Ride"
	ridePrompt.ObjectText = modelName
	ridePrompt.KeyboardKeyCode = Enum.KeyCode.E
	ridePrompt.HoldDuration = 0
	ridePrompt.MaxActivationDistance = ScooterConfig.RidePromptDistance
	ridePrompt.RequiresLineOfSight = false
	ridePrompt.Parent = root

	root:SetNetworkOwner(nil)
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
		driveForce = driveForce,
		ridePrompt = ridePrompt,
		raycastParams = RaycastParams.new(),
		frontSuspensionPoint = findAttachment(scooter, "FrontSuspensionPoint"),
		rearSuspensionPoint = findAttachment(scooter, "RearSuspensionPoint"),
		wheelRadius = math.clamp(
			if typeof(scooter:GetAttribute("WheelRadius")) == "number"
				then scooter:GetAttribute("WheelRadius") :: number
				else ScooterConfig.WheelRadius,
			0.2,
			3
		),
		connections = {},
		lastTrickAt = 0,
		lastDriveInputAt = 0,
		lastDriveRemoteAt = 0,
		lastJumpAt = 0,
		throttle = 0,
		steering = 0,
		wheelieTriggerQueued = false,
		wheelieActive = false,
		jumpQueued = false,
		desiredForward = desiredForward,
		wheeliePitch = 0,
		fallen = false,
		fallenAt = 0,
		lastStepAt = 0,
		lastGroundRecoveryAt = 0,
		crashToken = 0,
		displaySpeedKmh = 0,
		displayFrontCompression = 0,
		displayRearCompression = 0,
		frontGrounded = false,
		rearGrounded = false,
		burnoutActive = false,
		riderCollisionStates = {},
		cleaning = false,
	}
	record.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
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
			record.model:SetAttribute("RiderMounted", occupant ~= nil)
			if occupant ~= nil and root.Parent ~= nil then
				local character = occupant.Parent
				record.raycastParams.FilterDescendantsInstances = if character
					then { scooter, character }
					else { scooter }
				root:SetNetworkOwner(nil)
				suppressRiderCollisions(record, occupant)
				task.defer(function()
					if not record.cleaning and seat.Occupant == occupant then
						alignRiderToDeck(record, occupant)
					end
				end)
			else
				record.raycastParams.FilterDescendantsInstances = { scooter }
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
			if (humanoidRootPart.Position - root.Position).Magnitude > ScooterConfig.RidePromptDistance + 2 then
				return
			end

			ridePrompt.Enabled = false
			seat:Sit(humanoid)
		end)
	)

	return scooter
end

local function playerOwnsModel(player: Player, modelName: string): boolean
	local product = ShopConfig.GetScooterProduct(modelName)
	if not product then
		return false
	end
	return product.price == 0 or (product.stat ~= nil and player:GetAttribute(product.stat) == true)
end

local function setBurnout(record: ScooterRecord, active: boolean, smokeColor: Color3?)
	if record.burnoutActive == active and smokeColor == nil then
		return
	end

	record.burnoutActive = active
	setAttributeIfChanged(record.model, "BurnoutActive", active)
	record.smoke.Enabled = active
	if smokeColor then
		record.smoke.Color = ColorSequence.new(smokeColor)
	end
end

local function playerOwnsOccupiedScooter(player: Player, record: ScooterRecord): boolean
	local occupant = record.seat.Occupant
	if not occupant then
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
	local wasPlatformStanding = humanoid.PlatformStand
	local wasAutoRotate = humanoid.AutoRotate

	record.seat.Disabled = true
	record.ridePrompt.Enabled = false
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
		if record.crashToken ~= crashToken then
			return
		end
		if record.seat.Parent then
			record.seat.Disabled = false
			record.ridePrompt.Enabled = record.seat.Occupant == nil
		end
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = wasPlatformStanding
			humanoid.AutoRotate = wasAutoRotate
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function projectOntoPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

local function applySuspension(
	record: ScooterRecord,
	localZ: number,
	deltaTime: number
): (RaycastResult?, boolean, number)
	local root = record.root
	if root.CFrame.UpVector.Y < 0.25 then
		return nil, false, 0
	end

	local suspensionPoint = if localZ < 0 then record.frontSuspensionPoint else record.rearSuspensionPoint
	local origin = if suspensionPoint then suspensionPoint.WorldPosition
		else root.CFrame:PointToWorldSpace(Vector3.new(0, 0, localZ))
	local rayLength = record.wheelRadius
		+ ScooterConfig.SuspensionRestLength
		+ ScooterConfig.SuspensionTravel
	local result = Workspace:Raycast(origin, -root.CFrame.UpVector * rayLength, record.raycastParams)
	if not result then
		return nil, false, 0
	end

	local springLength = math.max(0, result.Distance - record.wheelRadius)
	local compression = math.clamp(
		ScooterConfig.SuspensionRestLength - springLength,
		0,
		ScooterConfig.SuspensionTravel
	)
	local pointVelocity = root:GetVelocityAtPosition(origin)
	local normalVelocity = pointVelocity:Dot(result.Normal)
	local suspensionAcceleration = compression * ScooterConfig.SuspensionStiffness
		- normalVelocity * ScooterConfig.SuspensionDamping
	suspensionAcceleration = math.clamp(suspensionAcceleration, 0, ScooterConfig.MaxSuspensionAcceleration)

	local impulse = result.Normal * suspensionAcceleration * root.AssemblyMass * 0.5 * deltaTime
	root:ApplyImpulseAtPosition(impulse, origin)
	return result, true, compression
end

local function recoverGroundPenetration(record: ScooterRecord)
	local root = record.root
	local now = os.clock()
	if
		root.CFrame.UpVector.Y < 0.5
		or now - record.lastGroundRecoveryAt < ScooterConfig.GroundRecoveryInterval
	then
		return
	end
	record.lastGroundRecoveryAt = now

	local correction = 0
	for _, point in { record.frontSuspensionPoint, record.rearSuspensionPoint } do
		if point then
			local probeHeight = ScooterConfig.GroundRecoveryProbeHeight
			local origin = point.WorldPosition + Vector3.yAxis * probeHeight
			local result = Workspace:Raycast(
				origin,
				-Vector3.yAxis * (probeHeight + record.wheelRadius + ScooterConfig.SuspensionTravel + 1),
				record.raycastParams
			)
			if result and result.Normal.Y > 0.5 then
				local axleHeight = point.WorldPosition.Y - result.Position.Y
				local penetration = record.wheelRadius + ScooterConfig.GroundClearance - axleHeight
				correction = math.max(correction, penetration)
			end
		end
	end

	if correction <= ScooterConfig.GroundRecoveryThreshold then
		return
	end
	root.CFrame += Vector3.yAxis * correction
	local velocity = root.AssemblyLinearVelocity
	if velocity.Y < 0 then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
end

local function tryStepAssist(record: ScooterRecord, speed: number)
	if speed < 3 or os.clock() - record.lastStepAt < ScooterConfig.StepCooldown then
		return
	end

	local root = record.root
	local up = root.CFrame.UpVector
	local front = record.frontSuspensionPoint
	local frontCenter = if front then front.WorldPosition
		else root.Position + record.desiredForward * (ScooterConfig.WheelBase * 0.5)
	local lowOrigin = frontCenter - up * math.max(0, record.wheelRadius - ScooterConfig.StepProbeHeight)
	local probe = record.desiredForward * ScooterConfig.StepProbeDistance
	local lowHit = Workspace:Raycast(lowOrigin, probe, record.raycastParams)
	if not lowHit then
		return
	end

	local highOrigin = lowOrigin + up * ScooterConfig.MaxStepHeight
	if Workspace:Raycast(highOrigin, probe, record.raycastParams) then
		return
	end

	record.lastStepAt = os.clock()
	local velocityChange = up * ScooterConfig.StepUpVelocity
		+ record.desiredForward * ScooterConfig.StepForwardVelocity
	root:ApplyImpulse(velocityChange * root.AssemblyMass)
end

function ScooterServer.SpawnForPlayer(player: Player, modelName: string?): Model
	return spawnForPlayer(player, modelName)
end

function ScooterServer.RequestSpawnForPlayer(player: Player, modelName: string): (boolean, string)
	if player.Parent ~= Players or ScooterConfig.Models[modelName] == nil or not playerOwnsModel(player, modelName) then
		return false, "Nie posiadasz tej hulajnogi."
	end

	local now = os.clock()
	local lastSpawn = lastSpawnByPlayer[player]
	if lastSpawn and now - lastSpawn < ScooterConfig.SpawnCooldown then
		return false, "Hulajnoga byla przywolana przed chwila."
	end
	lastSpawnByPlayer[player] = now
	spawnForPlayer(player, modelName)
	return true, "Hulajnoga czeka przy spawnie."
end

function ScooterServer.Start()
	remotesFolder = getOrCreateFolder(ReplicatedStorage, ScooterConfig.RemoteFolderName)
	requestSpawnRemote = getOrCreateRemote("RequestSpawn")
	trickRemote = getOrCreateRemote("TrickState")
	driveInputRemote = getOrCreateRemote("DriveInput")

	requestSpawnRemote.OnServerEvent:Connect(function(player: Player, requestedModel: unknown)
		local modelName = if typeof(requestedModel) == "string" then requestedModel else nil
		if modelName == nil then
			modelName = ScooterConfig.DefaultModel
		end
		ScooterServer.RequestSpawnForPlayer(player, modelName)
	end)

	driveInputRemote.OnServerEvent:Connect(
		function(player: Player, throttle: unknown, steering: unknown, wheelieTrigger: unknown, jump: unknown)
			local record = recordsByPlayer[player]
			if not record or not playerOwnsOccupiedScooter(player, record) then
				return
			end
			if
				typeof(throttle) ~= "number"
				or typeof(steering) ~= "number"
				or typeof(wheelieTrigger) ~= "boolean"
				or typeof(jump) ~= "boolean"
			then
				return
			end
			if throttle ~= throttle or steering ~= steering then
				return
			end
			local now = os.clock()
			if now - record.lastDriveRemoteAt < 0.025 then
				return
			end
			record.lastDriveRemoteAt = now

			local clampedThrottle = math.clamp(throttle, -1, 1)
			local clampedSteering = math.clamp(steering, -1, 1)
			record.throttle = clampedThrottle
			record.steering = clampedSteering
			setAttributeIfChanged(record.model, "ThrottleInput", clampedThrottle)
			if wheelieTrigger then
				record.wheelieTriggerQueued = true
			end
			record.jumpQueued = record.jumpQueued or jump
			record.lastDriveInputAt = now
		end
	)

	trickRemote.OnServerEvent:Connect(function(player: Player, trickName: unknown, active: unknown, smokeColor: unknown)
		if trickName ~= "Burnout" or typeof(active) ~= "boolean" then
			return
		end

		local record = recordsByPlayer[player]
		if not record or not playerOwnsOccupiedScooter(player, record) then
			return
		end

		local now = os.clock()
		if now - record.lastTrickAt < ScooterConfig.TrickCooldown then
			return
		end
		record.lastTrickAt = now

		local speed = record.root.AssemblyLinearVelocity.Magnitude
		if active and speed > ScooterConfig.BurnoutMaxSpeed then
			return
		end

		local color = Color3.fromRGB(235, 235, 235)
		if typeof(smokeColor) == "Color3" then
			color = smokeColor
		end
		setBurnout(record, active, color)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local record = recordsByPlayer[player]
		if record then
			cleanupRecord(record)
		end
		lastSpawnByPlayer[player] = nil
	end)

	RunService.Heartbeat:Connect(function(deltaTime: number)
		for _, record in pairs(recordsByPlayer) do
			local occupied = playerOwnsOccupiedScooter(record.owner, record)
			if not occupied then
				if record.burnoutActive then
					setBurnout(record, false, nil)
				end
				record.throttle = 0
				record.steering = 0
				setAttributeIfChanged(record.model, "Steering", 0)
				record.wheelieTriggerQueued = false
				if not record.fallen then
					record.wheelieActive = false
					record.wheeliePitch = 0
				end
				record.jumpQueued = false
			end

			if os.clock() - record.lastDriveInputAt > 0.35 then
				record.throttle = 0
				record.steering = 0
				setAttributeIfChanged(record.model, "ThrottleInput", 0)
				setAttributeIfChanged(record.model, "Steering", 0)
			end

			local modelName = record.model:GetAttribute("ScooterModel")
			local tuning = ScooterConfig.Models[if typeof(modelName) == "string"
				then modelName
				else ScooterConfig.DefaultModel] or ScooterConfig.Models[ScooterConfig.DefaultModel]
			local root = record.root
			recoverGroundPenetration(record)
			local velocity = root.AssemblyLinearVelocity
			local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			local speed = flatVelocity.Magnitude
			local maxSpeed = tuning.maxSpeed * ScooterConfig.StudsPerKmH
			local halfWheelBase = ScooterConfig.WheelBase * 0.5
			local frontHit, frontGrounded, frontCompression = applySuspension(record, -halfWheelBase, deltaTime)
			local rearHit, rearGrounded, rearCompression = applySuspension(record, halfWheelBase, deltaTime)
			local visualFrontCompression = math.floor(frontCompression * 100 + 0.5) / 100
			local visualRearCompression = math.floor(rearCompression * 100 + 0.5) / 100
			if visualFrontCompression ~= record.displayFrontCompression then
				record.displayFrontCompression = visualFrontCompression
				record.model:SetAttribute("FrontSuspensionCompression", visualFrontCompression)
			end
			if visualRearCompression ~= record.displayRearCompression then
				record.displayRearCompression = visualRearCompression
				record.model:SetAttribute("RearSuspensionCompression", visualRearCompression)
			end
			if record.frontGrounded ~= frontGrounded then
				record.frontGrounded = frontGrounded
				record.model:SetAttribute("FrontGrounded", frontGrounded)
			end
			if record.rearGrounded ~= rearGrounded then
				record.rearGrounded = rearGrounded
				record.model:SetAttribute("RearGrounded", rearGrounded)
			end

			local groundUp = Vector3.yAxis
			if frontHit and rearHit then
				groundUp = (frontHit.Normal + rearHit.Normal).Unit
			elseif frontHit then
				groundUp = frontHit.Normal
			elseif rearHit then
				groundUp = rearHit.Normal
			end
			local motionAlongScooter = math.abs(flatVelocity:Dot(record.desiredForward))
			local displaySpeedKmh = if motionAlongScooter < ScooterConfig.StopSpeed
				then 0
				else math.floor(motionAlongScooter / ScooterConfig.StudsPerKmH + 0.5)
			if displaySpeedKmh ~= record.displaySpeedKmh then
				record.displaySpeedKmh = displaySpeedKmh
				record.model:SetAttribute("SpeedKmh", displaySpeedKmh)
			end
			local speedKmh = motionAlongScooter / ScooterConfig.StudsPerKmH
			local steeringFade = math.clamp(
				(speedKmh - ScooterConfig.SteeringFadeStartKmh)
					/ (ScooterConfig.SteeringFadeEndKmh - ScooterConfig.SteeringFadeStartKmh),
				0,
				1
			)
			local steeringScale = 1 + (ScooterConfig.HighSpeedSteeringScale - 1) * steeringFade
			local effectiveSteering = if motionAlongScooter >= ScooterConfig.MinSteeringSpeed
				then record.steering * steeringScale
				else 0
			setAttributeIfChanged(record.model, "Steering", effectiveSteering)
			if math.abs(effectiveSteering) > 0.01 then
				local turnScale = math.clamp(speed / 12, 0.25, 1)
				local yaw = -effectiveSteering * ScooterConfig.TurnRate * turnScale * deltaTime
				record.desiredForward = CFrame.fromAxisAngle(Vector3.yAxis, yaw)
					:VectorToWorldSpace(record.desiredForward).Unit
			end

			local driveForward = projectOntoPlane(record.desiredForward, groundUp)
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

			local targetForwardSpeed = 0
			local speedChangeRate = ScooterConfig.CoastingDeceleration
			if not record.fallen and record.throttle > 0 then
				if forwardSpeed < -ScooterConfig.StopSpeed then
					speedChangeRate = ScooterConfig.BrakingDeceleration
				else
					targetForwardSpeed = maxSpeed * record.throttle
					speedChangeRate = tuning.acceleration
				end
			elseif not record.fallen and record.throttle < 0 then
				if forwardSpeed > ScooterConfig.StopSpeed then
					speedChangeRate = ScooterConfig.BrakingDeceleration
				else
					targetForwardSpeed = -ScooterConfig.MaxReverseSpeedKmh * ScooterConfig.StudsPerKmH
					speedChangeRate = ScooterConfig.ReverseAcceleration
				end
			end
			if record.burnoutActive then
				targetForwardSpeed = 0
				speedChangeRate = ScooterConfig.BrakingDeceleration
			end

			local grounded = frontGrounded or rearGrounded
			if grounded and not record.fallen then
				local safeDeltaTime = math.max(deltaTime, 1 / 240)
				local forwardAcceleration = math.clamp(
					(targetForwardSpeed - forwardSpeed) / safeDeltaTime,
					-speedChangeRate,
					speedChangeRate
				)
				local lateralVelocity = flatVelocity - driveForward * flatVelocity:Dot(driveForward)
				local lateralAcceleration = Vector3.zero
				if lateralVelocity.Magnitude > 0.001 then
					lateralAcceleration = -lateralVelocity.Unit
						* math.min(lateralVelocity.Magnitude / safeDeltaTime, ScooterConfig.LateralGripDeceleration)
				end
				record.driveForce.Force = (driveForward * forwardAcceleration + lateralAcceleration)
					* root.AssemblyMass
			else
				record.driveForce.Force = Vector3.zero
			end
			if occupied and frontGrounded and not record.fallen then
				tryStepAssist(record, speed)
			end

			local now = os.clock()
			if record.wheelieTriggerQueued then
				record.wheelieTriggerQueued = false
				if occupied and rearGrounded and forwardSpeed > ScooterConfig.WheelieMinSpeed and not record.fallen then
					record.wheelieActive = true
					record.wheeliePitch = math.max(record.wheeliePitch, ScooterConfig.WheelieKickAngle)
				end
			end

			if record.wheelieActive and not record.fallen then
				if forwardSpeed <= 0 then
					record.wheelieActive = false
				elseif record.throttle > 0 then
					record.wheeliePitch += ScooterConfig.WheeliePitchRate * record.throttle * deltaTime
				elseif record.throttle < 0 then
					record.wheeliePitch += ScooterConfig.WheelieReturnRate * record.throttle * deltaTime
				else
					record.wheeliePitch -= ScooterConfig.WheelieNeutralDropRate * deltaTime
				end
				record.wheeliePitch = math.clamp(record.wheeliePitch, 0, ScooterConfig.WheelieFallAngle)
				if record.wheeliePitch <= 0 and frontGrounded then
					record.wheelieActive = false
				end
			elseif not record.fallen then
				record.wheeliePitch = math.max(
					0,
					record.wheeliePitch - ScooterConfig.WheelieReturnRate * deltaTime
				)
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

			if not record.fallen then
				local suspensionPitch = (rearCompression - frontCompression) * 0.12
				local accelerationLean = record.throttle * ScooterConfig.MaxAccelerationLean
				local steeringLean = -effectiveSteering
					* ScooterConfig.MaxSteeringLean
					* math.clamp(speed / 22, 0, 1)
				local targetPitch = suspensionPitch + accelerationLean + record.wheeliePitch

				record.upright.MaxTorque = tuning.turnTorque * root.AssemblyMass
				record.upright.CFrame = CFrame.lookAt(Vector3.zero, driveForward, groundUp)
					* CFrame.Angles(targetPitch, 0, steeringLean)
			end

			if record.jumpQueued then
				record.jumpQueued = false
				if now - record.lastJumpAt >= 0.8 and (frontGrounded or rearGrounded) and not record.fallen then
					record.lastJumpAt = now
					root:ApplyImpulse(Vector3.new(0, tuning.jumpImpulse * root.AssemblyMass, 0))
				end
			end
		end
	end)
end

return ScooterServer
