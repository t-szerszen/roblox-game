--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local RacingConfig = require(ReplicatedStorage.Shared.Phone.RacingConfig)

type Connection = RBXScriptConnection
type Maid = {
	tasks: { Connection | Instance },
	Give: (self: Maid, task: Connection | Instance) -> (),
	Clean: (self: Maid) -> (),
}
type VisualState = {
	frontWheel: Motor6D?,
	rearWheel: Motor6D?,
	steering: Motor6D?,
	frontSpin: number,
	rearSpin: number,
	displayedSteering: number,
}

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild(ScooterConfig.RemoteFolderName)
local requestSpawnRemote = remotesFolder:WaitForChild("RequestSpawn") :: RemoteEvent
local trickRemote = remotesFolder:WaitForChild("TrickState") :: RemoteEvent
local driveInputRemote = remotesFolder:WaitForChild("DriveInput") :: RemoteEvent

local activeMaid: Maid? = nil
local activeScooter: Model? = nil
local activeSeat: VehicleSeat? = nil
local characterSeatConnection: RBXScriptConnection? = nil
local burnoutActive = false
local jumpQueued = false
local wheelieQueued = false
local visualStates: { [Model]: VisualState } = {}

local inputState = {
	throttle = false,
	brake = false,
	left = false,
	right = false,
}

local function newMaid(): Maid
	local maid = {}
	maid.tasks = {}

	function maid:Give(task: Connection | Instance)
		table.insert(self.tasks, task)
	end

	function maid:Clean()
		for _, task in ipairs(self.tasks) do
			if typeof(task) == "RBXScriptConnection" then
				task:Disconnect()
			elseif typeof(task) == "Instance" then
				task:Destroy()
			end
		end
		table.clear(self.tasks)
	end

	return maid :: Maid
end

local function resetInput()
	inputState.throttle = false
	inputState.brake = false
	inputState.left = false
	inputState.right = false
	jumpQueued = false
	wheelieQueued = false
end

local function keyChanged(input: InputObject, isDown: boolean)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		inputState.throttle = isDown
	elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		inputState.brake = isDown
	elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		inputState.left = isDown
	elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		inputState.right = isDown
	elseif (keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.C) and isDown then
		wheelieQueued = true
	elseif keyCode == Enum.KeyCode.Space and isDown then
		jumpQueued = true
	elseif keyCode == Enum.KeyCode.H and isDown then
		local RacingRemotes = ReplicatedStorage:WaitForChild(RacingConfig.RemoteFolderName)
		local honkEvent = RacingRemotes:WaitForChild("Honk") :: RemoteEvent
		local requestChallenge = RacingRemotes:WaitForChild("RequestChallenge") :: RemoteFunction
		honkEvent:FireServer()
		task.spawn(function()
			requestChallenge:InvokeServer()
		end)
	end
end

local function findControlledScooter(): Model?
	local folder = workspace:FindFirstChild(ScooterConfig.ScooterFolderName)
	if not folder then
		return nil
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == localPlayer.UserId then
			return child
		end
	end

	return nil
end

local function setLocalBurnout(active: boolean)
	if burnoutActive == active then
		return
	end

	burnoutActive = active
	trickRemote:FireServer("Burnout", active, Color3.fromRGB(235, 235, 235))
end

local function cleanupController()
	if activeMaid then
		activeMaid:Clean()
		activeMaid = nil
	end
	if burnoutActive then
		trickRemote:FireServer("Burnout", false, Color3.fromRGB(235, 235, 235))
	end
	activeScooter = nil
	activeSeat = nil
	burnoutActive = false
	resetInput()
end

