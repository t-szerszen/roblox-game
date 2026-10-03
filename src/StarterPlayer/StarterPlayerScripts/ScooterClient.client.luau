--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
type DriveInput = {
	throttleHeld: boolean,
	brakeHeld: boolean,
	steering: number,
	wheelieHeld: boolean,
}

type CleanupTask = RBXScriptConnection | Instance | (() -> ())
type Maid = {
	tasks: { CleanupTask },
	Give: (self: Maid, task: CleanupTask) -> (),
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
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(ScooterConfig.RemoteFolderName)
local requestSpawnRemote = remotesFolder:WaitForChild("RequestSpawn") :: RemoteEvent
local trickRemote = remotesFolder:WaitForChild("TrickState") :: RemoteEvent
local driveInputRemote = remotesFolder:WaitForChild("DriveInput") :: RemoteEvent

local activeMaid: Maid? = nil
local characterMaid: Maid? = nil
local activeScooter: Model? = nil
local activeSeat: VehicleSeat? = nil
local localSteering = 0
local burnoutActive = false
local wheelieButtonHeld = false
local focused = true
local destroyed = false
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local visualStates: { [Model]: VisualState } = {}
local mountedActions = { "ScooterBlockJump", "ScooterWheelie", "ScooterDismount" }

local function newMaid(): Maid
	local maid = {} :: Maid
	maid.tasks = {}
	function maid:Give(task: CleanupTask)
		table.insert(self.tasks, task)
	end
	function maid:Clean()
		for _, task in self.tasks do
			if typeof(task) == "RBXScriptConnection" then
				task:Disconnect()
			elseif typeof(task) == "Instance" then
				task:Destroy()
			else
				task()
			end
		end
		table.clear(self.tasks)
	end
	return maid
end

local function resetInput()
	table.clear(heldKeys)
	wheelieButtonHeld = false
	localSteering = 0
end

local function setLocalBurnout(active: boolean)
	if burnoutActive ~= active then
		burnoutActive = active
		trickRemote:FireServer("Burnout", active)
	end
end

local function clearControls()
	resetInput()
	if activeSeat then
		activeSeat.ThrottleFloat = 0
		activeSeat.SteerFloat = 0
	end
	if activeScooter then
		driveInputRemote:FireServer(false, false, 0, false)
	end
	setLocalBurnout(false)
end

local function cleanupController()
	clearControls()
	activeScooter = nil
	activeSeat = nil
	if activeMaid then
		activeMaid:Clean()
		activeMaid = nil
	end
	for _, action in mountedActions do
		ContextActionService:UnbindAction(action)
	end
end

local function keyHeld(first: Enum.KeyCode, second: Enum.KeyCode): boolean
	return heldKeys[first] == true or heldKeys[second] == true
end

local function readInput(seat: VehicleSeat): DriveInput
	if not focused or UserInputService:GetFocusedTextBox() ~= nil then
		return { throttleHeld = false, brakeHeld = false, steering = 0, wheelieHeld = false }
	end
	local keyboardSteering = (if keyHeld(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0)
		- (if keyHeld(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)
	return {
		throttleHeld = keyHeld(Enum.KeyCode.W, Enum.KeyCode.Up) or seat.ThrottleFloat > 0.1,
		brakeHeld = keyHeld(Enum.KeyCode.S, Enum.KeyCode.Down) or seat.ThrottleFloat < -0.1,
		steering = math.clamp(if math.abs(seat.SteerFloat) > 0.1 then seat.SteerFloat else keyboardSteering, -1, 1),
		wheelieHeld = wheelieButtonHeld or keyHeld(Enum.KeyCode.LeftShift, Enum.KeyCode.C),
	}
end

local function startController(scooter: Model, seat: VehicleSeat, root: BasePart)
	cleanupController()
	local character = localPlayer.Character
	if not character then
		return
	end
	activeScooter = scooter
	activeSeat = seat
	local maid = newMaid()
	activeMaid = maid
	local lastInputSentAt = -math.huge
	local lastBurnoutSentAt = -math.huge
	local lastSent: DriveInput? = nil

	local function mountedAction(action: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		local allowed = focused and UserInputService:GetFocusedTextBox() == nil
		if action == "ScooterWheelie" then
			local held = allowed and (state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change)
			if input.UserInputType == Enum.UserInputType.Touch then
				wheelieButtonHeld = held
			else
				heldKeys[input.KeyCode] = held
			end
		elseif state == Enum.UserInputState.Begin and allowed then
			if action == "ScooterDismount" then
				clearControls()
				trickRemote:FireServer("Dismount", true)
			end
		end
		-- Space/ButtonA is intentionally inert while mounted and must not reach
		-- the default Humanoid jump/dismount binding.
		return Enum.ContextActionResult.Sink
	end
	local priority = Enum.ContextActionPriority.High.Value + 10
	ContextActionService:BindActionAtPriority("ScooterBlockJump", mountedAction, false, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("ScooterWheelie", mountedAction, true, priority, Enum.KeyCode.LeftShift, Enum.KeyCode.C)
	ContextActionService:BindActionAtPriority("ScooterDismount", mountedAction, true, priority, Enum.KeyCode.E)
	ContextActionService:SetTitle("ScooterWheelie", "Wheelie")
	ContextActionService:SetTitle("ScooterDismount", "Exit")

	maid:Give(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not focused or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			heldKeys[input.KeyCode] = true
		end
	end))
	maid:Give(UserInputService.InputEnded:Connect(function(input: InputObject)
		heldKeys[input.KeyCode] = nil
	end))
	maid:Give(UserInputService.TextBoxFocused:Connect(clearControls))
	maid:Give(seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil or seat.Occupant.Parent ~= character then
			cleanupController()
		end
	end))
	maid:Give(scooter.Destroying:Connect(cleanupController))

	maid:Give(RunService.PreSimulation:Connect(function(deltaTime: number)
		if activeScooter ~= scooter or activeSeat ~= seat or seat.Occupant == nil then
			cleanupController()
			return
		end
		local input = readInput(seat)
		localSteering = ScooterPhysics.SmoothSteering(localSteering, input.steering, deltaTime)

		local now = os.clock()
		local elapsed = now - lastInputSentAt
		local previous = lastSent
		local changed = previous == nil or input.throttleHeld ~= previous.throttleHeld
			or input.brakeHeld ~= previous.brakeHeld or input.wheelieHeld ~= previous.wheelieHeld
			or math.abs(input.steering - previous.steering) >= ScooterConfig.SteeringSendThreshold
		if elapsed >= ScooterConfig.DriveInputSendInterval
			and (changed or elapsed >= ScooterConfig.DriveInputKeepalive)
		then
			driveInputRemote:FireServer(input.throttleHeld, input.brakeHeld, input.steering, input.wheelieHeld)
			lastInputSentAt = now
			lastSent = input
		end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local grounded = scooter:GetAttribute("FrontGrounded") == true or scooter:GetAttribute("RearGrounded") == true
		local wantsBurnout = input.throttleHeld and input.brakeHeld and grounded
			and scooter:GetAttribute("Fallen") ~= true and speed <= ScooterConfig.BurnoutSmokeMaxSpeed
		if wantsBurnout ~= burnoutActive
			or (wantsBurnout and scooter:GetAttribute("BurnoutActive") ~= true
				and now - lastBurnoutSentAt >= ScooterConfig.DriveInputKeepalive)
		then
			burnoutActive = wantsBurnout
			trickRemote:FireServer("Burnout", wantsBurnout)
			lastBurnoutSentAt = now
		end
	end))
end

local function tryStartFromSeat(seat: BasePart)
	if not seat:IsA("VehicleSeat") then
		return
	end
	local scooter = seat:FindFirstAncestorOfClass("Model")
	if not scooter or scooter:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
		return
	end
	local root = scooter.PrimaryPart
	if root then
		startController(scooter, seat, root)
	end
end

local function requestDefaultScooter()
	if destroyed then
		return
	end
	local folder = workspace:FindFirstChild(ScooterConfig.ScooterFolderName)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("OwnerUserId") == localPlayer.UserId then
				return
			end
		end
	end
	requestSpawnRemote:FireServer(ScooterConfig.DefaultModel)
end

local function hookCharacter(character: Model)
	cleanupController()
	if characterMaid then
		characterMaid:Clean()
	end
	local maid = newMaid()
	characterMaid = maid
	local humanoid = character:WaitForChild("Humanoid", 10)
	if destroyed or localPlayer.Character ~= character or characterMaid ~= maid or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	maid:Give(humanoid.Seated:Connect(function(isSeated: boolean, seat: BasePart?)
		if isSeated and seat then
			tryStartFromSeat(seat)
		else
			cleanupController()
		end
	end))
	maid:Give(humanoid.Died:Connect(cleanupController))
	maid:Give(character.Destroying:Connect(cleanupController))
	if humanoid.SeatPart then
		tryStartFromSeat(humanoid.SeatPart)
	end
	task.defer(requestDefaultScooter)
end

local focusLostConnection = UserInputService.WindowFocusReleased:Connect(function()
	focused = false
	clearControls()
end)
local focusGainedConnection = UserInputService.WindowFocused:Connect(function()
	focused = true
	clearControls()
end)
local characterAddedConnection = localPlayer.CharacterAdded:Connect(hookCharacter)
local characterRemovingConnection = localPlayer.CharacterRemoving:Connect(function()
	cleanupController()
	if characterMaid then
		characterMaid:Clean()
		characterMaid = nil
	end
end)
if localPlayer.Character then
	task.spawn(hookCharacter, localPlayer.Character)
end

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
			local steering = scooter:GetAttribute("SteeringInput")
			local steeringInput = if scooter == activeScooter
				then localSteering
				else if typeof(steering) == "number" then math.clamp(steering, -1, 1) else 0
			local steeringAlpha = 1 - math.exp(-ScooterConfig.HandlebarSmoothSpeed * math.min(deltaTime, 0.1))
			state.displayedSteering += (steeringInput - state.displayedSteering) * steeringAlpha
			local animatedSteering = math.sign(state.displayedSteering)
				* math.abs(state.displayedSteering) ^ ScooterConfig.HandlebarInputExponent
			state.steering.Transform = CFrame.Angles(
				0,
				-animatedSteering * ScooterConfig.MaxHandlebarAngle,
				0
			)
		end
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	cleanupController()
	if characterMaid then
		characterMaid:Clean()
		characterMaid = nil
	end
	characterAddedConnection:Disconnect()
	characterRemovingConnection:Disconnect()
	focusLostConnection:Disconnect()
	focusGainedConnection:Disconnect()
	visualConnection:Disconnect()
	scooterAddedConnection:Disconnect()
	scooterRemovedConnection:Disconnect()
	motorAddedConnection:Disconnect()
	motorRemovingConnection:Disconnect()
	table.clear(visualStates)
end)
