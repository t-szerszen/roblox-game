-- Run in Studio Edit after syncing, with the approved draft in Workspace or ScooterAuthoring.
local folder = Instance.new("Folder")
local models: { Model } = {}
local function sameFrame(first: CFrame, second: CFrame): boolean
	-- Imported matrices carry rounding; compare bases directly rather than inverse/acos near zero.
	return (first.Position - second.Position).Magnitude < 0.001
		and (first.RightVector - second.RightVector).Magnitude < 0.0001
		and (first.UpVector - second.UpVector).Magnitude < 0.0001
		and (first.LookVector - second.LookVector).Magnitude < 0.0001
end
local ok, result = xpcall(function()
	for _, name in { "DevScooterBuildConfig", "DevScooterBuild", "ScooterCollision", "ScooterSuspension",
		"ScooterRigGeometry", "ScooterRig", "DevScooterInstall" } do
		local copy = game.ServerScriptService.Scooter[name]:Clone()
		copy.Parent = folder
	end
	local Installer = require(folder.DevScooterInstall)
	local BuildConfig = require(folder.DevScooterBuildConfig)
	local Rig = require(folder.ScooterRig)
	local Geometry = require(folder.ScooterRigGeometry)
	local authoring = game.ServerStorage:FindFirstChild("ScooterAuthoring")
	local selected = workspace:FindFirstChild("ScooterFinalRig") or (authoring and authoring:FindFirstChild("ScooterFinalRig"))
	assert(selected and selected:IsA("Model"), "Build a real draft first")
	-- Exercise preparation on a detached copy without approving or installing the user's draft.
	local draft = selected:Clone()
	table.insert(models, draft)
	draft:SetAttribute("MountsVerified", true)
	local independent = draft:GetAttribute("IndependentFrontSteering") == true
	local original = {}
	local meshCount = 0
	for _, part in draft:GetDescendants() do
		if part:IsA("BasePart") then
			original[part] = { frame = part.CFrame, size = part.Size, parent = part.Parent, anchored = part.Anchored }
			if part:IsA("MeshPart") then meshCount += 1 end
		end
	end
	local springs = {}
	local hinges = {}
	for _, joint in draft:GetDescendants() do
		if joint:IsA("SpringConstraint") then springs[joint.Name] = { joint.Attachment0.WorldPosition, joint.Attachment1.WorldPosition }
		elseif joint:IsA("HingeConstraint") then hinges[joint.Name] = { joint.Attachment0.WorldCFrame, joint.Attachment1.WorldCFrame } end
	end
	local template = Installer.Prepare(draft)
	table.insert(models, template)
	assert(template.Parent == nil and template.PrimaryPart == template.Root)
	assert(template:GetAttribute("CentralShockRig") and template:GetAttribute("ArticulatedScooter"))
	assert(template:GetAttribute("FrontRestPoseStatus") == "Authored" and template:GetAttribute("FrontMountShift") == nil)
	assert(template:GetAttribute("ScooterDraftScale") == draft:GetAttribute("ScooterDraftScale"))
	assert(math.abs(template.Root:GetMass() - 12) < 0.01)
	assert(template.FootRest:IsA("Part") and template.RearFootRest:IsA("MeshPart"))
	assert(template.FootRest.Transparency == 1 and template.DeckCollider.CanCollide)
	assert((template.LeftGrip.Position - template.HandleBar.LeftHandGrip.WorldPosition).Magnitude < 0.001)
	assert((template.RightGrip.Position - template.HandleBar.RightHandGrip.WorldPosition).Magnitude < 0.001)
	local actualMeshes, hingeCount, springCount = 0, 0, 0
	for _, part in template:GetDescendants() do
		if part:IsA("MeshPart") then
			actualMeshes += 1
			local matched = false
			for source, state in original do
				if source:IsA("MeshPart") and source.MeshId == part.MeshId
					and sameFrame(state.frame, part.CFrame)
					and (state.size - part.Size).Magnitude < 0.001 then matched = true; break end
			end
			assert(matched, "Runtime changed or invented an imported mesh: " .. part.Name)
		elseif part:IsA("HingeConstraint") then
			hingeCount += 1
			local matched = false
			for _, frames in hinges do
				if sameFrame(frames[1], part.Attachment0.WorldCFrame)
					and sameFrame(frames[2], part.Attachment1.WorldCFrame) then matched = true; break end
			end
			assert(matched, "Runtime moved an approved hinge")
		elseif part:IsA("SpringConstraint") then
			springCount += 1
			local positions = springs[if part.Name == "ShockAbsorber_Front" then "FrontShock" else "BackShock"]
			assert((positions[1] - part.Attachment0.WorldPosition).Magnitude < 0.001)
			assert((positions[2] - part.Attachment1.WorldPosition).Magnitude < 0.001)
			local length = (positions[1] - positions[2]).Magnitude
			assert(part.MinLength < length and part.MaxLength > length and part.Damping > 0 and part.Stiffness > 0)
		end
		if part:IsA("BasePart") then assert(not part.Anchored, "Runtime remains anchored") end
	end
	assert(actualMeshes == meshCount and hingeCount == (if independent then 8 else 7) and springCount == 2)
	local frontBase = if independent then template.ScooterBody else template.HandleBarStick
	assert(frontBase.PivotHinge_FrontSuspensionLeft.Attachment0.Parent == frontBase)
	assert(frontBase.ShockAbsorber_Front.Attachment0.Parent == frontBase)
	assert(template:FindFirstChild("_ScooterRigReview") == nil, "Review adornments must not enter gameplay")
	if independent then
		assert(template.FrontSteeringCarrier.HingeConstraint.Attachment0.Parent == template.FrontSteeringCarrier)
		assert(Rig.Inspect(template).wheelSteering == template.VirtualFrontAxle.FrontSteeringHinge)
	else
		assert(Rig.Inspect(template).wheelSteering == nil and template:FindFirstChild("FrontSteeringCarrier") == nil)
		assert(template.VirtualFrontAxle.HingeConstraint.Attachment0.Parent == template.VirtualFrontAxle)
	end
	assert(#Geometry.Check(template).errors == 0)
	local badWeld = Instance.new("WeldConstraint")
	badWeld.Part0, badWeld.Part1, badWeld.Parent = template.FrontSpringVisual, template.BackWheel, template.FrontSpringVisual
	assert(#Geometry.Check(template).errors > 0, "Decorations cannot weld different assemblies together")
	badWeld:Destroy()
	local clone = Rig.Prepare(template)
	table.insert(models, clone)
	assert(#clone:GetDescendants() == #template:GetDescendants(), "Runtime clone duplicated joints")
	local cloneFrontBase = if independent then clone.ScooterBody else clone.HandleBarStick
	local frontMount = cloneFrontBase.PivotAttBase_FrontSuspensionLeft.WorldPosition
	Geometry.Repair(clone)
	assert(#Geometry.Check(clone).errors == 0, "Repair must retain the chosen front steering topology")
	Geometry.AlignFrontRest(clone)
	assert((cloneFrontBase.PivotAttBase_FrontSuspensionLeft.WorldPosition - frontMount).Magnitude < 0.001,
		"Legacy rest correction must preserve the authored central-rig mounts")
	local invalid = draft:Clone()
	table.insert(models, invalid)
	invalid:SetAttribute("MountsVerified", false)
	assert(not pcall(Installer.Prepare, invalid), "Installer must reject unapproved mounts")
	for source, state in original do
		assert(source.CFrame == state.frame and source.Size == state.size and source.Parent == state.parent
			and source.Anchored == state.anchored, "Installer changed the authoring draft")
	end
	return "PASS: central-shock runtime, approved geometry/meshes preserved, real deck/grip targets, mass, calibration, cloning and approval guard"
end, debug.traceback)
for _, model in models do model:Destroy() end
folder:Destroy()
if not ok then error(result) end
print(result)
return result