local function startController(scooter: Model, seat: VehicleSeat, root: BasePart)
	cleanupController()

	activeScooter = scooter
	activeSeat = seat
	local maid = newMaid()
	activeMaid = maid

	local lastInputSentAt = 0
	local lastSentThrottle: number? = nil
	local lastSentSteering: number? = nil
	local smoothedSteering = 0

	maid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed and UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		keyChanged(input, true)
	end))

	maid:Give(UserInputService.InputEnded:Connect(function(input: InputObject)
		keyChanged(input, false)
	end))

	maid:Give(seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			cleanupController()
		end
	end))

	maid:Give(scooter.Destroying:Connect(function()
		cleanupController()
	end))

	maid:Give(RunService.Heartbeat:Connect(function(deltaTime: number)
		if activeScooter ~= scooter or activeSeat ~= seat or seat.Occupant == nil then
			cleanupController()
			return
		end

		local velocity = root.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = flatVelocity.Magnitude

		local grounded = scooter:GetAttribute("FrontGrounded") == true
			or scooter:GetAttribute("RearGrounded") == true

		local seatThrottle = seat.ThrottleFloat
		local throttleHeld = seatThrottle > 0.1 or inputState.throttle
		local brakeHeld = seatThrottle < -0.1 or inputState.brake
		local keyboardSteering = (if inputState.right then 1 else 0) - (if inputState.left then 1 else 0)
		local targetSteering = if math.abs(seat.SteerFloat) > 0.1 then seat.SteerFloat else keyboardSteering
		targetSteering = math.clamp(targetSteering, -1, 1)
		local steeringAlpha = 1 - math.exp(-ScooterConfig.SteerSmoothSpeed * math.min(deltaTime, 0.1))
		smoothedSteering += (targetSteering - smoothedSteering) * steeringAlpha
		if math.abs(smoothedSteering) < 0.001 and targetSteering == 0 then
			smoothedSteering = 0
		end
		local wantsBurnout = throttleHeld
			and brakeHeld
			and speed <= ScooterConfig.BurnoutSmokeMaxSpeed
			and grounded
		local driveThrottle = if throttleHeld == brakeHeld then 0 else if throttleHeld then 1 else -1
		local sendJump = jumpQueued
		local sendWheelie = wheelieQueued
		jumpQueued = false
		wheelieQueued = false
		local now = os.clock()
		local elapsed = now - lastInputSentAt
		local throttleChanged = driveThrottle ~= lastSentThrottle
		local steeringChanged = lastSentSteering == nil
			or math.abs(smoothedSteering - lastSentSteering) >= ScooterConfig.SteeringSendThreshold
		local shouldSendSteering = steeringChanged and elapsed >= ScooterConfig.DriveInputSendInterval
		if elapsed >= ScooterConfig.DriveInputKeepalive or throttleChanged or shouldSendSteering or sendJump or sendWheelie then
			lastInputSentAt = now
			lastSentThrottle = driveThrottle
			lastSentSteering = smoothedSteering
			driveInputRemote:FireServer(driveThrottle, smoothedSteering, sendWheelie, sendJump)
		end

		if wantsBurnout then
			setLocalBurnout(true)
		else
			setLocalBurnout(false)
		end
	end))
end

local function tryStartFromSeat(seat: Seat)
	if not seat:IsA("VehicleSeat") then
		return
	end

	local scooter = seat:FindFirstAncestorOfClass("Model")
	if not scooter or scooter:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
		return
	end

	local root = scooter.PrimaryPart
	if not root then
		return
	end

	startController(scooter, seat, root)
end

local function hookCharacter(character: Model)
	cleanupController()
	if characterSeatConnection then
		characterSeatConnection:Disconnect()
		characterSeatConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	characterSeatConnection = humanoid.Seated:Connect(function(isSeated: boolean, seat: Seat?)
		if isSeated and seat then
			tryStartFromSeat(seat)
		else
			cleanupController()
		end
	end)
end

local characterAddedConnection = localPlayer.CharacterAdded:Connect(hookCharacter)
if localPlayer.Character then
	hookCharacter(localPlayer.Character)
end

task.defer(function()
	if not findControlledScooter() then
		requestSpawnRemote:FireServer(ScooterConfig.DefaultModel)
	end
end)

local function findMotor(scooter: Model, name: string): Motor6D?
	local instance = scooter:FindFirstChild(name, true)
	return if instance and instance:IsA("Motor6D") then instance else nil
end

local scooterFolderInstance = workspace:WaitForChild(ScooterConfig.ScooterFolderName)
assert(scooterFolderInstance:IsA("Folder"), "Workspace scooter container must be a Folder")
local scooterFolder = scooterFolderInstance

