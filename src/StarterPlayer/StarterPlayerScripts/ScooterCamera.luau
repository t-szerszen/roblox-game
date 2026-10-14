--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Scooter.ScooterCameraConfig)
local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type CameraMode = "ThirdPerson" | "FirstPerson"
export type ModeChangeCallback = (mode: CameraMode) -> ()

export type Controller = {
	Destroy: () -> (),
	SetMode: (mode: CameraMode) -> (),
	GetMode: () -> CameraMode,
	CycleMode: () -> CameraMode,
}

local ScooterCamera = {}
local BIND_NAME = "ScooterDynamicCamera"

function ScooterCamera.Start(
	scooter: Model,
	seat: VehicleSeat,
	root: BasePart,
	onModeChanged: ModeChangeCallback?
): Controller
	local camera = Workspace.CurrentCamera
	local player = Players.LocalPlayer
	if not camera or not player then
		return {
			Destroy = function() end,
			SetMode = function(_) end,
			GetMode = function() return "ThirdPerson" end,
			CycleMode = function() return "ThirdPerson" end,
		}
	end

	local originalMinZoom = player.CameraMinZoomDistance
	local originalMaxZoom = player.CameraMaxZoomDistance
	local originalCameraType = camera.CameraType
	local originalCameraSubject = camera.CameraSubject

	local character = player.Character
	local headPart = if character then character:FindFirstChild("Head") :: BasePart? else nil
	-- Setting CameraSubject to HeadPart (BasePart) prevents Roblox VehicleCamera
	-- from locking focus onto DriverSeat (handlebar/deck height).
	if headPart then
		camera.CameraSubject = headPart
	end

	local destroyed = false
	local currentMode: CameraMode = "ThirdPerson"
	local currentFov = camera.FieldOfView
	local currentRoll = 0
	local currentPullback = 0
	local currentInertiaShift = 0
	local shakeTime = 0
	local lastAutoModeSwitchAt = 0
	local setMode: (mode: CameraMode, skipNotify: boolean?, customZoomDist: number?) -> ()
	local handleZoomOut: () -> ()

	local lastManualInputAt = 0
	local isManualLooking = false

	local firstPersonYaw = 0
	local firstPersonPitch = 0
	local lastFirstPersonLookAt = 0
	local currentWheelieComp = 0

	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?

	local userGameSettings = UserSettings():GetService("UserGameSettings")
	local function getSensitivity(): number
		local ok, sens = pcall(function() return userGameSettings.MouseSensitivity end)
		if ok and typeof(sens) == "number" and sens > 0 then
			return sens * 0.0032
		end
		return 0.0032
	end

	handleZoomOut = function()
		if destroyed or currentMode ~= "FirstPerson" then return end
		local now = os.clock()
		if (now - lastAutoModeSwitchAt) < 0.3 then return end
		lastAutoModeSwitchAt = now
		setMode("ThirdPerson", false, 5.0)
	end

	local inputConnections: { RBXScriptConnection } = {}

	table.insert(inputConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if destroyed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
			isManualLooking = true
			lastManualInputAt = os.clock()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			if not gameProcessed then
				isManualLooking = true
				lastManualInputAt = os.clock()
			end
		end
	end))

	table.insert(inputConnections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
			isManualLooking = false
			lastManualInputAt = os.clock()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			isManualLooking = false
			lastManualInputAt = os.clock()
		end
	end))

	table.insert(inputConnections, UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if destroyed then return end

		if currentMode == "FirstPerson" then
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local isBlocked = (playerGui and playerGui:GetAttribute("GameplayInputBlocked") == true)
					or UserInputService:GetFocusedTextBox() ~= nil
				if not isBlocked then
					local sens = getSensitivity()
					local deltaX = input.Delta.X * sens
					local deltaY = input.Delta.Y * sens

					local targetYaw = firstPersonYaw - deltaX
					local maxYaw = Config.FirstPerson.MaxHeadYaw
					local resistLimit = Config.FirstPerson.YawResistanceLimit

					if math.abs(targetYaw) > maxYaw then
						-- Smooth elastic resistance beyond MaxHeadYaw
						local excess = math.abs(targetYaw) - maxYaw
						local sign = math.sign(targetYaw)
						firstPersonYaw = sign * math.clamp(maxYaw + excess * 0.18, maxYaw, resistLimit)
					else
						firstPersonYaw = targetYaw
					end

					local minPitchOffset = Config.FirstPerson.MinPitch - Config.FirstPerson.DefaultPitch
					local maxPitchOffset = Config.FirstPerson.MaxPitch - Config.FirstPerson.DefaultPitch
					firstPersonPitch = math.clamp(
						firstPersonPitch - deltaY,
						minPitchOffset,
						maxPitchOffset
					)

					lastFirstPersonLookAt = os.clock()
				end
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				if input.Position.Magnitude > 0.15 then
					local minPitchOffset = Config.FirstPerson.MinPitch - Config.FirstPerson.DefaultPitch
					local maxPitchOffset = Config.FirstPerson.MaxPitch - Config.FirstPerson.DefaultPitch
					local targetYaw = firstPersonYaw - input.Position.X * 0.045
					local maxYaw = Config.FirstPerson.MaxHeadYaw
					firstPersonYaw = math.clamp(targetYaw, -maxYaw, maxYaw)
					firstPersonPitch = math.clamp(
						firstPersonPitch + input.Position.Y * 0.035,
						minPitchOffset,
						maxPitchOffset
					)
					lastFirstPersonLookAt = os.clock()
				end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local minPitchOffset = Config.FirstPerson.MinPitch - Config.FirstPerson.DefaultPitch
				local maxPitchOffset = Config.FirstPerson.MaxPitch - Config.FirstPerson.DefaultPitch
				local targetYaw = firstPersonYaw - input.Delta.X * 0.0035
				local maxYaw = Config.FirstPerson.MaxHeadYaw
				firstPersonYaw = math.clamp(targetYaw, -maxYaw, maxYaw)
				firstPersonPitch = math.clamp(
					firstPersonPitch - input.Delta.Y * 0.0035,
					minPitchOffset,
					maxPitchOffset
				)
				lastFirstPersonLookAt = os.clock()
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				if input.Position.Z < 0 then
					-- User scrolled backwards -> return to ThirdPerson smoothly at 5.0 studs zoom
					handleZoomOut()
				end
			end
		else
			-- ThirdPerson
			if input.UserInputType == Enum.UserInputType.MouseMovement and isManualLooking then
				lastManualInputAt = os.clock()
			elseif input.UserInputType == Enum.UserInputType.Touch and isManualLooking then
				lastManualInputAt = os.clock()
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				if input.Position.Magnitude > 0.25 then
					isManualLooking = true
					lastManualInputAt = os.clock()
				else
					isManualLooking = false
				end
			end
		end
	end))

	table.insert(inputConnections, UserInputService.PointerAction:Connect(function(wheel, _pan, pinch, gameProcessed)
		if destroyed or gameProcessed then return end
		if currentMode == "FirstPerson" and (wheel < -0.1 or pinch < -0.1) then
			handleZoomOut()
		end
	end))

	-- Hides head and accessories (hair, hats, masks) in First Person so nothing clips the camera
	local function setCharacterHeadVisibility(visible: boolean)
		local char = player.Character
		if not char then return end
		for _, item in char:GetChildren() do
			if item:IsA("Accessory") then
				local handle = item:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					handle.LocalTransparencyModifier = if visible then 0 else 1
				end
			elseif item.Name == "Head" and item:IsA("BasePart") then
				item.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end

	-- Allow zooming freely between 0.5 (first person) and originalMaxZoom
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = originalMaxZoom

	setMode = function(mode: CameraMode, skipNotify: boolean?, customZoomDist: number?)
		if destroyed then return end
		if mode == currentMode then return end
		local prevMode = currentMode
		currentMode = mode
		lastAutoModeSwitchAt = os.clock()

		local char = player.Character
		local currentHead = if char then char:FindFirstChild("Head") :: BasePart? else nil

		if mode == "FirstPerson" then
			camera.CameraType = Enum.CameraType.Scriptable
			setCharacterHeadVisibility(false)
			firstPersonYaw = 0
			firstPersonPitch = 0
			lastFirstPersonLookAt = 0
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

			player.CameraMinZoomDistance = 0.5
			player.CameraMaxZoomDistance = originalMaxZoom
		elseif mode == "ThirdPerson" then
			camera.CameraType = Enum.CameraType.Custom
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			if currentHead then camera.CameraSubject = currentHead end
			setCharacterHeadVisibility(true)

			-- Always align camera strictly behind the vehicle/character facing forward
			if prevMode == "FirstPerson" then
				local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local forwardUnit = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, -1)
				local targetFocus = if currentHead then currentHead.Position else (root.Position + Vector3.new(0, 3, 0))
				local targetDist = customZoomDist or Config.ThirdPerson.DefaultZoom
				local cameraPos = targetFocus - forwardUnit * targetDist + Vector3.new(0, 2.2, 0)

				camera.CFrame = CFrame.lookAt(cameraPos, targetFocus + Vector3.new(0, 0.4, 0))
				camera.Focus = CFrame.new(targetFocus)

				player.CameraMinZoomDistance = targetDist
				player.CameraMaxZoomDistance = targetDist
				task.delay(0.20, function()
					if not destroyed and currentMode == "ThirdPerson" then
						player.CameraMinZoomDistance = 0.5
						player.CameraMaxZoomDistance = originalMaxZoom
					end
				end)
			else
				player.CameraMinZoomDistance = 0.5
				player.CameraMaxZoomDistance = originalMaxZoom
			end
		end

		if not skipNotify and onModeChanged then
			onModeChanged(currentMode)
		end
	end

	-- Check if player was already at first-person zoom when mounting
	local initialZoom = (camera.Focus.Position - camera.CFrame.Position).Magnitude
	if initialZoom <= 1.2 then
		setMode("FirstPerson")
	end

	local function cycleMode(): CameraMode
		if currentMode == "ThirdPerson" then
			setMode("FirstPerson")
		else
			setMode("ThirdPerson")
		end
		return currentMode
	end

	local function onRender(dt: number)
		if destroyed or not camera or not root.Parent or not seat.Parent then
			return
		end

		local characterInstance = player.Character
		local currentHead = if characterInstance then characterInstance:FindFirstChild("Head") :: BasePart? else nil

		-- Guarantee that CameraSubject is Head in ThirdPerson.
		if currentMode == "ThirdPerson" and currentHead and camera.CameraSubject ~= currentHead then
			camera.CameraSubject = currentHead
		end

		-- Automatically transition to FirstPerson when zooming in with mouse wheel in ThirdPerson
		if currentMode == "ThirdPerson" then
			local currentZoom = (camera.Focus.Position - camera.CFrame.Position).Magnitude
			local now = os.clock()
			if currentZoom <= 1.2 and (now - lastAutoModeSwitchAt) > 0.8 then
				lastAutoModeSwitchAt = now
				setMode("FirstPerson")
			end
		end

		local isFirstPerson = currentMode == "FirstPerson"
		if isFirstPerson then
			setCharacterHeadVisibility(false)
		end

		local velocity = root.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local speedKmh = planarSpeed / ScooterConfig.StudsPerKmH

		local baseFov = Config.Fov.Base
		local targetFov = baseFov
		if speedKmh > Config.Fov.SpeedThresholdKmh then
			local t = math.clamp(
				(speedKmh - Config.Fov.SpeedThresholdKmh) / (Config.Fov.MaxSpeedKmh - Config.Fov.SpeedThresholdKmh),
				0,
				1
			)
			targetFov = baseFov + (Config.Fov.Max - baseFov) * (t ^ Config.Fov.RampPower)
		end
		currentFov += (targetFov - currentFov) * math.clamp(dt * Config.Fov.Smoothing, 0, 1)
		camera.FieldOfView = currentFov

		local steerInput = seat.SteerFloat
		local turnIntensity = math.clamp(steerInput, -1, 1) * math.clamp(speedKmh / 20, 0, 1)

		local isBurnout = scooter:GetAttribute("BurnoutActive") == true

		if isFirstPerson then
			local now = os.clock()

			-- Lock mouse cursor in First Person unless UI is open or typing
			local isInputBlocked = (playerGui and playerGui:GetAttribute("GameplayInputBlocked") == true)
				or UserInputService:GetFocusedTextBox() ~= nil
			if isInputBlocked then
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
			else
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				end
			end

			local timeSinceInput = now - lastFirstPersonLookAt

			-- If user over-dragged past MaxHeadYaw ("w razie próby przeciągania"), smoothly snap back excess:
			local maxYaw = Config.FirstPerson.MaxHeadYaw
			if math.abs(firstPersonYaw) > maxYaw then
				local sign = math.sign(firstPersonYaw)
				local excess = math.abs(firstPersonYaw) - maxYaw
				firstPersonYaw = sign * (maxYaw + excess * math.clamp(1 - dt * 14, 0, 1))
			end

			-- Auto-center: if player hasn't moved head for AutoCenterDelay,
			-- smoothly return head orientation to straight ahead (following driving vector)
			if timeSinceInput >= Config.FirstPerson.AutoCenterDelay then
				local returnFactor = math.clamp(dt * Config.FirstPerson.AutoCenterSpeed, 0, 1)
				firstPersonYaw += (0 - firstPersonYaw) * returnFactor
				firstPersonPitch += (0 - firstPersonPitch) * returnFactor
			end

			-- Roll dynamics in corners
			local targetRoll = -turnIntensity * Config.FirstPerson.HeadRollAngle
			currentRoll += (targetRoll - currentRoll) * math.clamp(dt * Config.FirstPerson.HeadRollSmoothing, 0, 1)

			-- Longitudinal inertia on accel / brake
			local targetShift = 0
			local throttle = seat.ThrottleFloat
			if throttle > 0.1 then
				targetShift = -Config.FirstPerson.AccelShift * math.clamp(throttle, 0, 1)
			elseif throttle < -0.1 then
				targetShift = Config.FirstPerson.BrakeShift * math.clamp(-throttle, 0, 1)
			end
			currentInertiaShift += (targetShift - currentInertiaShift) * math.clamp(dt * Config.FirstPerson.ShiftSmoothing, 0, 1)

			-- High-speed and burnout handlebar vibration
			local shakeOffset = Vector3.zero
			if isBurnout or speedKmh > Config.FirstPerson.VibrationSpeedThresholdKmh then
				shakeTime += dt * Config.ThirdPerson.ShakeFrequency
				local amp = if isBurnout
					then Config.FirstPerson.BurnoutVibrationAmplitude
					else Config.FirstPerson.VibrationAmplitude * math.clamp((speedKmh - 45) / 45, 0, 1)
				shakeOffset = Vector3.new(
					math.noise(shakeTime, 0, 0),
					math.noise(0, shakeTime, 0),
					0
				) * amp
			end

			-- Compute vehicle base heading and pitch from root CFrame
			local rootCF = root.CFrame
			local forwardHoriz = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
			local vehicleYaw = if forwardHoriz.Magnitude > 0.01
				then math.atan2(-forwardHoriz.X, -forwardHoriz.Z)
				else 0
			local vehiclePitch = math.asin(math.clamp(rootCF.LookVector.Y, -1, 1))

			-- Wheelie pitch compensation:
			-- Counter-rotate head forward when front wheel lifts so sightline stays level with the road
			-- and frames the raised handlebars & dashboard directly in front of the rider.
			local targetWheelieComp = if vehiclePitch > 0
				then -vehiclePitch * Config.FirstPerson.WheeliePitchCompensation
				else 0
			currentWheelieComp += (targetWheelieComp - currentWheelieComp) * math.clamp(dt * 12, 0, 1)

			-- Combined head orientation (resting at natural downward road gaze to frame dashboard):
			local totalYaw = vehicleYaw + firstPersonYaw
			local restingPitch = vehiclePitch + currentWheelieComp + Config.FirstPerson.DefaultPitch
			local totalPitch = math.clamp(
				restingPitch + firstPersonPitch,
				Config.FirstPerson.MinPitch,
				Config.FirstPerson.MaxPitch
			)
			local totalRoll = currentRoll

			-- Eye position in world space:
			local char = player.Character
			local headPartInstance = if char then char:FindFirstChild("Head") :: BasePart? else nil
			local baseEyePos = if headPartInstance
				then headPartInstance.Position
				else (root.Position + Vector3.new(0, 3.8, 0))

			local eyeWorldPos = baseEyePos
				+ rootCF.LookVector * (Config.FirstPerson.EyeForwardOffset + currentInertiaShift)
				+ rootCF.UpVector * Config.FirstPerson.EyeUpOffset
				+ shakeOffset

			local cameraRotation = CFrame.Angles(0, totalYaw, 0)
				* CFrame.Angles(totalPitch, 0, 0)
				* CFrame.Angles(0, 0, totalRoll)

			camera.CFrame = CFrame.new(eyeWorldPos) * cameraRotation
			camera.Focus = CFrame.new(eyeWorldPos + camera.CFrame.LookVector * 5)

		else
			local now = os.clock()

			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then
				isManualLooking = true
				lastManualInputAt = now
			end

			local isFreeLooking = isManualLooking or ((now - lastManualInputAt) < Config.ThirdPerson.AutoFollowDelay)
			local isDriving = speedKmh > Config.ThirdPerson.AutoFollowMinSpeedKmh
				or math.abs(seat.ThrottleFloat) > 0.05
				or math.abs(seat.SteerFloat) > 0.05

			local baseCFrame = camera.CFrame

			-- Auto-follow: if player is driving and has not touched camera controls in 3s,
			-- smoothly align camera yaw behind the scooter's forward heading
			if not isFreeLooking and isDriving then
				local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				if forward.Magnitude > 0.01 then
					forward = forward.Unit
					local targetFocus = if currentHead then currentHead.Position else camera.Focus.Position
					local camOffset = baseCFrame.Position - targetFocus
					local camDistHoriz = Vector3.new(camOffset.X, 0, camOffset.Z).Magnitude

					if camDistHoriz > 0.5 then
						local currentCamYaw = math.atan2(camOffset.X, camOffset.Z)
						local targetCamYaw = math.atan2(-forward.X, -forward.Z)
						local diffYaw = (targetCamYaw - currentCamYaw + math.pi) % (2 * math.pi) - math.pi

						if math.abs(diffYaw) > 0.002 then
							local step = diffYaw * math.clamp(dt * Config.ThirdPerson.AutoFollowSpeed, 0, 1)
							local rotCFrame = CFrame.new(targetFocus) * CFrame.Angles(0, step, 0) * CFrame.new(-targetFocus)
							baseCFrame = rotCFrame * baseCFrame
						end
					end
				end
			end

			local targetRoll = -turnIntensity * Config.ThirdPerson.MaxBankingAngle
			currentRoll += (targetRoll - currentRoll) * math.clamp(dt * Config.ThirdPerson.BankingSmoothing, 0, 1)

			local speedRatio = math.clamp(speedKmh / Config.Fov.MaxSpeedKmh, 0, 1)
			local targetPullback = speedRatio * Config.ThirdPerson.MaxSpeedPullback
			currentPullback += (targetPullback - currentPullback) * math.clamp(dt * Config.ThirdPerson.PullbackSmoothing, 0, 1)

			local shakeOffset = Vector3.zero
			if isBurnout or speedKmh > Config.ThirdPerson.ShakeSpeedThresholdKmh then
				shakeTime += dt * Config.ThirdPerson.ShakeFrequency
				local amp = if isBurnout
					then Config.ThirdPerson.BurnoutShakeAmplitude
					else Config.ThirdPerson.ShakeAmplitude * math.clamp((speedKmh - 50) / 40, 0, 1)
				shakeOffset = Vector3.new(
					math.noise(shakeTime, 0, 0),
					math.noise(0, shakeTime, 0),
					0
				) * amp
			end

			local rollRotation = CFrame.Angles(0, 0, currentRoll)
			local pullbackOffset = -baseCFrame.LookVector * currentPullback

			camera.CFrame = CFrame.new(pullbackOffset + shakeOffset)
				* baseCFrame
				* rollRotation
		end
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRender)

	return {
		Destroy = function()
			if destroyed then return end
			destroyed = true
			RunService:UnbindFromRenderStep(BIND_NAME)

			for _, conn in inputConnections do
				conn:Disconnect()
			end
			table.clear(inputConnections)

			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			setCharacterHeadVisibility(true)

			local currentCam = Workspace.CurrentCamera
			local char = player.Character
			local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil

			if currentCam then
				currentCam.CameraType = Enum.CameraType.Custom
				if humanoid then
					currentCam.CameraSubject = humanoid
				elseif originalCameraSubject and originalCameraSubject.Parent then
					currentCam.CameraSubject = originalCameraSubject
				end

				local resetTween = TweenService:Create(
					currentCam,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ FieldOfView = Config.Fov.Base }
				)
				resetTween:Play()
			end

			player.CameraMinZoomDistance = originalMinZoom
			player.CameraMaxZoomDistance = originalMaxZoom
		end,
		SetMode = setMode,
		GetMode = function() return currentMode end,
		CycleMode = cycleMode,
	}
end

return ScooterCamera
