--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Gang.GangConfig)
local Types = require(ReplicatedStorage.Shared.Gang.GangTypes)
local Names = require(script.Parent.GangNames)
local Tags = require(script.Parent.GangTags)
export type GangState = Types.State

type Member = { userId: number, displayName: string, order: number, player: Player? }
type Gang = {
	id: string, name: string, normalizedName: string, colorId: number, color: Color3,
	leaderUserId: number, offlineUntil: number?, members: { [number]: Member }, identityVersion: number,
}
type Invite = { id: string, gangId: string, inviterUserId: number, expiresAt: number }
type JoinRequest = { id: string, userId: number, displayName: string, expiresAt: number }
local GangService = {}
local gangs: { [string]: Gang } = {}
local membership: { [number]: string } = {}
local invites: { [number]: { [string]: Invite } } = {}
local requests: { [string]: { [number]: JoinRequest } } = {}
local cooldowns: { [number]: { [string]: number } } = {}
local connections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local subscribers: { [number]: (string) -> () } = {}
local nextSubscriber = 0
local nextMemberOrder = 0
local changedCallback: ((Player) -> ())? = nil
local notificationQueued = false
local started = false
local palette = Config.GetPalette(Players.MaxPlayers)
local function now(): number return Workspace:GetServerTimeNow() end
local function maxMembers(): number return math.max(1, math.floor(Players.MaxPlayers * Config.MemberRatio)) end
local function count(gang: Gang): number
	local total = 0
	for _ in gang.members do total += 1 end
	return total
end
local function getGang(player: Player): Gang?
	local id = membership[player.UserId]
	return if id then gangs[id] else nil
end
local function online(player: Player): boolean return player.Parent == Players end
local function eligibleToJoin(player: Player): boolean
	local deadlines = cooldowns[player.UserId]
	return started and online(player) and not getGang(player) and (not deadlines or (deadlines.membership or 0) <= now())
end
local function availableName(normalized: string, exceptId: string?): boolean
	for id, gang in gangs do if id ~= exceptId and gang.normalizedName == normalized then return false end end
	return true
end
local function availableColor(colorId: number, exceptId: string?): boolean
	if colorId ~= math.floor(colorId) or not palette[colorId] then return false end
	for id, gang in gangs do if id ~= exceptId and gang.colorId == colorId then return false end end
	return true
end
local function takeCooldown(player: Player, key: string, duration: number): boolean
	local times = cooldowns[player.UserId] or {}
	cooldowns[player.UserId] = times
	if (times[key] or 0) > now() then return false end
	times[key] = now() + duration
	return true
end
function GangService.NotifyAll()
	if notificationQueued then return end
	notificationQueued = true
	task.defer(function()
		notificationQueued = false
		if not started then return end
		local callback = changedCallback
		if callback then for _, player in Players:GetPlayers() do callback(player) end end
	end)
end
local function emit(gangId: string)
	for _, callback in table.clone(subscribers) do
		local success, problem = pcall(function(): string?
			callback(gangId)
			return nil
		end)
		if not success then warn("GangService: listener failed: " .. tostring(problem)) end
	end
	GangService.NotifyAll()
end
local function syncPlayer(player: Player)
	local gang = getGang(player)
	player:SetAttribute("GangId", if gang then gang.id else nil)
	player:SetAttribute("GangName", if gang then gang.name else nil)
	player:SetAttribute("GangRole", if gang then (if gang.leaderUserId == player.UserId then "Leader" else "Member") else nil)
	player:SetAttribute("GangColor", if gang then gang.color else nil)
	if not gang then
		player:SetAttribute("GangFlagsOwned", 0)
		player:SetAttribute("GangIncomePerMinute", 0)
	end
	Tags.Apply(player, if gang then gang.name else nil, if gang then gang.color else nil)
end
local function syncGang(gang: Gang)
	for _, member in gang.members do if member.player then syncPlayer(member.player) end end
	emit(gang.id)
end
local function clearPlayerPending(userId: number)
	invites[userId] = nil
	for _, pending in requests do pending[userId] = nil end
