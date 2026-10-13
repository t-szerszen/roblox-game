--!strict
local Catalog = require(script.Parent.ScooterUpgradeCatalog)

export type BaseStats = {
	SpeedKmh: number,
	Acceleration: number,
	WeightKg: number?,
	BrakeForce: number,
	PowerWatts: number?,
	WheelieAngle: number,
}
export type Stats = {
	SpeedKmh: number,
	Acceleration: number,
	StartBonusPercent: number,
	WeightKg: number?,
	WeightRemovedKg: number,
	BrakeForce: number,
	PowerWatts: number?,
	AddedPowerWatts: number,
	WheelieAngle: number,
	DualMotor: boolean,
	FendersRemoved: boolean,
	DisplayRemoved: boolean,
	SparksDisabled: boolean,
	UpgradedBrakes: boolean,
}

local Stats = {}

function Stats.Calculate(base: BaseStats, equipped: {[string]: boolean}): Stats
	local speed, acceleration, braking, power, wheelie = 0, 0, 0, 0, 0
	for _, item in Catalog.Items do
		if equipped[item.Id] ~= true then continue end
		speed += item.SpeedKmh or 0
		acceleration += item.AccelerationBonus or 0
		braking += item.BrakeBonus or 0
		power += item.PowerWatts or 0
		wheelie += item.WheelieBonus or 0
	end
	local removed = 0
	if equipped.WeightReduction == true then removed += Catalog.WeightReductionKg end
	if equipped.WheelieMode == true then removed += Catalog.FenderWeightKg end
	-- Always derive from immutable base stats; reinstalling cannot compound bonuses.
	return {
		SpeedKmh=base.SpeedKmh + speed,
		Acceleration=base.Acceleration * (1 + acceleration),
		StartBonusPercent=acceleration * 100,
		WeightKg=if base.WeightKg then math.max(.1, base.WeightKg - removed) else nil,
		WeightRemovedKg=removed,
		BrakeForce=base.BrakeForce * (1 + braking),
		PowerWatts=if base.PowerWatts then base.PowerWatts + power else nil,
		AddedPowerWatts=power,
		WheelieAngle=base.WheelieAngle * (1 + wheelie),
		DualMotor=equipped.DualMotor == true,
		FendersRemoved=equipped.WheelieMode == true,
		DisplayRemoved=false,
		SparksDisabled=equipped.WheelieMode == true,
		UpgradedBrakes=equipped.Brakes == true,
	}
end

return table.freeze(Stats)
