--!strict

export type Member = { userId: number, displayName: string, isLeader: boolean, online: boolean }
export type Invite = { id: string, gangId: string, gangName: string, inviterName: string, expiresAt: number }
export type JoinRequest = { id: string, userId: number, displayName: string, expiresAt: number }
export type DirectoryEntry = { id: string, name: string, color: Color3, memberCount: number, maxMembers: number, requested: boolean }
export type ColorChoice = { id: number, color: Color3, available: boolean }
export type State = {
	canCreate: boolean,
	gangId: string?, gangName: string?, gangColor: Color3?, colorId: number?,
	isLeader: boolean, leaderOfflineUntil: number?,
	members: { Member }, maxMembers: number,
	invite: Invite?, invites: { Invite }, requests: { JoinRequest },
	candidates: { { userId: number, displayName: string } },
	directory: { DirectoryEntry }, colors: { ColorChoice },
	flagsOwned: number, incomePerMinute: number,
}

return {}
