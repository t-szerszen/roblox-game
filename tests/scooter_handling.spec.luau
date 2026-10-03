local start = testCount
check(Physics.CanBurnout(0, true, true), "W+S starts burnout from rest")
check(Physics.CanBurnout(5 * Config.StudsPerKmH, true, true), "Burnout includes exactly 5 km/h")
check(Physics.CanBurnout(-5 * Config.StudsPerKmH, true, true), "Burnout permits reverse crawl within the same limit")
check(not Physics.CanBurnout(5.01 * Config.StudsPerKmH, true, true), "Burnout rejects motion above 5 km/h")
check(not Physics.CanBurnout(0, true, false) and not Physics.CanBurnout(0, false, true), "Releasing either key stops burnout")

near(Physics.GetYawRate(1, 0), 0, "Full steering cannot create stationary yaw")
near(Physics.GetEffectiveSteering(1, 0, true), 1, "Burnout retains handlebar input at rest")
near(Physics.GetYawRate(1, 0, 4, true), -Config.BurnoutTurnRate, "Burnout permits bounded stationary right yaw")
near(Physics.GetYawRate(-1, 0, 4, true), Config.BurnoutTurnRate, "Burnout permits mirrored left yaw")
near(Physics.GetYawRate(0, 0, 4, true), 0, "Burnout does not yaw without steering")
for _, speed in { 0.5, 1, 5 } do
	local yaw = Physics.GetYawRate(1, speed, 4)
	near(speed / math.abs(yaw), 4 / math.tan(Config.MaxHandlebarAngle), "Slow steering retains a finite geometric radius")
end
near(Physics.GetYawRate(1, 1, 8), Physics.GetYawRate(1, 1, 4) / 2, "Actual longer wheelbase widens the turn")
check(math.abs(Physics.GetYawRate(1, 100, 4)) <= Config.TurnRate, "Fast yaw retains its configured bound")
local fwd = Vector.new(0, 0, -1)
local lead = Physics.ClampForwardLead(fwd, -fwd, Physics.GetYawRate(1, 0.6, 4))
check(math.acos(math.clamp(fwd:Dot(lead), -1, 1)) < math.rad(2), "Slow motion cannot accumulate a large orientation target error")
local held = fwd
for _ = 1, 120 do
	held = Physics.ClampForwardLead(fwd, Physics.AdvanceForward(held, 1, 20, 1 / 60, 4), Physics.GetYawRate(1, 20, 4))
end
check(math.acos(math.clamp(fwd:Dot(held), -1, 1)) <= Config.MaxHeadingLeadAngle + 1e-6,
	"Blocked chassis cannot wind up several revolutions of desired heading")
local reducedTarget = Physics.GetServoSteering(1, false, false, -90, 90)
check(math.abs(reducedTarget) <= 30 and math.abs(reducedTarget) < 45,
	"Handlebar no longer reaches the excessive former 45-degree deflection")

local pitch = math.rad(50)
local dropped = Physics.AdvanceWheeliePitch(pitch, 0, 20, 0.1)
check(dropped < pitch and pitch - dropped <= Config.WheelieNaturalDropRate * 0.1 + 1e-6,
	"Released wheelie lowers at cruising speed with bounded angular rate")
check(Physics.AdvanceWheeliePitch(pitch, -1, 20, 0.1) < dropped, "Brake lowers wheelie faster than natural return")
local thirty, sixty = pitch, pitch
for _ = 1, 30 do thirty = Physics.AdvanceWheeliePitch(thirty, 0, 20, 1 / 30) end
for _ = 1, 60 do sixty = Physics.AdvanceWheeliePitch(sixty, 0, 20, 1 / 60) end
near(thirty, sixty, "Natural wheelie return is frame-rate independent")
for _ = 1, 180 do pitch = Physics.AdvanceWheeliePitch(pitch, 0, 20, 1 / 60) end
near(pitch, 0, "Released wheelie reaches the riding pose without stopping the scooter")

