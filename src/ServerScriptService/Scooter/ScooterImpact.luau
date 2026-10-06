--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Physics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)

export type Tracker = { velocity: Vector3, normal: Vector3?, hitAt: number }
local ScooterImpact = {}

function ScooterImpact.New(): Tracker
	return { velocity = Vector3.zero, normal = nil, hitAt = -math.huge }
end

function ScooterImpact.Update(tracker: Tracker, velocity: Vector3, center: Vector3, radius: number,
	params: RaycastParams, occupied: boolean, now: number, deltaTime: number): boolean
	local settings = Config.Impact
	local impact = occupied and tracker.normal ~= nil and now - tracker.hitAt <= settings.MemorySeconds
		and Physics.IsCollisionImpact(tracker.velocity, velocity, tracker.normal :: Vector3)
	tracker.velocity = velocity
	if not occupied then tracker.normal = nil; return false end
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	if planar.Magnitude >= settings.MinSpeedKmh * Config.StudsPerKmH then
		-- Probe above climbable curb faces. A sudden loss of approach speed must
		-- follow this wall contact; braking, landings and glancing turns are excluded.
		local direction = planar.Unit
		local clearance = math.min(Config.MaxStepHeight, (radius - Config.WheelColliderClearance) * Config.StepTraction.MaxRadiusRatio)
		local hit = Workspace:Raycast(center + Vector3.yAxis * (clearance - radius + settings.ProbePadding),
			direction * (radius + settings.ProbePadding + planar.Magnitude * math.clamp(deltaTime, 0, 0.1)), params)
		if hit and math.abs(hit.Normal.Y) <= settings.MaxNormalY and hit.Normal:Dot(direction) <= -settings.MinOpposition then
			tracker.normal, tracker.hitAt = hit.Normal, now
		end
	end
	return impact
end

return ScooterImpact
