--!strict

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Scooter.ScooterConfig)

type Wheel = { part: BasePart, point: Attachment, radius: number }
type Contact = { position: Vector3, normal: Vector3, instance: Instance?, topHeight: number? }
type Probe = (Wheel, Vector3, RaycastParams, Contact?) -> (Vector3?, number?, Contact?)
type Mask = { pairs: { NoCollisionConstraint }, contact: Contact, triggered: { boolean } }
type Arm = { hinge: HingeConstraint, actuator: Enum.ActuatorType, target: number, torque: number,
	speed: number, responsiveness: number, rest: number, compression: number, endIndex: number }

local ArcadeSteps = {}

function ArcadeSteps.AdvanceHeight(current: number, target: number, deltaTime: number, velocity: number?): (number, number)
	local settings = Config.ArcadeSteps
	local rate = velocity or 0
	local remaining = math.clamp(deltaTime, 0, 0.1)
	while remaining > 0 do
		local dt = math.min(remaining, settings.IntegrationStep)
		local acceleration = math.clamp(settings.HeightResponse ^ 2 * (target - current)
			- 2 * settings.HeightResponse * rate, -settings.MaxHeightAcceleration, settings.MaxHeightAcceleration)
		local nextRate = math.clamp(rate + acceleration * dt, -settings.MaxDropSpeed, settings.MaxRiseSpeed)
		current += (rate + nextRate) * 0.5 * dt
		rate, remaining = nextRate, remaining - dt
	end
	return current, rate
end

function ArcadeSteps.CompressionPulse(age: number): number
	local settings = Config.ArcadeSteps
	local phase = if age < settings.SuspensionAttack then math.clamp(age / settings.SuspensionAttack, 0, 1)
		else 1 - math.clamp((age - settings.SuspensionAttack - settings.SuspensionHold) / settings.SuspensionRelease, 0, 1)
	return phase * phase * (3 - 2 * phase)
end

