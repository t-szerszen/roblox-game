--!strict

local GangService = require(script.Parent.GangService)
local GangRequests = {}
local commands = {
	CreateGang = true, InviteGangMember = true, RespondGangInvite = true,
	RequestJoinGang = true, RespondGangRequest = true, KickGangMember = true,
	LeaveGang = true, RenameGang = true, SetGangColor = true,
}
local function integer(value: unknown): boolean
	return typeof(value) == "number" and value == value and value == math.floor(value) and value >= 1 and value <= 9_007_199_254_740_991
end
local function shortString(value: unknown): boolean return typeof(value) == "string" and #value > 0 and #value <= 64 end
local function onlyKeys(value: { [string]: any }, allowed: { [string]: boolean }): boolean
	for key in value do if typeof(key) ~= "string" or not allowed[key] then return false end end
	return true
end
function GangRequests.IsCommand(action: string): boolean return commands[action] == true end
function GangRequests.Handle(player: Player, action: string, payload: unknown): (boolean, string)
	if action == "LeaveGang" and payload == nil then return GangService.Leave(player) end
	if action == "RenameGang" and shortString(payload) then return GangService.Rename(player, payload) end
	if action == "CreateGang" then
		if typeof(payload) == "string" then return GangService.Create(player, payload) end
		if typeof(payload) == "table" then
			local data = payload :: { [string]: any }
			if onlyKeys(data, { name = true, colorId = true }) and shortString(data.name) and integer(data.colorId) then
				return GangService.Create(player, data.name, data.colorId)
			end
		end
	elseif (action == "InviteGangMember" or action == "KickGangMember" or action == "SetGangColor") and integer(payload) then
		if action == "InviteGangMember" then return GangService.Invite(player, payload :: number)
		elseif action == "KickGangMember" then return GangService.Kick(player, payload :: number)
		else return GangService.SetColor(player, payload :: number) end
	elseif action == "RequestJoinGang" and shortString(payload) then
		return GangService.RequestJoin(player, payload :: string)
	elseif (action == "RespondGangInvite" or action == "RespondGangRequest") and typeof(payload) == "table" then
		local data = payload :: { [string]: any }
		if onlyKeys(data, { id = true, accept = true }) and shortString(data.id) and typeof(data.accept) == "boolean" then
			if action == "RespondGangInvite" then return GangService.RespondInvite(player, data.id, data.accept) end
			return GangService.RespondRequest(player, data.id, data.accept)
		end
	end
	return false, "Nieprawidłowe żądanie gangu."
end
return GangRequests
