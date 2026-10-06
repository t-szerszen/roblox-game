--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local AnimationMath = require(ReplicatedStorage.Shared.Scooter.ScooterAnimationMath)

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

type LimbDefinition = {
	chainRoot: string,
	endEffector: string,
	target: string,
	poleSide: number?,
}

export type Controller = {
	Update: (self: Controller, deltaTime: number) -> (),
	SetAuthoredLegWeight: (self: Controller, weight: number) -> (),
	SetSolvedLimbs: (self: Controller, limbs: { [string]: boolean }) -> (),
	GetTargets: (self: Controller) -> { [string]: Attachment },
	GetPoles: (self: Controller) -> { [string]: Attachment },
	Destroy: (self: Controller) -> (),
}

local LIMBS: { [string]: LimbDefinition } = {
	LeftFoot = {
		chainRoot = "LeftUpperLeg",
		endEffector = "LeftFoot",
		target = "LeftFootPlant",
		poleSide = -1,
	},
	RightFoot = {
		chainRoot = "RightUpperLeg",
		endEffector = "RightFoot",
		target = "RightFootPlant",
		poleSide = 1,
	},
}

local ScooterRiderPose = {}

local function findPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

function ScooterRiderPose.Start(character: Model, scooter: Model, preserveAnimations: { [string]: boolean }?): Controller?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = scooter.PrimaryPart
	if not humanoid or not root then
		return nil
	end

	local created: { Instance } = {}
	local targets: { [string]: Attachment } = {}
	local footControls: { IKControl } = {}
	local solvedLimbs: { [string]: boolean } = {}
	local poles: { [string]: Attachment } = {}
	local motorTransforms: { [Motor6D]: CFrame } = {}
	local animateScript = character:FindFirstChild("Animate")
	local animateWasDisabled: boolean? = nil
	if animateScript and animateScript:IsA("LocalScript") then
		animateWasDisabled = animateScript.Disabled
		animateScript.Disabled = true
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			local animation = track.Animation
			if not animation or not preserveAnimations or not preserveAnimations[animation.AnimationId] then
				track:Stop(0.1)
			end
		end
	end

	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		for limbName, definition in LIMBS do
			local source = scooter:FindFirstChild(definition.target, true)
			local chainRoot = findPart(character, definition.chainRoot)
			local endEffector = findPart(character, definition.endEffector)
			if not source or not source:IsA("Attachment") or not chainRoot or not endEffector then
				for _, instance in created do
					instance:Destroy()
				end
				if animateScript and animateScript:IsA("LocalScript") and animateWasDisabled ~= nil then
					animateScript.Disabled = animateWasDisabled
				end
				return nil
			end

			local target = Instance.new("Attachment")
			target.Name = string.format("Local%sTarget", limbName)
			-- FootPlant marks the sole contact point; IK targets the foot center.
			local endEffectorOffset = if string.find(limbName, "Foot")
				then endEffector.Size.Y * 0.5 - ScooterConfig.RiderPose.FootTargetSink
				else 0
			target.CFrame = root.CFrame:ToObjectSpace(source.WorldCFrame) * CFrame.new(0, endEffectorOffset, 0)
			target.Parent = root
			targets[limbName] = target
			table.insert(created, target)

			local control = Instance.new("IKControl")
			control.Name = string.format("Scooter%sIK", limbName)
			local isFoot = definition.poleSide ~= nil
			control.Type = if isFoot then Enum.IKControlType.Transform else Enum.IKControlType.Position
			control.ChainRoot = chainRoot
			control.EndEffector = endEffector
			control.Target = target
			control.Priority = 100
			control.SmoothTime = 0
			control.Weight = 1
			local poleSide = definition.poleSide
			if poleSide then
				local lowerLeg = findPart(character, if poleSide < 0 then "LeftLowerLeg" else "RightLowerLeg")
				if lowerLeg then
					local pole = Instance.new("Attachment")
					pole.Name = string.format("Local%sPole", limbName)
					local poleWorldPosition = lowerLeg.Position
						+ root.CFrame.RightVector * poleSide * 0.25
						+ root.CFrame.LookVector * 2
					pole.Position = root.CFrame:PointToObjectSpace(poleWorldPosition)
					pole.Parent = root
					control.Pole = pole
					poles[limbName] = pole
					table.insert(created, pole)
				end
			end
			control.Parent = humanoid
			table.insert(footControls, control)
			table.insert(created, control)
		end
	else
		for _, motorName in { "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" } do
			local motor = character:FindFirstChild(motorName, true)
			if motor and motor:IsA("Motor6D") then
				motorTransforms[motor] = motor.Transform
			end
		end
	end

	local leftFootBase = if targets.LeftFoot then targets.LeftFoot.CFrame else CFrame.identity
	local rightFootBase = if targets.RightFoot then targets.RightFoot.CFrame else CFrame.identity
	if targets.RightFoot then
		rightFootBase *= CFrame.new(0, 0, -ScooterConfig.RiderPose.RightFootForwardShift)
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character, scooter }
	groundParams.RespectCanCollide = true
	local idleState: AnimationMath.LegState? = nil
	local idleBlend = 0
	local probeElapsed = math.huge
	local groundFrame: CFrame? = nil
	local wheelieBlend = 0
	local elapsed = 0
	local destroyed = false

	local controller = {} :: any
	function controller:SetSolvedLimbs(limbs: { [string]: boolean }) solvedLimbs = limbs end
	function controller:GetTargets(): { [string]: Attachment } return targets end
	function controller:GetPoles(): { [string]: Attachment } return poles end

	function controller:SetAuthoredLegWeight(weight: number)
		if destroyed then return end
		local ikWeight = 1 - math.clamp(weight, 0, 1)
		for _, control in footControls do
			control.Weight = ikWeight
			-- Zero Weight alone still lets the pole influence the authored pose.
			local effector = control.EndEffector
			control.Enabled = ikWeight > 0.001 and not (effector and solvedLimbs[effector.Name])
		end
	end

	function controller:Update(deltaTime: number)
		if destroyed or scooter.Parent == nil or character.Parent == nil then
			return
		end

		elapsed += deltaTime
		local wheelieTarget = if scooter:GetAttribute("WheelieActive") == true then 1 else 0
		local blendStep = 1 - math.exp(-ScooterConfig.RiderPose.BlendSpeed * deltaTime)
		wheelieBlend += (wheelieTarget - wheelieBlend) * blendStep

		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			local settings = ScooterConfig.RiderPose
			local speed = scooter:GetAttribute("SpeedKmh")
			idleState = AnimationMath.GetLegState(idleState, if typeof(speed) == "number" then speed else math.huge,
				wheelieTarget > 0, scooter:GetAttribute("Fallen") ~= true and scooter:GetAttribute("DriveState") ~= "Airborne")
			local idleTarget = if idleState == "IDLE" then 1 else 0
			idleBlend += (idleTarget - idleBlend) * blendStep
			probeElapsed += deltaTime
			if idleTarget > 0 and probeElapsed >= settings.IdleProbeInterval then
				probeElapsed = 0
				local location = root.CFrame:PointToWorldSpace(Vector3.new(-settings.IdleFootSideOffset, leftFootBase.Position.Y, leftFootBase.Position.Z))
				local hit = Workspace:Raycast(location + Vector3.yAxis * settings.IdleProbeLift,
					-Vector3.yAxis * settings.IdleProbeDepth, groundParams)
				local foot = findPart(character, "LeftFoot")
				groundFrame = nil
				if hit and foot and hit.Normal.Y > 0.35 then
					local up = hit.Normal
					local forward = root.CFrame.LookVector - up * root.CFrame.LookVector:Dot(up)
					if forward.Magnitude > 0.01 then
						groundFrame = CFrame.fromMatrix(hit.Position + up * (foot.Size.Y * 0.5 - settings.FootTargetSink),
							forward.Unit:Cross(up), up)
					end
				end
			end
			local phase = elapsed * settings.BalanceFootFrequency
			local swing = settings.BalanceFootSwing
			local balanceOffset = settings.BalanceFootOffset
				+ Vector3.new(math.sin(phase) * swing.X, (1 - math.cos(phase * 2)) * 0.5 * swing.Y, math.sin(phase) * swing.Z)
			local leftPose = leftFootBase:Lerp(leftFootBase * CFrame.new(balanceOffset), wheelieBlend)
			local desired = root.CFrame * leftPose
			if groundFrame then desired = desired:Lerp(groundFrame, idleBlend) end
			targets.LeftFoot.WorldCFrame = targets.LeftFoot.WorldCFrame:Lerp(desired, blendStep)
			targets.RightFoot.CFrame = targets.RightFoot.CFrame:Lerp(rightFootBase, blendStep)
		else
			for motor in motorTransforms do
				if motor.Name == "Left Shoulder" then
					motor.Transform = CFrame.Angles(math.rad(72), 0, math.rad(-8))
				elseif motor.Name == "Right Shoulder" then
					motor.Transform = CFrame.Angles(math.rad(72), 0, math.rad(8))
				elseif motor.Name == "Left Hip" then
					motor.Transform = CFrame.Angles(math.sin(elapsed * ScooterConfig.RiderPose.BalanceFootFrequency) * math.rad(40) * wheelieBlend, 0, math.rad(-4))
				else
					motor.Transform = CFrame.Angles(0, 0, math.rad(4))
				end
			end
		end
	end

	function controller:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, instance in created do
			instance:Destroy()
		end
		for motor, transform in motorTransforms do
			if motor.Parent then
				motor.Transform = transform
			end
		end
		if animateScript and animateScript:IsA("LocalScript") and animateWasDisabled ~= nil then
			animateScript.Disabled = animateWasDisabled
		end
		table.clear(created)
		table.clear(motorTransforms)
		table.clear(targets)
		table.clear(poles)
		table.clear(footControls)
	end

	return controller :: Controller
end

return ScooterRiderPose
