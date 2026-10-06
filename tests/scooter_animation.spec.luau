-- Runs actual rig preparation and animator lifecycle against object doubles.
local AnimationMath = loadModule("ReplicatedStorage/Shared/Scooter/ScooterAnimationMath")
local Rig = loadModule("ServerScriptService/Scooter/ScooterRig")
local ScooterAnimator = loadModule("StarterPlayer/StarterPlayerScripts/ScooterAnimator")
local before = testCount

near(AnimationMath.Lean(0, 0, Config.MaxHandlebarAngle), 0, "Stationary steering does not lean torso")
near(AnimationMath.Lean(30, 0, 0), 0, "Straight travel keeps torso neutral")
check(AnimationMath.Lean(30, 0, Config.MaxHandlebarAngle) < 0, "Right turn leans rider right")
near(AnimationMath.Lean(30, 0, Config.MaxHandlebarAngle),
	-AnimationMath.Lean(30, 0, -Config.MaxHandlebarAngle), "Left/right lean is symmetric")
check(math.abs(AnimationMath.Lean(3, 0, 0.2)) < math.abs(AnimationMath.Lean(24, 0, 0.2)),
	"Speed increases torso lean")
check(AnimationMath.Lean(0, 5, 0) < 0, "Lateral movement contributes through RightVector speed")
near(AnimationMath.Lean(100, 100, 100), -Config.RiderPose.MaxBodyLean, "Combined lean is capped")
near(AnimationMath.Lean(-24, 0, 0.2), AnimationMath.Lean(24, 0, 0.2), "Reverse lean uses speed magnitude")

local function make(parent, className, name)
	local instance = InstanceMock.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end
local source = make(nil, "Folder", "scooter")
for _, name in { "ScooterBody", "HandleBarStick", "HandleBar", "FrontWheel", "BackWheel", "FootRest", "BackFender",
	"FrontSuspensionLeft", "FrontSuspensionRight", "BackSuspensionLeft", "BackSuspensionRight" } do
	make(source, "MeshPart", name)
end
local function link(parent, className, name, a, b)
	local constraint = make(parent, className, name)
	constraint.Attachment0, constraint.Attachment1 = a, b
	return constraint
end
local function weldTest(parent, first, second, name)
	local constraint = make(parent, "WeldConstraint", name)
	constraint.Part0, constraint.Part1 = first, second
	return constraint
end
local steerBase = make(source.ScooterBody, "Attachment", "SteerBase")
source.HandleBar.CFrame = Frame.new(0, 3, 0)
local steerPivot = make(source.HandleBarStick, "Attachment", "SteerPivot")
link(source.ScooterBody, "HingeConstraint", "HingeConstraint", steerBase, steerPivot)
weldTest(source.HandleBarStick, source.HandleBarStick, source.HandleBar, "WeldConstraint")
for _, endName in { "Front", "Back" } do
	local axle = make(source, "Part", "Virtual" .. endName .. "Axle")
	axle.CFrame = Frame.new(0, 0, if endName == "Front" then -2 else 2)
	local pivot = make(axle, "Attachment", "AxlePivot")
	local wheel = source:FindFirstChild(endName .. "Wheel")
	wheel.CFrame = axle.CFrame
	local center = make(wheel, "Attachment", "WheelCenter")
	link(axle, "HingeConstraint", "HingeConstraint", pivot, center)
	local base = if endName == "Front" then source.HandleBarStick else source.ScooterBody
	for _, side in { "Left", "Right" } do
		local suffix = endName .. "Suspension" .. side
		local arm = source:FindFirstChild(suffix)
		local a = make(base, "Attachment", "PivotAttBase_" .. suffix)
		local b = make(arm, "Attachment", "PivotAtt_" .. suffix)
		a.Position = Vector.new(if side == "Left" then -0.5 else 0.5, 0, 0)
		b.Position = a.Position
		link(base, "HingeConstraint", "PivotHinge_" .. suffix, a, b)
		a = make(base, "Attachment", "SpringAttBase_" .. suffix)
		b = make(arm, "Attachment", "SpringAtt_" .. suffix)
		a.Position = Vector.new(if side == "Left" then -0.5 else 0.5, 0.5, 0)
		b.Position = Vector.new(a.Position.X, 0, -0.3)
		local spring = link(base, "SpringConstraint", "ShockAbsorber_" .. suffix, a, b)
		spring.Stiffness, spring.Damping, spring.FreeLength = 777, 33, 1.5
		weldTest(axle, axle, arm, "Weld" .. side)
	end
