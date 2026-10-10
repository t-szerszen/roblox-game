--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterPhysics = require(ReplicatedStorage.Shared.Scooter.ScooterPhysics)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Feedback = require(script.Parent.UI.Feedback)
local Speedometer = require(script.Parent.ScooterSpeedometer)
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

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(ScooterConfig.RemoteFolderName)
local requestSpawnRemote = remotesFolder:WaitForChild("RequestSpawn") :: RemoteEvent
local trickRemote = remotesFolder:WaitForChild("TrickState") :: RemoteEvent
local driveInputRemote = remotesFolder:WaitForChild("DriveInput") :: RemoteEvent
local toggleDriveModeRemote = remotesFolder:WaitForChild(ScooterConfig.DriveModes.ToggleRemoteName) :: RemoteEvent
local toggleHeadlightRemote = remotesFolder:WaitForChild(ScooterConfig.Headlight.ToggleRemoteName) :: RemoteEvent

local activeMaid: Maid? = nil
local characterMaid: Maid? = nil
local activeScooter: Model? = nil
local activeSeat: VehicleSeat? = nil
local burnoutActive = false
local wheelieButtonHeld = false
local focused = true
local destroyed = false
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local mountedActions = { "ScooterBlockJump", "ScooterWheelie", "ScooterDismount", "ScooterDriveMode", "ScooterHeadlight" }
local driveModeKey = Enum.KeyCode.P

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
	if not focused or playerGui:GetAttribute("GameplayInputBlocked") == true or UserInputService:GetFocusedTextBox() ~= nil then
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
	local lastModeRequestAt = -math.huge
	local lastLightRequestAt = -math.huge
	maid:Give(Speedometer.Start(scooter, playerGui).Destroy)
	local hintScope = Scope.new()
	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "ScooterRideFeedback"
	hintGui.ResetOnSpawn = false
	hintGui.DisplayOrder = 40
	hintGui.Parent = playerGui
	maid:Give(function() hintScope:Clean(); hintGui:Destroy() end)
	local feedback = Feedback.new(hintGui, hintScope)
	feedback.Show(driveModeKey.Name .. " — ECO / SPORT · L — światła")

	local function mountedAction(action: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if playerGui:GetAttribute("GameplayInputBlocked") == true then
			return Enum.ContextActionResult.Pass
		end
		local allowed = focused and UserInputService:GetFocusedTextBox() == nil
		if action == "ScooterWheelie" then
			local held = allowed and (state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change)
			if input.UserInputType == Enum.UserInputType.Touch then
				wheelieButtonHeld = held
			else
				heldKeys[input.KeyCode] = held
			end
		elseif state == Enum.UserInputState.Begin and allowed then
			if action == "ScooterDriveMode" then
				local now = os.clock()
				if now - lastModeRequestAt >= ScooterConfig.DriveModes.ToggleCooldown then
					lastModeRequestAt = now
					toggleDriveModeRemote:FireServer()
				end
			elseif action == "ScooterHeadlight" then
				local now = os.clock()
				if now - lastLightRequestAt >= ScooterConfig.Headlight.ToggleCooldown then
					lastLightRequestAt = now
					toggleHeadlightRemote:FireServer()
				end
			elseif action == "ScooterDismount" then
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
	ContextActionService:BindActionAtPriority("ScooterDriveMode", mountedAction, true, priority,
		driveModeKey)
	ContextActionService:BindActionAtPriority("ScooterHeadlight", mountedAction, true, priority, Enum.KeyCode.L)
	ContextActionService:SetTitle("ScooterWheelie", "Wheelie")
	ContextActionService:SetTitle("ScooterDismount", "Exit")
	ContextActionService:SetTitle("ScooterDriveMode", "ECO / SPORT")
	ContextActionService:SetTitle("ScooterHeadlight", "Światła")

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
	maid:Give(playerGui:GetAttributeChangedSignal("GameplayInputBlocked"):Connect(function()
		if playerGui:GetAttribute("GameplayInputBlocked") == true then clearControls() end
	end))
	maid:Give(seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil or seat.Occupant.Parent ~= character then
			cleanupController()
		end
	end))
	maid:Give(scooter.Destroying:Connect(cleanupController))

	maid:Give(RunService.PreSimulation:Connect(function()
		if activeScooter ~= scooter or activeSeat ~= seat or seat.Occupant == nil then
			cleanupController()
			return
		end
		local input = readInput(seat)

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
		local wantsBurnout = ScooterPhysics.CanBurnout(speed, input.throttleHeld, input.brakeHeld) and grounded
			and scooter:GetAttribute("Fallen") ~= true
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
	local characterRoot = character:WaitForChild("HumanoidRootPart", 10)
	if destroyed or localPlayer.Character ~= character or characterMaid ~= maid
		or not humanoid or not humanoid:IsA("Humanoid") or not characterRoot or not characterRoot:IsA("BasePart") then
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
end)
