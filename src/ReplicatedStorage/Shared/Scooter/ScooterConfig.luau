--!strict

-- Existing imports resolve to the canonical shared tuning, including Studio-authored values.
local ScooterConfig = require(script.Parent.Parent.ScooterConfig)

export type ModelTuning = ScooterConfig.ModelTuning
export type Tuning = ScooterConfig.Tuning

return ScooterConfig
