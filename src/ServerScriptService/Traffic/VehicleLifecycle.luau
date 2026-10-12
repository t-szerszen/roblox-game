--!strict

local Lifecycle = {}
local routineRemoval: {[string]: boolean} = table.freeze({
	DeadEnd = true, Irrelevant = true, RecoveryTimeout = true, Stuck = true,
	PoliceStuck = true, IntersectionTimeout = true, NightReduction = true,
})
local normalWait: {[string]: boolean} = table.freeze({
	StopSign = true, IntersectionYield = true, CommandedStop = true, RouteEnd = true,
})

function Lifecycle.CanRemove(protected: boolean, reason: string): boolean
	return not protected or not routineRemoval[reason]
end

function Lifecycle.NormalWait(reason: string, obstacle: Instance?): boolean
	if normalWait[reason] then return true end
	local current = obstacle
	while current do
		if current:GetAttribute("NPCVehicle") == true then return true end
		current = current.Parent
	end
	return false
end

return Lifecycle
