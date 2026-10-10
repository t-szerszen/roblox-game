--!strict

local ScooterConfig = require(script.Parent.ScooterConfig)

export type DriveInput = {
	velocity: Vector3,
	forward: Vector3,
	groundUp: Vector3,
	gravity: number,
	mass: number,
	maxSpeed: number,
	acceleration: number,
	throttleHeld: boolean,
	brakeHeld: boolean,
	burnout: boolean,
	grounded: boolean,
	fallen: boolean,
	deltaTime: number,
}

local ScooterPhysics = {}

function ScooterPhysics.IsCollisionImpact(previous: Vector3, current: Vector3, normal: Vector3): boolean
	local settings = ScooterConfig.Impact
	local approachSpeed = -previous:Dot(normal)
	return math.abs(normal.Y) <= settings.MaxNormalY
		and approachSpeed >= settings.MinSpeedKmh * ScooterConfig.StudsPerKmH
		and (current - previous):Dot(normal) >= settings.MinSpeedLoss
end

function ScooterPhysics.ComputeStepForce(tangent: Vector3, velocity: Vector3, mass: number, gravity: number, forwardTarget: number?, stepRise: number?, supportFraction: number?): Vector3
	if mass <= 0 or gravity <= 0 or tangent.Y <= 0 then return Vector3.zero end
	local settings = ScooterConfig.StepTraction
	local gentle = stepRise ~= nil and stepRise <= settings.GentleStep.MaxRise
	local vertical = if gentle then settings.GentleStep else settings
	local acceleration = math.clamp((vertical.ClimbSpeed - velocity.Y) * vertical.Response,
		-vertical.Acceleration, vertical.Acceleration)
	local planar = Vector3.new(tangent.X, 0, tangent.Z)
	local push = Vector3.zero
	if planar.Magnitude > 0.001 then
		local forward = planar.Unit
		local target = forwardTarget or settings.MinimumForwardSpeed
		local forwardAcceleration = math.clamp((target - velocity:Dot(forward)) * settings.ForwardResponse,
			0, settings.ForwardAcceleration)
		push = forward * forwardAcceleration
	end
	-- Bound vertical climbing speed without braking horizontal approach momentum.
	-- A rising tire can briefly outrun the chassis through its spring. Continuing
	-- to support it then stores energy that kicks the chassis up over the corner.
	local liftScale = if gentle then math.clamp(1 - (velocity.Y - vertical.ClimbSpeed) / settings.GentleStep.LiftFadeSpeed, 0, 1) else 1
	return (Vector3.yAxis * math.max(0, gravity + acceleration) * liftScale + push) * mass
		* (supportFraction or settings.SupportMassFraction)
end

function ScooterPhysics.IsBraking(forwardSpeed: number, throttleHeld: boolean, brakeHeld: boolean): boolean
	-- S drives reverse once forward motion stops; W brakes a reverse roll.
	return (throttleHeld and brakeHeld)
		or (brakeHeld and forwardSpeed > ScooterConfig.StopSpeed)
		or (throttleHeld and forwardSpeed < -ScooterConfig.StopSpeed)
end

function ScooterPhysics.ProjectOntoPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

function ScooterPhysics.SmoothSteering(current: number, target: number, deltaTime: number): number
	local alpha = 1 - math.exp(-ScooterConfig.SteerSmoothSpeed * math.clamp(deltaTime, 0, 0.1))
	local steering = current + (math.clamp(target, -1, 1) - current) * alpha
	return if target == 0 and math.abs(steering) < 0.001 then 0 else steering
end

function ScooterPhysics.GetEffectiveSteering(steering: number, forwardSpeed: number, _burnout: boolean?): number
	local speed = math.abs(forwardSpeed)
	local speedKmh = speed / ScooterConfig.StudsPerKmH
	local fade = math.clamp(
		(speedKmh - ScooterConfig.SteeringFadeStartKmh)
			/ (ScooterConfig.SteeringFadeEndKmh - ScooterConfig.SteeringFadeStartKmh),
		0,
		1
	)
	return math.clamp(steering, -1, 1) * (1 + (ScooterConfig.HighSpeedSteeringScale - 1) * fade)
end

function ScooterPhysics.GetTurnSteering(steering: number, forwardSpeed: number): number
	-- Reversing changes which end of the scooter leads the turn. Invert only the
	-- chassis yaw; the handlebar still follows the player's left/right input.
	return if forwardSpeed < -ScooterConfig.StopSpeed then -steering else steering
end

function ScooterPhysics.GetServoSteering(
	effectiveSteering: number,
	reversedAttachments: boolean,
	limitsEnabled: boolean,
	lowerAngle: number,
	upperAngle: number
): (number, number)
	local fullAngle = ScooterConfig.SteeringServoSign * math.deg(ScooterConfig.MaxHandlebarAngle)
		* (if reversedAttachments then -1 else 1)
	local angle = math.clamp(effectiveSteering, -1, 1) * fullAngle
	if limitsEnabled then angle = math.clamp(angle, lowerAngle, upperAngle) end
	-- Use the actual available steering range for chassis yaw as well as the Servo.
	return angle, angle / fullAngle
