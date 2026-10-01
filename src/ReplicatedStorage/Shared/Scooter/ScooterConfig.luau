--!strict

local ScooterConfig = {}

ScooterConfig.Models = {
	["KuKirin G2 Pro"] = {
		maxSpeed = 45,
		acceleration = 82,
		turnTorque = 4200,
		brakeForce = 70,
		reverseAcceleration = 38,
		jumpImpulse = 48,
		wheelieTorque = 5200,
	},
	["KuKirin G2 Max"] = {
		maxSpeed = 55,
		acceleration = 92,
		turnTorque = 4500,
		brakeForce = 76,
		reverseAcceleration = 42,
		jumpImpulse = 50,
		wheelieTorque = 5700,
	},
	["KuKirin G2 Master"] = {
		maxSpeed = 60,
		acceleration = 98,
		turnTorque = 4700,
		brakeForce = 80,
		reverseAcceleration = 44,
		jumpImpulse = 52,
		wheelieTorque = 6100,
	},
	["KuKirin G3 Pro"] = {
		maxSpeed = 65,
		acceleration = 104,
		turnTorque = 5000,
		brakeForce = 84,
		reverseAcceleration = 46,
		jumpImpulse = 54,
		wheelieTorque = 6500,
	},
	["KuKirin G4"] = {
		maxSpeed = 70,
		acceleration = 112,
		turnTorque = 5400,
		brakeForce = 90,
		reverseAcceleration = 50,
		jumpImpulse = 56,
		wheelieTorque = 7000,
	},
}

ScooterConfig.DefaultModel = "KuKirin G2 Pro"
ScooterConfig.StudsPerKmH = 0.78
ScooterConfig.BurnoutMaxSpeed = 6
ScooterConfig.MaxReverseSpeed = 14
ScooterConfig.TurnRate = math.rad(105)
ScooterConfig.MinSteeringSpeed = 1.5
ScooterConfig.StopSpeed = 2.25
ScooterConfig.LaunchSpeed = 5
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
ScooterConfig.SuspensionRestLength = 0.8
ScooterConfig.SuspensionTravel = 0.65
ScooterConfig.SuspensionStiffness = 520
ScooterConfig.SuspensionDamping = 42
ScooterConfig.MaxSuspensionAcceleration = 520
ScooterConfig.VisualSuspensionScale = 0.45
ScooterConfig.StepProbeDistance = 1.2
ScooterConfig.MaxStepHeight = 1.25
ScooterConfig.StepUpVelocity = 11
ScooterConfig.StepForwardVelocity = 4
ScooterConfig.StepCooldown = 0.3
ScooterConfig.RidePromptDistance = 8
ScooterConfig.WheelFriction = 0.03
ScooterConfig.TrickCooldown = 0.15
ScooterConfig.SpawnCooldown = 3
ScooterConfig.ScooterFolderName = "Scooters"
ScooterConfig.RemoteFolderName = "ScooterRemotes"

return ScooterConfig
