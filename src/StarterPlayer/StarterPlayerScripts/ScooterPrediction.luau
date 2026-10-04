--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local DashboardConfig = require(ReplicatedStorage.Shared.Scooter.ScooterDashboardConfig)
local Dashboard = require(ReplicatedStorage.Shared.Scooter.ScooterDashboard)

export type Input = {
	throttleHeld: boolean,
	brakeHeld: boolean,
	steering: number,
	wheelieHeld: boolean,
}

export type Controller = {
	Step: (self: Controller, deltaTime: number, input: Input) -> (),
	BeforeCamera: (self: Controller) -> (),
	Render: (self: Controller) -> (),
	Reset: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type Visual = {
	part: BasePart,
	originalTransparency: number,
	displayTransparency: number,
	dashboard: Dashboard.Controller?,
}

local ScooterPrediction = {}

-- Clone only the requested instance. Descendants are admitted individually;
-- scripts, joints, seats, humanoids and gameplay objects never enter the proxy.
local function cloneShallow(source: Instance): Instance?
	local saved: { [Instance]: boolean } = {}
	for _, child in source:GetChildren() do
		saved[child] = child.Archivable
		child.Archivable = false
	end
	local wasArchivable = source.Archivable
	source.Archivable = true
	local clone = source:Clone()
	source.Archivable = wasArchivable
	for child, archivable in saved do
		child.Archivable = archivable
	end
	return clone
end

local function copyAppearance(source: Instance, destination: Instance)
	for _, child in source:GetChildren() do
		if child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then
			local copy = cloneShallow(child)
			if copy then
				copy.Parent = destination
			end
		end
	end
end

function ScooterPrediction.Start(scooter: Model, root: BasePart, character: Model): Controller
	local container = Instance.new("Model")
	container.Name = "LocalScooterPresentation"
	local avatar = Instance.new("Model")
	avatar.Name = "RiderPresentation"
	avatar.Parent = container
	local appearanceHumanoid = Instance.new("Humanoid")
	local originalHumanoid = character:FindFirstChildOfClass("Humanoid")
	appearanceHumanoid.RigType = if originalHumanoid then originalHumanoid.RigType else Enum.HumanoidRigType.R15
	-- A fresh, inert humanoid is needed only for classic clothing rendering.
	appearanceHumanoid.EvaluateStateMachine = false
	appearanceHumanoid.AutomaticScalingEnabled = false
	appearanceHumanoid.RequiresNeck = false
	appearanceHumanoid.BreakJointsOnDeath = false
	appearanceHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	appearanceHumanoid.Parent = avatar
	for _, instance in character:GetChildren() do
		if instance:IsA("Clothing") or instance:IsA("ShirtGraphic") or instance:IsA("BodyColors") then
			local copy = cloneShallow(instance)
			if copy then
				copy.Parent = avatar
			end
		end
	end

	local proxy = Instance.new("Part")
	proxy.Name = "PredictionRoot"
	proxy.Size = root.Size
	proxy.Transparency = 1
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = false
	proxy.CFrame = root.CFrame
	proxy.CustomPhysicalProperties = root.CustomPhysicalProperties
	proxy.Parent = container
	container.PrimaryPart = proxy

	local attachment = Instance.new("Attachment")
	attachment.Parent = proxy
	local force = Instance.new("VectorForce")
	force.Name = "PredictedDriveForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Parent = proxy
	local torque = Instance.new("Torque")
	torque.Name = "PredictedUprightTorque"
	torque.Attachment0 = attachment
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Parent = proxy
	container.Parent = Workspace
	proxy.AssemblyLinearVelocity = root.AssemblyLinearVelocity
	proxy.AssemblyAngularVelocity = root.AssemblyAngularVelocity

	local visuals: { [BasePart]: Visual } = {}
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local smoothedSteering = 0
	local desiredForward = ScooterPhysics.ProjectOntoPlane(root.CFrame.LookVector, Vector3.yAxis)
	desiredForward = if desiredForward.Magnitude > 0.01 then desiredForward.Unit else Vector3.new(0, 0, -1)
	local wheeliePitch = 0
	local wheelieActive = false
	local lastWheelieAt = -math.huge
	local groundUp = Vector3.yAxis
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { scooter, character, container }
	groundParams.RespectCanCollide = true
	local cameraOffset = Vector3.zero
	local offsetCamera: Camera? = nil
	local lastCameraCFrame: CFrame? = nil

	local function addDashboard(instance: Instance)
		local source: Instance? = instance
		while source and not source:IsA("BasePart") do source = source.Parent end
		if not source or not source:IsA("BasePart") or source.Name ~= DashboardConfig.ScreenName then return end
		local visual = visuals[source]
		if visual and not visual.dashboard then
			visual.dashboard = Dashboard.CreatePresentation(scooter, source, visual.part)
		end
	end

	local function addVisual(instance: Instance)
		addDashboard(instance)
		if not instance:IsA("BasePart") or instance:IsA("Seat") or instance:IsA("VehicleSeat") or visuals[instance] then
			return
		end
		local copy = cloneShallow(instance)
		if not copy or not copy:IsA("BasePart") then
			return
		end
		copy.Anchored = true
		copy.Massless = true
		copy.CanCollide = false
		copy.CanTouch = false
		copy.CanQuery = false
		copy.LocalTransparencyModifier = instance.LocalTransparencyModifier
		copyAppearance(instance, copy)
		copy.Parent = if instance:IsDescendantOf(character) then avatar else container
		visuals[instance] = {
			part = copy,
			originalTransparency = instance.LocalTransparencyModifier,
			displayTransparency = instance.LocalTransparencyModifier,
			dashboard = nil,
		}
		addDashboard(instance)
		instance.LocalTransparencyModifier = 1
	end

	local function removeVisual(instance: Instance)
		if not instance:IsA("BasePart") then
			local source = instance:FindFirstAncestorWhichIsA("BasePart")
			local visual = if source and source:IsA("BasePart") then visuals[source] else nil
			if visual and visual.dashboard then
				visual.dashboard.Destroy()
				visual.dashboard = nil
			end
			return
		end
		local visual = visuals[instance]
		if visual then
			if visual.dashboard then visual.dashboard.Destroy() end
			instance.LocalTransparencyModifier = visual.originalTransparency
			visual.part:Destroy()
			visuals[instance] = nil
		end
	end

	for _, source in { scooter, character } do
		for _, descendant in source:GetDescendants() do
			addVisual(descendant)
		end
		table.insert(connections, source.DescendantAdded:Connect(addVisual))
		table.insert(connections, source.DescendantRemoving:Connect(removeVisual))
	end

	local controller = {} :: Controller

	function controller:BeforeCamera()
		-- Let the default camera set first-person avatar visibility before hiding
		-- originals again at render time; the presentation copies that visibility.
		for source, visual in visuals do
			if source.Parent then
				source.LocalTransparencyModifier = visual.displayTransparency
			end
		end
		local camera = offsetCamera
		if camera and camera.Parent and camera.CFrame == lastCameraCFrame then
			camera.CFrame -= cameraOffset
			camera.Focus -= cameraOffset
		end
		offsetCamera = nil
		lastCameraCFrame = nil
	end

	function controller:Reset()
		self:BeforeCamera()
		if destroyed then
			return
		end
		proxy.CFrame = root.CFrame
		proxy.AssemblyLinearVelocity = root.AssemblyLinearVelocity
		proxy.AssemblyAngularVelocity = root.AssemblyAngularVelocity
		force.Force = Vector3.zero
		torque.Torque = Vector3.zero
		wheeliePitch = 0
		wheelieActive = false
		smoothedSteering = 0
		cameraOffset = Vector3.zero
		local forward = ScooterPhysics.ProjectOntoPlane(root.CFrame.LookVector, Vector3.yAxis)
		desiredForward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, -1)
	end

	function controller:Step(deltaTime: number, input: Input)
		if destroyed or root.Parent == nil then
			return
		end
		local step = math.clamp(deltaTime, 0, 0.1)
		if (proxy.Position - root.Position).Magnitude > ScooterConfig.PredictionMaxError then
			self:Reset()
		end
		local positionAlpha = 1 - math.exp(-ScooterConfig.PredictionCorrectionRate * step)
		local velocityAlpha = 1 - math.exp(-ScooterConfig.PredictionVelocityCorrectionRate * step)
		proxy.CFrame = proxy.CFrame:Lerp(root.CFrame, positionAlpha)
		proxy.AssemblyLinearVelocity = proxy.AssemblyLinearVelocity:Lerp(root.AssemblyLinearVelocity, velocityAlpha)
		proxy.AssemblyAngularVelocity = proxy.AssemblyAngularVelocity:Lerp(root.AssemblyAngularVelocity, velocityAlpha)
		local canonicalForward = ScooterPhysics.ProjectOntoPlane(root.CFrame.LookVector, Vector3.yAxis)
		if canonicalForward.Magnitude > 0.01 then
			local blended = desiredForward:Lerp(canonicalForward.Unit, positionAlpha)
			if blended.Magnitude > 0.01 then
				desiredForward = blended.Unit
			end
		end

		local modelName = scooter:GetAttribute("ScooterModel")
		local tier = scooter:GetAttribute("SpeedUpgradeTier")
		local tuning = ScooterConfig.GetTuning(
			if typeof(modelName) == "string" then modelName else ScooterConfig.DefaultModel,
			if typeof(tier) == "number" then tier else 0
		)
		if not tuning then
			self:Reset()
			return
		end
		local grounded = scooter:GetAttribute("FrontGrounded") == true or scooter:GetAttribute("RearGrounded") == true
		local driveMode = scooter:GetAttribute("DriveMode")
		local maxSpeed = ScooterConfig.GetDriveModeMaxSpeed(tuning.maxSpeed,
			if typeof(driveMode) == "string" then driveMode else ScooterConfig.DriveModes.Default)
		local fallen = scooter:GetAttribute("Fallen") == true
		local velocity = proxy.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local groundHit = if grounded then Workspace:Raycast(
			root.Position + Vector3.yAxis * ScooterConfig.SuspensionProbeLift,
			-Vector3.yAxis * (root.Size.Y + ScooterConfig.WheelRadius * 2 + ScooterConfig.SuspensionProbeLift),
			groundParams
		) else nil
		local targetGroundUp = if groundHit then groundHit.Normal else Vector3.yAxis
		local groundBlend = groundUp:Lerp(targetGroundUp, 1 - math.exp(-ScooterConfig.GroundNormalSmoothSpeed * step))
		groundUp = if groundBlend.Magnitude > 0.01 then groundBlend.Unit else Vector3.yAxis
		smoothedSteering = ScooterPhysics.SmoothSteering(smoothedSteering, input.steering, step)
		local headingSpeed = velocity:Dot(desiredForward)
		local effectiveSteering = ScooterPhysics.GetEffectiveSteering(smoothedSteering, headingSpeed)
		local turnSteering = ScooterPhysics.GetTurnSteering(effectiveSteering, headingSpeed)
		desiredForward = ScooterPhysics.AdvanceForward(desiredForward, turnSteering, headingSpeed, step)
		local forward = ScooterPhysics.ProjectOntoPlane(desiredForward, groundUp)
		forward = if forward.Magnitude > 0.01 then forward.Unit else desiredForward
		local burnout = input.throttleHeld and input.brakeHeld and speed <= ScooterConfig.BurnoutSmokeMaxSpeed
		local mass = proxy.AssemblyMass
		force.Force = ScooterPhysics.ComputeDriveForce({
			velocity = velocity,
			forward = forward,
			groundUp = groundUp,
			gravity = Workspace.Gravity,
			mass = mass,
			maxSpeed = maxSpeed * ScooterConfig.StudsPerKmH,
			acceleration = tuning.acceleration,
			throttleHeld = input.throttleHeld,
			brakeHeld = input.brakeHeld,
			burnout = burnout,
			grounded = grounded,
			fallen = fallen,
			deltaTime = step,
		}) + (if grounded then Vector3.yAxis * Workspace.Gravity * mass else Vector3.zero)

		local now = os.clock()
		local rearGrounded = scooter:GetAttribute("RearGrounded") == true
		local forwardSpeed = velocity:Dot(forward)
		if input.wheelieHeld and not wheelieActive and not input.brakeHeld and not fallen
			and forwardSpeed > ScooterConfig.WheelieMinSpeed and rearGrounded
			and now - lastWheelieAt >= ScooterConfig.WheelieCooldown
		then
			lastWheelieAt = now
			wheelieActive = true
			wheeliePitch = math.max(wheeliePitch, ScooterConfig.WheelieKickAngle)
		end
		local throttle = (if input.throttleHeld then 1 else 0) - (if input.brakeHeld then 1 else 0)
		if wheelieActive and rearGrounded and forwardSpeed > 0 and not fallen then
			wheeliePitch = ScooterPhysics.AdvanceWheeliePitch(wheeliePitch, throttle, forwardSpeed, step)
			if wheeliePitch <= 0 and scooter:GetAttribute("FrontGrounded") == true then
				wheelieActive = false
			end
		else
			wheelieActive = false
			wheeliePitch = math.max(0, wheeliePitch - ScooterConfig.WheelieStallDropRate * step)
		end
		local target = CFrame.lookAt(Vector3.zero, forward, groundUp)
			* CFrame.Angles(wheeliePitch, 0,
				-effectiveSteering * ScooterConfig.MaxSteeringLean * math.clamp(speed / 22, 0, 1))
		torque.Torque = if fallen then Vector3.zero else ScooterPhysics.ComputeUprightTorque(
			proxy.CFrame, target, proxy.AssemblyAngularVelocity, mass, tuning.turnTorque
		)
	end

	function controller:Render()
		if destroyed or root.Parent == nil then
			return
		end
		local lead = proxy.Position - root.Position
		if lead.Magnitude > ScooterConfig.PredictionCameraLead then
			lead = lead.Unit * ScooterConfig.PredictionCameraLead
		end
		local rotation = proxy.CFrame.Rotation * root.CFrame.Rotation:Inverse()
		local axis, angle = rotation:ToAxisAngle()
		local boundedRotation = CFrame.fromAxisAngle(axis, math.min(angle, ScooterConfig.PredictionMaxAngle))
		local offset = CFrame.new(root.Position + lead) * boundedRotation * CFrame.new(-root.Position)
		for source, visual in visuals do
			if source.Parent then
				visual.displayTransparency = source.LocalTransparencyModifier
				visual.part.LocalTransparencyModifier = visual.displayTransparency
				visual.part.CFrame = offset * source.CFrame
				visual.part.Transparency = source.Transparency
				visual.part.Color = source.Color
				visual.part.Material = source.Material
				visual.part.Size = source.Size
				source.LocalTransparencyModifier = 1
			end
		end
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Custom then
			cameraOffset = lead
			camera.CFrame += lead
			camera.Focus += lead
			offsetCamera = camera
			lastCameraCFrame = camera.CFrame
		end
	end

	function controller:Destroy()
		if destroyed then
			return
		end
		self:BeforeCamera()
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		for source, visual in visuals do
			if visual.dashboard then visual.dashboard.Destroy() end
			if source.Parent then
				source.LocalTransparencyModifier = visual.originalTransparency
			end
		end
		table.clear(visuals)
		table.clear(connections)
		container:Destroy()
	end

	return controller
end

return ScooterPrediction
