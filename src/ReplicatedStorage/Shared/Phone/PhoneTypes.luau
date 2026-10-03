--!strict

export type Page = "Home" | "Scooters" | "Delivery" | "Gang" | "Daily" | "Protection"
export type GangState = {
	canCreate: boolean,
	gangId: string?,
	gangName: string?,
	gangColor: Color3?,
	isLeader: boolean,
	members: { { userId: number, displayName: string, isLeader: boolean } },
	maxMembers: number,
	invite: { gangName: string, inviterName: string, expiresAt: number }?,
	candidates: { { userId: number, displayName: string } },
}
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
