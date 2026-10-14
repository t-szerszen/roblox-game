--!strict
local ScooterConfig = require(script.Parent.Parent.ScooterConfig)
local RideCoinsPerKilometer = 100
-- The arcade speed conversion defines distance too: km/h * 3600 s per hour.
local StudsPerKilometer = ScooterConfig.StudsPerKmH * 3600
-- Ride income is credited in short steps so coins arrive while riding, not only per full kilometer.
local RideCoinStepMeters = 10
return table.freeze({
	RideCoinsPerKilometer = RideCoinsPerKilometer,
	StudsPerKilometer = StudsPerKilometer,
	RideCoinStepMeters = RideCoinStepMeters,
	RideCoinStepStuds = StudsPerKilometer * RideCoinStepMeters / 1000,
	RideCoinsPerStep = RideCoinsPerKilometer * RideCoinStepMeters / 1000,
	BurnoutCoinsPerMinute = 25,
	FlagCoinsPerMinute = 100,
	DeliveryMinCoins = 100, DeliveryMaxCoins = 250,
	DeliveryFullRewardStuds = 2000,
	-- x1.00 -> x2.00 over 20 s, visible and paid in 0.01 increments.
	WheelieRampSeconds = 20, WheelieMaxMultiplier = 2, WheelieMultiplierStep = 0.01,
	SampleInterval = 0.25, MaxSampleSeconds = 1,
	MinimumRideSpeed = 4, MinimumNetTravelStuds = 8,
	MaxVerticalStep = 12, MotionTolerance = 1.25,
	SessionLeaseSeconds = 180, SaveAttempts = 3, SaveRetrySeconds = 1,
	TransactionHistoryLimit = 40,
	-- Frequent small credits of one reason are merged so they don't evict the rest of the audit history.
	TransactionMergeSeconds = 60,
})