end
local function clearGangInvites(gangId: string)
	for _, pending in invites do
		for id, invite in pending do if invite.gangId == gangId then pending[id] = nil end end
	end
end
local function disband(gang: Gang)
	gangs[gang.id] = nil
	requests[gang.id] = nil
	clearGangInvites(gang.id)
	for userId, member in gang.members do
		membership[userId] = nil
		if member.player then syncPlayer(member.player) end
	end
	emit(gang.id)
end
local function oldestOnline(gang: Gang): Member?
	local oldest: Member? = nil
	for _, member in gang.members do
		if member.player and online(member.player) and (not oldest or member.order < oldest.order) then oldest = member end
	end
	return oldest
end
local function removeMember(gang: Gang, userId: number)
	local member = gang.members[userId]
	if not member then return end
	gang.members[userId] = nil
	membership[userId] = nil
	clearPlayerPending(userId)
	if member.player then
		takeCooldown(member.player, "membership", Config.MembershipCooldown)
		syncPlayer(member.player)
	end
	if not oldestOnline(gang) then disband(gang); return end
	if userId == gang.leaderUserId then
		local successor = oldestOnline(gang) :: Member
		gang.leaderUserId = successor.userId
		gang.offlineUntil = nil
		clearGangInvites(gang.id)
	end
	syncGang(gang)
end
local function addMember(gang: Gang, player: Player)
	nextMemberOrder += 1
	gang.members[player.UserId] = { userId = player.UserId, displayName = player.DisplayName, order = nextMemberOrder, player = player }
	membership[player.UserId] = gang.id
	clearPlayerPending(player.UserId)
	syncGang(gang)
end
local function isLeader(player: Player, gang: Gang?): boolean
	return started and online(player) and gang ~= nil and gang.leaderUserId == player.UserId
end
function GangService.SetChangedCallback(callback: (Player) -> ()) changedCallback = callback end
function GangService.Subscribe(callback: (string) -> ()): () -> ()
	nextSubscriber += 1
	local key = nextSubscriber
	subscribers[key] = callback
	return function() subscribers[key] = nil end
end
function GangService.GetGangId(player: Player): string? return membership[player.UserId] end
function GangService.Exists(id: string): boolean return gangs[id] ~= nil end
function GangService.GetIdentity(id: string): (string?, Color3?)
	local gang = gangs[id]
	return if gang then gang.name else nil, if gang then gang.color else nil
end
function GangService.GetOnlineMembers(id: string): { Player }
	local result: { Player } = {}
	local gang = gangs[id]
	if gang then
		for _, member in gang.members do if member.player and online(member.player) then table.insert(result, member.player) end end
	end
	return result
