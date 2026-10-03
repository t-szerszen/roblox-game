--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

local TEMPLATE_NAME = "KuKirin G2 Pro"
local REQUIRED_NAMES = {
	ScooterBody = true,
	FrontWheel = true,
	RearWheel = true,
	Fork = true,
	Handlebar = true,
}

type SelectedParts = {
	ScooterBody: BasePart,
	FrontWheel: BasePart,
	RearWheel: BasePart,
	Fork: BasePart,
	Handlebar: BasePart,
}

local DevScooterAssembler = {}

local function collectSelectedParts(): SelectedParts
	local found: { [string]: BasePart } = {}
	local function consider(instance: Instance)
		if instance:IsA("BasePart") and REQUIRED_NAMES[instance.Name] then
			if found[instance.Name] and found[instance.Name] ~= instance then
				error(string.format("Select only one BasePart named %s", instance.Name))
			end
			found[instance.Name] = instance
		end
	end

	for _, selected in Selection:Get() do
		consider(selected)
		for _, descendant in selected:GetDescendants() do
			consider(descendant)
		end
	end
	for name in REQUIRED_NAMES do
		if not found[name] then
			error(string.format("Missing selected BasePart named %s", name))
		end
	end
	return found :: any
end

local function weld(part0: BasePart, part1: BasePart, name: string): WeldConstraint
	local joint = Instance.new("WeldConstraint")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.Parent = part0
	return joint
end

local function motor(part0: BasePart, part1: BasePart, name: string, jointWorldCFrame: CFrame): Motor6D
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = part0.CFrame:ToObjectSpace(jointWorldCFrame)
	joint.C1 = part1.CFrame:ToObjectSpace(jointWorldCFrame)
	joint.Parent = part0
	return joint
end

