--!strict
local ScooterConfig = require(script.Parent.Parent.ScooterConfig)
return table.freeze({
	RideCoinsPerKilometer = 100,
	-- The arcade speed conversion defines distance too: km/h * 3600 s per hour.
	StudsPerKilometer = ScooterConfig.StudsPerKmH * 3600,
	BurnoutCoinsPerMinute = 25,
	FlagCoinsPerMinute = 100,
	DeliveryMinCoins = 100, DeliveryMaxCoins = 250,
	DeliveryFullRewardStuds = 2000,
	WheelieRampSeconds = 5, WheelieMaxMultiplier = 2,
	SampleInterval = 0.25, MaxSampleSeconds = 1,
	MinimumRideSpeed = 4, MinimumNetTravelStuds = 8,
	MaxVerticalStep = 12, MotionTolerance = 1.25,
	SessionLeaseSeconds = 180, SaveAttempts = 3, SaveRetrySeconds = 1,
	TransactionHistoryLimit = 40,
})