end
function GangService.GetState(player: Player): GangState
	local gang = getGang(player)
	local members: { Types.Member } = {}
	local candidates: { { userId: number, displayName: string } } = {}
	local received: { Types.Invite } = {}
	local pendingRequests: { Types.JoinRequest } = {}
	local directory: { Types.DirectoryEntry } = {}
	local colors: { Types.ColorChoice } = {}
	if gang then
		for userId, member in gang.members do
			table.insert(members, { userId = userId, displayName = member.displayName, isLeader = userId == gang.leaderUserId, online = member.player ~= nil })
		end
		table.sort(members, function(a, b)
			if a.isLeader ~= b.isLeader then return a.isLeader end
			return a.displayName < b.displayName
		end)
		if isLeader(player, gang) then
			for _, candidate in Players:GetPlayers() do
				if eligibleToJoin(candidate) then table.insert(candidates, { userId = candidate.UserId, displayName = candidate.DisplayName }) end
			end
			for _, request in pairs(requests[gang.id] or {}) do
				if request.expiresAt > now() then table.insert(pendingRequests, table.clone(request)) end
			end
		end
	end
	for _, invite in pairs(invites[player.UserId] or {}) do
		local invitedGang = gangs[invite.gangId]
		local inviter = Players:GetPlayerByUserId(invite.inviterUserId)
		if invitedGang and inviter and invitedGang.leaderUserId == inviter.UserId and invite.expiresAt > now() then
			table.insert(received, { id = invite.id, gangId = invite.gangId, gangName = invitedGang.name, inviterName = inviter.DisplayName, expiresAt = invite.expiresAt })
		end
	end
	table.sort(received, function(a, b) return a.expiresAt < b.expiresAt end)
	if not gang then
		for id, entry in gangs do
			local request = (requests[id] or {})[player.UserId]
			table.insert(directory, { id = id, name = entry.name, color = entry.color, memberCount = count(entry), maxMembers = maxMembers(), requested = request ~= nil and request.expiresAt > now() })
		end
		table.sort(directory, function(a, b) return a.name < b.name end)
	end
	for id, color in palette do table.insert(colors, { id = id, color = color, available = availableColor(id, if gang then gang.id else nil) }) end
	return {
		canCreate = eligibleToJoin(player), gangId = if gang then gang.id else nil, gangName = if gang then gang.name else nil,
		gangColor = if gang then gang.color else nil, colorId = if gang then gang.colorId else nil,
		isLeader = isLeader(player, gang), leaderOfflineUntil = if gang then gang.offlineUntil else nil,
		members = members, maxMembers = maxMembers(), candidates = candidates,
		invite = received[1], invites = received, requests = pendingRequests, directory = directory, colors = colors,
		flagsOwned = (player:GetAttribute("GangFlagsOwned") :: number?) or 0,
		incomePerMinute = (player:GetAttribute("GangIncomePerMinute") :: number?) or 0,
	}
end
function GangService.Create(player: Player, requestedName: unknown, requestedColor: number?): (boolean, string)
	if not eligibleToJoin(player) then return false, "Należysz już do gangu lub trwa czas odnowienia." end
	if not takeCooldown(player, "nameAttempt", Config.NameAttemptCooldown) then return false, "Spróbuj za chwilę." end
	local name, message = Names.Filter(player, requestedName)
	if not name then return false, message end
	-- Filtering yields; recheck membership, uniqueness and colors before committing.
	if not eligibleToJoin(player) then return false, "Stan członkostwa uległ zmianie." end
	if not availableName(Names.Normalize(name), nil) then return false, "Ta nazwa jest już zajęta." end
	local colorId = requestedColor
	if colorId == nil then for id in palette do if availableColor(id, nil) then colorId = id; break end end end
	if colorId == nil or not availableColor(colorId, nil) then return false, "Ten kolor jest już zajęty." end
	local id = HttpService:GenerateGUID(false)
	local gang: Gang = { id = id, name = name, normalizedName = Names.Normalize(name), colorId = colorId,
		color = palette[colorId], leaderUserId = player.UserId, members = {}, identityVersion = 0 }
	gangs[id] = gang
	requests[id] = {}
	addMember(gang, player)
	return true, "Gang został założony."
end
function GangService.Rename(player: Player, requestedName: unknown): (boolean, string)
	local gang = getGang(player)
	if not gang or not isLeader(player, gang) then return false, "Tylko lider może zmienić nazwę." end
	if not takeCooldown(player, "rename", Config.IdentityCooldown) then return false, "Nazwę można zmienić raz na minutę." end
	local version = gang.identityVersion
	local name, message = Names.Filter(player, requestedName)
	if not name then return false, message end
	if getGang(player) ~= gang or not isLeader(player, gang) or gang.identityVersion ~= version then return false, "Stan gangu uległ zmianie." end
	if not availableName(Names.Normalize(name), gang.id) then return false, "Ta nazwa jest już zajęta." end
	gang.name = name
	gang.normalizedName = Names.Normalize(name)
	gang.identityVersion += 1
	syncGang(gang)
	return true, "Nazwa została zmieniona."
