local start = testCount
local Terrain = loadModule("ServerScriptService/Scooter/ScooterTerrain")
local Impact = loadModule("ServerScriptService/Scooter/ScooterImpact")
local savedRaycast = services.Workspace.Raycast
local model = make(nil, "Model", "TerrainFixture")
local wheel = make(model, "MeshPart", "FrontWheel")
wheel.CFrame = Frame.new(0, 1, 0)
wheel.AssemblyLinearVelocity = Vector.zero
local point = make(wheel, "Attachment", "WheelCenter")
local contact = { part = wheel, point = point, radius = 1.03 }
local forward = Vector.new(0, 0, -1)
local face = { Position = Vector.new(0, 0.14, -0.94), Normal = Vector.zAxis }
local function top(height, normal)
	return { Position = Vector.new(0, height, -0.99), Normal = normal or Vector.yAxis }
end
local function probe(faceHit, topHit, overhead)
	local calls = 0
	local lowOrigin, lowLength
	services.Workspace.Raycast = function(_, origin, direction)
		calls += 1
		local index = (calls - 1) % 3 + 1
		if index == 1 then lowOrigin = origin; lowLength = direction.Magnitude; return faceHit end
		if index == 2 then return topHit end
		return overhead
	end
	return Terrain.Probe(contact, forward, {}), lowOrigin, lowLength
end
local tangent, low = probe(face, top(0.65))
check(tangent ~= nil and tangent.Y > 0 and tangent:Dot(forward) > 0,
	"A contacted 0.65 curb supplies a forward/up climbing tangent from rest")
check(low.Y > 0.1, "Face ray clears solver contact penetration instead of starting inside the road")
check(probe(nil, nil) == nil, "No obstacle never supplies artificial lift")
check(probe({ Position = face.Position, Normal = Vector.yAxis }, top(0.65)) == nil,
	"Road surfaces are not treated as vertical curb faces")
check(probe(face, top(3)) == nil, "A wall exceeding the absolute rise limit is not climbable")
check(probe(face, top(2.4)) ~= nil, "Arcade support accepts a verified tall ledge below 2.5 studs")
wheel.CFrame = Frame.new(0, 0.96, 0)
check(probe(face, top(2.5)) ~= nil, "Solver contact penetration does not reject a ledge at the configured limit")
check(probe(face, top(2.6)) == nil, "Contact tolerance does not remove the maximum height bound")
wheel.CFrame = Frame.new(0, 1, 0)
check(probe(face, top(1.05)) ~= nil, "A one-stud sidewalk still climbs when contact compression puts its corner above the tire center")
local angledFace = { Position = Vector.new(0, 0.14, -1.33), Normal = Vector.new(math.sqrt(0.5), 0, math.sqrt(0.5)) }
local angledTangent, _, rayLength = probe(angledFace, top(0.65))
check(angledTangent ~= nil and rayLength >= 1.33,
	"A 45-degree approach reaches a face already touching the round tire")
local shallowFace = { Position = Vector.new(0, 0.14, -3.76), Normal = Vector.new(math.sqrt(1 - 0.25^2), 0, 0.25) }
check(probe(shallowFace, top(1.05)) ~= nil,
	"A 75-degree glancing approach still finds contacted curb support")
