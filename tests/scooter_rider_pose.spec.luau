local start = testCount
local Solver = loadModule("StarterPlayer/StarterPlayerScripts/ScooterLimbSolver")
local origin, goal, pole = Vector.zero, Vector.new(0, -2, 0), Vector.new(0, -1, -2)
local knee, finish = Solver.Knee(origin, goal, pole, 1.5, 1.5)
near((knee - origin).Magnitude, 1.5, "The upper limb retains its length")
near((finish - knee).Magnitude, 1.5, "The lower limb retains its length")
near((finish - goal).Magnitude, 0, "A reachable limb reaches its target")
check(knee.Z < 0, "The pole bends the knee forward")
local farKnee, farEnd = Solver.Knee(origin, Vector.new(0, -20, 0), pole, 1.5, 1)
near((farKnee - origin).Magnitude, 1.5, "Unreachable goals do not lengthen the upper segment")
near((farEnd - farKnee).Magnitude, 1, "Unreachable goals do not lengthen the lower segment")
check(farEnd.Magnitude < 2.5, "Unreachable targets clamp inside the chain's reach")
local nearKnee, nearEnd = Solver.Knee(origin, origin, origin, 1.5, 1)
check(nearKnee.Magnitude == nearKnee.Magnitude and nearEnd.Magnitude > 0.5,
	"Coincident targets and collinear poles produce a finite solution")
local Physics = loadModule("ReplicatedStorage/Shared/Scooter/ScooterPhysics")
local forward = Vector.new(0, 0, -1)
local tangent = Vector.new(0, 0.7, -0.7).Unit
local fast = Physics.ComputeStepForce(tangent, forward * 70, 60, 196.2, 60)
near(fast:Dot(forward), 0, "Step assistance never brakes a fast approach horizontally")
local recover = Physics.ComputeStepForce(tangent, forward * 15, 60, 196.2, 60)
check(recover:Dot(forward) > 0, "A contacted ledge recovers lost entry momentum")
local capped = Physics.ComputeStepForce(tangent, forward * 60, 60, 196.2, 55)
near(capped:Dot(forward), 0, "Assistance does not accelerate beyond the server speed target")

for _, className in { "Motor6D", "AnimationConstraint" } do
	local character = make(services.Workspace, "Model", "Reach" .. className)
	local torso = make(character, "Part", "UpperTorso")
	local upper = make(character, "Part", "RightUpperArm")
	local lower = make(character, "Part", "RightLowerArm")
	local hand = make(character, "Part", "RightHand")
	upper.Size, lower.Size = Vector.new(1, 2, 1), Vector.new(1, 2, 1)
	local function joint(name, first, second, c0, c1)
		local j = make(second, className, name)
		if className == "Motor6D" then
			j.Part0, j.Part1, j.C0, j.C1 = first, second, c0, c1
		else
			j.Attachment0 = make(first, "Attachment", name .. "Origin")
			j.Attachment1 = make(second, "Attachment", name .. "Tip")
			j.Attachment0.CFrame, j.Attachment1.CFrame = c0, c1
		end
		return j
	end
	local shoulder = joint("RightShoulder", torso, upper, Frame.new(1, 1, 0), Frame.new(0, 0.5, 0))
	local elbow = joint("RightElbow", upper, lower, Frame.new(0.2, -0.5, 0), Frame.new(0, 0.5, 0))
	local wrist = joint("RightWrist", lower, hand, Frame.new(-0.1, -0.5, 0.15), Frame.new(0, 0.25, 0))
	local target = make(torso, "Attachment", "Target")
	target.CFrame = Frame.new(1, -0.5, -0.8)
	local controller = Solver.Start(character)
	check(controller.HasLimb("RightHand") and not controller.HasLimb("LeftHand"),
		className .. " discovers only complete chains")
	controller.Apply(torso.CFrame, nil, { RightHand = target }, {}, true)
	local upperPose = Solver.JointPose(shoulder, torso.CFrame)
	local lowerPose = Solver.JointPose(elbow, upperPose)
	local handPose = Solver.JointPose(wrist, lowerPose)
	near((handPose.Position - target.WorldPosition).Magnitude, 0,
		className .. " reaches a nearby grip without changing joint lengths")
	for _, joint in { shoulder, elbow, wrist } do
		near(joint.Transform.Position.Magnitude, 0, className .. " never translates joints while riding")
	end
	target.CFrame = Frame.new(1, -20, -0.8)
	controller.Apply(torso.CFrame, nil, { RightHand = target }, {}, true)
	for _, joint in { shoulder, elbow, wrist } do
		near(joint.Transform.Position.Magnitude, 0, className .. " clamps distant targets instead of stretching")
	end
	controller.Destroy()
	near(shoulder.Transform.Position.Magnitude, 0, className .. " restores the original pose on cleanup")
	controller.Destroy()
	character:Destroy()
