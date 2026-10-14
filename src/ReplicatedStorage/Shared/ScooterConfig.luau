--!strict

export type ModelTuning = {
	maxSpeed: number,
	acceleration: number,
	turnTorque: number,
	wheelieTorque: number,
}
export type Tuning = ModelTuning & { speedTier: number }

local ScooterConfig = {}

-- Secondary systems remain parked while validating the drivable Studio MVP.
ScooterConfig.GarageEnabled = false
ScooterConfig.StudioScaleComparisonEnabled = false -- 0.25 selected after comparison.
ScooterConfig.StudioModelComparisonEnabled = true
ScooterConfig.StudioModelVariants = {
	{ Id = "g2_pro", TemplateName = "scooter", Label = "G2 Pro — jazda testowa", Offset = Vector3.new(-6, 0, 8) },
	{ Id = "g4", TemplateName = "scooter_g4", Label = "G4 — jazda testowa", Offset = Vector3.new(6, 0, 8) },
}

-- Developer comparisons reuse the owned scooter's tuning; they are not shop products.
ScooterConfig.StudioScaleVariants = {
	{ Id = "scale020", Scale = 0.20, TemplateName = "scooter_scale020", Label = "KuKirin 0,20", Offset = Vector3.new(-10, 0, 9) },
	{ Id = "scale025", Scale = 0.25, TemplateName = "scooter", Label = "KuKirin 0,25", Offset = Vector3.new(10, 0, 9) },
}

ScooterConfig.DriveModes = {
	Default = "SPORT",
	EcoMaxSpeedKmh = 25,
	EcoAccelerationScale = 0.7,
	ToggleCooldown = 0.4,
	ToggleRemoteName = "ToggleDriveMode",
}

ScooterConfig.Models = {
	["KuKirin G2 Pro"] = {
		maxSpeed = 55,
		acceleration = 25,
		turnTorque = 6200,
		wheelieTorque = 5200,
	},
	["KuKirin G2 Max"] = {
		maxSpeed = 65,
		acceleration = 28,
		turnTorque = 6500,
		wheelieTorque = 5700,
	},
	["KuKirin G2 Master"] = {
		maxSpeed = 72,
		acceleration = 31,
		turnTorque = 6800,
		wheelieTorque = 6100,
	},
	["KuKirin G3 Pro"] = {
		maxSpeed = 80,
		acceleration = 35,
		turnTorque = 7200,
		wheelieTorque = 6500,
	},
	["KuKirin G4"] = {
		maxSpeed = 90,
		acceleration = 40,
		turnTorque = 7600,
		wheelieTorque = 7000,
	},
} :: { [string]: ModelTuning }

ScooterConfig.MaxSpeedUpgradeTier = 3
ScooterConfig.SpeedPerUpgradeKmh = 1.5
ScooterConfig.SpeedUpgradeCosts = {
	["KuKirin G2 Pro"] = { 300, 600, 1_200 },
	["KuKirin G2 Max"] = { 600, 1_200, 2_400 },
	["KuKirin G2 Master"] = { 1_500, 3_000, 6_000 },
	["KuKirin G3 Pro"] = { 4_000, 8_000, 14_000 },
	["KuKirin G4"] = { 8_000, 16_000, 24_000 },
} :: { [string]: { number } }
ScooterConfig.GarageRequestCooldown = 0.25
ScooterConfig.EntitlementCacheSeconds = 60
ScooterConfig.GarageRequestFunctionName = "GarageRequest"