local parallelFace = { Position = face.Position, Normal = Vector.xAxis }
check(probe(parallelFace, top(1)) == nil, "Travel parallel to a face never triggers climbing")
for _, side in { -1, 1 } do
	local normal = Vector.new(side * math.cos(math.rad(1)), 0, math.sin(math.rad(1)))
	local facePoint = point.WorldPosition - normal * 0.94
	local longestRay, topInset = 0, 0
	services.Workspace.Raycast = function(_, origin, ray)
		if ray.Y < -0.1 then
			topInset = -(origin - facePoint):Dot(normal)
			if topInset > 0 then return { Position = Vector.new(origin.X, 1.05, origin.Z), Normal = Vector.yAxis } end
			return nil
		end
		longestRay = math.max(longestRay, ray.Magnitude)
		local denominator = ray:Dot(normal)
		if denominator >= 0 or origin.Y > 1.05 then return nil end
		local fraction = (facePoint - origin):Dot(normal) / denominator
		if fraction >= 0 and fraction <= 1 then return { Position = origin + ray * fraction, Normal = normal } end
		return nil
	end
	local shallow = Terrain.Probe(contact, forward, {})
	check(shallow ~= nil and Vector.new(shallow.X, 0, shallow.Z).Unit:Dot(-normal) > 0.4,
		"A real one-degree plane intersection gets inward assistance on either side")
	check(longestRay < 2 and topInset > 0.04,
		"Shallow detection stays local and probes the top inward from its face")
	wheel.AssemblyLinearVelocity = forward * 120
	local fastEntry = Terrain.Create({ contact })
	fastEntry.Update(forward, 60, {}, true)
	check(wheel.WheelStepTraction.Force:Dot(-normal) > 0,
		"Fast motion along either edge still gets inward traction instead of exhausting the forward-speed target")
	fastEntry.Destroy()
	wheel.AssemblyLinearVelocity = Vector.zero
end
do
	services.Workspace.Raycast = function(_, origin, ray)
		if ray.Y < -0.1 then
			return { Position = Vector.new(origin.X, 1.05, origin.Z), Normal = Vector.yAxis }
		end
		if ray.Z >= 0 or origin.Y > 1.05 then return nil end
		local fraction = (-0.94 - origin.Z) / ray.Z
		local x = origin.X + ray.X * fraction
		if fraction >= 0 and fraction <= 1 and x >= 0.25 and x <= 1 then
			return { Position = origin + ray * fraction, Normal = Vector.zAxis }
		end
		return nil
	end
	check(Terrain.Probe(contact, forward, {}) ~= nil,
		"A diagonal detects a narrow obstacle corner when straight and side rays miss its finite face")
end
check(probe({ Position = Vector.new(0, 0.14, -2), Normal = Vector.zAxis }, top(0.65)) == nil,
	"Extended approach rays do not supply lift before the tire contacts the curb")
check(probe(face, top(-0.1)) == nil, "A depression never supplies climbing force")
check(probe(face, top(0.65, Vector.zAxis)) == nil, "A vertical top hit cannot be a supported step")
check(probe(face, top(0.65), face) == nil, "Blocked overhead rejects climbing")
check(probe(face, top(0.1)) ~= nil, "Support continues through the final small rise instead of cutting out early")
do
	for _, vertical in { 0.09, 0.5, 0.9 } do
		check(probe({ Position = face.Position, Normal = Vector.new(0, vertical, math.sqrt(1 - vertical^2)) }, top(0.65)) ~= nil,
			"Rounded and sloping uphill contacts are climbable from rest")
	end
	services.Workspace.Raycast = function(_, origin, ray)
		if ray.Y < 0 then
			return top(0.65, if origin.Z < -1.3 then Vector.yAxis else Vector.zAxis)
		end
		if origin.Y < 0.3 then return face end
		return nil
	end
	check(Terrain.Probe(contact, forward, {}) ~= nil,
		"A rounded obstacle finds its walkable arc beyond the steep near edge")
	local ahead = { Position = Vector.new(0, 0.14, -3), Normal = Vector.zAxis }
	wheel.AssemblyLinearVelocity = forward * 20
	check(probe(ahead, top(1)) ~= nil, "Rolling approach starts lifting before sharp tire collision")
	check(probe(ahead, top(3)) == nil, "Earlier detection retains the wall height limit")
	wheel.AssemblyLinearVelocity = Vector.zero
	check(probe(ahead, top(1)) == nil, "Stationary assistance remains local to the tire")
