--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

type Connection = RBXScriptConnection
type ScooterRecord = {
	model: Model,
	owner: Player,
	seat: VehicleSeat,
	root: BasePart,
	smoke: ParticleEmitter,
	upright: AlignOrientation,
	connections: { Connection },
	lastTrickAt: number,
	lastDriveInputAt: number,
	lastDriveRemoteAt: number,
	lastJumpAt: number,
	throttle: number,
	steering: number,
	wheelie: boolean,
	jumpQueued: boolean,
	desiredForward: Vector3,
	burnoutActive: boolean,
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

local function createFallbackScooter(owner: Player, modelName: string): Model
	local model = Instance.new("Model")
	model.Name = string.format("%s Scooter", owner.Name)
	model:SetAttribute("ScooterModel", modelName)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("BurnoutActive", false)

	local root = createPart(
		model,
		"Root",
		Vector3.new(2.1, 0.45, 5.4),
		CFrame.new(0, 2.2, 0),
		Color3.fromRGB(38, 43, 50),
		Enum.Material.Metal
	)
	root.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.8, 0.2, 1, 1)
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
	seat.Color = Color3.fromRGB(46, 50, 58)
	seat.Material = Enum.Material.SmoothPlastic
	seat.Disabled = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model

	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= root then
			weld(root, part)
		end
	end

	local smokeAttachment = Instance.new("Attachment")
	smokeAttachment.Name = "BurnoutSmokeAttachment"
	smokeAttachment.Parent = rearWheel

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "BurnoutSmoke"
	smoke.Enabled = false
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	smoke.Lifetime = NumberRange.new(0.6, 1.15)
	smoke.Rate = 95
	smoke.Speed = NumberRange.new(4, 8)
	smoke.SpreadAngle = Vector2.new(24, 24)
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Parent = smokeAttachment

	return model
end

local function cleanupRecord(record: ScooterRecord)
	if record.cleaning then
		return
	end

	record.cleaning = true
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

	local scooter = createFallbackScooter(player, modelName)
	scooter:PivotTo(getScooterSpawnPivot())
	scooter.Parent = getOrCreateFolder(Workspace, ScooterConfig.ScooterFolderName)

	local root = scooter.PrimaryPart
	local seat = scooter:FindFirstChild("DriverSeat")
	local smoke = scooter:FindFirstChild("BurnoutSmoke", true)
	assert(root ~= nil, "Scooter requires a PrimaryPart")
	assert(seat and seat:IsA("VehicleSeat"), "Scooter requires DriverSeat")
	assert(smoke and smoke:IsA("ParticleEmitter"), "Scooter requires BurnoutSmoke")

	local driveAttachment = Instance.new("Attachment")
	driveAttachment.Name = "ScooterDriveAttachment"
	driveAttachment.Parent = root

	local upright = Instance.new("AlignOrientation")
	upright.Name = "ScooterUpright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = driveAttachment
	upright.RigidityEnabled = false
	upright.Responsiveness = ScooterConfig.UprightResponsiveness
	upright.MaxAngularVelocity = 8
	upright.Parent = root

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
		connections = {},
		lastTrickAt = 0,
		lastDriveInputAt = 0,
		lastDriveRemoteAt = 0,
		lastJumpAt = 0,
		throttle = 0,
		steering = 0,
		wheelie = false,
		jumpQueued = false,
		desiredForward = desiredForward,
		burnoutActive = false,
		cleaning = false,
	}
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
			if seat.Occupant ~= nil and root.Parent ~= nil then
				root:SetNetworkOwner(nil)
			end
		end)
	)

	return scooter
end

local function setBurnout(record: ScooterRecord, active: boolean, smokeColor: Color3?)
	if record.burnoutActive == active and smokeColor == nil then
		return
	end

	record.burnoutActive = active
	record.model:SetAttribute("BurnoutActive", active)
	record.smoke.Enabled = active
	if smokeColor then
		record.smoke.Color = ColorSequence.new(smokeColor)
	end

	trickRemote:FireAllClients(
		record.owner,
		record.model,
		"Burnout",
		active,
		smokeColor or Color3.fromRGB(235, 235, 235)
	)
end

local function playerOwnsOccupiedScooter(player: Player, record: ScooterRecord): boolean
	local occupant = record.seat.Occupant
	if not occupant then
		return false
	end

	local character = occupant.Parent
	return character == player.Character
end

