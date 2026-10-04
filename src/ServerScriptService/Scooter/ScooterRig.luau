--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Geometry = require(script.Parent.ScooterRigGeometry)
local Collision = require(script.Parent.ScooterCollision)
local Suspension = require(script.Parent.ScooterSuspension)

export type Rig = {
	body: MeshPart,
	frontWheel: MeshPart,
	backWheel: MeshPart,
	handleBar: MeshPart,
	stick: MeshPart,
	frontAxle: Part,
	backAxle: Part,
	steering: HingeConstraint,
	frontHinge: HingeConstraint,
	backHinge: HingeConstraint,
	frontPoint: Attachment,
	backPoint: Attachment,
}

local ScooterRig = {}

local function child(parent: Instance, name: string, className: string): Instance
	local instance = parent:FindFirstChild(name)
	assert(instance and instance:IsA(className), string.format("%s requires %s [%s]", parent.Name, name, className))
	return instance
end

local function checkLink(constraint: Constraint, first: Attachment, second: Attachment)
	assert(constraint.Enabled, constraint.Name .. " must be enabled")
	assert((constraint.Attachment0 == first and constraint.Attachment1 == second)
		or (constraint.Attachment1 == first and constraint.Attachment0 == second),
		constraint.Name .. " has incorrect attachment endpoints")
end

local function checkWeld(parent: Instance, first: BasePart, second: BasePart)
	for _, instance in parent:GetChildren() do
		if instance:IsA("WeldConstraint") and instance.Enabled
			and ((instance.Part0 == first and instance.Part1 == second)
				or (instance.Part1 == first and instance.Part0 == second)) then
			return
		end
	end
	error(string.format("%s must weld %s to %s", parent.Name, first.Name, second.Name))
end

function ScooterRig.Inspect(source: Instance): Rig
	assert(source:IsA("Folder") or source:IsA("Model"), "Select the scooter Folder or Model")
	local body = child(source, "ScooterBody", "MeshPart") :: MeshPart
	local stick = child(source, "HandleBarStick", "MeshPart") :: MeshPart
	local handleBar = child(source, "HandleBar", "MeshPart") :: MeshPart
	local frontWheel = child(source, "FrontWheel", "MeshPart") :: MeshPart
	local backWheel = child(source, "BackWheel", "MeshPart") :: MeshPart
	local frontAxle = child(source, "VirtualFrontAxle", "Part") :: Part
	local backAxle = child(source, "VirtualBackAxle", "Part") :: Part
	child(source, "FootRest", "MeshPart")
	child(source, "BackFender", "MeshPart")
	local steering = child(body, "HingeConstraint", "HingeConstraint") :: HingeConstraint
	assert(not steering.LimitsEnabled or (steering.LowerAngle <= 0 and steering.UpperAngle >= 0),
		"ScooterBody.HingeConstraint limits must include neutral steering (0 degrees)")
	checkLink(steering, child(body, "SteerBase", "Attachment") :: Attachment,
		child(stick, "SteerPivot", "Attachment") :: Attachment)
	checkWeld(stick, stick, handleBar)

	for _, endName in { "Front", "Back" } do
		local base = if endName == "Front" then stick else body
		local axle = if endName == "Front" then frontAxle else backAxle
		for _, side in { "Left", "Right" } do
			local suffix = endName .. "Suspension" .. side
			local arm = child(source, suffix, "MeshPart") :: MeshPart
			local hinge = child(base, "PivotHinge_" .. suffix, "HingeConstraint") :: HingeConstraint
			local spring = child(base, "ShockAbsorber_" .. suffix, "SpringConstraint") :: SpringConstraint
			checkLink(hinge, child(base, "PivotAttBase_" .. suffix, "Attachment") :: Attachment,
				child(arm, "PivotAtt_" .. suffix, "Attachment") :: Attachment)
			checkLink(spring, child(base, "SpringAttBase_" .. suffix, "Attachment") :: Attachment,
				child(arm, "SpringAtt_" .. suffix, "Attachment") :: Attachment)
			checkWeld(axle, axle, arm)
		end
	end
	local frontHinge = child(frontAxle, "HingeConstraint", "HingeConstraint") :: HingeConstraint
	local backHinge = child(backAxle, "HingeConstraint", "HingeConstraint") :: HingeConstraint
	local frontPoint = child(frontAxle, "AxlePivot", "Attachment") :: Attachment
	local backPoint = child(backAxle, "AxlePivot", "Attachment") :: Attachment
	checkLink(frontHinge, frontPoint, child(frontWheel, "WheelCenter", "Attachment") :: Attachment)
	checkLink(backHinge, backPoint, child(backWheel, "WheelCenter", "Attachment") :: Attachment)
	return {
		body = body, stick = stick, handleBar = handleBar, frontWheel = frontWheel, backWheel = backWheel,
		frontAxle = frontAxle, backAxle = backAxle, steering = steering,
		frontHinge = frontHinge, backHinge = backHinge, frontPoint = frontPoint, backPoint = backPoint,
	}
