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

function ScooterPhysics.ProjectOntoPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

function ScooterPhysics.SmoothSteering(current: number, target: number, deltaTime: number): number
	local alpha = 1 - math.exp(-ScooterConfig.SteerSmoothSpeed * math.clamp(deltaTime, 0, 0.1))
	local steering = current + (math.clamp(target, -1, 1) - current) * alpha
	return if target == 0 and math.abs(steering) < 0.001 then 0 else steering
end

function ScooterPhysics.GetEffectiveSteering(steering: number, forwardSpeed: number): number
	local speed = math.abs(forwardSpeed)
	if speed < ScooterConfig.MinSteeringSpeed then
		return 0
	end
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

function ScooterPhysics.AdvanceForward(
	forward: Vector3,
	effectiveSteering: number,
	forwardSpeed: number,
	deltaTime: number
): Vector3
	if math.abs(effectiveSteering) <= 0.01 then
		return forward
	end
	local turnScale = math.clamp(math.abs(forwardSpeed) / 12, 0.25, 1)
	local yaw = -effectiveSteering * ScooterConfig.TurnRate * turnScale * math.clamp(deltaTime, 0, 0.1)
	return CFrame.fromAxisAngle(Vector3.yAxis, yaw):VectorToWorldSpace(forward).Unit
end

function ScooterPhysics.AdvanceWheeliePitch(
	currentPitch: number,
	balanceInput: number,
	forwardSpeed: number,
	deltaTime: number
): number
	local rate = 0
	if balanceInput > 0 then
		rate = ScooterConfig.WheeliePitchRate
	elseif balanceInput < 0 then
		rate = -ScooterConfig.WheelieBrakeDropRate
	end

	-- Wheelie cannot balance itself when momentum disappears. The rider must use
	-- throttle to retain speed; braking deliberately drops the front much faster.
	local lowSpeedRatio = 1 - math.clamp(
		math.max(0, forwardSpeed) / ScooterConfig.WheelieLowSpeedDropStart,
		0,
		1
	)
	rate -= ScooterConfig.WheelieLowSpeedDropRate * lowSpeedRatio
	return math.clamp(
		currentPitch + rate * math.clamp(deltaTime, 0, 0.1),
		0,
		ScooterConfig.WheelieFallAngle
	)
end

function ScooterPhysics.ComputeDriveForce(input: DriveInput): Vector3
	if not input.grounded or input.fallen or input.mass <= 0 then
		return Vector3.zero
	end

	local forwardSpeed = input.velocity:Dot(input.forward)
	local targetSpeed = 0
	local rate = ScooterConfig.CoastingDeceleration
	if input.burnout or (input.throttleHeld and input.brakeHeld) then
		rate = ScooterConfig.BrakingDeceleration
	elseif input.throttleHeld then
		if forwardSpeed < -ScooterConfig.StopSpeed then
			rate = ScooterConfig.BrakingDeceleration
		else
			targetSpeed = input.maxSpeed
			rate = input.acceleration
		end
	elseif input.brakeHeld then
		if forwardSpeed > ScooterConfig.StopSpeed then
			rate = ScooterConfig.BrakingDeceleration
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
	if targetSpeed ~= 0 then
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