function ArcadeSteps.Create(wheels: { Wheel }, root: BasePart, _assemblies: { BasePart }, probe: Probe)
	local model = root:FindFirstAncestorOfClass("Model") :: Model
	local settings = Config.ArcadeSteps
	local masks: { [BasePart]: Mask } = {}
	local contacts: { Contact? } = {}
	local offsets: { number } = {}
	local arms: { Arm } = {}
	local springs: { [SpringConstraint]: boolean } = {}
	local proxies: { BasePart } = {}
	local heightPoint = Instance.new("Attachment")
	heightPoint.Name, heightPoint.Parent = "ArcadeStepHeightPoint", root
	local heightDrive = Instance.new("LinearVelocity")
	heightDrive.Name = "ArcadeStepHeightDrive"
	heightDrive.Attachment0 = heightPoint
	heightDrive.RelativeTo = Enum.ActuatorRelativeTo.World
	heightDrive.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	heightDrive.LineDirection = Vector3.yAxis
	heightDrive.ForceLimitsEnabled = false
	heightDrive.Enabled = false
	heightDrive.Parent = root
	local active, destroyed = false, false
	local height, targetHeight, startedAt = 0, 0, 0
	local heightVelocity, heightCommand = 0, 0
	local lastAt = os.clock()
	local compression = { 0, 0 }
	local pulseAges = { math.huge, math.huge }
	local supportHeights: { number? } = {}
	local previousDirection: Vector3? = nil
	for _, instance in model:GetDescendants() do
		if instance:IsA("BasePart") and instance:GetAttribute("RuntimeCollisionProxy") == true then
			table.insert(proxies, instance)
		elseif instance:IsA("HingeConstraint") and instance.Name:find("PivotHinge_", 1, true) then
			local rest = instance:GetAttribute("SuspensionRestAngle")
			local neutral = if typeof(rest) == "number" then rest else instance.CurrentAngle
			local first, second = instance.LowerAngle - neutral, instance.UpperAngle - neutral
			-- Calibration gives compression more travel than droop, on either axis sign.
			local travel = if math.abs(first) > math.abs(second) then first else second
			table.insert(arms, { hinge = instance, actuator = instance.ActuatorType,
				target = instance.TargetAngle, torque = instance.ServoMaxTorque, speed = instance.AngularSpeed,
				responsiveness = instance.AngularResponsiveness, rest = neutral, compression = travel,
				endIndex = if instance.Name:find("Front", 1, true) then 1 else 2 })
		elseif instance:IsA("SpringConstraint") then springs[instance] = instance.Enabled end
	end

	local function clear()
		heightDrive.Enabled = false
		heightDrive.LineVelocity = 0
		for part, mask in masks do
			for _, pair in mask.pairs do pair:Destroy() end
			masks[part] = nil
		end
		if active then
			for spring, enabled in springs do if spring.Parent then spring.Enabled = enabled end end
			for _, arm in arms do
				local hinge = arm.hinge
				if hinge.Parent then
					hinge.ActuatorType, hinge.TargetAngle = arm.actuator, arm.target
					hinge.ServoMaxTorque, hinge.AngularSpeed = arm.torque, arm.speed
					hinge.AngularResponsiveness = arm.responsiveness
				end
			end
		end
		active = false
		table.clear(contacts)
		compression[1], compression[2] = 0, 0
		pulseAges[1], pulseAges[2] = math.huge, math.huge
		table.clear(supportHeights)
		if model.Parent then model:SetAttribute("ArcadeStepActive", false) end
	end

	local function maskObstacle(part: BasePart, contact: Contact)
		if masks[part] then masks[part].contact = contact; return end
		local pairs = {}
		for _, proxy in proxies do
			local pair = Instance.new("NoCollisionConstraint")
			pair.Name = "ArcadeStepCollision"
			pair.Part0, pair.Part1 = proxy, part
			pair.Parent = proxy
			table.insert(pairs, pair)
		end
		masks[part] = { pairs = pairs, contact = contact, triggered = { false, false } }
	end
	local function begin(now: number)
		if active then return end
		active, height, targetHeight, startedAt = true, root.Position.Y, root.Position.Y, now
		heightVelocity = math.clamp(root.AssemblyLinearVelocity.Y, -settings.MaxDropSpeed, settings.MaxRiseSpeed)
		heightCommand = heightVelocity
		heightDrive.LineVelocity = heightCommand
		for i, tire in wheels do offsets[i] = tire.point.WorldPosition.Y - root.Position.Y end
		-- Return to loaded sag, so restoring passive springs does not lift the rider.
		for _, arm in arms do
			arm.rest = arm.hinge.CurrentAngle
			local limit = if arm.compression >= 0 then arm.hinge.UpperAngle else arm.hinge.LowerAngle
			arm.compression = limit - arm.rest
		end
		for spring in springs do spring.Enabled = false end
		heightDrive.Enabled = true
		model:SetAttribute("ArcadeStepActive", true)
	end

	return {
		Update = function(direction: Vector3?, mass: number, params: RaycastParams, grounded: boolean?,
			_speedLimit: number?, groundUp: Vector3?): Vector3?
			if destroyed then return nil end
			local now = os.clock()
			local dt = math.clamp(now - lastAt, 0, 0.1)
			lastAt = now
			-- Nil support is the existing server's reset/wheelie/fall/unauthorized path.
			-- Coasting can still cross a ledge without pressing a drive button.
			local planar = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
			if not direction and groundUp and planar.Magnitude > Config.StopSpeed then direction = planar.Unit end
			if (not direction and not groundUp) or model:GetAttribute("WheelieActive") == true
				or model:GetAttribute("Fallen") == true or model:GetAttribute("RiderMounted") ~= true then
				clear(); return nil
			end
			if previousDirection and direction and previousDirection:Dot(direction) < 0 then clear() end
			previousDirection = direction
			-- Descending a small edge also uses the height path. Both walkable surfaces
			-- must be sampled; a cliff or an isolated airborne tire cannot start it.
			if not active and direction and grounded ~= false then
				local hits: { RaycastResult } = {}
				for index, tire in wheels do
					local hit = Workspace:Raycast(tire.point.WorldPosition + Vector3.yAxis * Config.SuspensionProbeLift,
						-Vector3.yAxis * (Config.SuspensionProbeLift + tire.radius + Config.MaxStepHeight + Config.GroundProbeTolerance), params)
					if hit and hit.Normal.Y >= settings.FlatSurfaceNormalY then
						table.insert(hits, hit)
						local previous = supportHeights[index]
						if previous and math.abs(hit.Position.Y - previous) >= settings.MinimumEdgeHeight then pulseAges[index] = 0 end
						supportHeights[index] = hit.Position.Y
					end
				end
				if #hits == #wheels and #hits == 2 then
					local difference = math.abs(hits[1].Position.Y - hits[2].Position.Y)
					if difference >= settings.MinimumEdgeHeight and difference <= Config.MaxStepHeight + Config.StepTraction.HeightTolerance then begin(now) end
				end
			end
			local found = false
			if direction and (grounded ~= false or active) then
				for index, wheel in wheels do
					local _, _, contact = probe(wheel, direction, params, contacts[index])
					contacts[index] = contact
					local part = contact and contact.instance
					if contact and contact.topHeight and part and part:IsA("BasePart") and part.Anchored then
						begin(now)
						maskObstacle(part, contact)
						targetHeight = math.max(targetHeight, contact.topHeight + wheel.radius - offsets[index] + settings.Clearance)
						found = true
					end
				end
			end
			if not active then return nil end
			if now - startedAt > settings.MaxDuration then clear(); return nil end

			local supported, cleared = false, true
			local sampledHeight = -math.huge
			local lowSurface, highSurface = math.huge, -math.huge
			for index, wheel in wheels do
				local center = wheel.point.WorldPosition
				local hit = Workspace:Raycast(center + Vector3.yAxis * Config.MaxStepHeight,
					-Vector3.yAxis * (Config.MaxStepHeight * 2 + wheel.radius + Config.GroundProbeTolerance), params)
				if hit and hit.Normal.Y >= Config.GroundMinNormalY then
					supported = true
					lowSurface, highSurface = math.min(lowSurface, hit.Position.Y), math.max(highSurface, hit.Position.Y)
					sampledHeight = math.max(sampledHeight, hit.Position.Y + wheel.radius - offsets[index] + settings.Clearance)
					local previous = supportHeights[index]
					if previous and math.abs(hit.Position.Y - previous) >= settings.MinimumEdgeHeight
						and pulseAges[index] > settings.SuspensionAttack + settings.SuspensionHold then pulseAges[index] = 0 end
					supportHeights[index] = hit.Position.Y
				end
				pulseAges[index] += dt
				for part, mask in masks do
					if not part.Parent then continue end
					local contact = mask.contact
					local distance = (center - contact.position):Dot(contact.normal)
					if distance > -wheel.radius - Config.StepTraction.ContactPadding then cleared = false end
					local approachSpeed = math.max(0, -planar:Dot(contact.normal))
					if not mask.triggered[index] and distance <= wheel.radius * 2 + approachSpeed * settings.SuspensionLeadSeconds then
						mask.triggered[index] = true
						pulseAges[index] = 0
					end
				end
				local bump = ArcadeSteps.CompressionPulse(pulseAges[index])
				compression[index] += (bump - compression[index]) * (1 - math.exp(-settings.SuspensionResponse * dt))
			end
			if not supported then clear(); return nil end
			if not found and sampledHeight > -math.huge then targetHeight = sampledHeight end
			height, heightVelocity = ArcadeSteps.AdvanceHeight(height, targetHeight, dt, heightVelocity)
			-- Let native simulation move the chassis. PivotTo each server tick
			-- teleports replicated assemblies and breaks their render interpolation.
			local command = math.clamp(heightVelocity + (height - root.Position.Y) * settings.HeightTrackingResponse,
				-settings.MaxDropSpeed, settings.MaxRiseSpeed)
			heightCommand += math.clamp(command - heightCommand, -settings.MaxHeightAcceleration * dt, settings.MaxHeightAcceleration * dt)
			heightDrive.LineVelocity = heightCommand
			for _, arm in arms do
				local hinge = arm.hinge
				hinge.ActuatorType = Enum.ActuatorType.Servo
				hinge.ServoMaxTorque = math.max(Config.SteeringServoTorque, mass * Workspace.Gravity * wheels[arm.endIndex].radius * settings.SuspensionTorqueScale)
				hinge.AngularSpeed, hinge.AngularResponsiveness = settings.SuspensionAngularSpeed, settings.SuspensionResponsiveness
				hinge.TargetAngle = arm.rest + arm.compression * compression[arm.endIndex] * settings.SuspensionCompression
			end
			if cleared and highSurface - lowSurface < settings.MinimumEdgeHeight
				and math.abs(height - targetHeight) < settings.SettleTolerance
				and math.abs(root.Position.Y - targetHeight) < settings.SettleTolerance
				and math.abs(heightCommand) < settings.SettleTolerance
				and compression[1] < 0.03 and compression[2] < 0.03 then clear() end
			return nil
		end,
		Stabilize = function()
			-- The legacy controller needs a post-solver pass; native height motion does not.
		end,
		Destroy = function()
			if destroyed then return end
			clear()
			heightDrive:Destroy()
			heightPoint:Destroy()
			destroyed = true
		end,
	}
end

return ArcadeSteps
