--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Collision = require(script.Parent.ScooterCollision)

type SpringGeometry = {
	spring: SpringConstraint,
	fixed: Vector3,
	offset: Vector3,
	derivative: number,
	length: number,
}
type EndPlan = {
	springs: { SpringGeometry },
	hinges: { HingeConstraint },
	basePoints: { Attachment },
	pivot: Vector3,
	axis: Vector3,
	wheelOffset: Vector3,
	wheelDerivative: number,
	compression: number,
	droop: number,
	stiffness: number,
	damping: number,
	loadTorque: number,
	derivativesSquared: number,
}
local ScooterSuspension = {}

local function child(parent: Instance, name: string): Instance
	return assert(parent:FindFirstChild(name), parent.Name .. " requires " .. name)
end

local function springPose(data: SpringGeometry, pivot: Vector3, axis: Vector3, angle: number): (number, number)
	local offset = CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(data.offset)
	local delta = pivot + offset - data.fixed
	local length = delta.Magnitude
	local derivative = if length > 0 then delta:Dot(axis:Cross(offset)) / length else 0
	return length, derivative
end

local function safeRange(
	plan: EndPlan, direction: number, maxDegrees: number, travel: number, settings: typeof(Config.Suspension)
): number
	local safe = 0
	for degrees = settings.SampleStepDegrees, maxDegrees, settings.SampleStepDegrees do
		local angle = math.rad(degrees) * direction
		local offset = CFrame.fromAxisAngle(plan.axis, angle):VectorToWorldSpace(plan.wheelOffset)
		local wheelDerivative = plan.axis:Cross(offset).Y
		if wheelDerivative * plan.wheelDerivative <= 0 then break end
		local valid = true
		for _, spring in plan.springs do
			local length, derivative = springPose(spring, plan.pivot, plan.axis, angle)
			if length <= 0 or derivative * spring.derivative <= 0
				or math.abs(derivative / wheelDerivative) < settings.MinimumLeverageRatio then
				valid = false
				break
			end
		end
		if not valid then break end
		safe = degrees
		if math.abs(offset.Y - plan.wheelOffset.Y) >= travel then break end
	end
	-- Stop before either spring or wheel passes its turning point.
	return math.rad(math.max(0, safe - settings.LimitMarginDegrees)) * direction
end

local function planEnd(model: Model, endName: string, mass: number, configuration: typeof(Config)): EndPlan
	local settings = configuration.Suspension
	local tune = if endName == "Front" then settings.Front else settings.Back
	local base = child(model, if endName == "Front" then "HandleBarStick" else "ScooterBody")
	local wheel = child(model, endName .. "Wheel") :: MeshPart
	local radius = Collision.ResolveRadius(model, wheel)
	local leftPoint = child(base, "PivotAttBase_" .. endName .. "SuspensionLeft") :: Attachment
	local axis, pivot = leftPoint.WorldAxis, leftPoint.WorldPosition
	local wheelOffset = (child(wheel, "WheelCenter") :: Attachment).WorldPosition - pivot
	local wheelDerivative = axis:Cross(wheelOffset).Y
	assert(math.abs(wheelDerivative) > configuration.RigValidation.PositionTolerance,
		endName .. " suspension: wheel is at a vertical travel turning point; inspect pivot position")
	local plan: EndPlan = {
		springs = {}, hinges = {}, basePoints = {}, pivot = pivot, axis = axis, wheelOffset = wheelOffset,
		wheelDerivative = wheelDerivative, compression = 0, droop = 0, stiffness = 0, damping = 0,
		loadTorque = 0, derivativesSquared = 0,
	}
	for _, side in { "Left", "Right" } do
		local suffix = endName .. "Suspension" .. side
		local spring = child(base, "ShockAbsorber_" .. suffix) :: SpringConstraint
		local fixed = child(base, "SpringAttBase_" .. suffix) :: Attachment
		local moving = child(child(model, suffix), "SpringAtt_" .. suffix) :: Attachment
		local delta = moving.WorldPosition - fixed.WorldPosition
		local offset = moving.WorldPosition - pivot
		local derivative = delta.Unit:Dot(axis:Cross(offset))
		assert(math.abs(derivative / wheelDerivative) >= settings.MinimumLeverageRatio,
			suffix .. ": spring has insufficient leverage; move its authored mounting attachments")
		table.insert(plan.springs, {
			spring = spring, fixed = fixed.WorldPosition, offset = offset, derivative = derivative, length = delta.Magnitude,
		})
		table.insert(plan.hinges, child(base, "PivotHinge_" .. suffix) :: HingeConstraint)
		table.insert(plan.basePoints, child(base, "PivotAttBase_" .. suffix) :: Attachment)
		plan.derivativesSquared += derivative * derivative
	end
	local compressionDirection = if wheelDerivative > 0 then 1 else -1
	plan.compression = safeRange(plan, compressionDirection, tune.MaxCompressionDegrees,
		radius * tune.CompressionRadiusRatio, settings)
	plan.droop = safeRange(plan, -compressionDirection, tune.MaxDroopDegrees,
		radius * tune.DroopRadiusRatio, settings)
	assert(plan.compression ~= 0 and plan.droop ~= 0,
		endName .. ": insufficient safe suspension travel; inspect spring mounting geometry")
	local compressedOffset = CFrame.fromAxisAngle(axis, plan.compression):VectorToWorldSpace(wheelOffset)
	local sag = math.abs(compressedOffset.Y - wheelOffset.Y) * tune.SagFraction
	local gravity = Workspace.Gravity
	assert(gravity > 0 and sag > 0, "Suspension tuning requires gravity and positive wheel travel")
	local endMass = mass * 0.5
	-- Tune at the wheel, then divide by the actual linkage leverage of both shocks.
	-- This avoids a short front spring appearing rigid while a long rear one folds.
	local frequencySquared = gravity * (1 - settings.PreloadSupportFraction) / sag
	local leverageScale = wheelDerivative * wheelDerivative / plan.derivativesSquared
	plan.stiffness = endMass * frequencySquared * leverageScale
	plan.damping = 2 * settings.DampingRatio * endMass * math.sqrt(frequencySquared) * leverageScale
	plan.loadTorque = -endMass * gravity * wheelDerivative * settings.PreloadSupportFraction
	return plan