local function attachmentAt(root: BasePart, worldPosition: Vector3, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = root.CFrame:PointToObjectSpace(worldPosition)
	attachment.Parent = root
	return attachment
end

local function configureVisual(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	if part:IsA("MeshPart") then
		-- Command Bar/plugin contexts may author this property; runtime scripts cannot.
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.Box
		end)
	end
end

local function createSmoke(rearWheel: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BurnoutSmokeAttachment"
	attachment.Position = Vector3.new(0, -rearWheel.Size.Y * 0.35, 0)
	attachment.Parent = rearWheel

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
	smoke.Parent = attachment
end

function DevScooterAssembler.AssembleFromSelection(): Model
	assert(RunService:IsStudio(), "DevScooterAssembler can only run in Roblox Studio")
	local parts = collectSelectedParts()
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "ScooterModels"
		templates.Parent = ServerStorage
	end
	assert(templates:IsA("Folder"), "ServerStorage.ScooterModels must be a Folder")
	assert(templates:FindFirstChild(TEMPLATE_NAME) == nil, "Delete or rename the existing KuKirin G2 Pro template first")

	local wheelDirection = parts.FrontWheel.Position - parts.RearWheel.Position
	local flatForward = Vector3.new(wheelDirection.X, 0, wheelDirection.Z)
	assert(flatForward.Magnitude > 1, "FrontWheel and RearWheel must be placed at different positions")
	flatForward = flatForward.Unit
	local bodyPosition = parts.ScooterBody.Position
	local bodySize = parts.ScooterBody.Size
	local wheelBase = (parts.FrontWheel.Position - parts.RearWheel.Position).Magnitude
	local bodyWidth = math.clamp(math.min(bodySize.X, bodySize.Y, bodySize.Z), 1, 2.5)
	local radiusOverride = parts.FrontWheel:GetAttribute("WheelRadius")
	local visualWheelRadius = if typeof(radiusOverride) == "number"
		then math.clamp(radiusOverride, 0.2, 3)
		else ScooterConfig.WheelRadius
	local rootHeight = math.clamp(bodyWidth * 0.3, 0.35, 0.8)
	local wheelBottomY = math.min(parts.FrontWheel.Position.Y, parts.RearWheel.Position.Y) - visualWheelRadius
	local rootPosition = Vector3.new(bodyPosition.X, wheelBottomY + rootHeight * 0.5, bodyPosition.Z)
	local rootCFrame = CFrame.lookAt(rootPosition, rootPosition + flatForward, Vector3.yAxis)
	local bodyHalfHeight = math.abs(parts.ScooterBody.CFrame.RightVector.Y) * bodySize.X * 0.5
		+ math.abs(parts.ScooterBody.CFrame.UpVector.Y) * bodySize.Y * 0.5
		+ math.abs(parts.ScooterBody.CFrame.LookVector.Y) * bodySize.Z * 0.5
	local deckY = bodyPosition.Y + bodyHalfHeight
	local root = Instance.new("Part")
	root.Name = "Root"
	-- A short safety foot cannot dig a long chassis corner into the road during wheelies.
	root.Size = Vector3.new(bodyWidth, rootHeight, math.clamp(wheelBase * 0.28, 1, 1.6))
	root.CFrame = rootCFrame
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = true
	root.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.1, 0, 10, 10)

	local model = Instance.new("Model")
	model.Name = TEMPLATE_NAME
	root.Parent = model
	model.PrimaryPart = root

	for _, part in { parts.ScooterBody, parts.FrontWheel, parts.RearWheel, parts.Fork, parts.Handlebar } do
		configureVisual(part)
		part.Parent = model
	end

	weld(root, parts.ScooterBody, "BodyWeld")
	weld(parts.Fork, parts.Handlebar, "HandlebarWeld")
	local steeringJoint = CFrame.lookAt(parts.Fork.Position, parts.Fork.Position + flatForward, Vector3.yAxis)
	local frontWheelJoint = CFrame.lookAt(
		parts.FrontWheel.Position,
		parts.FrontWheel.Position + flatForward,
		Vector3.yAxis
	)
	local rearWheelJoint = CFrame.lookAt(
		parts.RearWheel.Position,
		parts.RearWheel.Position + flatForward,
		Vector3.yAxis
	)
	motor(root, parts.Fork, "SteeringMotor", steeringJoint)
	motor(parts.Fork, parts.FrontWheel, "FrontWheelMotor", frontWheelJoint)
	motor(root, parts.RearWheel, "RearWheelMotor", rearWheelJoint)

	local driveAttachment = Instance.new("Attachment")
	driveAttachment.Name = "ScooterDriveAttachment"
	driveAttachment.Parent = root
	attachmentAt(root, parts.FrontWheel.Position, "FrontSuspensionPoint")
	attachmentAt(root, parts.RearWheel.Position, "RearSuspensionPoint")
	local right = rootCFrame.RightVector
	attachmentAt(root, Vector3.new(bodyPosition.X, deckY + 2.8, bodyPosition.Z) - flatForward * 0.25, "RiderRootAttachment")
	local footY = deckY + ScooterConfig.RiderPose.FootPlantClearance
	attachmentAt(root, Vector3.new(bodyPosition.X, footY, bodyPosition.Z) + flatForward * 0.45 - right * 0.32, "LeftFootPlant")
	attachmentAt(root, Vector3.new(bodyPosition.X, footY, bodyPosition.Z) - flatForward * 0.55 + right * 0.32, "RightFootPlant")
	attachmentAt(root, parts.Handlebar.Position - right * 0.58, "LeftHandGrip")
	attachmentAt(root, parts.Handlebar.Position + right * 0.58, "RightHandGrip")
	createSmoke(parts.RearWheel)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(math.max(1.2, bodyWidth * 0.75), 0.35, math.max(1.1, wheelBase * 0.28))
	local seatPosition = Vector3.new(bodyPosition.X, bodyPosition.Y + bodyHalfHeight + 0.35, bodyPosition.Z)
		+ flatForward * (-wheelBase * 0.12)
	seat.CFrame = CFrame.lookAt(seatPosition, seatPosition + flatForward, Vector3.yAxis)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	weld(root, seat, "SeatWeldConstraint")

	model:SetAttribute("ScooterModel", TEMPLATE_NAME)
	model:SetAttribute("BurnoutActive", false)
	model:SetAttribute("WheelieActive", false)
	model:SetAttribute("Fallen", false)
	model:SetAttribute("RiderMounted", false)
	model:SetAttribute("Steering", 0)
	model:SetAttribute("SpeedKmh", 0)
	model:SetAttribute("WheelRadius", visualWheelRadius)
	model.Parent = templates
	Selection:Set({ model })
	print(string.format("DevScooterAssembler: created ServerStorage.ScooterModels.%s", TEMPLATE_NAME))
	return model
end

function DevScooterAssembler.DisassembleTemplateToWorkspace(): Folder
	assert(RunService:IsStudio(), "DevScooterAssembler can only run in Roblox Studio")
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	local template = if templates then templates:FindFirstChild(TEMPLATE_NAME) else nil
	assert(template and template:IsA("Model"), "KuKirin G2 Pro template was not found in ServerStorage.ScooterModels")
	local existingFolder = workspace:FindFirstChild("kukurinNieruszac")
	if existingFolder and #existingFolder:GetChildren() == 0 then
		existingFolder:Destroy()
		existingFolder = nil
	end
	assert(existingFolder == nil, "Workspace.kukurinNieruszac already exists and is not empty")

	local visuals: { BasePart } = {}
	for name in REQUIRED_NAMES do
		local part = template:FindFirstChild(name, true)
		assert(part and part:IsA("BasePart"), string.format("Template is missing %s", name))
		table.insert(visuals, part)
	end
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "kukurinNieruszac"
	folder.Parent = workspace
	for _, part in visuals do
		part.Anchored = true
		part.CanCollide = false
		part.Massless = false
		part.Parent = folder
	end
	template:Destroy()
	Selection:Set({ folder })
	print("DevScooterAssembler: moved five visual parts back to Workspace.kukurinNieruszac")
	return folder
end

return DevScooterAssembler
