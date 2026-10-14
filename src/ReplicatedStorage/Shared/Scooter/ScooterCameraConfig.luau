--!strict

-- Configuration for dynamic riding camera and camera view modes.
return table.freeze({
	-- Field of View dynamics (applies across camera modes)
	Fov = table.freeze({
		Base = 70,
		Max = 84,
		SpeedThresholdKmh = 10,
		MaxSpeedKmh = 90, -- Matches KuKirin G4 top speed
		RampPower = 1.15,
		Smoothing = 7.5, -- Lerp rate per second
	}),

	-- Third person dynamic camera offsets
	ThirdPerson = table.freeze({
		-- Classic Roblox starting zoom distance
		DefaultZoom = 12.8,

		-- Roll / banking in turns (subtle Dutch angle)
		MaxBankingAngle = math.rad(3.5),
		BankingSmoothing = 6,

		-- Speed lag (camera slightly pulls back on speed)
		MaxSpeedPullback = 1.8,
		PullbackSmoothing = 5,

		-- Subtle road vibration at high speed & burnout
		ShakeSpeedThresholdKmh = 50,
		ShakeAmplitude = 0.035, -- studs
		ShakeFrequency = 22, -- Hz
		BurnoutShakeAmplitude = 0.07,

		-- Auto-follow: smoothly tracks behind the driving vector if user is not manually orbiting
		AutoFollowSpeed = 3.0,
		AutoFollowDelay = 3.0,
		AutoFollowMinSpeedKmh = 2.0,
	}),

	-- First person dynamic adjustments (looking from avatar's eyes at handlebars)
	FirstPerson = table.freeze({
		HeadRollAngle = math.rad(3.5), -- Head leans into corner apex
		HeadRollSmoothing = 8,

		-- Forward and up eye shift from head center (lowered and pushed forward to clearly frame dashboard)
		EyeForwardOffset = 0.60,
		EyeUpOffset = -0.10, -- Lowered so speedometer & handlebars are in full view with straight head

		-- Natural resting pitch (downward road gaze so the entire speedometer is readable without looking down)
		DefaultPitch = -math.rad(14.0),

		-- Head yaw limits relative to vehicle forward heading (cannot look backwards)
		MaxHeadYaw = math.rad(75), -- Maximum 75 deg turn left / right
		YawResistanceLimit = math.rad(84), -- Elastic resistance limit when over-dragging
		AutoCenterDelay = 1.0, -- Seconds after mouse look stops before head smoothly re-centers
		AutoCenterSpeed = 4.0, -- Smoothing speed to return gaze forward

		-- Pitch limits (sees handlebars and dashboard, prevents looking into torso or straight up)
		MinPitch = -math.rad(36), -- Max down angle (stops before collar / torso)
		MaxPitch = math.rad(42), -- Max up angle (stops before vertical sky)

		-- Wheelie pitch compensation: counter-rotates head forward so gaze stays on road and dashboard
		WheeliePitchCompensation = 0.85, -- Fraction of vehicle pitch compensated when front lifts

		-- Longitudinal inertia (head shifts back on accel, forward on brake)
		AccelShift = 0.15, -- Studs back on acceleration
		BrakeShift = 0.22, -- Studs forward on braking
		ShiftSmoothing = 7,

		-- High-speed and burnout handlebar vibration
		VibrationSpeedThresholdKmh = 45,
		VibrationAmplitude = 0.02,
		BurnoutVibrationAmplitude = 0.04,
	}),

	-- Mode names
	Modes = table.freeze({
		ThirdPerson = "ThirdPerson",
		FirstPerson = "FirstPerson",
	}),
})