end
check(Rig.Inspect(source).frontAxle == source.VirtualFrontAxle, "Rig discovers exact virtual axle paths")
local wrong = source.VirtualFrontAxle.HingeConstraint
local endpoint = wrong.Attachment1
wrong.Attachment1 = source.VirtualBackAxle.AxlePivot
check(not pcall(Rig.Inspect, source), "Cross-rig wheel endpoints rejected")
wrong.Attachment1 = endpoint
local armWeld = source.VirtualFrontAxle.WeldLeft
armWeld.Enabled = false
check(not pcall(Rig.Inspect, source), "Disconnected suspension arm rejected")
armWeld.Enabled = true
local savedStick = source.HandleBarStick
savedStick.Parent = nil
check(not pcall(Rig.Inspect, source), "Missing authored part rejected without waiting")
savedStick.Parent = source

local model = Rig.Prepare(source)
check(model:IsA("Model") and model.PrimaryPart.Name == "Root", "Folder wrapped in runtime Model")
check(source.ScooterBody.Parent == source and not source:FindFirstChild("Root"), "Preparation preserves source")
local prepared = Rig.Inspect(model)
near(prepared.body.ShockAbsorber_BackSuspensionLeft:GetAttribute("AuthoredStiffness"), 777, "Authored stiffness retained for diagnosis")
near(prepared.body.ShockAbsorber_BackSuspensionLeft:GetAttribute("AuthoredDamping"), 33, "Authored damping retained for diagnosis")
near(prepared.body.ShockAbsorber_BackSuspensionLeft:GetAttribute("AuthoredFreeLength"), 1.5, "Authored free length retained for diagnosis")
check(prepared.frontHinge.Attachment1.Parent == prepared.frontWheel, "Cloned hinge references cloned wheel")
check(prepared.frontAxle.WeldLeft.Part1 == model.FrontSuspensionLeft, "Cloned axle weld preserved")
check(model.HandleBar.LeftHandGrip.Parent == model.HandleBar, "Hand grip follows physical handlebar")
check(not model.HandleBarStick.Massless and not model.VirtualBackAxle.Massless, "Articulated assemblies retain mass")
check(model.ScooterBody.RuntimeBodyWeld.Part0 == model.PrimaryPart, "Chassis connected without rigidly welding suspension")
local cloneAgain = Rig.Prepare(model)
check(#cloneAgain:GetDescendants() == #model:GetDescendants(), "Prepared templates do not accumulate generated joints")

local character = make(nil, "Model", "Rider")
character.Parent = InstanceMock.new("Folder")
local humanoid = make(character, "Humanoid", "Humanoid")
humanoid.RigType = enumMock.HumanoidRigType.R15
local animate = make(character, "LocalScript", "Animate")
animate.Disabled = false
for _, name in { "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
	"LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" } do make(character, "Part", name) end
local waist = make(character, "Motor6D", "Waist")
local rootJoint = make(character, "Motor6D", "Root")
model.Parent = InstanceMock.new("Folder")
local animator = ScooterAnimator.new(model)
check(animator.mount(character), "Complete R15 rig mounts")
check(animate.Disabled, "Mounted rider disables default seated animation")
local leftIK = humanoid.ScooterLeftHandIK
local rightIK = humanoid.ScooterRightHandIK
check(leftIK.Target == model.HandleBar.LeftHandGrip and rightIK.Target == model.HandleBar.RightHandGrip,
	"IK targets moving HandleBar grips directly")
local previousGrip = rightIK.Target.WorldPosition
model.HandleBar.CFrame = Frame.Angles(0, 0.5, 0)
check((rightIK.Target.WorldPosition - previousGrip).Magnitude > 0, "Steering motion carries IK target")
model:SetAttribute("SteeringAngle", Config.MaxHandlebarAngle)
model.PrimaryPart.AssemblyLinearVelocity = Vector.new(0, 0, -30)
services.RunService.PreAnimation:Fire(1 / 60)
services.RunService.PreSimulation:Fire()
local torsoPosture = Frame.Angles(-Config.RiderPose.WaistForwardPitch,
	-Config.MaxHandlebarAngle * Config.RiderPose.WaistSteeringYawFactor, 0)
check((torsoPosture:Inverse() * waist.Transform).z < 0 and rootJoint.Transform.z < 0,
	"Waist and Root apply turn lean over the forward and steering posture")
check(rightIK.Pole.Position.Y > leftIK.Pole.Position.Y, "Right turn raises right elbow pole")
local firstLean = waist.Transform.z
services.RunService.PreAnimation:Fire(0)
services.RunService.PreSimulation:Fire()
near(waist.Transform.z, firstLean, "Procedural lean does not accumulate across frames")
local leftPole = leftIK.Pole
animator.dismount()
check(leftIK.Parent == nil and rightIK.Parent == nil and leftPole.Parent == nil, "Dismount destroys IK and elbow targets")
check(not animate.Disabled, "Dismount restores default animation script")
near(waist.Transform.z, 0, "Dismount restores Waist transform")
services.RunService.PreAnimation:Fire(1 / 60)
services.RunService.PreSimulation:Fire()
near(waist.Transform.z, 0, "Dismount disconnects frame callbacks")
check(animator.mount(character) and animator.mount(character), "Repeated mounting replaces its prior controller")
check(#humanoid:GetChildren() == 5, "Remount retains one Animator and exactly four IK chains")
humanoid.Died:Fire()
check(not humanoid:FindFirstChild("ScooterLeftHandIK"), "Death cleans up hand IK")
animator.dismount()
character.LeftHand:Destroy()
check(not animator.mount(character), "Incomplete character is rejected cleanly")
check(not humanoid:FindFirstChild("ScooterLeftHandIK"), "Failed mount leaves no IK behind")

local r6 = make(character.Parent, "Model", "R6Rider")
local r6Humanoid = make(r6, "Humanoid", "Humanoid")
r6Humanoid.RigType = enumMock.HumanoidRigType.R6
local r6Root = make(r6, "Motor6D", "RootJoint")
check(animator.mount(r6), "R6 retains procedural fallback without nonexistent LeftHand paths")
services.RunService.PreAnimation:Fire(1 / 60)
services.RunService.PreSimulation:Fire()
check(r6Root.Transform.z < 0, "R6 RootJoint applies lean")
r6:Destroy()
near(r6Root.Transform.z, 0, "Character destruction restores pose and removes callbacks")

-- Exercise the reload entry point with deliberately stale canonical module caches.
services.ServerScriptService = InstanceMock.new("ServerScriptService")
services.ReplicatedStorage = InstanceMock.new("ReplicatedStorage")
services.ServerStorage = InstanceMock.new("ServerStorage")
services.RunService.IsStudio = function() return true end
services.RunService.IsRunning = function() return false end
local nextGuid = 0
services.HttpService = { GenerateGUID = function() nextGuid += 1; return tostring(nextGuid) end }
services.Selection = {
	Get = function() return { source } end,
	Set = function(_, selected) services.Selection.selected = selected end,
}
local serverFolder = make(services.ServerScriptService, "Folder", "Scooter")
local sharedFolder = make(services.ReplicatedStorage, "Folder", "Shared")
local configModule = make(sharedFolder, "ModuleScript", "ScooterConfig")
configModule._values._path = "ReplicatedStorage/Shared/ScooterConfig"
local sharedScooterFolder = make(sharedFolder, "Folder", "Scooter")
local sharedConfigModule = make(sharedScooterFolder, "ModuleScript", "ScooterConfig")
sharedConfigModule._values._path = "ReplicatedStorage/Shared/Scooter/ScooterConfig"
for _, name in { "ScooterCollision", "ScooterSuspension", "ScooterRigGeometry", "ScooterRig", "DevScooterAssembler" } do
	local module = make(serverFolder, "ModuleScript", name)
	module._values._path = "ServerScriptService/Scooter/" .. name
end
baseEnvironment.workspace = InstanceMock.new("Workspace")
source.Parent = baseEnvironment.workspace
local canonicalAssemblerPath = "ServerScriptService/Scooter/DevScooterAssembler"
moduleCache[canonicalAssemblerPath] = {
	AssembleFromSelection = function() error("Missing selected BasePart named Fork") end,
}
local priorTemplateName = Config.TemplateName
Config.TemplateName = nil
local Workflow = loadModule("ServerScriptService/Scooter/ScooterWorkflow")
local installed = Workflow.Assemble()
check(installed.Name == "scooter", "Workflow bypasses stale assembler and configuration caches")
check(installed.Parent == services.ServerStorage.ScooterModels, "Workflow installs prepared template")
check(source.Parent == services.ServerStorage, "Source moves out of live Workspace after installation")
check(#services.ServerScriptService:GetChildren() == 1, "Workflow destroys temporary modules after success")
local repeatInstall = Workflow.Assemble()
check(repeatInstall ~= installed and installed.Parent == nil, "Cached wrapper reloads fresh modules on each invocation")
local badRigModule = serverFolder.ScooterRig
badRigModule.Parent = nil
check(not pcall(Workflow.Assemble), "Workflow rejects missing unsynchronized rig module")
check(#services.ServerScriptService:GetChildren() == 1, "Workflow destroys temporary modules after failure")
check(repeatInstall.Parent == services.ServerStorage.ScooterModels, "Reload failure preserves installed template")
Config.TemplateName = priorTemplateName

print(string.format("PASS: %d rig/animation assertions", testCount - before))
