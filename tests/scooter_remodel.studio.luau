-- Run in Edit after syncing Rojo. Uses the actual imports, without installing a template.
local modules = Instance.new("Folder")
local fixtures = {}
local original = assert(game.ServerStorage.ScooterAuthoring:FindFirstChild("ScooterFinal"))
local imported = assert(workspace:FindFirstChild("newFrontWheel"))
local originalState = {}
for _, root in { original, imported } do
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			originalState[item] = { item.CFrame, item.Size, item.Parent, item.Anchored, item.CanCollide }
		end
	end
end
local installed = game.ServerStorage.ScooterModels.scooter
local ok, result = xpcall(function()
	for _, name in { "DevScooterBuildConfig", "DevScooterBuild", "DevScooterRemodelConfig", "ScooterCollision",
		"ScooterSuspension", "ScooterRigGeometry", "ScooterRig", "DevScooterInstall", "DevScooterRemodel" } do
		local copy = game.ServerScriptService.Scooter[name]:Clone()
		copy.Parent = modules
	end
	local remodel = require(modules.DevScooterRemodel)
	local builder = require(modules.DevScooterBuild)
	local installer = require(modules.DevScooterInstall)
	local rig = require(modules.ScooterRig)
	local settings = require(modules.DevScooterRemodelConfig)
	local source = remodel.BuildSource(original, imported)
	table.insert(fixtures, source)
	assert(source.Parent == nil)
	assert(not source:FindFirstChildWhichIsA("Constraint", true))
	local front, back = source.FrontWheel.Mesh_0, source.BackWheel.Mesh_0
	assert(math.abs(front.Position.Y - back.Position.Y) < 0.001, "Tires must share a level rest pose")
	assert(source.ScooterBody.Mesh_0.Size == original.ScooterBody.Mesh_0.Size)
	assert(source.HandleBarStick.Mesh_0.Size == original.HandleBarStick.Mesh_0.Size)
	assert(source.Handbar.Mesh_0.Size == original.Handbar.Mesh_0.Size)
	assert(back.Size.Z == original.BackWheel.Mesh_0.Size.Z, "Rear tire width must be preserved")
	assert(front.MeshId == imported.Mesh_0.MeshId)
	local appearance = front:FindFirstChildWhichIsA("SurfaceAppearance")
	assert(appearance and appearance.ColorMap == imported.Mesh_0.SurfaceAppearance.ColorMap
		and appearance.NormalMap == imported.Mesh_0.SurfaceAppearance.NormalMap)
	assert(back.TextureID == original.BackWheel.Mesh_0.TextureID)
	assert(#source.Kickstand:GetChildren() == 3 and #source.BackFender:GetChildren() == 10)
	local draft = builder.Build(source)
	table.insert(fixtures, draft)
	builder.Validate(draft)
	local runtime = installer.Prepare(draft)
	table.insert(fixtures, runtime)
	rig.Inspect(runtime)
	assert(math.abs(runtime:GetAttribute("ResolvedFrontWheelRadius") - settings.PlayableWheelDiameter * 0.5) < 0.001)
	assert(math.abs(front.Size.Z / front.Size.X - imported.Mesh_0.Size.Z / imported.Mesh_0.Size.X) < 0.001,
		"Resizing the imported tire must retain its proportions")
	assert(math.abs(runtime:GetAttribute("ResolvedBackWheelRadius") - runtime:GetAttribute("ResolvedFrontWheelRadius")) < 0.001)
	assert(runtime.ScooterBody.Size == installed.ScooterBody.Size)
	local joints, shocks, contacts = 0, 0, 0
	for _, item in runtime:GetDescendants() do
		if item:IsA("HingeConstraint") then
			joints += 1
			assert((item.Attachment0.WorldPosition - item.Attachment1.WorldPosition).Magnitude < 0.001)
		elseif item:IsA("SpringConstraint") then
			shocks += 1
			assert(item.Stiffness > 0 and item.Damping > 0 and item.MaxForce > 0)
		elseif item:IsA("BasePart") and item.CanCollide then contacts += 1 end
	end
	assert(joints == 7 and shocks == 2 and contacts == 3)
	for _, name in { "Kickstand", "BackFender" } do
		local component = runtime[name]
		assert(component:IsA("Model"), "Compound decorations must survive installation")
		for _, item in component:GetChildren() do
			assert(item:IsA("BasePart") and item.Massless and not item.CanCollide and not item.Anchored)
			local fixed = if name == "Kickstand" then runtime.ScooterBody else runtime.VirtualBackAxle
			local linked = false
			for _, joint in fixed:GetChildren() do
				if joint:IsA("WeldConstraint") and joint.Part0 == fixed and joint.Part1 == item then linked = true end
			end
			assert(linked, "Decoration must follow its correct rigid assembly")
		end
	end
	local preparedAgain = rig.Prepare(runtime)
	table.insert(fixtures, preparedAgain)
	assert(#preparedAgain:GetDescendants() == #runtime:GetDescendants(), "Runtime clones must not duplicate joints")
	local tooLarge = imported:Clone()
	table.insert(fixtures, tooLarge)
	tooLarge.Mesh_0.Size = Vector3.new(4, 4, 0.7)
	assert(not pcall(remodel.BuildSource, original, tooLarge), "Oversized imports must fail before source changes")
	assert(not pcall(remodel.BuildSource, source, imported), "Repeated remodeling must not compound dimensions")
	for item, state in originalState do
		assert(item.CFrame == state[1] and item.Size == state[2] and item.Parent == state[3]
			and item.Anchored == state[4] and item.CanCollide == state[5], "Input assets must remain unchanged")
	end
	assert(game.ServerStorage.ScooterModels.scooter == installed, "Tests must preserve the gameplay template")
end, debug.traceback)
for _, fixture in fixtures do fixture:Destroy() end
modules:Destroy()
if not ok then error(result) end
print("PASS: actual larger-wheel source, appearance, unchanged chassis, articulation, compound decoration and clone safety")