end
function GangService.SetColor(player: Player, colorId: number): (boolean, string)
	local gang = getGang(player)
	if not gang or not isLeader(player, gang) then return false, "Tylko lider może zmienić kolor." end
	if not availableColor(colorId, gang.id) then return false, "Kolor jest niedostępny." end
	if not takeCooldown(player, "color", Config.IdentityCooldown) then return false, "Kolor można zmienić raz na minutę." end
	gang.colorId = colorId
	gang.color = palette[colorId]
	gang.identityVersion += 1
	syncGang(gang)
	return true, "Kolor został zmieniony."
end
function GangService.Invite(player: Player, targetUserId: number): (boolean, string)
	local gang = getGang(player)
	if not gang or not isLeader(player, gang) then return false, "Tylko lider może zapraszać." end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player or not eligibleToJoin(target) then return false, "Ten gracz nie może dołączyć." end
	if count(gang) >= maxMembers() then return false, "Gang osiągnął limit członków." end
	if not takeCooldown(player, "invite:" .. targetUserId, Config.PairCooldown) then return false, "Odczekaj przed kolejnym zaproszeniem tej osoby." end
	local pending: { [string]: Invite } = invites[targetUserId] or {}
	local total = 0
	for _, invite in pending do
		if invite.expiresAt > now() then
			total += 1
			if invite.gangId == gang.id then return false, "Zaproszenie już oczekuje na odpowiedź." end
		end
	end
	if total >= Config.MaxIncomingInvites then return false, "Gracz ma zbyt wiele zaproszeń." end
	local id = HttpService:GenerateGUID(false)
	pending[id] = { id = id, gangId = gang.id, inviterUserId = player.UserId, expiresAt = now() + Config.InviteLifetime }
	invites[targetUserId] = pending
	GangService.NotifyAll()
	return true, "Zaproszenie wysłane."
end
function GangService.RespondInvite(player: Player, id: string, accepted: boolean): (boolean, string)
	local pending = invites[player.UserId]
	local invite = if pending then pending[id] else nil
	if not invite or invite.expiresAt <= now() then return false, "Zaproszenie wygasło." end
	local gang = gangs[invite.gangId]
	if not gang or gang.leaderUserId ~= invite.inviterUserId or not Players:GetPlayerByUserId(invite.inviterUserId) then return false, "Zaproszenie jest nieaktualne." end
	if accepted and (not eligibleToJoin(player) or count(gang) >= maxMembers()) then return false, "Nie możesz dołączyć lub gang jest pełny." end
	(pending :: { [string]: Invite })[id] = nil
	if accepted then addMember(gang, player) else GangService.NotifyAll() end
	return true, if accepted then "Dołączono do gangu." else "Zaproszenie odrzucone."
end
function GangService.RequestJoin(player: Player, gangId: string): (boolean, string)
	local gang = gangs[gangId]
	if not gang or not eligibleToJoin(player) or count(gang) >= maxMembers() then return false, "Nie możesz złożyć prośby do tego gangu." end
	if not takeCooldown(player, "request:" .. gangId, Config.PairCooldown) then return false, "Odczekaj przed kolejną prośbą." end
	local outgoing = 0
	for _, pending in requests do local request = pending[player.UserId]; if request and request.expiresAt > now() then outgoing += 1 end end
	if outgoing >= Config.MaxOutgoingRequests then return false, "Masz już zbyt wiele oczekujących próśb." end
	local pending = requests[gangId]
	local existing = pending[player.UserId]
	if existing and existing.expiresAt > now() then return false, "Prośba już oczekuje na odpowiedź." end
	pending[player.UserId] = { id = HttpService:GenerateGUID(false), userId = player.UserId, displayName = player.DisplayName, expiresAt = now() + Config.RequestLifetime }
	GangService.NotifyAll()
	return true, "Prośba o dołączenie wysłana."
