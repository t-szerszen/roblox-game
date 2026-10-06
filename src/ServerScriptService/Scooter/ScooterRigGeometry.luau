--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Collision = require(script.Parent.ScooterCollision)

export type Report = { errors: { string }, warnings: { string }, details: { string } }
local ScooterRigGeometry = {}

local groups = {
	ScooterBody = "body", Root = "body", DriverSeat = "body", FootRest = "body", DeckCollider = "body",
	HandleBarStick = "steering", HandleBar = "steering",
	VirtualFrontAxle = "front", FrontSuspensionLeft = "front", FrontSuspensionRight = "front",
	FrontSteeringCarrier = "frontSteering",
	VirtualBackAxle = "back", BackSuspensionLeft = "back", BackSuspensionRight = "back", BackFender = "back",
	FrontWheel = "frontWheel", FrontWheelCollider = "frontWheel",
	BackWheel = "backWheel", BackWheelCollider = "backWheel",
} :: { [string]: string }

local function conflictingWeld(weld: WeldConstraint, model: Instance): boolean
	local first, second = weld.Part0, weld.Part1
	if not first or not second then return true end
	if not first:IsDescendantOf(model) or not second:IsDescendantOf(model) then return true end
	local firstGroup = groups[first.Name] or first:GetAttribute("ScooterAssembly")
	local secondGroup = groups[second.Name] or second:GetAttribute("ScooterAssembly")
	return firstGroup ~= nil and secondGroup ~= nil and firstGroup ~= secondGroup
end

local function base(model: Instance, endName: string): BasePart?
	local part = model:FindFirstChild(if endName == "Front" and model:GetAttribute("IndependentFrontSteering") ~= true then "HandleBarStick" else "ScooterBody")
	return if part and part:IsA("BasePart") then part else nil
end

local function namedAttachment(parent: Instance, name: string): Attachment
	local instance = parent:FindFirstChild(name)
	assert(instance and instance:IsA("Attachment"), parent.Name .. " requires " .. name)
	return instance
end

