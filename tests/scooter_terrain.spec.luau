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
check(probe({ Position = Vector.new(0, 0.14, -2), Normal = Vector.zAxis }, top(0.65)) == nil,
	"Extended approach rays do not supply lift before the tire contacts the curb")
check(probe(face, top(-0.1)) == nil, "A depression never supplies climbing force")
check(probe(face, top(0.65, Vector.zAxis)) == nil, "A vertical top hit cannot be a supported step")
check(probe(face, top(0.65), face) == nil, "Blocked overhead rejects climbing")
check(probe(face, top(0.1)) ~= nil, "Support continues through the final small rise instead of cutting out early")
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
