--!strict

local ScooterConfig = {}

ScooterConfig.Models = {
	["KuKirin G2 Pro"] = {
		maxSpeed = 45,
		acceleration = 82,
		turnTorque = 4200,
		jumpImpulse = 48,
		wheelieTorque = 5200,
	},
	["KuKirin G2 Max"] = {
		maxSpeed = 55,
		acceleration = 92,
		turnTorque = 4500,
		jumpImpulse = 50,
		wheelieTorque = 5700,
	},
	["KuKirin G2 Master"] = {
		maxSpeed = 60,
		acceleration = 98,
		turnTorque = 4700,
		jumpImpulse = 52,
		wheelieTorque = 6100,
	},
	["KuKirin G3 Pro"] = {
		maxSpeed = 65,
		acceleration = 104,
		turnTorque = 5000,
		jumpImpulse = 54,
		wheelieTorque = 6500,
	},
	["KuKirin G4"] = {
		maxSpeed = 70,
		acceleration = 112,
		turnTorque = 5400,
		jumpImpulse = 56,
		wheelieTorque = 7000,
	},
}

ScooterConfig.DefaultModel = "KuKirin G2 Pro"
ScooterConfig.StudsPerKmH = 0.78
ScooterConfig.BurnoutMaxSpeed = 6
ScooterConfig.CoastingDeceleration = 10
ScooterConfig.BrakingDeceleration = 40
ScooterConfig.ReverseAcceleration = 11
ScooterConfig.MaxReverseSpeedKmh = 12
ScooterConfig.TurnRate = math.rad(105)
ScooterConfig.MinSteeringSpeed = 1.5
ScooterConfig.StopSpeed = 0.25
ScooterConfig.SteerSmoothSpeed = 10
ScooterConfig.SteeringFadeStartKmh = 18
ScooterConfig.SteeringFadeEndKmh = 55
ScooterConfig.HighSpeedSteeringScale = 0.32
ScooterConfig.LateralGripDeceleration = 24
ScooterConfig.WheelieMinSpeed = 3
ScooterConfig.WheelieKickAngle = math.rad(14)
ScooterConfig.WheeliePitchRate = math.rad(34)
ScooterConfig.WheelieReturnRate = math.rad(70)
ScooterConfig.WheelieNeutralDropRate = math.rad(30)
ScooterConfig.WheelieFallAngle = math.rad(68)
ScooterConfig.WheelieRecoveryDelay = 1.5
ScooterConfig.CrashStunDuration = 2
ScooterConfig.CrashEjectUpVelocity = 7
ScooterConfig.CrashEjectSideVelocity = 9
ScooterConfig.UprightResponsiveness = 12
ScooterConfig.MaxSteeringLean = math.rad(8)
ScooterConfig.MaxHandlebarAngle = math.rad(28)
ScooterConfig.MaxAccelerationLean = math.rad(3)
ScooterConfig.WheelBase = 4.5
ScooterConfig.WheelRadius = 0.7
ScooterConfig.SuspensionRestLength = 0.32
ScooterConfig.SuspensionTravel = 0.32
ScooterConfig.SuspensionStiffness = 700
ScooterConfig.SuspensionDamping = 55
ScooterConfig.MaxSuspensionAcceleration = 700
ScooterConfig.VisualSuspensionScale = 0.45
ScooterConfig.GroundRecoveryProbeHeight = 2.5
ScooterConfig.GroundClearance = 0.04
ScooterConfig.GroundRecoveryInterval = 0.1
ScooterConfig.GroundRecoveryThreshold = 0.08
ScooterConfig.StepProbeDistance = 1.2
ScooterConfig.StepProbeHeight = 0.12
ScooterConfig.MaxStepHeight = 1.25
ScooterConfig.StepUpVelocity = 11
ScooterConfig.StepForwardVelocity = 4
ScooterConfig.StepCooldown = 0.3
ScooterConfig.RidePromptDistance = 8
ScooterConfig.WheelFriction = 0.03
ScooterConfig.TrickCooldown = 0.15
ScooterConfig.SpawnCooldown = 3
ScooterConfig.DriveInputKeepalive = 0.25
ScooterConfig.DriveInputSendInterval = 0.05
ScooterConfig.SteeringSendThreshold = 0.02
ScooterConfig.BurnoutWheelAngularSpeed = 55
ScooterConfig.BurnoutSmokeRate = 32
ScooterConfig.BurnoutSmokeLifetime = NumberRange.new(0.6, 0.9)
ScooterConfig.RiderPose = {
	BlendSpeed = 9,
	WheelieRearFootShift = 0.55,
	BalanceFootOffset = Vector3.new(0.5, 0.65, 0.75),
	BalanceFootSwing = Vector3.new(0.16, 0.1, 0.18),
	BalanceFootFrequency = 7,
}
ScooterConfig.ScooterFolderName = "Scooters"
ScooterConfig.RemoteFolderName = "ScooterRemotes"

return ScooterConfig