end
function GangService.RespondRequest(player: Player, id: string, accepted: boolean): (boolean, string)
	local gang = getGang(player)
	if not gang or not isLeader(player, gang) then return false, "Tylko lider może odpowiadać na prośby." end
	local pending = requests[gang.id]
	for userId, request in pending do
		if request.id ~= id then continue end
		if request.expiresAt <= now() then return false, "Prośba wygasła." end
		local target = Players:GetPlayerByUserId(userId)
		if accepted and (not target or not eligibleToJoin(target) or count(gang) >= maxMembers()) then return false, "Gracz jest niedostępny lub gang jest pełny." end
		pending[userId] = nil
		if accepted then addMember(gang, target :: Player) else GangService.NotifyAll() end
		return true, if accepted then "Przyjęto członka." else "Prośba odrzucona."
	end
	return false, "Prośba jest nieaktualna."
end
function GangService.Kick(player: Player, targetUserId: number): (boolean, string)
	local gang = getGang(player)
	if not gang or not isLeader(player, gang) or targetUserId == player.UserId or not gang.members[targetUserId] then return false, "Nie możesz wyrzucić tego gracza." end
	removeMember(gang, targetUserId)
	return true, "Gracz został wyrzucony."
end
function GangService.Leave(player: Player): (boolean, string)
	local gang = getGang(player)
	if not gang then return false, "Nie należysz do gangu." end
	removeMember(gang, player.UserId)
	return true, "Opuszczono gang."
end
function GangService.CanDamage(attacker: Player, target: Player): boolean
	local id = membership[attacker.UserId]
	return attacker ~= target and (id == nil or id ~= membership[target.UserId])
end
local function maintain()
	local changed = false
	for _, gang in table.clone(gangs) do
		if gang.offlineUntil and gang.offlineUntil <= now() then removeMember(gang, gang.leaderUserId); changed = true end
	end
	for userId, pending in invites do
		for id, invite in pending do if invite.expiresAt <= now() then pending[id] = nil; changed = true end end
		if next(pending) == nil then invites[userId] = nil end
	end
	for _, pending in requests do
		for userId, request in pending do if request.expiresAt <= now() then pending[userId] = nil; changed = true end end
	end
	for userId, times in cooldowns do
		for key, deadline in times do if deadline <= now() then times[key] = nil end end
		if next(times) == nil then cooldowns[userId] = nil end
	end
	if changed then GangService.NotifyAll() end
end
local function hookPlayer(player: Player)
	maintain()
	local gang = getGang(player)
	if gang then
		local member = gang.members[player.UserId]
		member.player = player
		member.displayName = player.DisplayName
		gang.offlineUntil = nil
		syncGang(gang)
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		task.spawn(function()
			character:WaitForChild("Head", 10)
			character:WaitForChild("Humanoid", 10)
			if started and online(player) and player.Character == character then syncPlayer(player) end
		end)
	end)
	if player.Character then syncPlayer(player) end
	GangService.NotifyAll()
end
function GangService.Start()
	if started then return end
	started = true
	for _, player in Players:GetPlayers() do hookPlayer(player) end
	table.insert(connections, Players.PlayerAdded:Connect(hookPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		local connection = characterConnections[player]
		if connection then connection:Disconnect(); characterConnections[player] = nil end
		clearPlayerPending(player.UserId)
		local gang = getGang(player)
		if gang then
			if gang.leaderUserId == player.UserId then
				gang.members[player.UserId].player = nil
				gang.offlineUntil = now() + Config.LeaderOfflineGrace
				clearGangInvites(gang.id)
				if oldestOnline(gang) then syncGang(gang) else disband(gang) end
			else removeMember(gang, player.UserId) end
		end
		GangService.NotifyAll()
	end))
	local elapsed = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(delta: number)
		elapsed += delta
		if elapsed >= Config.MaintenanceInterval then elapsed = 0; maintain() end
	end))
end
function GangService.Stop()
	if not started then return end
	for _, connection in connections do connection:Disconnect() end
	for _, connection in characterConnections do connection:Disconnect() end
	table.clear(connections); table.clear(characterConnections)
	for _, gang in table.clone(gangs) do disband(gang) end
	started = false
	changedCallback = nil
	table.clear(subscribers); table.clear(invites); table.clear(requests); table.clear(cooldowns)
end
return GangService
