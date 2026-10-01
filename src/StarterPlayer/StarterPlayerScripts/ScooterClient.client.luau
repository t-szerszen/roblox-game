--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

type Connection = RBXScriptConnection
type Maid = {
	tasks: { Connection | Instance },
	Give: (self: Maid, task: Connection | Instance) -> (),
	Clean: (self: Maid) -> (),
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

local inputState = {
	throttle = false,
	brake = false,
	left = false,
	right = false,
	wheelie = false,
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
	inputState.wheelie = false
	jumpQueued = false
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
	elseif keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.C then
		inputState.wheelie = isDown
	elseif keyCode == Enum.KeyCode.Space and isDown then
		jumpQueued = true
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

local function isGrounded(root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local scooter = activeScooter
	if scooter then
		params.FilterDescendantsInstances = { scooter }
	end

	local result = workspace:Raycast(root.Position, Vector3.new(0, -3.2, 0), params)
	return result ~= nil
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

	maid:Give(RunService.Heartbeat:Connect(function(_deltaTime: number)
		if activeScooter ~= scooter or activeSeat ~= seat or seat.Occupant == nil then
			cleanupController()
			return
		end

		local velocity = root.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = flatVelocity.Magnitude

		local grounded = isGrounded(root)

		local seatThrottle = seat.ThrottleFloat
		local throttleHeld = seatThrottle > 0.1 or inputState.throttle
		local brakeHeld = seatThrottle < -0.1 or inputState.brake
		local keyboardSteering = (if inputState.right then 1 else 0) - (if inputState.left then 1 else 0)
		local steering = if math.abs(seat.SteerFloat) > 0.1 then seat.SteerFloat else keyboardSteering
		local wantsBurnout = throttleHeld and brakeHeld and speed <= ScooterConfig.BurnoutMaxSpeed and grounded
		local driveThrottle = if throttleHeld == brakeHeld then 0 else if throttleHeld then 1 else -1
		local sendJump = jumpQueued
		jumpQueued = false
		if os.clock() - lastInputSentAt >= 0.05 or sendJump then
			lastInputSentAt = os.clock()
			driveInputRemote:FireServer(driveThrottle, steering, inputState.wheelie, sendJump)
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

trickRemote.OnClientEvent:Connect(function(_owner: Player, scooter: Model, trickName: string, active: boolean, smokeColor: Color3)
	if trickName ~= "Burnout" then
		return
	end

	local smoke = scooter:FindFirstChild("BurnoutSmoke", true)
	if smoke and smoke:IsA("ParticleEmitter") then
		smoke.Enabled = active
		smoke.Color = ColorSequence.new(smokeColor)
	end
end)

localPlayer.CharacterAdded:Connect(hookCharacter)
if localPlayer.Character then
	hookCharacter(localPlayer.Character)
end

task.defer(function()
	if not findControlledScooter() then
		requestSpawnRemote:FireServer(ScooterConfig.DefaultModel)
	end
end)