end


local characterConfigModule = make(services.ReplicatedStorage.Shared, "ModuleScript", "CharacterConfig")
characterConfigModule._values._path = "ReplicatedStorage/Shared/CharacterConfig"
local CharacterConfig = loadModule("ReplicatedStorage/Shared/CharacterConfig")
local Proportions = loadModule("ServerScriptService/Characters/CharacterProportions")
for _, className in { "Motor6D", "AnimationConstraint" } do
	local character = make(services.Workspace, "Model", "Proportions" .. className)
	local humanoid = make(character, "Humanoid", "Humanoid")
	humanoid.RigType, humanoid.HipHeight = enumMock.HumanoidRigType.R15, 1
	local original = {}
	local joints = {}
	for _, side in { "Left", "Right" } do
		local upper = make(character, "MeshPart", side .. "UpperLeg")
		local lower = make(character, "MeshPart", side .. "LowerLeg")
		local foot = make(character, "MeshPart", side .. "Foot")
		upper.Size, lower.Size = Vector.new(1, 2, 1), Vector.new(1, 2, 1)
		for _, definition in { { upper, lower, "Hip", "Knee" }, { lower, foot, "Knee", "Ankle" } } do
			local first, second, topName, name = unpack(definition)
			local top = make(first, "Attachment", side .. topName .. "RigAttachment")
			top.Position = Vector.new(0, 0.5, 0)
			local source = make(first, "Attachment", side .. name .. "RigAttachment")
			source.Position = Vector.new(0, -0.5, 0)
			original[source] = source.CFrame
			local child = make(second, "Attachment", side .. name .. "Tip")
			local joint = make(second, className, side .. name)
			if className == "Motor6D" then
				joint.Part0, joint.Part1, joint.C0, joint.C1 = first, second, source.CFrame, child.CFrame
			else
				joint.Attachment0, joint.Attachment1 = source, child
				local socket = make(second, "BallSocketConstraint", side .. name .. "Socket")
				socket.Attachment0, socket.Attachment1 = source, child
			end
			table.insert(joints, { joint = joint, top = top, size = first.Size })
		end
	end
	check(Proportions.Apply(character), className .. " calibrates both complete legs")
	near(humanoid.HipHeight, 1 + 2 * (2 * CharacterConfig.LegBoneLengthFraction - 1),
		className .. " keeps feet at walking ground height after constant extension")
	local count = #character:GetDescendants()
	check(Proportions.Apply(character) and #character:GetDescendants() == count,
		className .. " does not extend again on repeated appearance events")
	for _, item in joints do
		local joint = item.joint
		local frame = if className == "Motor6D" then joint.C0 else joint.Attachment0.CFrame
		near((frame.Position - item.top.Position).Magnitude, 2 * CharacterConfig.LegBoneLengthFraction,
			className .. " sets permanent rest-bone length")
		near((item.top.Parent.Size - item.size).Magnitude, 0, "Proportions preserve the rectangular mesh size")
		if className == "AnimationConstraint" then
			local socket = joint.Parent:FindFirstChild(joint.Name .. "Socket")
			check(socket.Attachment0 == joint.Attachment0, "Physical fallback sockets use the same calibrated rest origin")
		end
	end
	for attachment, frame in original do
		if className == "AnimationConstraint" then
			near((attachment.CFrame.Position - frame.Position).Magnitude, 0,
				"Original RigAttachment metadata remains intact")
		end
	end
	character:Destroy()
