-- Run in Edit after ScooterWorkflow.InstallScaleVariants(). Uses detached clones.
local modules = Instance.new("Folder")
local clones = {}
local ok, result = xpcall(function()
	for _, name in { "ScooterCollision", "ScooterSuspension", "ScooterRigGeometry", "ScooterRig" } do
		game.ServerScriptService.Scooter[name]:Clone().Parent = modules
	end
	local configModule = game.ReplicatedStorage.Shared.ScooterConfig:Clone()
	configModule.Parent = modules
	local config = require(configModule)
	local rig = require(modules.ScooterRig)
	local geometry = require(modules.ScooterRigGeometry)
	local smaller
	for _, variant in config.StudioScaleVariants do
		local template = game.ServerStorage.ScooterModels:FindFirstChild(variant.TemplateName)
		assert(template and template:GetAttribute("StudioScaleVariant") == variant.Id)
		assert(template:GetAttribute("ScooterDraftScale") == variant.Scale)
		local clone = rig.Prepare(template)
		table.insert(clones, clone)
		assert(#geometry.Check(clone).errors == 0, "Scaled joints must remain coaxial and connected")
		assert(math.abs(clone.Root:GetMass() - 12) < 0.01, "Scaling must retain chassis mass")
		local hinges, springs, meshes = 0, 0, 0
		for _, item in clone:GetDescendants() do
			if item:IsA("HingeConstraint") then
				hinges += 1
				assert((item.Attachment0.WorldPosition - item.Attachment1.WorldPosition).Magnitude < 0.001)
			elseif item:IsA("SpringConstraint") then
				springs += 1
				local length = (item.Attachment0.WorldPosition - item.Attachment1.WorldPosition).Magnitude
				assert(item.MinLength < length and item.MaxLength > length)
				assert(item.Stiffness > 0 and item.Damping > 0)
			elseif item:IsA("MeshPart") then meshes += 1
			end
		end
		assert(hinges == 7 and springs == 2 and meshes == 21)
		local inspection = rig.Inspect(clone)
		assert(inspection.wheelSteering == nil, "Retain approved whole-front steering")
		assert((clone.LeftGrip.Position - clone.HandleBar.LeftHandGrip.WorldPosition).Magnitude < 0.001)
		if smaller then
			assert((clone.ScooterBody.Size - smaller.ScooterBody.Size * 1.25).Magnitude < 0.001)
			local shock = clone.HandleBarStick.ShockAbsorber_Front
			local smallShock = smaller.HandleBarStick.ShockAbsorber_Front
			local length = (shock.Attachment0.WorldPosition - shock.Attachment1.WorldPosition).Magnitude
			local smallLength = (smallShock.Attachment0.WorldPosition - smallShock.Attachment1.WorldPosition).Magnitude
			assert(math.abs(length / smallLength - 1.25) < 0.001)
		else smaller = clone end
	end
	return "PASS: both scales retain accepted topology, 21 meshes, aligned joints, calibrated spring travel, chassis mass and grip targets"
end, debug.traceback)
for _, clone in clones do clone:Destroy() end
modules:Destroy()
if not ok then error(result) end
return result