ScooterConfig.DefaultModel = "KuKirin G2 Pro"
-- Products without a dedicated model keep the existing articulated template.
ScooterConfig.TemplateName = "scooter"
ScooterConfig.ModelTemplates = { ["KuKirin G4"] = "scooter_g4" } :: { [string]: string }
ScooterConfig.SteeringServoTorque = 6000
ScooterConfig.SteeringServoSpeed = 14
ScooterConfig.SteeringServoResponsiveness = 40
ScooterConfig.TurnSteeringResponse = 8 -- Retained for existing helpers; the server no longer stacks this filter.
ScooterConfig.YawResponse = 30
ScooterConfig.MaxYawAcceleration = math.rad(1800)
ScooterConfig.SteeringServoSign = -1
ScooterConfig.SteeringAnglePrecisionDegrees = 0.1
ScooterConfig.BrakeLight = {
	Enabled = false,
	Color = Color3.fromRGB(255, 20, 20),
	Brightness = 1.5,
	Range = 4,
	EmissiveStrength = 1,
}
ScooterConfig.StopLight = {
	Enabled = true, Color = Color3.fromRGB(255, 28, 35),
	OffColor = Color3.fromRGB(85, 10, 14), Brightness = 1.5, Range = 4, EmissiveStrength = 1,
}
ScooterConfig.Headlight = {
	ToggleRemoteName = "ToggleHeadlight", ToggleCooldown = 0.35,
	Color = Color3.new(1, 1, 1), Brightness = 3, Range = 36, Angle = 65, EmissiveStrength = 1,
}
ScooterConfig.BurnoutMotorTorque = 100
ScooterConfig.BurnoutMotorForceScale = 0.6
ScooterConfig.BurnoutMotorAcceleration = 120
ScooterConfig.BurnoutTurnRate = math.rad(90)
-- Gameplay conversion keeps catalog ratings while increasing world travel speed.
ScooterConfig.StudsPerKmH = 1.6
ScooterConfig.BurnoutMaxSpeedKmh = 5
ScooterConfig.BurnoutSmokeMaxSpeed = ScooterConfig.BurnoutMaxSpeedKmh * ScooterConfig.StudsPerKmH
ScooterConfig.CoastingDeceleration = 6
ScooterConfig.BrakingDeceleration = 40
ScooterConfig.DirectionChangeBrakingDeceleration = 60
ScooterConfig.DirectionChangeSpeedKmh = 2
ScooterConfig.ReverseAcceleration = 25
ScooterConfig.MaxReverseSpeedKmh = 18
ScooterConfig.TurnRate = math.rad(165)
ScooterConfig.MaxHeadingLeadAngle = math.rad(12)
ScooterConfig.HeadingLeadSeconds = 0.15
ScooterConfig.MinSteeringSpeed = 0.5
ScooterConfig.StopSpeed = 0.25
ScooterConfig.SteerSmoothSpeed = 9
ScooterConfig.SteeringFadeStartKmh = 25
ScooterConfig.SteeringFadeEndKmh = 80
ScooterConfig.HighSpeedSteeringScale = 0.55
ScooterConfig.LateralGripDeceleration = 100
ScooterConfig.LateralGripResponse = 10
-- Build tighter held turns gradually; a brief steering tap keeps its original lead.
ScooterConfig.HeldSteering = { Delay = 0.18, RampTime = 0.45, MaxHeadingLeadAngle = math.rad(20) }
ScooterConfig.LowSpeedTurnBoost = 1.2
ScooterConfig.HillAssistGravityScale = 0.85
ScooterConfig.WheelieMinSpeedKmh = 10
ScooterConfig.WheelieMinSpeed = ScooterConfig.WheelieMinSpeedKmh * ScooterConfig.StudsPerKmH
ScooterConfig.WheelieKickAngle = math.rad(5)
ScooterConfig.WheeliePitchRate = math.rad(28)
ScooterConfig.WheelieBrakeDropRate = math.rad(125)
ScooterConfig.WheelieNaturalDropRate = math.rad(24)
ScooterConfig.WheelieReturnSpeed = 2.6
ScooterConfig.WheelieBrakeReturnSpeed = 8
ScooterConfig.WheelieRestAngle = math.rad(0.25)
ScooterConfig.WheelieLowSpeedDropStart = 6
ScooterConfig.WheelieLowSpeedDropRate = math.rad(80)
ScooterConfig.WheelieStallDropRate = math.rad(260)
ScooterConfig.WheelieFallAngle = math.rad(68)
ScooterConfig.WheelieRecoveryDelay = 1.5
ScooterConfig.WheelieSparks = {
	StartPitch = math.rad(48), StopPitch = math.rad(43), MinSpeed = 8,
	ContactDistance = 0.65, Rate = 85,
	Size = 0.36, Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(10, 18),
	Texture = "rbxasset://textures/particles/sparkles_main.dds",
}
ScooterConfig.CrashStunDuration = 2
ScooterConfig.CrashEjectUpVelocity = 7
ScooterConfig.CrashEjectSideVelocity = 9
ScooterConfig.Impact = {
	MinSpeedKmh = 24, MinSpeedLoss = 12, MemorySeconds = 0.2,
	ProbePadding = 0.15, MaxNormalY = 0.3, MinOpposition = 0.65,
	TipImpulsePerMass = 6,
}
ScooterConfig.UprightResponsiveness = 18
ScooterConfig.UprightTorqueStiffness = 180
ScooterConfig.UprightTorqueDamping = 26
ScooterConfig.PredictionCorrectionRate = 12
ScooterConfig.PredictionVelocityCorrectionRate = 10
ScooterConfig.PredictionMaxError = 2
ScooterConfig.PredictionMaxAngle = math.rad(12)
ScooterConfig.PredictionCameraLead = 0.35
ScooterConfig.PredictionCameraBlendSpeed = 12
ScooterConfig.MaxSteeringLean = math.rad(28)
ScooterConfig.SteeringLeanSmoothSpeed = 8
ScooterConfig.MaxHandlebarAngle = math.rad(48)
ScooterConfig.HandlebarSmoothSpeed = 18
ScooterConfig.HandlebarInputExponent = 0.72
ScooterConfig.WheelBase = 4.5
ScooterConfig.WheelRadius = 0.7
ScooterConfig.WheelColliderClearance = 0.03
ScooterConfig.SpawnGroundClearance = 0.25
ScooterConfig.DeckColliderInset = 0.03
ScooterConfig.FrontRestPose = {
	Revision = 1, MaxCorrectionDegrees = 45, HeightTolerance = 0.01,
	MatchRearMount = true, MaxMountShiftRadiusRatio = 4,
}
ScooterConfig.RigValidation = {
	PositionTolerance = 0.03,
	AxisToleranceDegrees = 2,
	MinimumSteeringAxisUpDot = 0.3,
}
ScooterConfig.Suspension = {
	Revision = 3,
	ShowConstraints = false,
	ReferenceRiderMass = 20,
	PreloadSupportFraction = 0.8,
	DampingRatio = 1.4,
	ForceHeadroom = 1.1,
	MinimumLeverageRatio = 0.02,
	SampleStepDegrees = 0.5,
	LimitMarginDegrees = 1,
	Front = {
		CompressionRadiusRatio = 0.4, DroopRadiusRatio = 0.2,
		MaxCompressionDegrees = 22, MaxDroopDegrees = 12, SagFraction = 0.4,
	},
	Back = {
		CompressionRadiusRatio = 0.4, DroopRadiusRatio = 0.2,
		MaxCompressionDegrees = 22, MaxDroopDegrees = 12, SagFraction = 0.3,
	},
}
ScooterConfig.GroundProbeTolerance = 0.45
ScooterConfig.DeckSupportTolerance = 0.18
ScooterConfig.DeckSupportProbeThickness = 0.05
ScooterConfig.SuspensionProbeLift = 1.25
ScooterConfig.GroundNormalSmoothSpeed = 14
ScooterConfig.StepProbeDistance = 1.8
ScooterConfig.StepProbeHeight = 0.14
ScooterConfig.StepProbeLowerHeight = 0.02
ScooterConfig.MaxStepHeight = 2.5
-- Small ledges use a server-authored height path rather than tire climbing forces.
ScooterConfig.ArcadeSteps = {
	Enabled = true,
	HeightResponse = 8,
	HeightTrackingResponse = 8,
	MaxRiseSpeed = 6,
	MaxDropSpeed = 6,
	MaxHeightAcceleration = 24,
	IntegrationStep = 1 / 120,
	ApproachSeconds = 0.25,
	MaxApproachDistance = 16,
	Clearance = 0,
	SettleTolerance = 0.04,
	MaxDuration = 8,
	MinimumEdgeHeight = 0.06,
	FlatSurfaceNormalY = 0.9,
	SuspensionCompression = 0.7,
	SuspensionResponse = 12,
	SuspensionAttack = 0.12,
	SuspensionHold = 0.08,
	SuspensionRelease = 0.4,
	SuspensionLeadSeconds = 0.06,
	SuspensionTorqueScale = 1.2,
	SuspensionAngularSpeed = 2.5,
	SuspensionResponsiveness = 24,
}
ScooterConfig.RideVisuals = { SuspensionResponse = 18, MaxSuspensionSpeed = 2, SpinResponse = 14, MaxDistance = 180 }
ScooterConfig.StepTraction = {
	-- Arcade curb assistance: a contacted ledge can be taller than the tire.
	MaxRadiusRatio = 3.5, ContactPadding = 0.18, MinForwardTangentRatio = 0.15,
	MinFaceOpposition = math.sin(math.rad(0.5)),
	FaceEntryBias = 0.6,
	RetainedContactPadding = 0.45,
	ContactTurnTolerance = math.sin(math.rad(3)),
	EntryNormalSpeed = 3,
	EntryNormalResponse = 14,
	EntryNormalAcceleration = 60,
	EntryNormalFadeOpposition = 0.5,
	ClimbSpeed = 5.5, Response = 16, Acceleration = 100, SupportMassFraction = 0.85,
	PairedSupportMassFraction = 1,
	ChassisRiseDamping = 35, ChassisRiseDeceleration = 600,
	ChassisClimbSpeed = 3.5,
	SurfaceRiseTolerance = 0.05,
	ApproachSeconds = 0.12, MaxApproachDistance = 5,
	SettleSeconds = 0.25, SettleProbeDistance = 0.65,
	RampMinNormalY = 0.08, RampMaxNormalY = 0.98,
	GentleStep = { MaxRise = 1.25, ClimbSpeed = 3.5, Response = 12, Acceleration = 60, LiftFadeSpeed = 3 },
	AirContactGraceSeconds = 1.25,
	HeightTolerance = 0.06, -- Solver penetration must not reject a ledge at the configured limit.
	ForwardAcceleration = 80, ForwardResponse = 8, MinimumForwardSpeed = 8, SpeedRetention = 1,
	MaxChassisPitch = math.rad(20),
}
ScooterConfig.ParkingLinearDamping = 4.5
ScooterConfig.ParkingAngularDamping = 7
ScooterConfig.ParkingGroundProbeDistance = 4
ScooterConfig.RidePromptDistance = 8
ScooterConfig.WheelFriction = 0.03
ScooterConfig.GroundColliderFriction = 0.15
ScooterConfig.DeckColliderFriction = 0.02
ScooterConfig.TrickCooldown = 0.15
ScooterConfig.WheelieCooldown = 0.3
ScooterConfig.GroundMinNormalY = 0.35
ScooterConfig.MaxGroundedVerticalSpeed = 8
ScooterConfig.SpawnCooldown = 3
ScooterConfig.DriveInputTimeout = 0.75
ScooterConfig.DriveRemoteMinInterval = 0.01
ScooterConfig.DriveInputKeepalive = 0.25
ScooterConfig.DriveInputSendInterval = 0.025
ScooterConfig.SteeringSendThreshold = 0.02
ScooterConfig.BurnoutWheelAngularSpeed = 55
ScooterConfig.BurnoutSmokeRate = 32
ScooterConfig.BurnoutSmokeLifetime = NumberRange.new(0.6, 0.9)
ScooterConfig.NeonBrightness = 1.5
ScooterConfig.NeonRange = 7
ScooterConfig.RiderGripHalfWidth = 0.58
ScooterConfig.RiderDeckClearance = 0.01
ScooterConfig.RiderAnimationDistance = 150
-- Calibrated against the 8-stud R15 rider and the installed FootRest/grips.
ScooterConfig.Handling = {
 ThrottleResponse = 6,
 BrakeResponse = 12,
 LeanAttackResponse = 12,
 LeanReturnResponse = 16,
 MaxLeanRate = math.rad(180),
}
ScooterConfig.RiderDynamics = {
 Response = 8,
 AccelerationReference = 35,
 AccelerationLean = math.rad(6),
 BrakingLean = math.rad(8),
 SpeedLean = math.rad(3),
 LeanFullSpeedKmh = 45,
 BodyCorneringFraction = -0.25,
 SteeringTorsoYaw = 0.55,
 SteeringReachLean = math.rad(8),
 MaximumBodyCornering = math.rad(8),
 WheelieRootCounter = 0.25,
 WheelieTorsoCounter = 0.30,
 WheelieCrouch = 0.14,
 WheelieStartCrouch = 0.05,
 AccelerationCrouch = 0.04,
 HeadLevelFraction = 0.55,
 LandingCrouch = 0.16,
 LandingResponse = 12,
 VerticalAccelerationReference = 100,
 ReachShiftLimit = 0.35,
 ArmReachMargin = 0.10,
}
ScooterConfig.WheelieBalance = {
 TargetAngle = math.rad(35),
 MaximumBalanceAngle = math.rad(45),
 Response = 2.2,
 SteeringScale = 0.30,
 MinimumPhysicalAngle = math.rad(8),
 SpeedReferenceKmh = 45,
 SpeedAngleBonus = math.rad(3),
 FallMargin = math.rad(5),
}
ScooterConfig.BaseRidingPose = {
	CrouchHipHeightFraction = 0.27,
	RootForwardOffset = 0.85,
	TorsoLean = math.rad(7),
	HandPalmPitch = math.rad(-90),
	FootLateralOffset = 0.10,
	DeckMargin = 0.015,
	ElbowPoleWidth = 1.8,
	ElbowPoleHeight = 4.2,
	ElbowPoleForwardOffset = 0.6,
	FrontFootPitch = math.rad(8),
	RearFootPitch = math.rad(-8),
}
ScooterConfig.IdleLeanSpeedKmh = 0.5
ScooterConfig.IdleScooterLean = math.rad(6)
ScooterConfig.IdleProbeLift = 3
ScooterConfig.IdleProbeDepth = 8
ScooterConfig.IdleProbeInterval = 0.08
ScooterConfig.ScooterFolderName = "Scooters"
ScooterConfig.RemoteFolderName = "ScooterRemotes"