local tuning = assert(Config.GetTuning(Config.DefaultModel, 0))
local velocity = Vector.zero
for _ = 1, 120 do
	local force = Physics.ComputeDriveForce({ velocity = velocity, forward = fwd, groundUp = Vector.yAxis,
		gravity = 196.2, mass = 10, maxSpeed = tuning.maxSpeed * Config.StudsPerKmH, acceleration = tuning.acceleration,
		throttleHeld = true, brakeHeld = false, burnout = false, grounded = true, fallen = false, deltaTime = 1 / 60 })
	velocity += force / 10 / 60
end
near(velocity.Magnitude, tuning.maxSpeed * Config.StudsPerKmH, "Drive reaches its tuned speed cap on flat ground")
check(velocity.Magnitude >= tuning.maxSpeed * 1.6 - 1e-6, "World travel speed is 60 percent above the previous 1.0 scale")

local function maneuver(speed, throttle, brake, dt, direction, up)
	return Physics.ComputeDriveForce({ velocity = direction * speed, forward = direction, groundUp = up,
		gravity = 196.2, mass = 10, maxSpeed = tuning.maxSpeed * Config.StudsPerKmH, acceleration = tuning.acceleration,
		throttleHeld = throttle, brakeHeld = brake, burnout = false, grounded = true, fallen = false, deltaTime = dt })
		:Dot(direction) / 10
end
local function integrateManeuver(speed, throttle, brake, dt, frames, direction, up)
	local gravityAlong = Vector.new(0, -196.2, 0):Dot(direction)
	for _ = 1, frames do
		speed += (maneuver(speed, throttle, brake, dt, direction, up) + gravityAlong) * dt
	end
	return speed
end
local reverseLimit = Config.MaxReverseSpeedKmh * Config.StudsPerKmH
check(integrateManeuver(0, false, true, 1 / 60, 60, fwd, Vector.yAxis) < -12 * Config.StudsPerKmH,
	"Reverse accelerates beyond the former 12 km/h limit")
near(integrateManeuver(0, false, true, 1 / 60, 60, fwd, Vector.yAxis), -reverseLimit,
	"Held S settles at the new reverse speed cap")
near(integrateManeuver(20, false, true, 1 / 30, 30, fwd, Vector.yAxis), -reverseLimit,
	"Continuous S transitions from braking into reverse without another press")
near(integrateManeuver(20, false, true, 1 / 120, 120, fwd, Vector.yAxis), -reverseLimit,
	"Braking into reverse also reaches its cap at higher frame rate")
check(1 + maneuver(1, false, true, 1 / 60, fwd, Vector.yAxis) / 60 < 0,
	"Crawling forward transitions into reverse without waiting at near-zero speed")
check(-1 + maneuver(-1, true, false, 1 / 60, fwd, Vector.yAxis) / 60 > 0,
	"W switches a reverse crawl smoothly back to forward drive")
near(maneuver(-reverseLimit, false, true, 1 / 60, fwd, Vector.yAxis), 0,
	"Reverse does not keep accelerating at its cap")
check(maneuver(-reverseLimit - 2, false, true, 1 / 60, fwd, Vector.yAxis) > 0,
	"Reverse overspeed is corrected toward the configured limit")
local coastBack = integrateManeuver(-reverseLimit, false, false, 1 / 60, 30, fwd, Vector.yAxis)
check(coastBack < 0 and coastBack > -reverseLimit, "Releasing S coasts smoothly instead of snapping to a stop")
near(integrateManeuver(20, true, true, 1 / 60, 120, fwd, Vector.yAxis), 0,
	"W+S remains a stop/burnout input and cannot engage reverse")
local downhill = Vector.new(0, -0.5, -math.sqrt(3) / 2)
local slopeUp = Vector.new(0, math.sqrt(3) / 2, -0.5)
check(20 + (maneuver(20, false, true, 1 / 60, downhill, slopeUp)
	+ Vector.new(0, -196.2, 0):Dot(downhill)) / 60 < 20,
	"S can brake downhill even when slope gravity exceeds the raw brake deceleration")
check(integrateManeuver(20, false, true, 1 / 60, 120, downhill, slopeUp) < -12 * Config.StudsPerKmH,
	"Held S can stop a downhill roll and then reverse uphill")
check(integrateManeuver(-20, true, false, 1 / 60, 120, -downhill, slopeUp) > 0,
	"W can stop a reverse slope roll and reengage forward drive")
print(string.format("PASS: %d handling assertions (%d total)", testCount - start, testCount))
