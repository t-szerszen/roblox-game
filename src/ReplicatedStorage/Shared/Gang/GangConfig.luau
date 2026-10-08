--!strict

local GangConfig = {}

GangConfig.MemberRatio = 1 / 3
GangConfig.InviteLifetime = 30
GangConfig.RequestLifetime = 30
GangConfig.PairCooldown = 15
GangConfig.MembershipCooldown = 30
GangConfig.IdentityCooldown = 60
GangConfig.NameAttemptCooldown = 2
GangConfig.LeaderOfflineGrace = 30 * 60
GangConfig.MaintenanceInterval = 1
GangConfig.MaxIncomingInvites = 5
GangConfig.MaxOutgoingRequests = 3
GangConfig.MinNameLength = 3
GangConfig.MaxNameLength = 20

GangConfig.Colors = {
	Color3.fromRGB(224, 76, 70),
	Color3.fromRGB(54, 139, 219),
	Color3.fromRGB(42, 171, 105),
	Color3.fromRGB(157, 89, 204),
	Color3.fromRGB(232, 158, 45),
	Color3.fromRGB(35, 171, 176),
}

function GangConfig.GetPalette(maxPlayers: number): { Color3 }
	local colors = table.clone(GangConfig.Colors)
	-- A one-member gang is legal; the palette must accommodate the entire server.
	for index = #colors + 1, maxPlayers do
		colors[index] = Color3.fromHSV((index * 0.61803398875) % 1, 0.72, 0.92)
	end
	return colors
end

return GangConfig