end

function ScooterPhysics.GetYawRate(
	effectiveSteering: number, forwardSpeed: number, wheelBase: number?, burnout: boolean?
): number
	local speed = math.abs(forwardSpeed)
	if math.abs(effectiveSteering) <= 0.01 then
		return 0
	end
	-- A powered, slipping rear tire permits donuts even with negligible travel speed.
	if burnout then return -math.clamp(effectiveSteering, -1, 1) * ScooterConfig.BurnoutTurnRate end
	if speed < ScooterConfig.MinSteeringSpeed then return 0 end
	local steerAngle = math.clamp(effectiveSteering, -1, 1) * ScooterConfig.MaxHandlebarAngle
	local length = math.max(wheelBase or ScooterConfig.WheelBase, ScooterConfig.RigValidation.PositionTolerance)
	local fade = math.clamp((speed / ScooterConfig.StudsPerKmH - ScooterConfig.SteeringFadeStartKmh)
		/ (ScooterConfig.SteeringFadeEndKmh - ScooterConfig.SteeringFadeStartKmh), 0, 1)
	local curvature = 1 + (ScooterConfig.LowSpeedTurnBoost - 1) * (1 - fade)
	-- Keep the previous bicycle controller; only crawling turns get a small boost.
	return math.clamp(-speed * math.tan(steerAngle) * curvature / length, -ScooterConfig.TurnRate, ScooterConfig.TurnRate)
end

function ScooterPhysics.GetSteeringLean(turnSteering: number, forwardSpeed: number, gravity: number, wheelBase: number?): number
	if gravity <= 0 then return 0 end
	local yawRate = ScooterPhysics.GetYawRate(turnSteering, forwardSpeed, wheelBase)
	-- tan(roll) = v * yawRate / g. Signed speed retains the inward lean in reverse.
	return math.clamp(math.atan2(forwardSpeed * yawRate, gravity),
		-ScooterConfig.MaxSteeringLean, ScooterConfig.MaxSteeringLean)
end

function ScooterPhysics.SmoothSteeringLean(current: number, target: number, deltaTime: number): number
	local alpha = 1 - math.exp(-ScooterConfig.SteeringLeanSmoothSpeed * math.clamp(deltaTime, 0, 0.1))
	return current + (target - current) * alpha
end

function ScooterPhysics.AdvanceForward(
	forward: Vector3,
	effectiveSteering: number,
	forwardSpeed: number,
	deltaTime: number,
	wheelBase: number?,
	burnout: boolean?
): Vector3
	local yaw = ScooterPhysics.GetYawRate(effectiveSteering, forwardSpeed, wheelBase, burnout) * math.clamp(deltaTime, 0, 0.1)
	if yaw == 0 then return forward end
	return CFrame.fromAxisAngle(Vector3.yAxis, yaw):VectorToWorldSpace(forward).Unit
end

function ScooterPhysics.AdvanceSteeringHold(current: number, input: number, deltaTime: number): number
	if math.abs(input) < 0.01 then return 0 end
	local direction = if input < 0 then -1 else 1
	local elapsed = if current * direction < 0 then 0 else math.abs(current)
	local settings = ScooterConfig.HeldSteering
	return direction * math.min(elapsed + math.clamp(deltaTime, 0, 0.1), settings.Delay + settings.RampTime)
end

function ScooterPhysics.ClampForwardLead(actual: Vector3, desired: Vector3, yawRate: number?, steeringInput: number?, holdTime: number?): Vector3
	local angle = math.atan2(actual:Cross(desired).Y, actual:Dot(desired))
	-- Small sustained input must not accumulate the same heading lead as full steering.
	local settings = ScooterConfig.HeldSteering
	local ramp = math.clamp(((holdTime or 0) - settings.Delay) / settings.RampTime, 0, 1)
	local fullLead = ScooterConfig.MaxHeadingLeadAngle
		+ (settings.MaxHeadingLeadAngle - ScooterConfig.MaxHeadingLeadAngle) * ramp
	local maximumLead = fullLead * math.abs(math.clamp(steeringInput or 1, -1, 1))
	local limit = if yawRate then math.min(maximumLead, math.abs(yawRate) * ScooterConfig.HeadingLeadSeconds)
		else maximumLead
	local limited = math.clamp(angle, -limit, limit)
	return CFrame.fromAxisAngle(Vector3.yAxis, limited):VectorToWorldSpace(actual).Unit
end

function ScooterPhysics.CanBurnout(speed: number, throttleHeld: boolean, brakeHeld: boolean): boolean
	return throttleHeld and brakeHeld and math.abs(speed) <= ScooterConfig.BurnoutMaxSpeedKmh * ScooterConfig.StudsPerKmH
end

