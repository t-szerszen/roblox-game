-- Run after Rojo sync in Studio Edit mode. Fixtures stay outside the DataModel.
-- Fresh modules keep repeated Edit-mode runs consistent after configuration edits.
local modules = Instance.new("Folder")
for _, name in { "DevScooterBuildConfig", "DevScooterBuild" } do
	local copy = game.ServerScriptService.Scooter[name]:Clone()
	copy.Parent = modules
end
local loaded, Builder, Config = pcall(function()
	return require(modules.DevScooterBuild), require(modules.DevScooterBuildConfig)
end)
modules:Destroy()
if not loaded then error(Builder) end
local source = Instance.new("Folder")
source.Name = "ScooterFinalFixture"
local external = Instance.new("Part")
local draft: Model? = nil
local fixtures: { Instance } = {}
local function component(name: string, position: Vector3): MeshPart
	local group = Instance.new("Model")
	group.Name, group.Parent = name, source
	local mesh = Instance.new("MeshPart")
	mesh.Name, mesh.Parent = "Mesh_0", group
	mesh.Size = Vector3.new(3, 2, 1)
	mesh.Position = position
	return mesh
end
local ok, result = xpcall(function()
	local body = component("ScooterBody", Vector3.new(30, 12, 6))
	body.Size = Vector3.new(25, 9, 5)
	for _, name in { "HandleBarStick", "Handbar", "Footrest", "FrontLight", "Display", "FrontSpring", "BackSpring", "BrakeDisc" } do
		component(name, Vector3.new(35, 20, 6))
	end
	local front = component("FrontWheel", Vector3.new(42, 6, 6))
	front.Size = Vector3.new(7, 7, 2)
	local back = component("BackWheel", Vector3.new(15, 6, 6))
	back.Size = Vector3.new(7, 7, 2)
	component("FrontLeftSuspension", Vector3.new(39, 7, 5))
	component("FrontRightSuspension", Vector3.new(39.1, 7.2, 7))
	component("BackLeftSuspension", Vector3.new(18, 7, 5))
	component("BackRightSuspension", Vector3.new(18, 7, 7))
	component("Grip", Vector3.new(35, 29, 0))
	component("Grip", Vector3.new(35, 29, 14))
	for _, name in { "StopLight", "BackSpringStick" } do
		local item = Instance.new("Part")
		item.Name, item.Parent = name, source
		item.Position = Vector3.new(18, 10, 6)
	end
	local dashboard = Instance.new("Model")
	dashboard.Name, dashboard.Parent = "ScooterDashboard", source
	local screen = Instance.new("Part")
	screen.Name, screen.Parent = "DisplaySurface", dashboard
	screen.Position = Vector3.new(35, 30, 6)
	local housing = Instance.new("Part")
	housing.Name, housing.Parent = "Housing", dashboard
	housing.Position = screen.Position
	local internal = Instance.new("WeldConstraint")
	internal.Part0, internal.Part1, internal.Parent = screen, housing, housing
	local original = {}
	for _, item in source:GetDescendants() do
		if item:IsA("BasePart") then original[item] = { item.CFrame, item.Size, item.Parent, item.Anchored, item.CanCollide } end
	end
	local count = #source:GetDescendants()
	draft = Builder.Build(source)
	assert(draft and draft.Parent == nil and draft:GetAttribute("ScooterDraftScale") == Config.Scale)
	assert(draft:GetAttribute("ReferenceAvatarHeight") == 8)
	assert(draft:GetAttribute("MountsVerified") == Config.MountsVerified and draft:GetAttribute("SuspensionCalibrated") == false)
	assert(#source:GetDescendants() == count)
	for item, state in original do
		assert(item.CFrame == state[1] and item.Size == state[2] and item.Parent == state[3]
			and item.Anchored == state[4] and item.CanCollide == state[5], "Source must remain unchanged")
	end
	local clonedBody = draft.ScooterBody.Mesh_0
	assert((clonedBody.Size - body.Size * Config.Scale).Magnitude < 0.001)
	local clonedFront = draft.FrontWheel.Mesh_0
	assert(math.abs((clonedFront.Position - clonedBody.Position).Magnitude
		- (front.Position - body.Position).Magnitude * Config.Scale) < 0.001)
	local hinges, springs = 0, 0
	for _, item in draft:GetDescendants() do
		if item:IsA("HingeConstraint") then hinges += 1 end
		if item:IsA("SpringConstraint") then springs += 1 end
		if item:IsA("BasePart") then assert(item.Anchored and not item.CanCollide) end
	end
	assert(hinges == (if Config.IndependentFrontSteering then 8 else 7) and springs == 2)
	assert(draft:GetAttribute("IndependentFrontSteering") == Config.IndependentFrontSteering)
	local frontBase = if Config.IndependentFrontSteering then clonedBody else draft.HandleBarStick.Mesh_0
	assert(draft:FindFirstChild("FrontSuspensionLeftHinge", true).Attachment0.Parent == frontBase)
	assert(draft:FindFirstChild("FrontShock", true).Attachment0.Parent == frontBase)
	Builder.Validate(draft)
	local independentConfig = table.clone(Config)
	independentConfig.IndependentFrontSteering = true
	local independent = Builder.Build(source, independentConfig)
	table.insert(fixtures, independent)
	assert(independent:FindFirstChild("FrontSuspensionLeftHinge", true).Attachment0.Parent == independent.ScooterBody.Mesh_0)
	assert(independent.FrontSteeringCarrier.FrontWheelHinge.Attachment0.Parent == independent.FrontSteeringCarrier)
	assert(independent.VirtualFrontAxle.FrontSteeringHinge.Attachment1.Parent == independent.FrontSteeringCarrier)
	Builder.Validate(independent)
	local remodeledSource = source:Clone()
	table.insert(fixtures, remodeledSource)
	for _, item in remodeledSource.ScooterDashboard:GetDescendants() do
		if item:IsA("WeldConstraint") then item:Destroy() end
	end
	for _, entry in Config.ExtraComponents do
		local group = Instance.new("Model")
		group.Name, group.Parent = entry.Name, remodeledSource
		local mesh = Instance.new("MeshPart")
		mesh.Name, mesh.Parent = "Mesh_0", group
		mesh.Position = Vector3.new(35, 18, 6)
	end
	local remodeledConfig = table.clone(Config)
	remodeledConfig.IndependentFrontSteering = false
	remodeledSource.ScooterBody.Mesh_0.PivotOffset = CFrame.Angles(math.pi / 2, 0, 0)
	local remodeled = Builder.Build(remodeledSource, remodeledConfig)
	table.insert(fixtures, remodeled)
	assert(remodeled:FindFirstChild("FrontSteeringCarrier") == nil)
	assert(remodeled.ScooterBody.Mesh_0.PivotOffset == CFrame.identity)
	assert(remodeledSource.ScooterBody.Mesh_0.PivotOffset ~= CFrame.identity, "Imported source pivot must remain unchanged")
	assert(remodeled:FindFirstChild("FrontShock", true).Attachment0.Parent == remodeled.HandleBarStick.Mesh_0)
	for _, entry in Config.ExtraComponents do
		local mesh = remodeled[entry.Name].Mesh_0
		assert(mesh:GetAttribute("ScooterDraftAssembly") == entry.Assembly)
		assert(mesh.DraftAssemblyWeld.Part0.Name == (if string.find(entry.FixedName, "Virtual") then entry.FixedName else "Mesh_0"))
	end
	Builder.Validate(remodeled)
	Builder.MarkLinks(remodeled)
	assert(#remodeled._ScooterRigReview:GetChildren() == 20, "All 18 endpoints and two springs need yellow review markers")
	Builder.MarkLinks(remodeled)
	assert(#remodeled._ScooterRigReview:GetChildren() == 20, "Repeated review must not duplicate markers")
	Builder.Validate(remodeled)
	local hinge = draft:FindFirstChild("FrontWheelHinge", true)
	local point = hinge.Attachment1
	local frame = point.CFrame
	point.Position += Vector3.new(0.1, 0, 0)
	assert(not pcall(Builder.Validate, draft), "Must reject a hinge gap")
	point.CFrame = frame
	local badWeld = Instance.new("WeldConstraint")
	badWeld.Part0, badWeld.Part1, badWeld.Parent = clonedBody, clonedFront, clonedBody
	assert(not pcall(Builder.Validate, draft), "Must reject a weld locking a wheel to the body")
	badWeld:Destroy()
	local copiedInternal = draft.ScooterDashboard.Housing:FindFirstChildWhichIsA("WeldConstraint")
	copiedInternal.Enabled = false
	assert(not pcall(Builder.Validate, draft), "Must reject a disconnected dashboard housing")
	copiedInternal.Enabled = true
	for _, scale in { 0, -1, math.huge, 0 / 0 } do
		local bad = table.clone(Config)
		bad.Scale = scale
		assert(not pcall(Builder.Build, source, bad), "Must reject invalid scale")
	end
	assert(not pcall(Builder.Build, draft), "Must reject rescaling a draft")
	local lamp = source.FrontLight
	lamp.Parent = nil
	assert(not pcall(Builder.Build, source), "Must reject a missing component")
	lamp.Parent = source
	local outsideWeld = Instance.new("WeldConstraint")
	outsideWeld.Part0, outsideWeld.Part1, outsideWeld.Parent = body, external, body
	assert(not pcall(Builder.Build, source), "Must reject an external source weld")
	outsideWeld:Destroy()
	local scriptFixture = Instance.new("Script")
	scriptFixture.Parent = source
	assert(not pcall(Builder.Build, source), "Must reject executable source content")
	scriptFixture:Destroy()
	assert(#source:GetDescendants() == count)
	return "PASS: scooter draft assembly, central springs, scaling, source preservation and rejection of invalid geometry/rigid links"
end, debug.traceback)
if draft then draft:Destroy() end
for _, fixture in fixtures do fixture:Destroy() end
source:Destroy()
external:Destroy()
if not ok then error(result) end
print(result)
return result
