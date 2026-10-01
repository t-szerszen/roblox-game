--!strict

export type DailyMission = {
	id: string,
	name: string,
	target: number,
	unit: string,
	progressAttribute: string,
}

local PhoneConfig = {}

PhoneConfig.RemoteFolderName = "PhoneRemotes"
PhoneConfig.RequestFunctionName = "PhoneRequest"
PhoneConfig.StateChangedEventName = "PhoneStateChanged"
PhoneConfig.RequestCooldown = 0.25

PhoneConfig.DailyMissions = {
	{
		id = "distance",
		name = "Przejedz dystans",
		target = 5,
		unit = "km",
		progressAttribute = "DailyDistanceKm",
	},
	{
		id = "deliveries",
		name = "Dostarcz paczki",
		target = 3,
		unit = "dostaw",
		progressAttribute = "DailyDeliveries",
	},
	{
		id = "police_escape",
		name = "Ucieknij policji",
		target = 1,
		unit = "ucieczka",
		progressAttribute = "DailyPoliceEscapes",
	},
	{
		id = "race_wins",
		name = "Wygraj wyscig 1v1",
		target = 1,
		unit = "wygrana",
		progressAttribute = "DailyRaceWins",
	},
	{
		id = "night_distance",
		name = "Przejedz dystans w nocy",
		target = 2,
		unit = "km",
		progressAttribute = "DailyNightDistanceKm",
	},
} :: { DailyMission }

return PhoneConfig
