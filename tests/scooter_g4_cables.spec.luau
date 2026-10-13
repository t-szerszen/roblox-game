do
local RigCables = loadModule("ServerScriptService/Scooter/ScooterG4Cables")
local VisualCables = loadModule("ReplicatedStorage/Shared/Scooter/ScooterCableVisuals")
local count = 0
local function check(condition, message) count += 1; assert(condition, message) end
local function near(a, b, message) check((a - b).Magnitude < .0001, message) end
local function make(parent, class, name)
	local part = InstanceMock.new(class)
	part.Name, part.Parent = name, parent
	part.LocalTransparencyModifier, part.Transparency = 0, 0
	part.DescendantRemoving = signal()
	return part
end
local model = make(nil, "Model", "CableFixture")
model:SetAttribute("ScooterG4Rig", true)
model.PrimaryPart = make(model, "Part", "Root")
model.PrimaryPart.CFrame = Frame.new(300, 4, 20) * Frame.Angles(0, .4, 0)
local stick = make(model, "Part", "HandleBarStick")
local body = make(model, "Part", "ScooterBody")
local front = make(model, "Part", "VirtualFrontAxle")
for part, assembly in { [stick] = "steering", [body] = "body", [front] = "front" } do
	part.CFrame = model.PrimaryPart.CFrame
	part:SetAttribute("ScooterAssembly", assembly)
end
local visuals = make(model, "Folder", "G4Visuals")
local group = make(visuals, "Model", "Cables")
local members, welds, snapshots = {}, {}, {}
-- The Instance double indexes children by unique name; native G4 repeats names.
group.GetChildren = function() return members end
local function cablePart(name, shape, point, owner)
	local part = make(group, "Part", name)
	part.Shape = shape
	part.CFrame = model.PrimaryPart.CFrame * Frame.new(point)
	part.Size = Vector.one * .05
	table.insert(members, part)
	local weld = make(owner, "WeldConstraint", "G4AssemblyWeld")
	weld.Part0, weld.Part1 = owner, part
	-- Retain every duplicate-named weld in the service double's descendant scan.
	owner._children[tostring(#members)] = weld
	welds[part] = weld
	return part
end
local routes = {}
for _, definition in {
	{ name = "FrontBrakeLine", owner = front, points = { Vector.new(0,3,0), Vector.new(.4,2,-.2), Vector.new(.6,1,-.4), Vector.new(.7,0,-.1) } },
	{ name = "RearBrakeLine", owner = body, points = { Vector.new(-.1,3,0), Vector.new(-.3,2,.1), Vector.new(-.4,1,.5), Vector.new(-.5,0,.8) } },
} do
	local cylinders, joints = {}, {}
	for index, point in definition.points do
		table.insert(joints, cablePart(definition.name .. "J", enumMock.PartType.Ball, point, definition.owner))
		local nextPoint = definition.points[index + 1]
		if nextPoint then
			local axis = (nextPoint - point).Unit
			local part = cablePart(definition.name, enumMock.PartType.Cylinder, (point + nextPoint) * .5, definition.owner)
			part.CFrame = model.PrimaryPart.CFrame * Frame.fromMatrix((point + nextPoint) * .5, axis,
				(Vector.zAxis - axis * Vector.zAxis:Dot(axis)).Unit)
			part.Size = Vector.new((nextPoint - point).Magnitude, .05, .05)
			table.insert(cylinders, part)
		end
	end
	routes[definition.name] = { cylinders = cylinders, joints = joints, points = definition.points }
end
cablePart("SpiralWrap", enumMock.PartType.Ball, Vector.new(.4,2,-.2), stick)
local tie = cablePart("CableTie", "Block", Vector.new(.6,1,-.4), stick)
local grommet = cablePart("CableGrommet", "Block", Vector.new(0,6,0), body)
for _, part in members do snapshots[part] = part.CFrame end
RigCables.Configure(model)
check(welds[tie].Part0 == front and tie:GetAttribute("ScooterAssembly") == "front", "Lower fork clip belongs to the axle")
check(welds[grommet].Part0 == stick and grommet:GetAttribute("ScooterAssembly") == "steering", "Handlebar grommet follows the column")
for _, part in members do near(part.Position, snapshots[part].Position, "Cable rigging preserves authored geometry") end
local revision = model:GetAttribute("G4CableRigRevision")
RigCables.Configure(model)
check(model:GetAttribute("G4CableRigRevision") == revision, "Repeated preparation retains its rest calibration")
for index, part in members do part.Name = "CableSource" .. index end
local destination = make(nil, "Folder", "CableCopies")
local presentation = assert(VisualCables.Create(model, destination))
presentation.Update(true)
for _, part in members do
	if part:GetAttribute("G4CableStartOwner") then
		near(destination.G4CableVisuals[part.Name].Position, snapshots[part].Position, "Rest rendering preserves every cable segment")
		check(part.LocalTransparencyModifier == 1, "Original cable hides while its flexible copy is visible")
	end
end
stick.CFrame *= Frame.Angles(0, .65, 0)
front.CFrame *= Frame.new(0,.3,0) * Frame.Angles(.2,0,0)
presentation.Update(true)
local function copy(part) return destination.G4CableVisuals[part.Name] end
for name, route in routes do
	near(copy(route.joints[1]).Position, stick.CFrame:PointToWorldSpace(route.points[1]), "Cable top remains on the steering assembly")
	local finish = if name == "FrontBrakeLine" then front else body
	near(copy(route.joints[4]).Position, finish.CFrame:PointToWorldSpace(route.points[4]), "Cable bottom remains on its mechanical assembly")
	for index, cylinder in route.cylinders do
		local part = copy(cylinder)
		near(part.Position - part.CFrame.RightVector * part.Size.X * .5, copy(route.joints[index]).Position,
			"Deformed cylinder starts on the shared joint without a gap")
		near(part.Position + part.CFrame.RightVector * part.Size.X * .5, copy(route.joints[index+1]).Position,
			"Deformed cylinder ends on the shared joint without a gap")
	end
end
local route = routes.FrontBrakeLine
near(copy(route.joints[3]).Position, front.CFrame:PointToWorldSpace(route.points[3]), "Cable remains routed through the lower fork clip")
local travel = Frame.new(800,12,-700) * Frame.Angles(0,-1,0)
for _, part in { stick, body, front } do part.CFrame = travel * part.CFrame end
presentation.Update(true)
near(copy(route.joints[1]).Position, stick.CFrame:PointToWorldSpace(route.points[1]), "Travel never uses an old WorldPivot")
presentation.Update(false)
check(route.joints[1].LocalTransparencyModifier == 0 and copy(route.joints[1]).Transparency == 1, "Distance culling restores source geometry")
presentation.Update(true)
model.DescendantRemoving:Fire(route.joints[1])
check(not presentation.IsAlive() and #destination:GetChildren() == 0, "Streaming removal releases cable copies")
check(route.joints[1].LocalTransparencyModifier == 0, "Streaming cleanup restores the original")
presentation.Destroy()
model:SetAttribute("ScooterG4Rig", nil)
check(VisualCables.Create(model, destination) == nil, "Legacy G2 Pro is untouched")
print(string.format("PASS: %d G4 cable assertions", count))
end
