--!strict

return table.freeze({
	ZoneTag = "GangTerritory",
	IdAttribute = "TerritoryId",
	NameAttribute = "TerritoryName",
	TintAttribute = "TerritoryTint",
	StateFolderName = "Territories",
	CaptureSeconds = 45,
	DecayPerSecond = 0.5,
	SampleInterval = 0.25,
	MaxStepSeconds = 1,
	RewardInterval = 60,
	CoinsPerFlag = 60,
	NeutralColor = Color3.fromRGB(180, 185, 195),
	WorldLabelDistance = 100,
	DefaultZoneSize = Vector3.new(36, 24, 36),
})
