--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local AnimationMath = require(ReplicatedStorage.Shared.Scooter.ScooterAnimationMath)
local RiderPose = require(script.Parent.ScooterRiderPose)

export type Animator = {
	mount: (character: Model) -> boolean,
	dismount: () -> (),
	getState: () -> AnimationMath.LegState?,
}

type Arm = { pole: Attachment, side: number, base: Vector3 }

local ScooterAnimator = {}

local function findMotor(character: Model, name: string): Motor6D?
	local instance = character:FindFirstChild(name, true)
	return if instance and instance:IsA("Motor6D") then instance else nil
end

local function animationId(value: string): string?
	if string.match(value, "^[1-9]%d*$") then return "rbxassetid://" .. value end
	return if string.match(value, "^rbxassetid://[1-9]%d*$") then value else nil
end

function ScooterAnimator.new(scooter: Model): Animator
	local connections: { RBXScriptConnection } = {}
	local created: { Instance } = {}
	local transforms: { [Motor6D]: CFrame } = {}
	local arms: { Arm } = {}
	local pose: RiderPose.Controller? = nil
	local lean = 0
	local mounted = false
	local state: AnimationMath.LegState? = nil
	local tracks: { [string]: AnimationTrack } = {}
	local ownsTracks = false
	local animator = {} :: Animator

	function animator.getState(): AnimationMath.LegState?
		return state
	end

	local function refreshState()
		local speed = scooter:GetAttribute("SpeedKmh")
		local driveState = scooter:GetAttribute("DriveState")
		local fallen = scooter:GetAttribute("Fallen") == true or driveState == "Fallen"
		local nextState: AnimationMath.LegState = AnimationMath.GetLegState(state, if typeof(speed) == "number" then speed else math.huge,
			scooter:GetAttribute("WheelieActive") == true and not fallen,
			not fallen and driveState ~= "Airborne")
		if state == nextState then return end
		state = nextState
		if not ownsTracks then return end
		local settings = Config.RiderAnimations
		for trackState, track in tracks do
			if trackState ~= state and track.IsPlaying then track:Stop(settings.FadeTime) end
		end
		local nextTrack = tracks[nextState]
		if nextTrack then
			local success, problem = pcall(function()
				nextTrack:Play(settings.FadeTime, settings.Weight, settings.PlaybackSpeed)
			end)
			if not success then
				warn("ScooterAnimator: " .. tostring(problem))
				nextTrack:Destroy()
				tracks[nextState] = nil
			end
		end
	end

	function animator.dismount()
		mounted = false
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		if ownsTracks then
			for _, track in tracks do track:Stop(0); track:Destroy() end
		end
		table.clear(tracks)
		ownsTracks = false
		state = nil
		for _, instance in created do instance:Destroy() end
		table.clear(created)
		if pose then pose:Destroy(); pose = nil end
		for motor, transform in transforms do
			if motor.Parent then motor.Transform = transform end
		end
		table.clear(transforms)
		table.clear(arms)
		lean = 0
	end

	function animator.mount(character: Model): boolean
		animator.dismount()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = scooter.PrimaryPart
		local handleBar = scooter:FindFirstChild("HandleBar")
		if not humanoid or humanoid.Health <= 0 or not root or not handleBar or not handleBar:IsA("MeshPart") then
			return false
		end
		local owner = Players:GetPlayerFromCharacter(character)
		if humanoid.RigType == Enum.HumanoidRigType.R15 and owner
			and not humanoid:FindFirstChildOfClass("Animator") then
			-- A client-created Animator cannot replicate tracks; the binding retries streamed descendants.
			return false
		end
		local waist = findMotor(character, "Waist")
		local rootJoint = findMotor(character, "RootJoint") or findMotor(character, "Root")
		for _, motor in { waist, rootJoint } do
			if motor then transforms[motor] = motor.Transform end
		end
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			-- IK requires an Animator. It stays on the character after this mount.
			if not humanoid:FindFirstChildOfClass("Animator") then
				local characterAnimator = Instance.new("Animator")
				characterAnimator.Parent = humanoid
			end
			for _, sideName in { "Left", "Right" } do
				local upperArm = character:FindFirstChild(sideName .. "UpperArm")
				local hand = character:FindFirstChild(sideName .. "Hand")
				local grip = handleBar:FindFirstChild(sideName .. "HandGrip")
				if not upperArm or not upperArm:IsA("BasePart") or not hand or not hand:IsA("BasePart")
					or not grip or not grip:IsA("Attachment") then
					animator.dismount()
					return false
				end
				local side = if sideName == "Left" then -1 else 1
				local pole = Instance.new("Attachment")
				pole.Name = "Scooter" .. sideName .. "ElbowPole"
				local base = root.CFrame:PointToObjectSpace(upperArm.Position)
					+ Vector3.new(side * Config.RiderPose.ElbowOutwardOffset, 0, -Config.RiderPose.ElbowForwardOffset)
				pole.Position = base
				pole.Parent = root
				table.insert(created, pole)
				table.insert(arms, { pole = pole, side = side, base = base })
				local control = Instance.new("IKControl")
				control.Name = "Scooter" .. sideName .. "HandIK"
				control.Type = Enum.IKControlType.Position
				control.ChainRoot = upperArm
				control.EndEffector = hand
				control.Target = grip
				control.Pole = pole
				control.Priority = 100
				control.SmoothTime = 0
				control.Weight = 1
				control.Parent = humanoid
				table.insert(created, control)
			end
		end
		local ids: { [string]: string } = {}
		local preserveAnimations: { [string]: boolean } = {}
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			-- The owner plays once; observers consume replicated tracks rather than layering duplicates.
			ownsTracks = owner == nil or owner == Players.LocalPlayer
			local clips: { [string]: string } = { IDLE = Config.RiderAnimations.IdleFootAnim, WHEELIE = Config.RiderAnimations.WheelieBalanceAnim }
			for clipState, configuredId in clips do
				local id = animationId(configuredId)
				if id then
					ids[clipState] = id
					if not ownsTracks then preserveAnimations[id] = true end
				end
			end
		end
		pose = RiderPose.Start(character, scooter, preserveAnimations)
		if not pose then animator.dismount(); return false end
		local characterAnimator = humanoid:FindFirstChildOfClass("Animator")
		if humanoid.RigType == Enum.HumanoidRigType.R15 and characterAnimator then
			for clipState, id in ids do
				if not ownsTracks then continue end
				local animation = Instance.new("Animation")
				animation.Name = if clipState == "IDLE" then "IdleFootAnim" else "WheelieBalanceAnim"
				animation.AnimationId = id
				table.insert(created, animation)
				local success, track = pcall(function() return characterAnimator:LoadAnimation(animation) end)
				if success then
					track.Looped = true
					track.Priority = Enum.AnimationPriority.Action
					tracks[clipState] = track
				else
					warn("ScooterAnimator: " .. tostring(track))
				end
			end
			if not ownsTracks then
				local function observeTrack(track: AnimationTrack)
					local animation = track.Animation
					if not animation then return end
					for clipState, id in ids do
						if animation.AnimationId == id then tracks[clipState] = track end
					end
				end
				for _, track in characterAnimator:GetPlayingAnimationTracks() do observeTrack(track) end
				table.insert(connections, characterAnimator.AnimationPlayed:Connect(observeTrack))
			end
		end
		mounted = true
		for _, attribute in { "SpeedKmh", "WheelieActive", "DriveState", "Fallen" } do
			table.insert(connections, scooter:GetAttributeChangedSignal(attribute):Connect(refreshState))
		end
		refreshState()
		table.insert(connections, humanoid.Died:Connect(animator.dismount))
		table.insert(connections, character.Destroying:Connect(animator.dismount))
		table.insert(connections, scooter.Destroying:Connect(animator.dismount))
		table.insert(connections, handleBar.Destroying:Connect(animator.dismount))
		table.insert(connections, root.Destroying:Connect(animator.dismount))
		table.insert(connections, character.AncestryChanged:Connect(function()
			if character.Parent == nil then animator.dismount() end
		end))
		table.insert(connections, RunService.PreAnimation:Connect(function(deltaTime: number)
			if not mounted then return end
			-- Remove our previous layer before the Animator evaluates, avoiding cumulative lean.
			for motor in transforms do
				if motor.Parent then motor.Transform = CFrame.identity end
			end
			local velocity = root.AssemblyLinearVelocity
			local angleAttribute = scooter:GetAttribute("SteeringAngle")
			local angle = if typeof(angleAttribute) == "number" then angleAttribute else 0
			local desiredLean = AnimationMath.Lean(
				velocity:Dot(root.CFrame.LookVector), velocity:Dot(root.CFrame.RightVector), angle
			)
			local alpha = 1 - math.exp(-Config.RiderPose.BlendSpeed * math.clamp(deltaTime, 0, 0.1))
			lean += (desiredLean - lean) * alpha
			local steering = math.clamp(angle / Config.MaxHandlebarAngle, -1, 1)
			for _, arm in arms do
				-- A pole lifts the elbow while leaving the hand under the IK solver's control.
				local lift = math.max(0, steering * arm.side) * Config.RiderPose.ElbowLift
				arm.pole.Position = arm.base + Vector3.yAxis * lift
			end
			if pose then
				local authoredWeight = 0
				for _, track in tracks do
					-- Stop begins a fade; its remaining weight still affects legs after playback stops.
					if track.Length > 0 then authoredWeight += track.WeightCurrent end
				end
				pose:SetAuthoredLegWeight(authoredWeight)
				pose:Update(deltaTime)
			end
		end))
		table.insert(connections, RunService.PreSimulation:Connect(function()
			if not mounted then return end
			local rootShare = if waist then Config.RiderPose.RootLeanShare else 1
			if rootJoint and rootJoint.Parent then
				rootJoint.Transform = rootJoint.Transform * CFrame.Angles(0, 0, lean * rootShare)
			end
			if waist and waist.Parent then
				waist.Transform = waist.Transform * CFrame.Angles(0, 0, lean * (if rootJoint then 1 - rootShare else 1))
			end
		end))
		return true
	end
	return animator
end

return ScooterAnimator
