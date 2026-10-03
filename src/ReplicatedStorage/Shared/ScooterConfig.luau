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

ScooterConfig.Models = {
	["KuKirin G2 Pro"] = {
		maxSpeed = 55,
		acceleration = 135,
		turnTorque = 6200,
		wheelieTorque = 5200,
	},
	["KuKirin G2 Max"] = {
		maxSpeed = 65,
		acceleration = 145,
		turnTorque = 6500,
		wheelieTorque = 5700,
	},
	["KuKirin G2 Master"] = {
		maxSpeed = 72,
		acceleration = 155,
		turnTorque = 6800,
		wheelieTorque = 6100,
	},
	["KuKirin G3 Pro"] = {
		maxSpeed = 80,
		acceleration = 170,
		turnTorque = 7200,
		wheelieTorque = 6500,
	},
	["KuKirin G4"] = {
		maxSpeed = 90,
		acceleration = 185,
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
-- All catalog entries use the single Studio-authored articulated rig.
ScooterConfig.TemplateName = "scooter"
ScooterConfig.SteeringServoTorque = 6000
ScooterConfig.SteeringServoSpeed = 8
ScooterConfig.SteeringServoSign = -1
ScooterConfig.SteeringAnglePrecisionDegrees = 0.1
ScooterConfig.BrakeLight = {
	Enabled = false,
	Color = Color3.fromRGB(255, 20, 20),
	Brightness = 1.5,
	Range = 4,
	EmissiveStrength = 1,
}
ScooterConfig.BurnoutMotorTorque = 100
ScooterConfig.BurnoutMotorForceScale = 0.6
ScooterConfig.BurnoutMotorAcceleration = 120
ScooterConfig.BurnoutTurnRate = math.rad(90)
-- Gameplay conversion keeps catalog ratings while increasing world travel speed.
ScooterConfig.StudsPerKmH = 1.6
ScooterConfig.BurnoutMaxSpeedKmh = 5
ScooterConfig.BurnoutSmokeMaxSpeed = ScooterConfig.BurnoutMaxSpeedKmh * ScooterConfig.StudsPerKmH
ScooterConfig.CoastingDeceleration = 10
ScooterConfig.BrakingDeceleration = 40
ScooterConfig.DirectionChangeBrakingDeceleration = 60
ScooterConfig.DirectionChangeSpeedKmh = 2
ScooterConfig.ReverseAcceleration = 75
ScooterConfig.MaxReverseSpeedKmh = 18
ScooterConfig.TurnRate = math.rad(165)
ScooterConfig.MaxHeadingLeadAngle = math.rad(12)
ScooterConfig.HeadingLeadSeconds = 0.15
ScooterConfig.MinSteeringSpeed = 0.5
ScooterConfig.StopSpeed = 0.25
ScooterConfig.SteerSmoothSpeed = 14
ScooterConfig.SteeringFadeStartKmh = 40
ScooterConfig.SteeringFadeEndKmh = 90
ScooterConfig.HighSpeedSteeringScale = 0.55
ScooterConfig.LateralGripDeceleration = 100
ScooterConfig.HillAssistGravityScale = 0.85
ScooterConfig.WheelieMinSpeedKmh = 10
ScooterConfig.WheelieMinSpeed = ScooterConfig.WheelieMinSpeedKmh * ScooterConfig.StudsPerKmH
ScooterConfig.WheelieKickAngle = math.rad(14)
ScooterConfig.WheeliePitchRate = math.rad(34)
ScooterConfig.WheelieBrakeDropRate = math.rad(125)
ScooterConfig.WheelieNaturalDropRate = math.rad(45)
ScooterConfig.WheelieReturnSpeed = 2.5
ScooterConfig.WheelieBrakeReturnSpeed = 8
ScooterConfig.WheelieRestAngle = math.rad(0.25)
ScooterConfig.WheelieLowSpeedDropStart = 6
ScooterConfig.WheelieLowSpeedDropRate = math.rad(80)
ScooterConfig.WheelieStallDropRate = math.rad(260)
ScooterConfig.WheelieFallAngle = math.rad(68)
ScooterConfig.WheelieRecoveryDelay = 1.5
ScooterConfig.CrashStunDuration = 2
ScooterConfig.CrashEjectUpVelocity = 7
ScooterConfig.CrashEjectSideVelocity = 9
ScooterConfig.UprightResponsiveness = 18
ScooterConfig.UprightTorqueStiffness = 180
ScooterConfig.UprightTorqueDamping = 26
ScooterConfig.PredictionCorrectionRate = 12
ScooterConfig.PredictionVelocityCorrectionRate = 10
ScooterConfig.PredictionMaxError = 2
ScooterConfig.PredictionMaxAngle = math.rad(12)
ScooterConfig.PredictionCameraLead = 0.35
ScooterConfig.PredictionCameraBlendSpeed = 12
ScooterConfig.MaxSteeringLean = math.rad(16)
ScooterConfig.SteeringLeanSmoothSpeed = 8
ScooterConfig.MaxHandlebarAngle = math.rad(30)
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
	Revision = 1,
	ShowConstraints = false,
	ReferenceRiderMass = 20,
	PreloadSupportFraction = 0.8,
	DampingRatio = 0.8,
	ForceHeadroom = 4,
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
ScooterConfig.SuspensionProbeLift = 1.25
ScooterConfig.GroundNormalSmoothSpeed = 14
ScooterConfig.StepProbeDistance = 1.8
ScooterConfig.StepProbeHeight = 0.02
ScooterConfig.MaxStepHeight = 1.6
ScooterConfig.StepMinUpVelocity = 4
ScooterConfig.StepMaxUpVelocity = 28
ScooterConfig.StepVelocityScale = 1.05
ScooterConfig.StepForwardVelocity = 8
ScooterConfig.StepCooldown = 0.18
ScooterConfig.ParkingLinearDamping = 4.5
ScooterConfig.ParkingAngularDamping = 7
ScooterConfig.ParkingGroundProbeDistance = 4
ScooterConfig.RidePromptDistance = 8
ScooterConfig.WheelFriction = 0.03
ScooterConfig.GroundColliderFriction = 0.15
ScooterConfig.TrickCooldown = 0.15
ScooterConfig.WheelieCooldown = 0.3
ScooterConfig.GroundMinNormalY = 0.35
ScooterConfig.MaxGroundedVerticalSpeed = 8
ScooterConfig.SpawnCooldown = 3
ScooterConfig.DriveInputTimeout = 0.75
ScooterConfig.DriveRemoteMinInterval = 0.04
ScooterConfig.DriveInputKeepalive = 0.25
ScooterConfig.DriveInputSendInterval = 0.05
ScooterConfig.SteeringSendThreshold = 0.02
ScooterConfig.BurnoutWheelAngularSpeed = 55
ScooterConfig.BurnoutSmokeRate = 32
ScooterConfig.BurnoutSmokeLifetime = NumberRange.new(0.6, 0.9)
ScooterConfig.NeonBrightness = 1.5
ScooterConfig.NeonRange = 7
ScooterConfig.RiderPose = {
	BlendSpeed = 9,
	FootPlantClearance = 0.01,
	FootTargetSink = 0.08,
	WheelieRearFootShift = 0.15,
	BalanceFootOffset = Vector3.new(0.2, 0, 0.2),
	BalanceFootSwing = Vector3.new(0.08, 0, 0.08),
	BalanceFootFrequency = 7,
	MaxBodyLean = math.rad(22),
	LeanFullSpeed = 24,
	LateralLeanFullSpeed = 10,
	LateralLeanWeight = 0.25,
	RootLeanShare = 0.3,
	ElbowOutwardOffset = 1.2,
	ElbowForwardOffset = 0.6,
	ElbowLift = 0.7,
	GripHalfWidth = 0.58,
}
ScooterConfig.RiderAnimations = {
	-- Supply R15 clips that key the legs/pelvis and leave the arms to hand IK.
	IdleFootAnim = "",
	WheelieBalanceAnim = "",
	FadeTime = 0.25,
	Weight = 1,
	PlaybackSpeed = 1,
	IdleEnterSpeedKmh = 0.5,
	IdleExitSpeedKmh = 1.5,
}
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

return ScooterConfig