function ScooterRigGeometry.Check(model: Instance, configuration: typeof(Config)?): Report
	local settings = (configuration or Config).RigValidation
	local report: Report = { errors = {}, warnings = {}, details = {} }
	local axisDot = math.cos(math.rad(settings.AxisToleranceDegrees))
	for _, instance in model:GetDescendants() do
		if instance:IsA("HingeConstraint") then
			local first, second = instance.Attachment0, instance.Attachment1
			if first and second then
				local gap = (first.WorldPosition - second.WorldPosition).Magnitude
				local alignment = first.WorldAxis:Dot(second.WorldAxis)
				table.insert(report.details, string.format("%s/%s: gap=%.4f studs, axis dot=%.4f, angle=%.2f limits=%s [%.2f, %.2f]",
					instance.Parent and instance.Parent.Name or "?", instance.Name, gap, alignment,
					instance.CurrentAngle, tostring(instance.LimitsEnabled), instance.LowerAngle, instance.UpperAngle))
				if gap > settings.PositionTolerance then
					table.insert(report.errors, instance.Name .. ": hinge attachments do not share a world position")
				end
				if alignment < axisDot then
					table.insert(report.errors, instance.Name .. ": hinge X axes do not point in the same direction")
				end
			end
		elseif instance:IsA("WeldConstraint") and instance.Enabled and conflictingWeld(instance, model) then
			table.insert(report.errors, instance.Name .. ": weld crosses separate moving assemblies or leaves the scooter")
		elseif instance:IsA("SpringConstraint") then
			if instance.Stiffness <= 0 or instance.MaxForce <= 0 then
				table.insert(report.errors, instance.Name .. ": spring has no supporting stiffness/force")
			end
			if instance.Damping <= 0 then table.insert(report.warnings, instance.Name .. ": no spring damping") end
			local first, second = instance.Attachment0, instance.Attachment1
			if first and second then
				local length = (first.WorldPosition - second.WorldPosition).Magnitude
				if length <= settings.PositionTolerance then
					table.insert(report.errors, instance.Name .. ": spring attachments have no separation")
				end
				table.insert(report.details, string.format("%s: length=%.3f free=%.3f stiffness=%.1f damping=%.1f maxForce=%.1f",
					instance.Name, length, instance.FreeLength, instance.Stiffness, instance.Damping, instance.MaxForce))
				if instance.LimitsEnabled and (length < instance.MinLength - settings.PositionTolerance
					or length > instance.MaxLength + settings.PositionTolerance) then
					table.insert(report.errors, instance.Name .. ": authored pose is outside the spring length limits")
				end
			end
		end
	end
	for _, endName in { "Front", "Back" } do
		local parent = base(model, endName)
		if parent then
			local left = parent:FindFirstChild("PivotAttBase_" .. endName .. "SuspensionLeft")
			local right = parent:FindFirstChild("PivotAttBase_" .. endName .. "SuspensionRight")
			if left and left:IsA("Attachment") and right and right:IsA("Attachment") then
				local delta = right.WorldPosition - left.WorldPosition
				local offAxis = (delta - left.WorldAxis * delta:Dot(left.WorldAxis)).Magnitude
				if math.abs(left.WorldAxis:Dot(right.WorldAxis)) < axisDot or offAxis > settings.PositionTolerance then
					table.insert(report.errors, endName .. ": welded suspension arms require coaxial left/right pivots")
				end
			end
			for _, side in { "Left", "Right" } do
				local hinge = parent:FindFirstChild("PivotHinge_" .. endName .. "Suspension" .. side)
				if hinge and hinge:IsA("HingeConstraint") and hinge.ActuatorType ~= Enum.ActuatorType.None then
					table.insert(report.errors, hinge.Name .. ": suspension pivot must be passive")
				end
			end
		end
	end
	local body = model:FindFirstChild("ScooterBody")
	local steeringBase = if body then body:FindFirstChild("SteerBase") else nil
	if steeringBase and steeringBase:IsA("Attachment")
		and math.abs(steeringBase.WorldAxis.Y) < settings.MinimumSteeringAxisUpDot then
		table.insert(report.warnings, "SteerBase: steering axis is nearly horizontal; inspect the shaft axis")
	end
	return report
end

function ScooterRigGeometry.AssertSafe(model: Instance, configuration: typeof(Config)?)
	local report = ScooterRigGeometry.Check(model, configuration)
	assert(#report.errors == 0, "Unsafe scooter rig. Run DevScooterRepair.DiagnoseSelection()/RepairSelection():\n"
		.. table.concat(report.errors, "\n"))
end

