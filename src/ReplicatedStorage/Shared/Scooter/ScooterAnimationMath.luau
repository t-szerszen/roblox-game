--!strict

local Config = require(script.Parent.ScooterConfig)

export type LegState = "IDLE" | "RIDING" | "WHEELIE"

local ScooterAnimationMath = {}

function ScooterAnimationMath.GetLegState(
	previous: LegState?, speedKmh: number, wheelieActive: boolean, canIdle: boolean
): LegState
	if wheelieActive then return "WHEELIE" end
	if not canIdle or speedKmh ~= speedKmh or math.abs(speedKmh) == math.huge then return "RIDING" end
	local threshold = if previous == "IDLE"
		then Config.RiderAnimations.IdleExitSpeedKmh
		else Config.RiderAnimations.IdleEnterSpeedKmh
	return if math.abs(speedKmh) <= threshold then "IDLE" else "RIDING"
end

function ScooterAnimationMath.Lean(forwardSpeed: number, lateralSpeed: number, steeringAngle: number): number
	local pose = Config.RiderPose
	local speedBlend = math.clamp(math.abs(forwardSpeed) / pose.LeanFullSpeed, 0, 1)
	local steering = math.clamp(steeringAngle / Config.MaxHandlebarAngle, -1, 1)
	local lateral = math.clamp(lateralSpeed / pose.LateralLeanFullSpeed, -1, 1)
	return -pose.MaxBodyLean * math.clamp(
		steering * speedBlend + lateral * pose.LateralLeanWeight, -1, 1
	)
end

return ScooterAnimationMath
