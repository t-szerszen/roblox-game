--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Physics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)

export type Wheel = { part: BasePart, point: Attachment, radius: number }
export type Contact = { position: Vector3, normal: Vector3, instance: Instance? }
export type Controller = {
	Update: (direction: Vector3?, mass: number, params: RaycastParams, grounded: boolean?, speedLimit: number?, groundUp: Vector3?) -> Vector3?,
	Stabilize: () -> (),
	Destroy: () -> (),
}
local ScooterTerrain = {}

function ScooterTerrain.Probe(wheel: Wheel, direction: Vector3, params: RaycastParams, previous: Contact?): (Vector3?, number?, Contact?)
	local radius = math.max(wheel.radius * 0.5, wheel.radius - Config.WheelColliderClearance)
	local center = wheel.point.WorldPosition
	local bottom = center - Vector3.yAxis * radius
	local height = math.min(Config.MaxStepHeight, radius * Config.StepTraction.MaxRadiusRatio)
	-- Short side rays find tire contact at shallow approaches without looking
	-- tens of studs ahead. Only faces the rider is driving into qualify.
	local reach = (radius + Config.StepTraction.ContactPadding) * math.sqrt(2)
	local approach = math.clamp(wheel.part.AssemblyLinearVelocity:Dot(direction) * Config.StepTraction.ApproachSeconds,
		0, Config.StepTraction.MaxApproachDistance)
	local sideways = direction:Cross(Vector3.yAxis)
	local low: Contact? = nil
	local probe = Vector3.zero
	for index = 1, 5 do
		local probeDirection = if index == 1 then direction
			elseif index <= 3 then sideways * (if index == 2 then 1 else -1)
			else (direction + sideways * (if index == 4 then 1 else -1)) / math.sqrt(2)
		local ray = probeDirection * (reach + (if index == 1 then approach else 0))
		local hit = Workspace:Raycast(bottom + Vector3.yAxis * Config.StepProbeHeight, ray, params)
		if not hit then
			hit = Workspace:Raycast(bottom + Vector3.yAxis * Config.StepProbeLowerHeight, ray, params)
		end
		if hit then
			local flatNormal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
			local distance = if flatNormal.Magnitude > 0.01 then (center - hit.Position):Dot(flatNormal.Unit) else math.huge
			if -hit.Normal:Dot(direction) >= Config.StepTraction.MinFaceOpposition
				and hit.Normal.Y < Config.StepTraction.RampMaxNormalY
				and hit.Normal.Y > -Config.StepTraction.RampMinNormalY
				and distance >= -Config.StepTraction.HeightTolerance
				and distance <= radius + Config.StepTraction.ContactPadding
					+ approach * math.max(0, -flatNormal.Unit:Dot(direction)) then
				low = { position = hit.Position, normal = flatNormal.Unit, instance = hit.Instance }
				probe = ray
				break
			end
		end
	end
	local retained = false
	if not low and previous and (not previous.instance or previous.instance.Parent) then
		local distance = (center - previous.position):Dot(previous.normal)
		if distance >= -radius - Config.StepTraction.ContactPadding
			and distance <= radius + Config.StepTraction.RetainedContactPadding
			and -previous.normal:Dot(direction) >= -Config.StepTraction.ContactTurnTolerance then
			-- Face rays start inside the ledge once the tire center crosses it. Keep
			-- that verified face locally, but recheck its actual top every frame.
			low, retained = previous, true
			probe = -previous.normal * reach
		end
	end
	if not low then return nil, nil, nil end
	local high = bottom + Vector3.yAxis * (height + radius * 2 + 0.1)
	local facePoint = if retained then center - low.normal * (center - low.position):Dot(low.normal) else low.position
	if retained then facePoint = Vector3.new(facePoint.X, bottom.Y + Config.StepProbeLowerHeight, facePoint.Z) end
	local depth = height + radius * 2 + 0.2
		+ (if retained then radius + Config.StepTraction.ContactPadding else 0)
	local top = Workspace:Raycast(facePoint - low.normal * 0.05 + Vector3.yAxis * (height + radius * 2 + 0.1),
		-Vector3.yAxis * depth, params)
	if not top or top.Normal.Y < Config.GroundMinNormalY then
		-- The near edge of a rounded hump can be too steep to support a tire.
		-- Find its actual walkable arc, rather than requiring a flat curb cap.
		for _, inset in { radius * 0.5, radius, radius * 2 } do
			local arc = Workspace:Raycast(facePoint - low.normal * inset
				+ Vector3.yAxis * (height + radius * 2 + 0.1), -Vector3.yAxis * depth, params)
			if arc and arc.Normal.Y >= Config.GroundMinNormalY
				and (not low.instance or arc.Instance == low.instance) then top = arc; break end
		end
	end
	if not top or top.Normal.Y < Config.GroundMinNormalY
		or (retained and low.instance and top.Instance ~= low.instance) then return nil, nil, nil end
	local rise = top.Position.Y - bottom.Y
	if rise > height + Config.StepTraction.HeightTolerance
		or (rise <= Config.StepProbeLowerHeight and (not retained or rise < -radius - Config.StepTraction.ContactPadding)) then
		return nil, nil, nil
	end
	-- Keep lift based on tire/face contact, independent of approach angle.
	-- Multiplying by opposition starved glancing approaches of vertical support.
	local gap = math.max(Config.StepProbeLowerHeight, (center - top.Position):Dot(low.normal))
	local above = math.max(radius * Config.StepTraction.MinForwardTangentRatio, center.Y - top.Position.Y)
	if Workspace:Raycast(high, probe, params) then return nil, nil, nil end
	-- A small inward component carries the tire over the corner even when most
	-- rider motion runs along the edge. It ends as soon as the face is cleared.
	local normal = Vector3.new(low.normal.X, 0, low.normal.Z).Unit
	local entry = (direction - normal * Config.StepTraction.FaceEntryBias).Unit
	return (entry * above + Vector3.yAxis * gap).Unit, rise, low