end

local function weld(first: BasePart, second: BasePart, name: string)
	local joint = Instance.new("WeldConstraint")
	joint.Name = name
	joint.Part0 = first
	joint.Part1 = second
	joint.Parent = second
end

local function attachment(parent: BasePart, name: string, worldPosition: Vector3): Attachment
	local point = Instance.new("Attachment")
	point.Name = name
	point.Position = parent.CFrame:PointToObjectSpace(worldPosition)
	point.Parent = parent
	return point
end

local function configureModel(model: Model, Config: typeof(Config)): Model
	model.Name = Config.TemplateName
	local rig = ScooterRig.Inspect(model)
	-- Prepared templates can be cloned at runtime without adding duplicate joints.
	if model:GetAttribute("ArticulatedScooter") == true then
		assert(model.PrimaryPart and model.PrimaryPart.Name == "Root", "Prepared scooter requires Root")
		Collision.Configure(model, Config)
		Suspension.Configure(model, Config)
		Geometry.AssertSafe(model, Config)
		return model
	end
	assert(not model:FindFirstChild("Root"), "Unprepared scooter contains an unrelated Root")
	for _, side in { "Left", "Right" } do
		local suffix = "FrontSuspension" .. side
		local point = child(child(model, suffix, "MeshPart"), "PivotAtt_" .. suffix, "Attachment") :: Attachment
		if point:GetAttribute("AuthoredPivotCFrame") == nil then point:SetAttribute("AuthoredPivotCFrame", point.CFrame) end
	end
	local direction = rig.frontPoint.WorldPosition - rig.backPoint.WorldPosition
	local forward = Vector3.new(direction.X, 0, direction.Z)
	assert(forward.Magnitude > 0.1, "Wheel axles must have distinct horizontal positions")
	forward = forward.Unit
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1.6, 0.24, 1.5)
	root.CFrame = CFrame.lookAt(rig.body.Position, rig.body.Position + forward, Vector3.yAxis)
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.RootPriority = 127
	root.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.1, 0, 10, 10)
	root.Parent = model
	model.PrimaryPart = root
	weld(root, rig.body, "RuntimeBodyWeld")
	local footRest = child(model, "FootRest", "MeshPart") :: MeshPart
	local fender = child(model, "BackFender", "MeshPart") :: MeshPart
	weld(rig.body, footRest, "RuntimeFootRestWeld")
	weld(rig.backAxle, fender, "RuntimeFenderWeld")

	local bodySize = rig.body.Size
	local deckHeight = (math.abs(rig.body.CFrame.RightVector.Y) * bodySize.X
		+ math.abs(rig.body.CFrame.UpVector.Y) * bodySize.Y
		+ math.abs(rig.body.CFrame.LookVector.Y) * bodySize.Z) * 0.5
	local deckCenter = rig.body.Position + Vector3.yAxis * (deckHeight + Config.RiderPose.FootPlantClearance)
	local right = root.CFrame.RightVector
	attachment(root, "RiderRootAttachment", deckCenter - forward * 0.25)
	attachment(root, "LeftFootPlant", deckCenter + forward * 0.45 - right * 0.32)
	attachment(root, "RightFootPlant", deckCenter - forward * 0.55 + right * 0.32)
	-- Targets live on the moving steering assembly, never on the chassis.
	attachment(rig.handleBar, "LeftHandGrip", rig.handleBar.Position - right * Config.RiderPose.GripHalfWidth)
	attachment(rig.handleBar, "RightHandGrip", rig.handleBar.Position + right * Config.RiderPose.GripHalfWidth)
	local smokePoint = attachment(rig.backAxle, "RearWheelAttachment", rig.backPoint.WorldPosition)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "BurnoutSmoke"
	smoke.Enabled = false
	smoke.LightEmission = 0
	smoke.Lifetime = Config.BurnoutSmokeLifetime
	smoke.Rate = Config.BurnoutSmokeRate
	smoke.Speed = NumberRange.new(4, 8)
	smoke.SpreadAngle = Vector2.new(24, 24)
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Parent = smokePoint
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.2, 0.35, 1.1)
	seat.CFrame = root.CFrame + Vector3.yAxis * (deckHeight + 0.35) - forward * 0.35
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model
	weld(root, seat, "RuntimeSeatWeld")
	for _, instance in model:GetDescendants() do
		if instance:IsA("BasePart") then
			instance.Anchored = false
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
			instance.Massless = instance == rig.body or instance == footRest
				or instance == fender or instance == rig.handleBar or instance == seat
				or instance:GetAttribute("ScooterDecoration") == true
		end
	end
	rig.frontAxle.Transparency = 1
	rig.backAxle.Transparency = 1
	rig.steering.ActuatorType = Enum.ActuatorType.Servo
	if rig.steering.ServoMaxTorque <= 0 then rig.steering.ServoMaxTorque = Config.SteeringServoTorque end
	if rig.steering.AngularSpeed <= 0 then rig.steering.AngularSpeed = Config.SteeringServoSpeed end
	rig.steering.TargetAngle = 0
	rig.frontHinge.ActuatorType = Enum.ActuatorType.None
	rig.backHinge.ActuatorType = Enum.ActuatorType.None
	model:SetAttribute("ArticulatedScooter", true)
	Collision.Configure(model, Config)
	Suspension.Configure(model, Config)
	return model