local function registerVisual(instance: Instance)
	if not instance:IsA("Model") or visualStates[instance] then
		return
	end
	visualStates[instance] = {
		frontWheel = findMotor(instance, "FrontWheelMotor"),
		rearWheel = findMotor(instance, "RearWheelMotor"),
		steering = findMotor(instance, "SteeringMotor"),
		frontSpin = 0,
		rearSpin = 0,
		displayedSteering = 0,
	}
end

local function unregisterVisual(instance: Instance)
	if instance:IsA("Model") then
		visualStates[instance] = nil
	end
end

for _, scooter in scooterFolder:GetChildren() do
	registerVisual(scooter)
end
local scooterAddedConnection = scooterFolder.ChildAdded:Connect(registerVisual)
local scooterRemovedConnection = scooterFolder.ChildRemoved:Connect(unregisterVisual)
local motorAddedConnection = scooterFolder.DescendantAdded:Connect(function(instance: Instance)
	if not instance:IsA("Motor6D") then
		return
	end
	local scooter = instance:FindFirstAncestorOfClass("Model")
	local state = if scooter then visualStates[scooter] else nil
	if not state then
		return
	end
	if instance.Name == "FrontWheelMotor" then
		state.frontWheel = instance
	elseif instance.Name == "RearWheelMotor" then
		state.rearWheel = instance
	elseif instance.Name == "SteeringMotor" then
		state.steering = instance
	end
end)
local motorRemovingConnection = scooterFolder.DescendantRemoving:Connect(function(instance: Instance)
	if not instance:IsA("Motor6D") then
		return
	end
	local scooter = instance:FindFirstAncestorOfClass("Model")
	local state = if scooter then visualStates[scooter] else nil
	if not state then
		return
	end
	if state.frontWheel == instance then
		state.frontWheel = nil
	elseif state.rearWheel == instance then
		state.rearWheel = nil
	elseif state.steering == instance then
		state.steering = nil
	end
end)

local visualConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
	for scooter, state in visualStates do
		local root = scooter.PrimaryPart
		if not root then
			continue
		end

		local forwardSpeed = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
		local wheelRadiusAttribute = scooter:GetAttribute("WheelRadius")
		local wheelRadius = if typeof(wheelRadiusAttribute) == "number"
			then math.clamp(wheelRadiusAttribute, 0.2, 3)
			else ScooterConfig.WheelRadius
		local travelAngularSpeed = -forwardSpeed / wheelRadius
		local rearAngularSpeed = if scooter:GetAttribute("BurnoutActive") == true
			then -ScooterConfig.BurnoutWheelAngularSpeed
			else travelAngularSpeed
		state.frontSpin = (state.frontSpin + travelAngularSpeed * deltaTime) % (math.pi * 2)
		state.rearSpin = (state.rearSpin + rearAngularSpeed * deltaTime) % (math.pi * 2)
		if state.frontWheel then
			state.frontWheel.Transform = CFrame.Angles(state.frontSpin, 0, 0)
		end
		if state.rearWheel then
			state.rearWheel.Transform = CFrame.Angles(state.rearSpin, 0, 0)
		end
		if state.steering then
			local steering = scooter:GetAttribute("Steering")
			local steeringInput = if typeof(steering) == "number" then math.clamp(steering, -1, 1) else 0
			local steeringAlpha = 1 - math.exp(-ScooterConfig.SteerSmoothSpeed * math.min(deltaTime, 0.1))
			state.displayedSteering += (steeringInput - state.displayedSteering) * steeringAlpha
			state.steering.Transform = CFrame.Angles(
				0,
				-state.displayedSteering * ScooterConfig.MaxHandlebarAngle,
				0
			)
		end
	end
end)

script.Destroying:Connect(function()
	cleanupController()
	if characterSeatConnection then
		characterSeatConnection:Disconnect()
		characterSeatConnection = nil
	end
	characterAddedConnection:Disconnect()
	visualConnection:Disconnect()
	scooterAddedConnection:Disconnect()
	scooterRemovedConnection:Disconnect()
	motorAddedConnection:Disconnect()
	motorRemovingConnection:Disconnect()
	table.clear(visualStates)
end)