end

local function applyPlan(plan: EndPlan, settings: typeof(Config.Suspension))
	for index, hinge in plan.hinges do
		local fixed = plan.basePoints[index]
		local first, second = assert(hinge.Attachment0), assert(hinge.Attachment1)
		local rest = math.deg(math.atan2(first.WorldAxis:Dot(first.WorldCFrame.UpVector:Cross(second.WorldCFrame.UpVector)),
			first.WorldCFrame.UpVector:Dot(second.WorldCFrame.UpVector)))
		local sign = (if first == fixed then 1 else -1) * first.WorldAxis:Dot(plan.axis)
		local firstLimit, secondLimit = rest + math.deg(plan.compression) * sign, rest + math.deg(plan.droop) * sign
		hinge.ActuatorType = Enum.ActuatorType.None
		hinge.LimitsEnabled = true
		hinge.LowerAngle = math.min(firstLimit, secondLimit)
		hinge.UpperAngle = math.max(firstLimit, secondLimit)
		hinge.Restitution = 0
		hinge:SetAttribute("SuspensionRestAngle", rest)
	end
	for _, spring in plan.springs do
		local force = plan.loadTorque * spring.derivative / plan.derivativesSquared
		local freeLength = spring.length + force / plan.stiffness
		assert(freeLength > 0, spring.spring.Name .. ": preload requires negative free length; inspect mounting geometry")
		local compressed = springPose(spring, plan.pivot, plan.axis, plan.compression)
		local drooped = springPose(spring, plan.pivot, plan.axis, plan.droop)
		local shock = spring.spring
		if shock:GetAttribute("AuthoredStiffness") == nil then
			shock:SetAttribute("AuthoredStiffness", shock.Stiffness)
			shock:SetAttribute("AuthoredDamping", shock.Damping)
			shock:SetAttribute("AuthoredFreeLength", shock.FreeLength)
		end
		shock.Stiffness = plan.stiffness
		shock.Damping = plan.damping
		shock.FreeLength = freeLength
		-- Hinges bound wheel travel. Length limits cover that entire arc with slack,
		-- so the two kinds of stops cannot pin the front suspension at rest.
		shock.LimitsEnabled = true
		local margin = spring.length * 0.02
		shock.MinLength = math.max(0, math.min(compressed, drooped, spring.length) - margin)
		shock.MaxLength = math.max(compressed, drooped, spring.length) + margin
		local maxDeflection = math.max(math.abs(freeLength - shock.MinLength), math.abs(freeLength - shock.MaxLength))
		shock.MaxForce = math.max(math.abs(force), plan.stiffness * maxDeflection) * settings.ForceHeadroom
		shock:SetAttribute("SuspensionRestLength", spring.length)
	end
end

function ScooterSuspension.ConfigureFront(model: Model, configuration: typeof(Config)?)
	local config = configuration or Config
	assert(model:GetAttribute("SuspensionRevision") == config.Suspension.Revision,
		"Front-only repair requires the current calibrated template; apply full suspension setup first")
	local mass = model:GetAttribute("SuspensionReferenceMass")
	assert(typeof(mass) == "number" and mass > 0 and mass < math.huge, "Template is missing calibrated reference mass")
	applyPlan(planEnd(model, "Front", mass, config), config.Suspension)
	local stick = child(model, "HandleBarStick")
	for _, instance in stick:GetChildren() do
		if instance:IsA("Constraint") then instance.Visible = config.Suspension.ShowConstraints end
	end
end

function ScooterSuspension.Configure(model: Model, configuration: typeof(Config)?)
	local config = configuration or Config
	for _, instance in model:GetDescendants() do
		if instance:IsA("Constraint") then instance.Visible = config.Suspension.ShowConstraints end
	end
	-- Clones retain calibrated rest limits; never use a compressed live pose as a new rest pose.
	if model:GetAttribute("SuspensionRevision") == config.Suspension.Revision then return end
	local mass = config.Suspension.ReferenceRiderMass
	for _, instance in model:GetDescendants() do
		if instance:IsA("BasePart") and not instance.Massless then mass += instance:GetMass() end
	end
	local front, back = planEnd(model, "Front", mass, config), planEnd(model, "Back", mass, config)
	applyPlan(front, config.Suspension)
	applyPlan(back, config.Suspension)
	model:SetAttribute("SuspensionReferenceMass", mass)
	model:SetAttribute("SuspensionRevision", config.Suspension.Revision)
end

return ScooterSuspension
