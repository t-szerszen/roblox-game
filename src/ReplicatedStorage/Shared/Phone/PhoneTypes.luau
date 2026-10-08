--!strict

export type Page = "Home" | "Scooters" | "Delivery" | "Gang" | "Daily" | "Protection"
local GangTypes = require(script.Parent.Parent.Gang.GangTypes)
export type GangState = GangTypes.State
export type State = {
	passiveEnabled: boolean,
	passiveAvailable: boolean,
	gangName: string?,
	gang: GangState,
	delivery: { active: boolean, destination: string, distance: number },
	daily: { { id: string, progress: number, target: number } },
	ownedScooters: { string },
	loginStreak: number,
	loginReward: number,
}

return {}
