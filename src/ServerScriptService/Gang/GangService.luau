--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GangConfig = require(ReplicatedStorage.Shared.Gang.GangConfig)

export type MemberState = {
	userId: number,
	displayName: string,
	isLeader: boolean,
}
export type InviteState = {
	gangName: string,
	inviterName: string,
	expiresAt: number,
}
export type CandidateState = {
	userId: number,
	displayName: string,
}
export type GangState = {
	canCreate: boolean,
	gangId: string?,
	gangName: string?,
	gangColor: Color3?,
	isLeader: boolean,
	members: { MemberState },
	maxMembers: number,
	invite: InviteState?,
	candidates: { CandidateState },
}

type GangRecord = {
	id: string,
	name: string,
	normalizedName: string,
	color: Color3,
	leaderUserId: number,
	members: { [number]: Player },
}
type PendingInvite = {
	gangId: string,
	inviterUserId: number,
	expiresAt: number,
}

local GangService = {}
local gangsById: { [string]: GangRecord } = {}
local gangIdByPlayer: { [Player]: string } = {}
local invitesByPlayer: { [Player]: PendingInvite } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local changedCallback: ((Player) -> ())? = nil
local started = false

local function maxMembers(): number
	return math.max(1, math.floor(Players.MaxPlayers * GangConfig.MemberRatio))
end

local function notify(player: Player)
	if changedCallback and player.Parent == Players then
		changedCallback(player)
	end
end

local function normalizeName(name: string): string
	return string.lower((string.gsub(name, "%s+", " ")):match("^%s*(.-)%s*$") or "")
end

local function isNameAvailable(normalizedName: string): boolean
	for _, gang in gangsById do
		if gang.normalizedName == normalizedName then
			return false
		end
	end
	return true
end

local function getGang(player: Player): GangRecord?
	local gangId = gangIdByPlayer[player]
	return if gangId then gangsById[gangId] else nil
end

local function clearTag(character: Model)
	local head = character:FindFirstChild("Head")
	local tag = if head then head:FindFirstChild("GangTag") else nil
	if tag then
		tag:Destroy()
	end
end

local function applyTag(player: Player)
	local character = player.Character
	if not character then
		return
	end
	clearTag(character)
	local gang = getGang(player)
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if gang then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
	if not gang or not head or not head:IsA("BasePart") then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "GangTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(180, 24)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 80
	gui.Parent = head

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.Text = string.format("[%s] %s", gang.name, player.DisplayName)
	text.TextColor3 = gang.color
	text.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	text.TextStrokeTransparency = 0.35
	text.TextScaled = true
	text.Parent = gui
end

local function setMembership(player: Player, gang: GangRecord?, isLeader: boolean)
	if gang then
		gangIdByPlayer[player] = gang.id
		gang.members[player.UserId] = player
		player:SetAttribute("GangId", gang.id)
		player:SetAttribute("GangName", gang.name)
		player:SetAttribute("GangRole", if isLeader then "Leader" else "Member")
		player:SetAttribute("GangColor", gang.color)
		player:SetAttribute("PassiveMode", false)
	else
		gangIdByPlayer[player] = nil
		player:SetAttribute("GangId", nil)
		player:SetAttribute("GangName", nil)
		player:SetAttribute("GangRole", nil)
		player:SetAttribute("GangColor", nil)
	end
	applyTag(player)
	notify(player)
end

local function memberCount(gang: GangRecord): number
	local count = 0
	for _ in gang.members do
		count += 1
	end
	return count
end

local function disband(gang: GangRecord)
	gangsById[gang.id] = nil
	local members: { Player } = {}
	for _, member in gang.members do
		table.insert(members, member)
	end
	for _, member in members do
		setMembership(member, nil, false)
	end
	for target, invite in invitesByPlayer do
		if invite.gangId == gang.id then
			invitesByPlayer[target] = nil
			notify(target)
		end
	end
end

function GangService.SetChangedCallback(callback: (Player) -> ())
	changedCallback = callback
end

function GangService.GetState(player: Player): GangState
	local gang = getGang(player)
	local members: { MemberState } = {}
	local candidates: { CandidateState } = {}
	if gang then
		for userId, member in gang.members do
			table.insert(members, {
				userId = userId,
				displayName = member.DisplayName,
				isLeader = userId == gang.leaderUserId,
			})
		end
		table.sort(members, function(a, b)
			if a.isLeader ~= b.isLeader then
				return a.isLeader
			end
			return a.displayName < b.displayName
		end)
		if gang.leaderUserId == player.UserId and #members < maxMembers() then
			for _, candidate in Players:GetPlayers() do
				if candidate ~= player and getGang(candidate) == nil then
					table.insert(candidates, { userId = candidate.UserId, displayName = candidate.DisplayName })
				end
			end
		end
	end

	local inviteState: InviteState? = nil
	local invite = invitesByPlayer[player]
	if invite and invite.expiresAt <= os.clock() then
		invitesByPlayer[player] = nil
		invite = nil
	end
	if invite then
		local invitedGang = gangsById[invite.gangId]
		local inviter = Players:GetPlayerByUserId(invite.inviterUserId)
		if invitedGang and inviter then
			inviteState = {
				gangName = invitedGang.name,
				inviterName = inviter.DisplayName,
				expiresAt = invite.expiresAt,
			}
		else
			invitesByPlayer[player] = nil
		end
	end

	return {
		canCreate = player:GetAttribute("CanCreateGang") == true,
		gangId = if gang then gang.id else nil,
		gangName = if gang then gang.name else nil,
		gangColor = if gang then gang.color else nil,
		isLeader = gang ~= nil and gang.leaderUserId == player.UserId,
		members = members,
		maxMembers = maxMembers(),
		invite = inviteState,
		candidates = candidates,
	}