end

function ScooterTerrain.Create(wheels: { Wheel }, root: BasePart?, assemblies: { BasePart }?): Controller
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
	local connectedAssemblies: { BasePart } = assemblies or (if root then { root } else {})
	local stabilizedAssemblies: { [BasePart]: boolean } = {}
	local riseDamper: VectorForce? = nil
	if root then
		local attachment = root:FindFirstChild("ScooterDriveAttachment") :: Attachment
		local damper = Instance.new("VectorForce")
		damper.Name = "StepRiseDamper"
		damper.Attachment0 = attachment
		damper.RelativeTo = Enum.ActuatorRelativeTo.World
		damper.ApplyAtCenterOfMass = true
		damper.Force = Vector3.zero
		damper.Parent = root
		riseDamper = damper
	end
	local destroyed = false
	local lastSupportedContact = -math.huge
	local approachSpeeds: { number } = {}
	local approachRises: { number } = {}
	local tangents: { Vector3 } = {}
	local rises: { number } = {}
	local verifiedContacts: { Contact? } = {}
	local previousDirection: Vector3? = nil
	local lastAssistedAt = -math.huge
	local stabilize = false
	local climbLimit = Config.StepTraction.ChassisClimbSpeed
	local momentumDirection: Vector3? = nil
	local momentumSpeed = 0
	local savedMomentumSpeed = 0
	local momentumContact: Contact? = nil
	return {
		Update = function(direction, mass, params, grounded, speedLimit, groundUp)
			if destroyed then return nil end
			stabilize = false
			momentumDirection, momentumSpeed = nil, 0
			climbLimit = Config.StepTraction.ChassisClimbSpeed
			local now = os.clock()
			if not direction then lastSupportedContact = -math.huge end
			if not direction or (previousDirection and previousDirection:Dot(direction) < 0.5) then
				savedMomentumSpeed, momentumContact = 0, nil
				table.clear(approachSpeeds)
				table.clear(approachRises)
				table.clear(verifiedContacts)
			end
			previousDirection = direction
			-- Starting a climb requires ground contact. A verified ledge may briefly
			-- lift both tires clear of the lower road before either reaches its top.
			local eligible = grounded ~= false
				or now - lastSupportedContact <= Config.StepTraction.AirContactGraceSeconds
			table.clear(tangents)
			table.clear(rises)
			local contacts = 0
			local entrySum = Vector3.zero
			for index, wheel in wheels do
				local tangent: Vector3? = nil
				local rise: number? = nil
				local contact: Contact? = nil
				if direction and eligible then
					tangent, rise, contact = ScooterTerrain.Probe(wheel, direction, params, verifiedContacts[index])
				end
				verifiedContacts[index] = contact
				if tangent and grounded ~= false then lastSupportedContact = now end
				if tangent then
					tangents[index] = tangent
					if rise then rises[index] = rise end
					contacts += 1
					entrySum += Vector3.new(tangent.X, 0, tangent.Z).Unit
				end
			end
			for index, wheel in wheels do
				local tangent, rise = tangents[index], rises[index]
				if tangent and direction then
					local velocity = wheel.part.AssemblyLinearVelocity
					local entryVelocity = if root then root.AssemblyLinearVelocity else velocity
					local entrySpeed = approachSpeeds[index] or math.max(0, entryVelocity:Dot(direction))
					approachSpeeds[index] = entrySpeed
					momentumSpeed = math.max(momentumSpeed, math.min(speedLimit or math.huge, entrySpeed * Config.StepTraction.SpeedRetention))
					-- Keep the initial height through the whole climb. Reclassifying a tall
					-- ledge near its top can reduce support while both tires are airborne.
					if rise then approachRises[index] = approachRises[index] or rise end
					if (approachRises[index] or 0) > Config.StepTraction.GentleStep.MaxRise then
						climbLimit = Config.StepTraction.ClimbSpeed
					end
					local target = math.min(speedLimit or Config.Models[Config.DefaultModel].maxSpeed * Config.StudsPerKmH,
						math.max(Config.StepTraction.MinimumForwardSpeed, entrySpeed * Config.StepTraction.SpeedRetention))
					-- Both tires share the carried load; otherwise simultaneous contact
					-- doubles gravity support and launches the chassis off a small curb.
					-- Paired contact must carry all gravity when both tires leave the lower
					-- road; the single-tire profile still leaves load on the other tire.
					local fraction = if contacts > 1 then Config.StepTraction.PairedSupportMassFraction else nil
					forces[index].Force = Physics.ComputeStepForce(tangent, velocity, mass / contacts,
						Workspace.Gravity, target, approachRises[index], fraction)
					local contact = verifiedContacts[index]
					if contact then
						momentumContact = contact
						local inward = -Vector3.new(contact.normal.X, 0, contact.normal.Z).Unit
						local settings = Config.StepTraction
						local fade = 1 - math.clamp(inward:Dot(direction) / settings.EntryNormalFadeOpposition, 0, 1)
						local acceleration = math.clamp((settings.EntryNormalSpeed - velocity:Dot(inward))
							* settings.EntryNormalResponse, 0, settings.EntryNormalAcceleration)
						-- Momentum along the edge can exceed the forward target while the
						-- tire still needs inward motion, especially during the brief lift.
						forces[index].Force += inward * acceleration * fade * (mass / contacts)
					end
					if rise and rise <= Config.StepProbeLowerHeight then
						local force = forces[index].Force
						forces[index].Force = Vector3.new(force.X, 0, force.Z)
					end
				else
					approachSpeeds[index] = nil
					approachRises[index] = nil
					forces[index].Force = Vector3.zero
				end
			end
			if contacts > 0 then
				lastAssistedAt = now
				savedMomentumSpeed = math.max(savedMomentumSpeed, momentumSpeed)
			end
			if direction and eligible and momentumContact
				and (contacts > 0 or now - lastAssistedAt <= Config.StepTraction.SettleSeconds)
				and (not momentumContact.instance or momentumContact.instance.Parent) then
				local last = momentumContact
				local cleared = true
				local nearest = math.huge
				local settleDistance = savedMomentumSpeed * Config.StepTraction.SettleSeconds
				for _, wheel in wheels do
					local distance = (wheel.point.WorldPosition - last.position):Dot(last.normal)
					nearest = math.min(nearest, math.abs(distance))
					if distance >= -wheel.radius - Config.StepTraction.ContactPadding - settleDistance then cleared = false end
				end
				if not cleared and nearest <= Config.StepTraction.MaxApproachDistance + 2 + settleDistance
					and -last.normal:Dot(direction) >= Config.StepTraction.MinFaceOpposition then
					momentumDirection, momentumSpeed = direction, savedMomentumSpeed
				else savedMomentumSpeed, momentumContact = 0, nil end
			else savedMomentumSpeed, momentumContact = 0, nil end
			if riseDamper and root then
				-- Absorb spring/contact rebound on verified climbs and supported road,
				-- while allowing the upward velocity needed to follow the surface.
				local settings = Config.StepTraction
				if contacts == 0 and groundUp then
					local planar = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
					local surfaceRise = -planar:Dot(groundUp) / math.max(groundUp.Y, Config.GroundMinNormalY)
					climbLimit = math.max(0, surfaceRise) + settings.SurfaceRiseTolerance
				end
				local excess = math.max(0, root.AssemblyLinearVelocity.Y - climbLimit)
				local settling = false
				if direction and contacts == 0 and now - lastAssistedAt <= settings.SettleSeconds then
					for _, wheel in wheels do
						local hit = Workspace:Raycast(wheel.point.WorldPosition,
							-Vector3.yAxis * (wheel.radius + settings.SettleProbeDistance), params)
						if hit and hit.Normal.Y >= Config.GroundMinNormalY then settling = true; break end
					end
				end
				stabilize = contacts > 0 or settling or groundUp ~= nil
				riseDamper.Force = if stabilize then -Vector3.yAxis * mass
					* math.min(excess * settings.ChassisRiseDamping, settings.ChassisRiseDeceleration) else Vector3.zero
			end
			return if entrySum.Magnitude > 0.01 then entrySum.Unit else nil
		end,
		Stabilize = function()
			if destroyed or not stabilize or not root then return end
			local correction = -Vector3.yAxis * math.max(0, root.AssemblyLinearVelocity.Y - climbLimit)
			if momentumDirection then
				-- Restore only longitudinal momentum lost to a verified climb, never a wall or free flight.
				correction += momentumDirection * math.max(0, momentumSpeed - root.AssemblyLinearVelocity:Dot(momentumDirection))
			end
			if correction.Magnitude <= 0 then return end
			-- Shared correction leaves relative suspension travel and sideways steering intact.
			table.clear(stabilizedAssemblies)
			for _, part in connectedAssemblies do
				local assembly = part.AssemblyRootPart
				if assembly and not stabilizedAssemblies[assembly] then
					stabilizedAssemblies[assembly] = true
					assembly.AssemblyLinearVelocity += correction
				end
			end
		end,
		Destroy = function()
			if destroyed then return end
			destroyed = true
			for _, force in forces do force:Destroy() end
			if riseDamper then riseDamper:Destroy() end
		end,
	}
end

return ScooterTerrain