end

local function tryFrontRest(model: Model, configuration: typeof(Config)): Model
	if model:GetAttribute("FrontRestPoseRevision") == configuration.FrontRestPose.Revision then return model end
	-- A guessed rest correction must never invalidate an otherwise usable rig.
	-- Keep the baseline entirely untouched, including welds and calibrated springs.
	local staged = model:Clone()
	local ok, problem = pcall(function()
		Geometry.AlignFrontRest(staged, configuration)
		Suspension.ConfigureFront(staged, configuration)
		Geometry.AssertSafe(staged, configuration)
	end)
	if not ok then
		staged:Destroy()
		model:SetAttribute("FrontRestPoseStatus", "Skipped")
		model:SetAttribute("FrontRestPoseError", tostring(problem))
		warn("ScooterRig: optional front correction skipped; spawning validated baseline. " .. tostring(problem))
		return model
	end
	staged:SetAttribute("FrontRestPoseStatus", "Applied")
	staged:SetAttribute("FrontRestPoseError", nil)
	model:Destroy()
	return staged
end

function ScooterRig.Prepare(source: Instance, configuration: typeof(Config)?): Model
	ScooterRig.Inspect(source)
	Geometry.AssertSafe(source, configuration or Config)
	local clone = source:Clone()
	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		for _, instance in clone:GetChildren() do instance.Parent = model end
		clone:Destroy()
	end
	local success, result = pcall(configureModel, model, configuration or Config)
	if not success then
		model:Destroy()
		error(tostring(result), 2)
	end
	return tryFrontRest(result, configuration or Config)
end

return ScooterRig