end

function GangService.Create(player: Player, requestedName: string): (boolean, string)
	if getGang(player) then
		return false, "Najpierw opusc obecny gang."
	end
	if player:GetAttribute("CanCreateGang") ~= true then
		return false, "Nie masz uprawnienia do zalozenia gangu."
	end
	local name = (string.gsub(requestedName, "%s+", " ")):match("^%s*(.-)%s*$") or ""
	if #name < GangConfig.MinNameLength or #name > GangConfig.MaxNameLength or not string.match(name, "^[%w ]+$") then
		return false, "Nazwa musi miec 3-20 znakow: litery, cyfry i spacje."
	end
	local normalizedName = normalizeName(name)
	if not isNameAvailable(normalizedName) then
		return false, "Ta nazwa jest juz zajeta."
	end

	local id = HttpService:GenerateGUID(false)
	local colorSeed = 0
	for index = 1, #id do
		colorSeed += string.byte(id, index)
	end
	local colorIndex = (colorSeed % #GangConfig.Colors) + 1
	local gang: GangRecord = {
		id = id,
		name = name,
		normalizedName = normalizedName,
		color = GangConfig.Colors[colorIndex],
		leaderUserId = player.UserId,
		members = {},
	}
	gangsById[id] = gang
	setMembership(player, gang, true)
	return true, "Gang zostal zalozony."
end

function GangService.Invite(player: Player, targetUserId: number): (boolean, string)
	local gang = getGang(player)
	if not gang or gang.leaderUserId ~= player.UserId then
		return false, "Tylko lider moze zapraszac."
	end
	if memberCount(gang) >= maxMembers() then
		return false, "Gang osiagnal limit czlonkow."
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player or getGang(target) then
		return false, "Ten gracz nie moze dolaczyc."
	end
	invitesByPlayer[target] = {
		gangId = gang.id,
		inviterUserId = player.UserId,
		expiresAt = os.clock() + GangConfig.InviteLifetime,
	}
	notify(target)
	return true, "Zaproszenie wyslane."
end

function GangService.RespondInvite(player: Player, accepted: boolean): (boolean, string)
	local invite = invitesByPlayer[player]
	invitesByPlayer[player] = nil
	if not invite or invite.expiresAt <= os.clock() then
		return false, "Zaproszenie wygaslo."
	end
	if not accepted then
		return true, "Zaproszenie odrzucone."
	end
	if getGang(player) then
		return false, "Juz nalezysz do gangu."
	end
	local gang = gangsById[invite.gangId]
	if not gang or memberCount(gang) >= maxMembers() then
		return false, "Gang nie istnieje lub jest pelny."
	end
	setMembership(player, gang, false)
	local leader = Players:GetPlayerByUserId(gang.leaderUserId)
	if leader then
		notify(leader)
	end
	return true, "Dolaczono do gangu."
end

function GangService.Kick(player: Player, targetUserId: number): (boolean, string)
	local gang = getGang(player)
	if not gang or gang.leaderUserId ~= player.UserId or targetUserId == player.UserId then
		return false, "Nie mozesz wyrzucic tego gracza."
	end
	local target = gang.members[targetUserId]
	if not target then
		return false, "Gracz nie nalezy do gangu."
	end
	gang.members[targetUserId] = nil
	setMembership(target, nil, false)
	notify(player)
	return true, "Gracz zostal wyrzucony."
end

function GangService.Leave(player: Player): (boolean, string)
	local gang = getGang(player)
	if not gang then
		return false, "Nie nalezysz do gangu."
	end
	if gang.leaderUserId == player.UserId then
		disband(gang)
		return true, "Gang zostal rozwiazany."
	end
	gang.members[player.UserId] = nil
	setMembership(player, nil, false)
	local leader = Players:GetPlayerByUserId(gang.leaderUserId)
	if leader then
		notify(leader)
	end
	return true, "Opuszczono gang."
end

function GangService.CanDamage(attacker: Player, target: Player): boolean
	if attacker == target then
		return false
	end
	local attackerGang = gangIdByPlayer[attacker]
	return attackerGang == nil or attackerGang ~= gangIdByPlayer[target]
end

function GangService.Start()
	if started then
		return
	end
	started = true

	local function hookPlayer(player: Player)
		characterConnections[player] = player.CharacterAdded:Connect(function()
			task.defer(applyTag, player)
		end)
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		invitesByPlayer[player] = nil
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
		local gang = getGang(player)
		if gang then
			if gang.leaderUserId == player.UserId then
				disband(gang)
			else
				gang.members[player.UserId] = nil
				gangIdByPlayer[player] = nil
				local leader = Players:GetPlayerByUserId(gang.leaderUserId)
				if leader then
					notify(leader)
				end
			end
		end
	end)
end

return GangService