local function isGrounded(record: ScooterRecord): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { record.model }
	return Workspace:Raycast(record.root.Position, Vector3.new(0, -3.2, 0), params) ~= nil
end

function ScooterServer.SpawnForPlayer(player: Player, modelName: string?): Model
	return spawnForPlayer(player, modelName)
end

function ScooterServer.Start()
	remotesFolder = getOrCreateFolder(ReplicatedStorage, ScooterConfig.RemoteFolderName)
	requestSpawnRemote = getOrCreateRemote("RequestSpawn")
	trickRemote = getOrCreateRemote("TrickState")
	driveInputRemote = getOrCreateRemote("DriveInput")

	requestSpawnRemote.OnServerEvent:Connect(function(player: Player, requestedModel: unknown)
		local now = os.clock()
		local lastSpawn = lastSpawnByPlayer[player]
		if lastSpawn and now - lastSpawn < ScooterConfig.SpawnCooldown then
			return
		end
		lastSpawnByPlayer[player] = now

		local modelName = if typeof(requestedModel) == "string" then requestedModel else nil
		spawnForPlayer(player, modelName)
	end)

	driveInputRemote.OnServerEvent:Connect(
		function(player: Player, throttle: unknown, steering: unknown, wheelie: unknown, jump: unknown)
			local record = recordsByPlayer[player]
			if not record or not playerOwnsOccupiedScooter(player, record) then
				return
			end
			if
				typeof(throttle) ~= "number"
				or typeof(steering) ~= "number"
				or typeof(wheelie) ~= "boolean"
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
			record.wheelie = wheelie
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
			if not playerOwnsOccupiedScooter(record.owner, record) then
				record.throttle = 0
				record.steering = 0
				record.wheelie = false
				continue
			end

			if os.clock() - record.lastDriveInputAt > 0.35 then
				record.throttle = 0
				record.steering = 0
				record.wheelie = false
			end

			local modelName = record.model:GetAttribute("ScooterModel")
			local tuning = ScooterConfig.Models[if typeof(modelName) == "string"
				then modelName
				else ScooterConfig.DefaultModel] or ScooterConfig.Models[ScooterConfig.DefaultModel]
			local root = record.root
			local velocity = root.AssemblyLinearVelocity
			local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			local speed = flatVelocity.Magnitude
			local forwardSpeed = flatVelocity:Dot(record.desiredForward)
			local maxSpeed = tuning.maxSpeed * ScooterConfig.StudsPerKmH

			if math.abs(record.steering) > 0.01 then
				local turnScale = math.clamp(speed / 12, 0.25, 1)
				local yaw = -record.steering * ScooterConfig.TurnRate * turnScale * deltaTime
				record.desiredForward = CFrame.fromAxisAngle(Vector3.yAxis, yaw)
					:VectorToWorldSpace(record.desiredForward).Unit
			end

			local acceleration = Vector3.zero
			if record.throttle > 0 and forwardSpeed < maxSpeed then
				acceleration += record.desiredForward * tuning.acceleration * record.throttle
			elseif record.throttle < 0 then
				if forwardSpeed > 2 then
					acceleration -= record.desiredForward * tuning.brakeForce
				elseif -forwardSpeed < ScooterConfig.MaxReverseSpeed then
					acceleration += record.desiredForward * tuning.reverseAcceleration * record.throttle
				end
			else
				acceleration -= flatVelocity * 1.5
			end

			local lateralVelocity = flatVelocity - record.desiredForward * forwardSpeed
			acceleration -= lateralVelocity * 5
			root:ApplyImpulse(acceleration * root.AssemblyMass * deltaTime)

			local pitch = if record.wheelie and speed > ScooterConfig.WheelieMinSpeed
				then ScooterConfig.WheelieAngle
				else 0
			record.upright.MaxTorque = tuning.turnTorque * root.AssemblyMass
			record.upright.CFrame = CFrame.lookAt(Vector3.zero, record.desiredForward, Vector3.yAxis)
				* CFrame.Angles(pitch, 0, 0)

			if record.jumpQueued then
				record.jumpQueued = false
				local now = os.clock()
				if now - record.lastJumpAt >= 0.8 and isGrounded(record) then
					record.lastJumpAt = now
					root:ApplyImpulse(Vector3.new(0, tuning.jumpImpulse * root.AssemblyMass, 0))
				end
			end
		end
	end)
end

return ScooterServer