end
do
	local chassis = make(model, "Part", "ReboundChassis")
	chassis.AssemblyRootPart = chassis
	wheel.AssemblyRootPart = wheel
	make(chassis, "Attachment", "ScooterDriveAttachment")
	local rebound = Terrain.Create({ contact }, chassis, { chassis, wheel, chassis })
	probe(face, top(1))
	rebound.Update(forward, 60, {}, true)
	chassis.AssemblyLinearVelocity = Vector.new(7, 12, -8)
	wheel.AssemblyLinearVelocity = Vector.new(8, 14, -9)
	rebound.Stabilize()
	near(chassis.AssemblyLinearVelocity.Y, Config.StepTraction.ChassisClimbSpeed,
		"Post-solver curb rebound respects the vertical climb limit")
	near(wheel.AssemblyLinearVelocity.Y - chassis.AssemblyLinearVelocity.Y, 2,
		"Common correction preserves relative suspension velocity")
	near(chassis.AssemblyLinearVelocity.X, 7, "Rebound correction preserves sideways momentum")
	near(chassis.AssemblyLinearVelocity.Z, -8, "Rebound correction preserves forward momentum")
	rebound.Update(nil, 60, {}, false)
	chassis.AssemblyLinearVelocity = Vector.new(7, 20, -8)
	rebound.Stabilize()
	near(chassis.AssemblyLinearVelocity.Y, 20, "Unassisted flight is never velocity-clamped")
	rebound.Destroy()
	check(chassis:FindFirstChild("StepRiseDamper") == nil, "Terrain cleanup removes the chassis rebound actuator")
	wheel.AssemblyLinearVelocity = Vector.zero
end
do
 local chassis = make(model, "Part", "MomentumChassis")
 chassis.AssemblyRootPart, wheel.AssemblyRootPart = chassis, wheel
 make(chassis, "Attachment", "ScooterDriveAttachment")
 local controller = Terrain.Create({ contact }, chassis, { chassis, wheel })
 chassis.AssemblyLinearVelocity, wheel.AssemblyLinearVelocity = forward * 50, forward * 45
 probe(face, top(1))
 controller.Update(forward, 60, {}, true, 88)
 chassis.AssemblyLinearVelocity, wheel.AssemblyLinearVelocity = forward * 20 + Vector.xAxis * 7, forward * 15
 controller.Stabilize()
 near(chassis.AssemblyLinearVelocity:Dot(forward), 50, "Verified climbing restores incoming chassis momentum instead of a slowed tire speed")
 near(chassis.AssemblyLinearVelocity.X, 7, "Momentum recovery preserves lateral steering velocity")
 near((chassis.AssemblyLinearVelocity-wheel.AssemblyLinearVelocity):Dot(forward), 5, "Momentum correction preserves relative suspension movement")
 services.Workspace.Raycast = function() return nil end
 testClock += Config.StepTraction.SettleSeconds + .01
 chassis.AssemblyLinearVelocity = forward * 10
 controller.Update(forward, 60, {}, true, 88, Vector.yAxis)
 controller.Stabilize()
 near(chassis.AssemblyLinearVelocity:Dot(forward), 10, "Cached momentum assistance expires instead of accelerating against a subsequent wall")
 controller.Update(nil, 60, {}, false)
 chassis.AssemblyLinearVelocity = forward * 10 + Vector.yAxis * 20
 controller.Stabilize()
 near(chassis.AssemblyLinearVelocity.Y, 20, "Unsupported travel keeps natural gravity and jump motion")
 services.Workspace.Raycast = function() return nil end
 controller.Update(nil, 60, {}, true, 88, Vector.yAxis)
 controller.Stabilize()
 near(chassis.AssemblyLinearVelocity.Y, Config.StepTraction.SurfaceRiseTolerance, "Supported flat-road spring rebound stays within the road-motion allowance")
 near(chassis.AssemblyLinearVelocity:Dot(forward), 10, "Ordinary road damping never supplies extra propulsion")
 controller.Destroy()
 wheel.AssemblyLinearVelocity = Vector.zero