end
local RiderPose = loadModule("StarterPlayer/StarterPlayerScripts/ScooterRiderPose")
local scooter = make(services.Workspace, "Model", "FootStateFixture")
local root = make(scooter, "Part", "Root")
scooter.PrimaryPart = root
for _, side in { "Left", "Right" } do
	local source = make(root, "Attachment", side .. "FootPlant")
	source.Position = Vector.new(if side == "Left" then -0.4 else 0.4, 0, 0)
end
local character = make(services.Workspace, "Model", "FootStateRider")
local humanoid = make(character, "Humanoid", "Humanoid")
humanoid.RigType = enumMock.HumanoidRigType.R15
for _, side in { "Left", "Right" } do
	for _, suffix in { "UpperLeg", "LowerLeg", "Foot" } do make(character, "Part", side .. suffix) end
end
local pose = RiderPose.Start(character, scooter)
scooter:SetAttribute("SpeedKmh", 20)
scooter:SetAttribute("WheelieActive", true)
local minZ, maxZ = math.huge, -math.huge
for _ = 1, 180 do
	pose:Update(1 / 60)
	local z = pose:GetTargets().LeftFoot.Position.Z
	minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
end
check(maxZ - minZ > 2.5, "Left foot balances with a large smooth fore/aft sweep")
near(pose:GetTargets().RightFoot.Position.Z, -Config.RiderPose.RightFootForwardShift, "Right foot stays planted during wheelie")
local savedRaycast = services.Workspace.Raycast
local rayCount = 0
services.Workspace.Raycast = function(_, origin)
	rayCount += 1
	return { Position = Vector.new(origin.X, -2, origin.Z), Normal = Vector.yAxis }
end
scooter:SetAttribute("WheelieActive", false)
scooter:SetAttribute("SpeedKmh", 0)
for _ = 1, 120 do pose:Update(1 / 60) end
near(pose:GetTargets().LeftFoot.WorldPosition.Y, -2 + character.LeftFoot.Size.Y * 0.5 - Config.RiderPose.FootTargetSink,
	"Idle left sole follows the sampled road")
check(rayCount < 35, "Idle ground sampling is throttled instead of raycasting each frame")
local target = pose:GetTargets().LeftFoot
pose:Destroy()
pose:Destroy()
check(target.Parent == nil, "Foot targets are removed on dismount")
services.Workspace.Raycast = savedRaycast
character:Destroy()
scooter:Destroy()


local FirstPerson = loadModule("StarterPlayer/StarterPlayerScripts/ScooterFirstPerson")
local previousPlayer, previousWorkspace = playersService.LocalPlayer, baseEnvironment.workspace
baseEnvironment.workspace = services.Workspace
local camera = { CFrame = Frame.identity }
services.Workspace.CurrentCamera = camera
local character = make(services.Workspace, "Model", "FirstPersonFixture")
local head = make(character, "Part", "Head")
local hand = make(character, "Part", "LeftHand")
hand.LocalTransparencyModifier = 0.75
playersService.LocalPlayer = { UserId = 999, Character = character }
enumMock.RenderPriority = { Camera = { Value = 200 } }
local bindings = {}
function services.RunService:BindToRenderStep(name, _, callback) bindings[name] = callback end
function services.RunService:UnbindFromRenderStep(name) bindings[name] = nil end
local view = FirstPerson.Start(character)
local callback = bindings.ScooterFirstPersonArms_999
callback()
near(hand.LocalTransparencyModifier, 0, "First person displays the existing posed hand")
camera.CFrame = Frame.new(0, 0, 10)
callback()
near(hand.LocalTransparencyModifier, 0.75, "Third person restores the previous local visibility")
view.Destroy()
view.Destroy()
check(next(bindings) == nil, "Dismount removes the first-person render callback")
playersService.LocalPlayer, baseEnvironment.workspace = previousPlayer, previousWorkspace
services.Workspace.CurrentCamera = nil
character:Destroy()

print(string.format("PASS: %d rider reach and momentum assertions (%d total)", testCount - start, testCount))
