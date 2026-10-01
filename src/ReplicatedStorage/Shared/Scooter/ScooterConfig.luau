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
ScooterConfig.WheelieAngle = math.rad(22)
ScooterConfig.WheelieMinSpeed = 3
ScooterConfig.UprightResponsiveness = 22
ScooterConfig.WheelFriction = 0.03
ScooterConfig.TrickCooldown = 0.15
ScooterConfig.SpawnCooldown = 3
ScooterConfig.ScooterFolderName = "Scooters"
ScooterConfig.RemoteFolderName = "ScooterRemotes"

return ScooterConfig