end
do
	probe(face, top(1.05))
	local _, _, verified = Terrain.Probe(contact, forward, {})
	check(verified ~= nil, "Verified face geometry is available for the inside-corner transition")
	wheel.CFrame = Frame.new(0, 1.25, -1.1)
	services.Workspace.Raycast = function(_, origin, ray)
		if ray.Y < 0 and origin.Y + ray.Y <= 1.05 then return top(1.05) end
		return nil
	end
	check(Terrain.Probe(contact, forward, {}, verified) ~= nil,
		"Contact remains verified when low face rays start inside the step during partial overlap")
	wheel.CFrame = Frame.new(0, 1.25, 0.36)
	check(Terrain.Probe(contact, forward, {}, verified) ~= nil,
		"A brief spring rebound keeps already-verified nearby contact instead of restarting the climb")
	wheel.CFrame = Frame.new(0, 1.25, -1.1)
	local shallowNormal = Vector.new(math.cos(math.rad(1)), 0, math.sin(math.rad(1)))
	local shallowContact = { position = point.WorldPosition - shallowNormal * 0.94, normal = shallowNormal }
	check(Terrain.Probe(contact, Vector.new(math.sin(math.rad(2)), 0, -math.cos(math.rad(2))), {}, shallowContact) ~= nil,
		"A tiny physical yaw perturbation does not abandon an already-verified one-degree climb")
	check(Terrain.Probe(contact, -forward, {}, verified) == nil,
		"Remembered contact cannot pull a retreating tire into the ledge")
	wheel.CFrame = Frame.new(0, 1.25, -2.5)
	check(Terrain.Probe(contact, forward, {}, verified) == nil,
		"Remembered face support ends once the tire has cleared its local contact range")
	wheel.CFrame = Frame.new(0, 1.25, -1.1)
	services.Workspace.Raycast = function() return nil end
	check(Terrain.Probe(contact, forward, {}, verified) == nil,
		"Remembered contact never substitutes for a still-existing walkable top")
	wheel.CFrame = Frame.new(0, 1, 0)
	probe(face, top(1.05))
	local overlap = Terrain.Create({ contact })
	overlap.Update(forward, 60, {}, true)
	wheel.CFrame = Frame.new(0, 2.25, -1.1)
	services.Workspace.Raycast = function(_, origin, ray)
		if ray.Y < 0 and origin.Y + ray.Y <= 1.05 then return top(1.05) end
		return nil
	end
	overlap.Update(forward, 60, {}, true)
	check(wheel.WheelStepTraction.Force.Y == 0 and wheel.WheelStepTraction.Force:Dot(forward) > 0,
		"A tire briefly above the platform retains inward entry without continuing to lift it")
	wheel.CFrame = Frame.new(0, 3.3, -1.1)
	check(Terrain.Probe(contact, forward, {}, verified) == nil,
		"Verified corner history cannot support an arbitrarily high airborne tire")
	wheel.CFrame = Frame.new(0, 2.25, -1.1)
	overlap.Update(nil, 60, {}, true)
	overlap.Update(forward, 60, {}, true)
	near(wheel.WheelStepTraction.Force.Magnitude, 0, "Input release also clears remembered inside-corner contact")
	overlap.Destroy()
	wheel.CFrame = Frame.new(0, 1, 0)
end
contact.radius = 0.714275
wheel.CFrame = Frame.new(0, contact.radius - Config.WheelColliderClearance, 0)
local smallFace = { Position = Vector.new(0, 0.14, -0.6), Normal = Vector.zAxis }
check(probe(smallFace, top(1.03)) ~= nil,
	"The 0.20 tire can restart against a one-stud sidewalk with contact compression")
check(probe(smallFace, top(2.47)) == nil,
	"A small tire still rejects steps exceeding its radius-based allowance")