local function lowerWheelie(pitch: number, deltaTime: number, dropRate: number, returnSpeed: number): number
	local transition = dropRate / returnSpeed
	local linearTime = if pitch > transition then math.min(deltaTime, (pitch - transition) / dropRate) else 0
	-- Cap the initial drop rate, then ease the last part of the landing without a snap.
	return (pitch - dropRate * linearTime) * math.exp(-returnSpeed * (deltaTime - linearTime))
end

function ScooterPhysics.AdvanceWheeliePitch(
	currentPitch: number,
	balanceInput: number,
	forwardSpeed: number,
	deltaTime: number
): number
	local step = math.clamp(deltaTime, 0, 0.1)
	local pitch = currentPitch
	if balanceInput > 0 then
		pitch += ScooterConfig.WheeliePitchRate * step
	elseif balanceInput < 0 then
		pitch = lowerWheelie(pitch, step, ScooterConfig.WheelieBrakeDropRate, ScooterConfig.WheelieBrakeReturnSpeed)
	else
		pitch = lowerWheelie(pitch, step, ScooterConfig.WheelieNaturalDropRate, ScooterConfig.WheelieReturnSpeed)
	end

	-- Wheelie cannot balance itself when momentum disappears. The rider must use
	-- throttle to retain speed; braking deliberately drops the front much faster.
	local lowSpeedRatio = 1 - math.clamp(
		math.max(0, forwardSpeed) / ScooterConfig.WheelieLowSpeedDropStart,
		0,
		1
	)
	pitch = math.clamp(pitch - ScooterConfig.WheelieLowSpeedDropRate * lowSpeedRatio * step, 0, ScooterConfig.WheelieFallAngle)
	return if step > 0 and pitch <= ScooterConfig.WheelieRestAngle then 0 else pitch
end

function ScooterPhysics.ComputeDriveForce(input: DriveInput): Vector3
	if not input.grounded or input.fallen or input.mass <= 0 then
		return Vector3.zero
	end

	local forwardSpeed = input.velocity:Dot(input.forward)
	local directionChangeSpeed = ScooterConfig.DirectionChangeSpeedKmh * ScooterConfig.StudsPerKmH
	local targetSpeed = 0
	local rate = ScooterConfig.CoastingDeceleration
	if input.burnout or (input.throttleHeld and input.brakeHeld) then
		rate = ScooterConfig.BrakingDeceleration
	elseif input.throttleHeld then
		if forwardSpeed < -directionChangeSpeed then
			rate = ScooterConfig.DirectionChangeBrakingDeceleration
		else
			targetSpeed = input.maxSpeed
			rate = input.acceleration
		end
	elseif input.brakeHeld then
		if forwardSpeed > directionChangeSpeed then
			rate = ScooterConfig.DirectionChangeBrakingDeceleration
		else
			targetSpeed = -ScooterConfig.MaxReverseSpeedKmh * ScooterConfig.StudsPerKmH
			rate = ScooterConfig.ReverseAcceleration
		end
	end

	local step = math.max(input.deltaTime, 1 / 240)
	local acceleration = 0
	if targetSpeed ~= 0 or math.abs(forwardSpeed) > ScooterConfig.StopSpeed then
		acceleration = math.clamp((targetSpeed - forwardSpeed) / step, -rate, rate)
	end
	-- Opposing input must also brake on slopes, otherwise gravity can prevent
	-- reaching the crawl speed where the reverse/forward drive engages.
	if input.throttleHeld ~= input.brakeHeld and not input.burnout then
		local gravityAlongForward = Vector3.new(0, -math.max(0, input.gravity), 0):Dot(input.forward)
		acceleration -= gravityAlongForward * ScooterConfig.HillAssistGravityScale
	end
	-- Work in the contact plane so grip does not cancel a jump or push into slopes.
	local contactVelocity = ScooterPhysics.ProjectOntoPlane(input.velocity, input.groundUp)
	local lateralVelocity = contactVelocity - input.forward * contactVelocity:Dot(input.forward)
	local lateralAcceleration = Vector3.zero
	if lateralVelocity.Magnitude > ScooterConfig.StopSpeed then
		lateralAcceleration = -lateralVelocity.Unit
			* math.min(lateralVelocity.Magnitude / step, ScooterConfig.LateralGripDeceleration)
	end
	return (input.forward * acceleration + lateralAcceleration) * input.mass
end

function ScooterPhysics.ComputeUprightTorque(
	current: CFrame,
	target: CFrame,
	angularVelocity: Vector3,
	mass: number,
	turnTorque: number
): Vector3
	if mass <= 0 then
		return Vector3.zero
	end
	local errorFrame = target.Rotation * current.Rotation:Inverse()
	local axis, angle = errorFrame:ToAxisAngle()
	local torque = (axis * angle * ScooterConfig.UprightTorqueStiffness
		- angularVelocity * ScooterConfig.UprightTorqueDamping) * mass
	local limit = math.max(0, turnTorque * mass)
	if torque.Magnitude > limit then
		return if limit > 0 then torque.Unit * limit else Vector3.zero
	end
	return torque
end

return ScooterPhysics
