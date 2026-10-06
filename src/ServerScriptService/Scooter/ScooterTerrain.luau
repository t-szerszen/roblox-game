--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Physics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)

export type Wheel = { part: BasePart, point: Attachment, radius: number }
export type Controller = {
	Update: (direction: Vector3?, mass: number, params: RaycastParams, grounded: boolean?, speedLimit: number?) -> (),
	Destroy: () -> (),
}
local ScooterTerrain = {}

function ScooterTerrain.Probe(wheel: Wheel, direction: Vector3, params: RaycastParams): Vector3?
	local radius = math.max(wheel.radius * 0.5, wheel.radius - Config.WheelColliderClearance)
	local center = wheel.point.WorldPosition
	local bottom = center - Vector3.yAxis * radius
	local height = math.min(Config.MaxStepHeight, radius * Config.StepTraction.MaxRadiusRatio)
	-- At an angle the travel ray reaches the face later than the round tire.
	-- Extend the ray, then gate on distance perpendicular to the actual face.
	local probe = direction * ((radius + Config.StepTraction.ContactPadding) / Config.StepTraction.MinFaceOpposition)
	local low = Workspace:Raycast(bottom + Vector3.yAxis * Config.StepProbeHeight,
		probe, params)
	if not low then
		-- Once lifted, the higher ray can clear the corner before the tire does.
		-- A lower fallback keeps support through the last part of the climb.
		low = Workspace:Raycast(bottom + Vector3.yAxis * Config.StepProbeLowerHeight,
			probe, params)
	end
	if not low then return nil end
	local opposition = -low.Normal:Dot(direction)
	local faceDistance = (center - low.Position):Dot(low.Normal)
	if opposition < Config.StepTraction.MinFaceOpposition
		or faceDistance > radius + Config.StepTraction.ContactPadding then return nil end
	local high = bottom + Vector3.yAxis * (height + radius * 2 + 0.1)
	local top = Workspace:Raycast(low.Position + direction * 0.05 + Vector3.yAxis * (height + radius * 2 + 0.1),
		-Vector3.yAxis * (height + radius * 2 + 0.2), params)
	if not top or top.Normal.Y < Config.GroundMinNormalY then return nil end
	local rise = top.Position.Y - bottom.Y
	if rise <= Config.StepProbeLowerHeight or rise > height + Config.StepTraction.HeightTolerance then return nil end
	-- Keep lift based on tire/face contact, independent of approach angle.
	-- Multiplying by opposition starved glancing approaches of vertical support.
	local gap = math.max(Config.StepProbeLowerHeight, (center - top.Position):Dot(low.Normal))
	local above = math.max(radius * Config.StepTraction.MinForwardTangentRatio, center.Y - top.Position.Y)
	if Workspace:Raycast(high, probe, params) then return nil end
	return (direction * above + Vector3.yAxis * gap).Unit
end

function ScooterTerrain.Create(wheels: { Wheel }): Controller
	local forces: { VectorForce } = {}
	for _, wheel in wheels do
		local force = Instance.new("VectorForce")
		force.Name = "WheelStepTraction"
		force.Attachment0 = wheel.point
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		force.Force = Vector3.zero
		force.Parent = wheel.part
		table.insert(forces, force)
	end
	local destroyed = false
	local lastSupportedContact = -math.huge
	local approachSpeeds: { number } = {}
	local previousDirection: Vector3? = nil
	return {
		Update = function(direction, mass, params, grounded, speedLimit)
			if destroyed then return end
			local now = os.clock()
			if not direction then lastSupportedContact = -math.huge end
			if not direction or (previousDirection and previousDirection:Dot(direction) < 0.5) then
				table.clear(approachSpeeds)
			end
			previousDirection = direction
			-- Starting a climb requires ground contact. A verified ledge may briefly
			-- lift both tires clear of the lower road before either reaches its top.
			local eligible = grounded ~= false
				or now - lastSupportedContact <= Config.StepTraction.AirContactGraceSeconds
			for index, wheel in wheels do
				local tangent = if direction and eligible then ScooterTerrain.Probe(wheel, direction, params) else nil
				if tangent and grounded ~= false then lastSupportedContact = now end
				if tangent and direction then
					local velocity = wheel.part.AssemblyLinearVelocity
					local entrySpeed = approachSpeeds[index] or math.max(0, velocity:Dot(direction))
					approachSpeeds[index] = entrySpeed
					local target = math.min(speedLimit or Config.Models[Config.DefaultModel].maxSpeed * Config.StudsPerKmH,
						math.max(Config.StepTraction.MinimumForwardSpeed, entrySpeed * Config.StepTraction.SpeedRetention))
					forces[index].Force = Physics.ComputeStepForce(tangent, velocity, mass, Workspace.Gravity, target)
				else
					approachSpeeds[index] = nil
					forces[index].Force = Vector3.zero
				end
			end
		end,
		Destroy = function()
			if destroyed then return end
			destroyed = true
			for _, force in forces do force:Destroy() end
		end,
	}
end

return ScooterTerrain