contact.radius = 1.03
wheel.CFrame = Frame.new(0, 1.55, 0)
local fallbackCalls = 0
services.Workspace.Raycast = function()
	fallbackCalls += 1
	if fallbackCalls == 2 then return face end
	if fallbackCalls == 3 then return top(0.65) end
	return nil
end
check(Terrain.Probe(contact, forward, {}) ~= nil and fallbackCalls == 4,
	"A lower face ray retains contact after the high ray clears the curb")
wheel.CFrame = Frame.new(0, 1, 0)
local force = Physics.ComputeStepForce(tangent, Vector.zero, 60, 196.2)
check(force.Y > 0 and force:Dot(forward) > 0, "Stationary throttle can climb without a launch impulse")
near(Physics.ComputeStepForce(tangent, Vector.zero, 120, 196.2).Magnitude, force.Magnitude * 2,
	"Climbing support scales with the actual carried mass")
check(Physics.ComputeStepForce(tangent, tangent * 100, 60, 196.2).Magnitude < force.Magnitude,
	"High climbing speed reduces added support instead of repeated upward kicks")
local fastRise = Physics.ComputeStepForce(tangent,
	Vector.yAxis * (Config.StepTraction.GentleStep.ClimbSpeed + Config.StepTraction.GentleStep.LiftFadeSpeed), 60, 196.2, nil, 1)
near(fastRise.Y, 0, "A fast-rising tire receives no added vertical lift through its spring")
check(fastRise:Dot(forward) > 0, "Vertical lift taper preserves forward curb traction")
local tallRise = Physics.ComputeStepForce(tangent, Vector.yAxis * 6.5, 60, 196.2, nil, 2.5)
check(tallRise.Y > 0, "Tall ledges retain the existing stronger arcade support")
near(Physics.ComputeStepForce(tangent, Vector.zero, 0, 196.2).Magnitude, 0, "Invalid support mass is inert")
near(Physics.ComputeStepForce(tangent, Vector.zero, 60, 0).Magnitude, 0, "No gravity does not produce fake support")
local backTangent = Vector.new(tangent.X, tangent.Y, -tangent.Z)
near(Physics.ComputeStepForce(backTangent, Vector.zero, 60, 196.2).Y, force.Y,
	"Reverse climbing gets the same bounded vertical support")
local controller = Terrain.Create({ contact })
probe(face, top(0.65))
controller.Update(forward, 60, {})
local actuator = wheel.WheelStepTraction
check(actuator.Attachment0.Parent == wheel and actuator.ApplyAtCenterOfMass
	and actuator.Force.Magnitude > 0, "Support acts on the tire assembly, leaving the spring free to compress")
testClock += Config.StepTraction.AirContactGraceSeconds * 0.5
controller.Update(forward, 60, {}, false)
check(actuator.Force.Magnitude > 0, "A climb retains verified contact support while both tires briefly leave the lower road")
testClock += Config.StepTraction.AirContactGraceSeconds + 0.01
controller.Update(forward, 60, {}, false)
near(actuator.Force.Magnitude, 0, "Airborne contact support expires instead of enabling sustained wall climbing")
controller.Update(forward, 60, {}, true)
controller.Update(nil, 60, {})
near(actuator.Force.Magnitude, 0, "Releasing drive or losing eligibility clears wheel support immediately")
controller.Update(forward, 60, {}, false)
near(actuator.Force.Magnitude, 0, "Releasing input clears grace; airborne drive cannot initiate a new climb")
controller.Destroy()
controller.Destroy()
do
local secondWheel = make(model, "MeshPart", "BackWheel")
secondWheel.CFrame, secondWheel.AssemblyLinearVelocity = wheel.CFrame, Vector.zero
local secondPoint = make(secondWheel, "Attachment", "WheelCenter")
probe(face, top(0.65))
local paired = Terrain.Create({ contact, { part = secondWheel, point = secondPoint, radius = contact.radius } })
local entry = paired.Update(forward, 60, {}, true)
local combined = wheel.WheelStepTraction.Force + secondWheel.WheelStepTraction.Force
near(combined.Y, (196.2 + Config.StepTraction.GentleStep.ClimbSpeed * Config.StepTraction.GentleStep.Response) * 60,
	"Simultaneous tire contact carries one complete gravity load and one climb response instead of doubling lift")