local function frameAt(position: Vector3, axis: Vector3): CFrame
	local reference = if math.abs(axis.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local secondary = (reference - axis * reference:Dot(axis)).Unit
	return CFrame.fromMatrix(position, axis, secondary)
end

local function place(point: Attachment, frame: CFrame)
	local parent = point.Parent
	assert(parent and parent:IsA("BasePart"), "Scooter attachment must belong to a BasePart")
	point.CFrame = parent.CFrame:ToObjectSpace(frame)
end

-- Only call on a staged clone, after ScooterRig.Inspect validates the named endpoints.
function ScooterRigGeometry.Repair(model: Instance, configuration: typeof(Config)?): { string }
	local changes: { string } = ScooterRigGeometry.RepairFront(model, nil, configuration)
	model:SetAttribute("SuspensionRevision", nil)
	local front = model:FindFirstChild("FrontWheel")
	local back = model:FindFirstChild("BackWheel")
	assert(front and back, "Scooter requires both wheels")
	local frontCenter, backCenter = namedAttachment(front, "WheelCenter"), namedAttachment(back, "WheelCenter")
	local direction = frontCenter.WorldPosition - backCenter.WorldPosition
	local forward = Vector3.new(direction.X, 0, direction.Z)
	assert(forward.Magnitude > 0.1, "WheelCenter positions cannot determine the scooter direction")
	local lateral = forward.Unit:Cross(Vector3.yAxis).Unit
	for _, endName in { "Back" } do
		local parent = assert(base(model, endName))
		local left = namedAttachment(parent, "PivotAttBase_" .. endName .. "SuspensionLeft")
		local right = namedAttachment(parent, "PivotAttBase_" .. endName .. "SuspensionRight")
		local delta = right.WorldPosition - left.WorldPosition
		local axis = if delta.Magnitude > 0.001 then delta.Unit else lateral
		if axis:Dot(lateral) < 0 then axis = -axis end
		for _, side in { "Left", "Right" } do
			local suffix = endName .. "Suspension" .. side
			local fixed = namedAttachment(parent, "PivotAttBase_" .. suffix)
			local arm = assert(model:FindFirstChild(suffix))
			local moving = namedAttachment(arm, "PivotAtt_" .. suffix)
			local frame = frameAt(fixed.WorldPosition, axis)
			place(fixed, frame)
			place(moving, frame)
			local hinge = parent:FindFirstChild("PivotHinge_" .. suffix) :: HingeConstraint
			hinge.ActuatorType = Enum.ActuatorType.None
		end
		local axle = assert(model:FindFirstChild("Virtual" .. endName .. "Axle"))
		local center = if endName == "Front" then frontCenter else backCenter
		local frame = frameAt(center.WorldPosition, axis)
		place(namedAttachment(axle, "AxlePivot"), frame)
		place(center, frame)
		local wheelHinge = axle:FindFirstChild("HingeConstraint") :: HingeConstraint
		wheelHinge.ActuatorType = Enum.ActuatorType.None
		wheelHinge.LimitsEnabled = false
		table.insert(changes, endName .. ": matched hinge positions/axes and made suspension pivots coaxial")
	end
	local body = assert(model:FindFirstChild("ScooterBody"))
	local stick = assert(model:FindFirstChild("HandleBarStick"))
	local steeringBase = namedAttachment(body, "SteerBase")
	local axis = steeringBase.WorldAxis
	if math.abs(axis.Y) < (configuration or Config).RigValidation.MinimumSteeringAxisUpDot then
		local handleBar = model:FindFirstChild("HandleBar") :: MeshPart
		local shaft = handleBar.Position - steeringBase.WorldPosition
		assert(shaft.Magnitude > 0.1, "Cannot infer steering shaft: position SteerBase and HandleBar first")
		axis = shaft.Unit
		table.insert(changes, "Steering: estimated shaft axis from SteerBase toward HandleBar; verify in Studio")
	end
	local steeringFrame = frameAt(steeringBase.WorldPosition, axis)
	place(steeringBase, steeringFrame)
	place(namedAttachment(stick, "SteerPivot"), steeringFrame)
	for _, instance in model:GetDescendants() do
		if instance:IsA("WeldConstraint") and instance.Enabled and conflictingWeld(instance, model) then
			instance.Enabled = false
			table.insert(changes, "Disabled incompatible weld: " .. instance.Name)
		end
	end
	return changes
end

-- A misplaced fixed attachment must not relocate the visible arm's pivot.
-- Reference is the untouched authored scooter, not a deformed Play-mode copy.
function ScooterRigGeometry.RepairFront(model: Instance, reference: Instance?, configuration: typeof(Config)?): { string }
	local config = configuration or Config
	local stick = assert(base(model, "Front"))
	local points: { Attachment } = {}
	for _, side in { "Left", "Right" } do
		local suffix = "FrontSuspension" .. side
		local arm = assert(model:FindFirstChild(suffix))
		local moving = namedAttachment(arm, "PivotAtt_" .. suffix)
		local originalArm = if reference then assert(reference:FindFirstChild(suffix)) else arm
		local original = namedAttachment(originalArm, "PivotAtt_" .. suffix)
		local frame = original:GetAttribute("AuthoredPivotCFrame")
		if frame == nil then
			assert((reference or model):GetAttribute("SuspensionRevision") == nil,
				"Front pivot originals unavailable. Select the installed template AND an untouched scooter from ScooterRepairBackups, or restore AuthoredPivotCFrame on both front arm attachments.")
			frame = original.CFrame
		end
		assert(typeof(frame) == "CFrame", suffix .. ": AuthoredPivotCFrame must be a CFrame")
		moving.CFrame = frame :: CFrame
		moving:SetAttribute("AuthoredPivotCFrame", frame)
		table.insert(points, moving)
	end
	local delta = points[2].WorldPosition - points[1].WorldPosition
	assert(delta.Magnitude > config.RigValidation.PositionTolerance, "Front arm pivots must define a shared axle")
	local axis = delta.Unit
	local wheel = assert(model:FindFirstChild("FrontWheel"))
	local center = namedAttachment(wheel, "WheelCenter")
	local back = namedAttachment(assert(model:FindFirstChild("BackWheel")), "WheelCenter")
	local direction = center.WorldPosition - back.WorldPosition
	local lateral = direction:Cross(Vector3.yAxis).Unit
	assert(math.abs(axis:Dot(lateral)) >= math.cos(math.rad(config.RigValidation.AxisToleranceDegrees)),
		"Front arm pivots are not transverse to the scooter; position both at the visible deck-side hinge centers")
	if axis:Dot(lateral) < 0 then axis = -axis end
	for index, side in { "Left", "Right" } do
		local suffix = "FrontSuspension" .. side
		local frame = frameAt(points[index].WorldPosition, axis)
		place(points[index], frame)
		place(namedAttachment(stick, "PivotAttBase_" .. suffix), frame)
		local hinge = stick:FindFirstChild("PivotHinge_" .. suffix) :: HingeConstraint
		hinge.ActuatorType = Enum.ActuatorType.None
	end
	local axle = assert(model:FindFirstChild(if model:GetAttribute("IndependentFrontSteering") == true
		then "FrontSteeringCarrier" else "VirtualFrontAxle"))
	local wheelFrame = frameAt(center.WorldPosition, axis)
	place(namedAttachment(axle, "AxlePivot"), wheelFrame)
	place(center, wheelFrame)
	local wheelHinge = axle:FindFirstChild("HingeConstraint") :: HingeConstraint
	wheelHinge.ActuatorType = Enum.ActuatorType.None
	wheelHinge.LimitsEnabled = false
	return { "Front: restored authored arm pivots at the deck-side mounts; fixed attachments now follow those mounts" }
end

-- Attachment repair alone cannot correct the imported arm/wheel rest pose.
-- Match tire bottom heights to the working rear by rotating the entire front linkage.
function ScooterRigGeometry.AlignFrontRest(model: Model, configuration: typeof(Config)?): { string }
	local config = configuration or Config
	if model:GetAttribute("CentralShockRig") == true then
		model:SetAttribute("FrontRestPoseStatus", "Authored")
		return {}
	end
	if model:GetAttribute("FrontRestPoseRevision") == config.FrontRestPose.Revision then return {} end
	local stick = assert(base(model, "Front"))
	local left = namedAttachment(stick, "PivotAttBase_FrontSuspensionLeft")
	local right = namedAttachment(stick, "PivotAttBase_FrontSuspensionRight")
	local pivot = (left.WorldPosition + right.WorldPosition) * 0.5
	local axis = left.WorldAxis
	local front = model:FindFirstChild("FrontWheel") :: MeshPart
	local back = model:FindFirstChild("BackWheel") :: MeshPart
	local center = namedAttachment(front, "WheelCenter")
	local backCenter = namedAttachment(back, "WheelCenter")
	local up = if model.PrimaryPart then model.PrimaryPart.CFrame.UpVector else Vector3.yAxis
	local frontRadius = Collision.ResolveRadius(model, front)
	local backRadius = Collision.ResolveRadius(model, back)
	local offset = center.WorldPosition - pivot
	local shift = Vector3.zero
	if config.FrontRestPose.MatchRearMount then
		local body = assert(base(model, "Back"))
		local rearLeft = namedAttachment(body, "PivotAttBase_BackSuspensionLeft")
		local rearRight = namedAttachment(body, "PivotAttBase_BackSuspensionRight")
		local rearPivot = (rearLeft.WorldPosition + rearRight.WorldPosition) * 0.5
		local deck = model:FindFirstChild("FootRest") :: BasePart
		local direction = center.WorldPosition - backCenter.WorldPosition
		local forward = (direction - up * direction:Dot(up)).Unit
		local mount = rearPivot - forward * (2 * (rearPivot - deck.Position):Dot(forward))
		shift = mount - pivot
		assert(shift.Magnitude <= frontRadius * config.FrontRestPose.MaxMountShiftRadiusRatio,
			"Front mounting is too far from the mirrored rear deck joint; inspect original arm pivots")
	end
	local target = (backCenter.WorldPosition - pivot - shift):Dot(up) + frontRadius - backRadius
	local height = offset:Dot(up)
	local angle = 0
	if math.abs(height - target) > config.FrontRestPose.HeightTolerance then
		local parallel = axis * offset:Dot(axis)
		local cosine, sine, constant = (offset - parallel):Dot(up), axis:Cross(offset):Dot(up), parallel:Dot(up)
		local amplitude = math.sqrt(cosine * cosine + sine * sine)
		assert(amplitude > config.RigValidation.PositionTolerance and math.abs(target - constant) <= amplitude,
			"Front rest pose cannot reach the rear tire level around its current pivot; inspect deck-side mounts")
		local phase = math.atan2(sine, cosine)
		local spread = math.acos(math.clamp((target - constant) / amplitude, -1, 1))
		local first = (phase + spread + math.pi) % (2 * math.pi) - math.pi
		local second = (phase - spread + math.pi) % (2 * math.pi) - math.pi
		angle = if math.abs(first) <= math.abs(second) then first else second
		assert(math.abs(angle) <= math.rad(config.FrontRestPose.MaxCorrectionDegrees),
			"Front rest correction exceeds safe angle; restore original mounting attachments")
	end
	local parts: { [BasePart]: boolean } = {}
	for _, name in { "FrontSuspensionLeft", "FrontSuspensionRight", "VirtualFrontAxle", "FrontWheel", "FrontWheelCollider" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then parts[part] = true end
	end
	local welds: { WeldConstraint } = {}
	for _, instance in model:GetDescendants() do
		if instance:IsA("WeldConstraint") and instance.Enabled
			and (parts[instance.Part0 :: BasePart] or parts[instance.Part1 :: BasePart]) then
			assert(parts[instance.Part0 :: BasePart] and parts[instance.Part1 :: BasePart], "Front rest pose has a cross-assembly weld")
			instance.Enabled = false
			table.insert(welds, instance)
		end
	end
	local transform = CFrame.new(shift) * CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot)
	for part in parts do part.CFrame = transform * part.CFrame end
	for _, weld in welds do weld.Enabled = true end
	for _, side in { "Left", "Right" } do
		local suffix = "FrontSuspension" .. side
		local fixed = namedAttachment(stick, "PivotAttBase_" .. suffix)
		local frame = frameAt(fixed.WorldPosition + shift, axis)
		place(fixed, frame)
		place(namedAttachment(assert(model:FindFirstChild(suffix)), "PivotAtt_" .. suffix), frame)
	end
	model:SetAttribute("FrontRestPoseRevision", config.FrontRestPose.Revision)
	model:SetAttribute("FrontRestCorrectionDegrees", math.deg(angle))
	model:SetAttribute("FrontMountShift", shift)
	return { string.format("Front: moved deck-side mount by %.3f studs and rotated arm/axle/wheel by %.2f degrees to match the working rear",
		shift.Magnitude, math.deg(angle)) }
end

return ScooterRigGeometry
