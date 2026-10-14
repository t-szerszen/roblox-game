-- CFrame/instance doubles exercise actual Compound.Create/Update, not a physics solver.
local Compound = loadModule("ReplicatedStorage/Shared/Scooter/ScooterCompoundVisuals")
enumMock.PartType.Cylinder = "Cylinder"
enumMock.BulkMoveMode = { FireCFrameChanged = "FireCFrameChanged" }
function services.Workspace:BulkMoveTo(parts, frames)
	for index, part in parts do part.CFrame = frames[index] end
end
function instanceMethods:GetPropertyChangedSignal() return signal() end
function instanceMethods:GetPivot() error("A shock Model's stationary WorldPivot must not be read") end
local count = 0
local function check(condition, message)
	count += 1
	assert(condition, message)
end
local function near(first, second, message)
	check((first - second).Magnitude < 0.0001, message)
end
local function make(parent, class, name)
	local item = InstanceMock.new(class)
	item.Name, item.Parent = name, parent
	item.LocalTransparencyModifier = 0
	item.Transparency = 0
	item.DescendantRemoving = signal()
	return item
end
local model = make(nil, "Model", "G4")
model:SetAttribute("ScooterG4Rig", true)
model.PrimaryPart = make(model, "Part", "Root")
model.PrimaryPart.CFrame = Frame.new(1200, 4, -300) * Frame.Angles(0, .4, 0)
local visuals = make(model, "Folder", "G4Visuals")
local shocks = {}
local lower = Vector.new(0, -2, -.6)
local length = lower.Magnitude
local rest = Frame.fromMatrix(lower * .5, Vector.xAxis, -lower.Unit)
for _, endName in { "Front", "Back" } do
	local base = make(model, "Part", if endName == "Front" then "HandleBarStick" else "ScooterBody")
	base.CFrame = model.PrimaryPart.CFrame
	local wheel = make(model, "Part", endName .. "Wheel")
	wheel.CFrame = base.CFrame
	wheel:SetAttribute("WheelRadius", 1)
	make(wheel, "Attachment", "WheelCenter")
	local axle = make(model, "Part", "Virtual" .. endName .. "Axle")
	axle.CFrame = base.CFrame
	make(axle, "Attachment", "AxlePivot")
	local group = make(visuals, "Model", endName .. "WheelVisuals")
	make(group, "Part", "Rim").CFrame = base.CFrame
	group:SetAttribute("CompoundVisualPartCount", 1)
	for _, side in { "Left", "Right" } do
		local suffix = endName .. "Suspension" .. side
		local arm = make(model, "Part", suffix)
		arm.CFrame = base.CFrame
		local fixed = make(base, "Attachment", "PivotAttBase_" .. suffix)
		local moving = make(arm, "Attachment", "PivotAtt_" .. suffix)
		moving:SetAttribute("AuthoredPivotCFrame", Frame.identity)
		local hinge = make(base, "HingeConstraint", "PivotHinge_" .. suffix)
		hinge.Attachment0, hinge.Attachment1 = fixed, moving
		local spring = make(base, "SpringConstraint", "ShockAbsorber_" .. suffix)
		spring.Attachment0 = make(base, "Attachment", "Upper" .. side)
		spring.Attachment1 = make(arm, "Attachment", "Lower")
		spring.Attachment1.Position = lower
		local coilGroup = make(visuals, "Model", suffix .. "CoilVisuals")
		coilGroup:SetAttribute("CompoundSpringConstraint", spring.Name)
		coilGroup:SetAttribute("CompoundVisualPartCount", 3)
		local members = {}
		for _, section in { "Upper", "Coil", "Lower" } do
			local part = make(coilGroup, "Part", suffix .. section)
			part.Shape = enumMock.PartType.Cylinder
			part:SetAttribute("G4ShockSection", section)
			local offset = rest * Frame.new(0, if section == "Upper" then .5 else if section == "Lower" then -.5 else 0, 0)
			part.CFrame = base.CFrame * offset
			table.insert(members, { part = part, section = section, offset = offset })
		end
		table.insert(shocks, { base = base, arm = arm, spring = spring, members = members })
	end
end
local function pose(compression, steering)
	for index, shock in shocks do
		shock.base.CFrame = model.PrimaryPart.CFrame * Frame.Angles(0, if index <= 2 then steering else 0, 0)
		shock.arm.CFrame = shock.base.CFrame * Frame.Angles(compression, 0, 0)
		for _, member in shock.members do
			member.part.CFrame = (if member.section == "Lower" then shock.arm.CFrame else shock.base.CFrame) * member.offset
		end
	end
end
local destination = make(nil, "Folder", "Copies")
local presentation = assert(Compound.Create(model, destination))
presentation.Update(1 / 60, true)
local firstFrames = {}
for _, shock in shocks do for _, member in shock.members do
	local copy = destination.G4RideVisuals[member.part.Name]
	near(copy.Position, member.part.Position, "Nominal shock geometry remains on its authored mount")
	check((copy.Position - model.PrimaryPart.Position).Magnitude < 5, "Travelled scooter does not leave springs at spawn")
end end
pose(.2, .7)
presentation.Update(1 / 60, true)
for _, shock in shocks do for _, member in shock.members do
	local copy = destination.G4RideVisuals[member.part.Name]
	firstFrames[member.part.Name] = copy.CFrame
end end
presentation.Destroy()
presentation = assert(Compound.Create(model, destination))
presentation.Update(1 / 60, true)
for _, shock in shocks do for _, member in shock.members do
	local copy = destination.G4RideVisuals[member.part.Name]
	local expected = firstFrames[member.part.Name]
	near(copy.Position, expected.Position, "Binding after compression/steering preserves shock placement")
	near(copy.CFrame.UpVector, expected.UpVector, "Rebinding uses the same authored rest orientation")
end end
model.PrimaryPart.CFrame = Frame.new(-200, 10, 800) * Frame.Angles(0, 1.2, 0)
pose(-.1, -.6)
presentation.Update(1 / 60, true)
for _, shock in shocks do
	local a, b = shock.spring.Attachment0.WorldPosition, shock.spring.Attachment1.WorldPosition
	local up = (a - b).Unit
	local upper = destination.G4RideVisuals[shock.members[1].part.Name]
	local lowerCopy = destination.G4RideVisuals[shock.members[3].part.Name]
	near(upper.Position, a + up * (.5 - length * .5), "Upper housing stays referenced to the current upper eye")
	near(lowerCopy.Position, b + up * (-.5 + length * .5), "Lower housing stays referenced to the current lower eye")
end
presentation.Destroy()
check(#destination:GetChildren() == 0, "All presentation copies clean up")
print(string.format("PASS: %d G4 shock presentation assertions", count))
