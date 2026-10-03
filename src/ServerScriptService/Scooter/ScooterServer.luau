--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local ScooterInput = require(script.Parent.ScooterInput)
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
	wheelRadius: number,
	connections: { Connection },
	lastTrickAt: number,
	lastWheelieAt: number,
	throttle: number,
	steering: number,
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
	burnoutRequested: boolean,
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
	local existing = findAttachment(root, name)
	local attachment: Attachment = existing or createAttachment(root, name, Vector3.zero)
	attachment.Parent = root
	-- Normalize existing templates too; stale attachment placement was causing
	-- the rider targets to disagree with the visible deck and handlebar.
	attachment.Position = root.CFrame:PointToObjectSpace(worldPosition)
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
	local footY = deckY + ScooterConfig.RiderPose.FootPlantClearance
	createWorldAttachment(root, "LeftFootPlant", Vector3.new(body.Position.X, footY, body.Position.Z) + forward * 0.45 - right * 0.32)
	createWorldAttachment(root, "RightFootPlant", Vector3.new(body.Position.X, footY, body.Position.Z) - forward * 0.55 + right * 0.32)
	createWorldAttachment(root, "LeftHandGrip", handlebarPosition - right * 0.58)
	createWorldAttachment(root, "RightHandGrip", handlebarPosition + right * 0.58)
end

local function createWheelCollider(
	model: Model,
	root: BasePart,
	point: Attachment,
	name: string,
	wheelRadius: number
): BasePart
	local collider = Instance.new("Part")
	collider.Name = name
	collider:SetAttribute("RuntimeCollisionProxy", true)
	local collisionRadius = math.max(0.1, wheelRadius - ScooterConfig.WheelColliderClearance)
	collider.Shape = Enum.PartType.Ball
	collider.Size = Vector3.one * collisionRadius * 2
	collider.CFrame = CFrame.new(point.WorldPosition)
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.Massless = true
	-- Rolling drag is controlled by propulsion; proxy friction only stabilizes contact.
	collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, ScooterConfig.GroundColliderFriction, 0, 100, 10)
	collider.Parent = model
	weld(root, collider)
	return collider
end

local function resolveWheelRadius(model: Model, frontWheel: BasePart?, rearWheel: BasePart?): number
	for _, wheel in { frontWheel, rearWheel } do
		if wheel then
			local override = wheel:GetAttribute("WheelRadius")
			if typeof(override) == "number" and override == override and math.abs(override) < math.huge then
				return math.clamp(override, 0.2, 3)
			end
		end
	end
	local configured = model:GetAttribute("WheelRadius")
	if typeof(configured) == "number" and configured == configured and math.abs(configured) < math.huge then
		return math.clamp(configured, 0.2, 3)
	end

	local derivedRadius = math.huge
	for _, wheel in { frontWheel, rearWheel } do
		if wheel then
			-- Visual wheel motors rotate around local X. The smaller of Y/Z avoids
			-- counting a fender or swingarm extending along the other dimension.
			derivedRadius = math.min(derivedRadius, math.min(wheel.Size.Y, wheel.Size.Z) * 0.5)
		end
	end
	if derivedRadius < math.huge then
		return math.clamp(derivedRadius, 0.2, 3)
	end

	return ScooterConfig.WheelRadius
end

local function ensureSuspensionPoint(
	root: BasePart,
	name: string,
	localZ: number,
	wheel: BasePart?
): Attachment
	local existing = root:FindFirstChild(name)
	local point = if existing and existing:IsA("Attachment")
		then existing
		else createAttachment(root, name, Vector3.new(0, 0, localZ))
	point.Parent = root
	if wheel then
		-- Runtime templates may contain suspension attachments authored against
		-- an older root offset. Always center contact and raycast on the wheel axle.
		point.Position = root.CFrame:PointToObjectSpace(wheel.Position)
	end
	return point
end