function ScooterConfig.IsValidSpeedTier(tier: unknown): boolean
	return typeof(tier) == "number"
		and tier == tier
		and tier >= 0
		and tier <= ScooterConfig.MaxSpeedUpgradeTier
		and tier % 1 == 0
end

function ScooterConfig.GetTuning(modelName: string, speedTier: number): Tuning?
	local base = ScooterConfig.Models[modelName]
	if not base or not ScooterConfig.IsValidSpeedTier(speedTier) then
		return nil
	end
	local maxSpeed = base.maxSpeed + speedTier * ScooterConfig.SpeedPerUpgradeKmh
	return {
		maxSpeed = maxSpeed,
		acceleration = base.acceleration * maxSpeed / base.maxSpeed,
		turnTorque = base.turnTorque,
		wheelieTorque = base.wheelieTorque,
		speedTier = speedTier,
	}
end

function ScooterConfig.GetUpgradeCost(modelName: string, currentTier: number): number?
	if not ScooterConfig.IsValidSpeedTier(currentTier) then
		return nil
	end
	local costs = ScooterConfig.SpeedUpgradeCosts[modelName]
	return if costs then costs[currentTier + 1] else nil
end

function ScooterConfig.GetDriveModeMaxSpeed(sportMaxSpeed: number, mode: string): number
	return if mode == "ECO" then math.min(sportMaxSpeed, ScooterConfig.DriveModes.EcoMaxSpeedKmh) else sportMaxSpeed
end

function ScooterConfig.GetDriveModeAcceleration(sportAcceleration: number, mode: string): number
	return sportAcceleration * (if mode == "ECO" then ScooterConfig.DriveModes.EcoAccelerationScale else 1)
end

return ScooterConfig