check(entry ~= nil and entry:Dot(forward) > 0, "The drive controller receives the supported entry direction for grip")
paired.Destroy()
end
wheel.AssemblyLinearVelocity = Vector.yAxis * 6.5
probe(face, top(2.5))
local tallController = Terrain.Create({ contact })
tallController.Update(forward, 60, {}, true)
check(wheel.WheelStepTraction.Force.Y > 0, "Tall contact selects the stronger lift profile")
wheel.CFrame = Frame.new(0, 2.4, 0)
probe({ Position = Vector.new(0, 1.54, -0.94), Normal = Vector.zAxis }, top(2.5))
tallController.Update(forward, 60, {}, true)
check(wheel.WheelStepTraction.Force.Y > 0, "A tall climb retains its profile when remaining rise becomes small")
tallController.Update(nil, 60, {})
tallController.Update(forward, 60, {}, true)
near(wheel.WheelStepTraction.Force.Y, 0, "Input release clears remembered height before a new small climb")
tallController.Destroy()
wheel.CFrame = Frame.new(0, 1, 0)
wheel.AssemblyLinearVelocity = Vector.zero
controller.Update(forward, 60, {})
check(wheel:FindFirstChild("WheelStepTraction") == nil, "Cleanup disposes actuators and repeated calls stay inert")

check(Physics.IsCollisionImpact(forward * 60, forward * 5, Vector.zAxis),
	"A fast frontal wall impact with sudden speed loss qualifies")
check(not Physics.IsCollisionImpact(forward * 20, Vector.zero, Vector.zAxis),
	"Low-speed nudges do not eject a rider")
check(not Physics.IsCollisionImpact(forward * 60, forward * 58, Vector.zAxis),
	"Ordinary braking is not an impact")
check(not Physics.IsCollisionImpact(forward * 60, forward * 5, Vector.xAxis),
	"Glancing contact without approach speed is not a frontal impact")
check(not Physics.IsCollisionImpact(Vector.new(0, -60, 0), Vector.zero, Vector.yAxis),
	"Ground landing is not mistaken for a wall impact")
local tracker = Impact.New()
services.Workspace.Raycast = function() return face end
check(not Impact.Update(tracker, forward * 60, point.WorldPosition, 1.03, {}, true, 1, 1 / 60),
	"Wall proximity alone does not crash before physical speed loss")
check(Impact.Update(tracker, forward * 5, point.WorldPosition, 1.03, {}, true, 1.02, 1 / 60),
	"A recent probed contact confirms actual solver impact")
tracker = Impact.New()
Impact.Update(tracker, forward * 60, point.WorldPosition, 1.03, {}, true, 1, 1 / 60)
check(not Impact.Update(tracker, forward * 5, point.WorldPosition, 1.03, {}, true, 2, 1 / 60),
	"Expired wall memory cannot turn unrelated deceleration into a crash")
tracker = Impact.New()
Impact.Update(tracker, forward * 60, point.WorldPosition, 1.03, {}, true, 1, 1 / 60)
check(not Impact.Update(tracker, Vector.zero, point.WorldPosition, 1.03, {}, false, 1.02, 1 / 60)
	and tracker.normal == nil, "Unmounted or fallen scooters clear crash eligibility")
model:Destroy()
services.Workspace.Raycast = savedRaycast
print(string.format("PASS: %d curb traction and collision assertions (%d total)", testCount - start, testCount))