local function assignNetworkOwner(root: BasePart, owner: Player?)
	local canSet, reason = root:CanSetNetworkOwnership()
	if not canSet then
		warn(string.format("ScooterServer: cannot assign network ownership: %s", reason))
		return
	end
	root:SetNetworkOwner(owner)
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
	model:SetAttribute("SteeringInput", 0)
	model:SetAttribute("WheelRadius", ScooterConfig.WheelRadius)
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
	seat.Disabled = false
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
	createAttachment(root, "LeftFootPlant", Vector3.new(-0.38, 0.06, -0.45))
	createAttachment(root, "RightFootPlant", Vector3.new(0.38, 0.06, 0.65))
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
	model:SetAttribute("SteeringInput", 0)
	model:SetAttribute("SpeedKmh", 0)
	model:SetAttribute("ThrottleInput", 0)
	model:SetAttribute("FrontGrounded", false)
	model:SetAttribute("RearGrounded", false)
	model:SetAttribute("ForwardSpeed", 0)
	model:SetAttribute("DriveState", "Idle")
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
	record.wheelieActive = false
	record.burnoutRequested = false
	record.burnoutActive = false
	record.smoke.Enabled = false
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
	if record.rider then
		record.rider.Sit = false
	end
	releaseRider(record)
	record.model:SetAttribute("BurnoutActive", false)
	record.model:SetAttribute("WheelieActive", false)
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

local function playerOwnsModel(player: Player, modelName: string): boolean
	local product = ShopConfig.GetScooterProduct(modelName)
	return product ~= nil and (product.price == 0 or (product.stat ~= nil and player:GetAttribute(product.stat) == true))
end

local function spawnForPlayer(player: Player, requestedModel: string?): Model
	local modelName = requestedModel or ScooterConfig.DefaultModel
	assert(player.Parent == Players and playerOwnsModel(player, modelName), "Cannot spawn an unowned scooter")
	local oldRecord = recordsByPlayer[player]
	if oldRecord then
		cleanupRecord(oldRecord)
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
	local halfWheelBase = ScooterConfig.WheelBase * 0.5
	local frontWheelCandidate = scooter:FindFirstChild("FrontWheel", true)
	local rearWheelCandidate = scooter:FindFirstChild("RearWheel", true)
	local frontWheel = if frontWheelCandidate and frontWheelCandidate:IsA("BasePart") then frontWheelCandidate else nil
	local rearWheel = if rearWheelCandidate and rearWheelCandidate:IsA("BasePart") then rearWheelCandidate else nil
	local wheelRadius = resolveWheelRadius(scooter, frontWheel, rearWheel)
	scooter:SetAttribute("WheelRadius", wheelRadius)
	local frontSuspensionPoint = ensureSuspensionPoint(root, "FrontSuspensionPoint", -halfWheelBase, frontWheel)
	local rearSuspensionPoint = ensureSuspensionPoint(root, "RearSuspensionPoint", halfWheelBase, rearWheel)
	local oldChassisCollider = scooter:FindFirstChild("ChassisCollider")
	if oldChassisCollider and oldChassisCollider:IsA("BasePart") then
		oldChassisCollider.CanCollide = false
		oldChassisCollider.CanTouch = false
		oldChassisCollider.CanQuery = false
	end
	local frontWheelCollider = createWheelCollider(
		scooter,
		root,
		frontSuspensionPoint,
		"FrontWheelCollider",
		wheelRadius
	)
	local rearWheelCollider = createWheelCollider(
		scooter,
		root,
		rearSuspensionPoint,
		"RearWheelCollider",
		wheelRadius
	)
	frontWheelCollider.Anchored = false
	rearWheelCollider.Anchored = false
	scooter:SetAttribute("CollisionProxyMode", "WheelSpheres")

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
	local smokeAttachment = findAttachment(scooter, "RearWheelAttachment")
		or createAttachment(root, "RearWheelAttachment", Vector3.zero)
	smokeAttachment.Parent = root
	smokeAttachment.Position = root.CFrame:PointToObjectSpace(rearSuspensionPoint.WorldPosition)
	smoke.Parent = smokeAttachment
	smoke.Color = ColorSequence.new(Color3.new(1, 1, 1))
	-- Base tuning keeps the MVP independent of garage/profile availability.
	local tuning = ScooterConfig.GetTuning(modelName, 0)
	assert(tuning, "Unknown scooter model")
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

	assignNetworkOwner(root, nil)
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
		wheelRadius = wheelRadius,
		connections = {},
		lastTrickAt = -math.huge,
		lastWheelieAt = -math.huge,
		throttle = 0,
		steering = 0,
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
		burnoutRequested = false,
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
				assignNetworkOwner(root, nil)
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
						assignNetworkOwner(root, nil)
						alignRiderToDeck(record, mountedRider)
					end
				end)
			else
				record.raycastParams.FilterDescendantsInstances = { scooter }
				assignNetworkOwner(root, nil)
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
	-- force because this model has no suspension travel to represent.
	local origin = point.WorldPosition + Vector3.yAxis * ScooterConfig.SuspensionProbeLift
	local rayLength = record.wheelRadius + ScooterConfig.GroundProbeTolerance
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
	local lowOrigin = leadingCenter - up * math.max(0, record.wheelRadius - ScooterConfig.StepProbeHeight)
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
	local wheelBottom = leadingCenter - up * record.wheelRadius
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
	spawnForPlayer(player, modelName)
	return true, "Hulajnoga czeka przy spawnie."
