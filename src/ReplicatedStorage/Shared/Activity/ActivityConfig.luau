--!strict

local ActivityConfig = {}

ActivityConfig.PickupTag = "DeliveryPickup"
ActivityConfig.DestinationTag = "DeliveryDestination"
ActivityConfig.BaseCoins = 100
ActivityConfig.BaseXP = 50
ActivityConfig.DistanceStepStuds = 100
ActivityConfig.DistanceBonusCoins = 15
ActivityConfig.InteractionDistance = 10
ActivityConfig.StudsPerKilometer = 3_571.43
ActivityConfig.DistanceSampleInterval = 1
ActivityConfig.MaxCreditedStudsPerSample = 180
ActivityConfig.ProfileAutosaveInterval = 60
ActivityConfig.LeaderboardRefreshInterval = 60
ActivityConfig.LeaderboardEntries = 10

-- GDD requires escalating rewards but does not define amounts yet.
ActivityConfig.DailyLoginCoinRewards = { 0, 0, 0, 0, 0, 0, 0 }

return ActivityConfig