end

function ScooterServer.Start()
	if started then return end
	started = true
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
			record.burnoutRequested = false
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
		-- Intent is evaluated against current server contact/speed every simulation step.
		record.burnoutRequested = true
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
			if record.burnoutActive and speed > ScooterConfig.BurnoutSmokeMaxSpeed then
				setBurnout(record, false)
			end
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
			local headingSpeed = flatVelocity:Dot(record.desiredForward)
			local motionAlongScooter = math.abs(headingSpeed)
			local displaySpeedKmh = if motionAlongScooter < ScooterConfig.StopSpeed
				then 0
				else math.floor(motionAlongScooter / ScooterConfig.StudsPerKmH + 0.5)
			if displaySpeedKmh ~= record.displaySpeedKmh then
				record.displaySpeedKmh = displaySpeedKmh
				record.model:SetAttribute("SpeedKmh", displaySpeedKmh)
			end
			local effectiveSteering = if frontGrounded or rearGrounded
				then ScooterPhysics.GetEffectiveSteering(record.steering, headingSpeed)
				else 0
			setAttributeIfChanged(record.model, "Steering", math.round(effectiveSteering * 100) / 100)
			setAttributeIfChanged(record.model, "SteeringInput", math.round(record.steering * 100) / 100)
			local turnSteering = ScooterPhysics.GetTurnSteering(effectiveSteering, headingSpeed)
			record.desiredForward = ScooterPhysics.AdvanceForward(
				record.desiredForward,
				turnSteering,
				headingSpeed,
				deltaTime
			)

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
			local canBurnout = occupied and not record.fallen and grounded
				and math.abs(velocity.Y) <= ScooterConfig.MaxGroundedVerticalSpeed
				and speed <= ScooterConfig.BurnoutSmokeMaxSpeed
				and input.throttleHeld and input.brakeHeld and record.burnoutRequested
			if not input.throttleHeld or not input.brakeHeld then record.burnoutRequested = false end
			setBurnout(record, canBurnout)
			record.driveForce.Force = ScooterPhysics.ComputeDriveForce({
				velocity = velocity,
				forward = driveForward,
				groundUp = groundUp,
				gravity = Workspace.Gravity,
				mass = root.AssemblyMass,
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
						record.throttle,
						forwardSpeed,
						deltaTime
					)
				end
				if record.wheeliePitch <= 0 and frontGrounded then
					record.wheelieActive = false
				end
			elseif not record.fallen then
				record.wheeliePitch = math.max(
					0,
					record.wheeliePitch - ScooterConfig.WheelieStallDropRate * deltaTime
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
				local steeringLean = -effectiveSteering
					* ScooterConfig.MaxSteeringLean
					* math.clamp(speed / ScooterConfig.SteeringLeanFullSpeed, 0, 1)

				local target = CFrame.lookAt(Vector3.zero, driveForward, groundUp)
					* CFrame.Angles(record.wheeliePitch, 0, steeringLean)
				record.upright.MaxTorque = tuning.turnTorque * root.AssemblyMass
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
