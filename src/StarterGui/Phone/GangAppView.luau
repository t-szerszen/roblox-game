--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Types = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
local GangTypes = require(ReplicatedStorage.Shared.Gang.GangTypes)
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Style = require(ReplicatedStorage.Shared.Phone.PhoneTheme)
local Components = require(script.Parent.PhoneComponents)
type Actions = { Action: (string, unknown) -> (), Draft: (string) -> () }
type Card = (string, string, string, Color3?) -> Frame
type Action = (Frame, string, string, string, unknown, boolean, boolean?) -> TextButton
local View = {}
local function nameInput(row: Frame, scope: Scope.Scope, draft: string, actions: Actions): TextBox
	local input = Instance.new("TextBox")
	input.Name = "GangName"
	input.LayoutOrder = 3
	input.Size = UDim2.new(1, 0, 0, Theme.TouchTarget)
	input.BackgroundColor3 = Style.Raised
	input.BorderSizePixel = 0
	input.Font = Theme.Font
	input.TextSize = 14
	input.TextColor3 = Style.White
	input.PlaceholderColor3 = Style.Dimmed
	input.PlaceholderText = "Nazwa gangu…"
	input.Text = draft
	input.ClearTextOnFocus = false
	input.Parent = row
	Components.Corner(input, 10)
	Components.Stroke(input)
	scope:Give(input:GetPropertyChangedSignal("Text"):Connect(function() actions.Draft(input.Text) end))
	return input
end
local function colors(row: Frame, scope: Scope.Scope, state: Types.GangState, onSelect: (number) -> ()): number?
	local options: { GangTypes.ColorChoice } = state.colors or {}
	local first: number? = nil
	for _, choice in options do if choice.available then first = choice.id; break end end
	local selected = state.colorId or first
	local holder = Components.Frame(row, "Colors")
	holder.LayoutOrder = 4
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, math.ceil(#options / 4) * (Theme.TouchTarget + 4))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.25, -4, 0, Theme.TouchTarget)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	local buttons: { [number]: TextButton } = {}
	local function refresh()
		for id, button in buttons do button.Text = if id == selected then "✓" else tostring(id) end
	end
	for _, choice in options do
		local button = Components.Button(holder, tostring(choice.id), scope, function()
			if not choice.available then return end
			selected = choice.id
			refresh()
			onSelect(choice.id)
		end, true, choice.color)
		button.Name = "Color_" .. choice.id
		button.LayoutOrder = choice.id
		button.BackgroundColor3 = choice.color
		button:SetAttribute("PhoneAction", true)
		button:SetAttribute("Available", choice.available)
		Components.SetEnabled(button, choice.available)
		buttons[choice.id] = button
	end
	refresh()
	return selected
end
local function territories(scope: Scope.Scope, card: Card)
	local folder = ReplicatedStorage:FindFirstChild(Config.StateFolderName)
	if not folder then return end
	local entries = folder:GetChildren()
	table.sort(entries, function(a, b) return a.Name < b.Name end)
	for _, entry in entries do
		local row = card("Territory_" .. entry.Name, (entry:GetAttribute("DisplayName") :: string?) or entry.Name, "", nil)
		local detail = row:FindFirstChild("Detail") :: TextLabel?
		local function update()
			if not detail then return end
			local owner = (entry:GetAttribute("OwnerName") :: string?) or "Niczyje"
			local capturer = entry:GetAttribute("CapturingName")
			local percent = (entry:GetAttribute("Progress") :: number?) or 0
			local phase = entry:GetAttribute("Phase")
			detail.Text = "Właściciel: " .. owner .. (if phase == "contested" then string.format(" • sporne (%d%%)", percent)
				elseif typeof(capturer) == "string" then string.format(" • %s: %d%%", capturer, percent) else "")
		end
		update()
		scope:Give(entry.AttributeChanged:Connect(update))
	end
end
function View.Render(scope: Scope.Scope, state: Types.State, draft: string, actions: Actions, card: Card, action: Action): TextBox?
	local gang = state.gang
	local received: { GangTypes.Invite } = gang.invites or (if gang.invite then { gang.invite } else {})
	if not gang.gangId then
		for _, invite in received do
			local row = card("Invite_" .. invite.id, invite.gangName, "Zaprasza: " .. invite.inviterName, nil)
			action(row, "Accept", "Dołącz", "RespondGangInvite", { id = invite.id, accept = true }, true, true)
			action(row, "Decline", "Odrzuć", "RespondGangInvite", { id = invite.id, accept = false }, true, false)
		end
		if gang.canCreate then
			local row = card("CreateGang", "Załóż gang bezpłatnie", "Wybierz unikalną nazwę i wolny kolor. Zajęte kolory są zablokowane.", nil)
			local input = nameInput(row, scope, draft, actions)
			local selected: number? = nil
			selected = colors(row, scope, gang, function(id) selected = id end)
			local button = Components.Button(row, "Utwórz gang", scope, function()
				actions.Action("CreateGang", { name = input.Text, colorId = selected })
			end, true, Style.Apps.Gang.Top)
			button.Name = "Create"
			button.LayoutOrder = 5
			button.Size = UDim2.new(1, 0, 0, Theme.TouchTarget)
			button:SetAttribute("PhoneAction", true)
			button:SetAttribute("Available", selected ~= nil)
			Components.SetEnabled(button, selected ~= nil)
		else card("NoGang", "Nie należysz do gangu", "Odczekaj po opuszczeniu gangu i odśwież telefon.", nil) end
		for _, entry in ipairs(gang.directory or {}) do
			local row = card("Directory_" .. entry.id, entry.name, string.format("%d / %d członków", entry.memberCount, entry.maxMembers), entry.color)
			action(row, "RequestJoin", if entry.requested then "Prośba wysłana" else "Poproś o dołączenie", "RequestJoinGang", entry.id,
				gang.canCreate and not entry.requested and entry.memberCount < entry.maxMembers, false)
		end
		return nil
	end
	card("GangSummary", gang.gangName or "Twój gang", string.format("%d / %d członków • %d flag • około %d Coins/min na osobę",
		#gang.members, gang.maxMembers, gang.flagsOwned or 0, gang.incomePerMinute or 0), gang.gangColor)
	if gang.leaderOfflineUntil then
		card("LeaderOffline", "Lider offline", string.format("Przywództwo przejdzie na najstarszego obecnego członka za około %d min.",
			math.max(0, math.ceil((gang.leaderOfflineUntil - Workspace:GetServerTimeNow()) / 60))), nil)
	end
	for _, member in gang.members do
		local row = card("Member_" .. member.userId, member.displayName,
			(if member.isLeader then "Lider" else "Członek") .. (if member.online == false then " • offline" else ""), nil)
		if gang.isLeader and not member.isLeader then action(row, "Kick", "Usuń z gangu", "KickGangMember", member.userId, true, false) end
	end
	if gang.isLeader then
		for _, request in ipairs(gang.requests or {}) do
			local row = card("Request_" .. request.id, request.displayName, "Prośba o dołączenie", nil)
			action(row, "AcceptRequest", "Przyjmij", "RespondGangRequest", { id = request.id, accept = true }, #gang.members < gang.maxMembers, true)
			action(row, "RejectRequest", "Odrzuć", "RespondGangRequest", { id = request.id, accept = false }, true, false)
		end
		if #gang.members < gang.maxMembers then
			for _, candidate in gang.candidates do
				local row = card("Candidate_" .. candidate.userId, candidate.displayName, "Gracz na serwerze", nil)
				action(row, "InviteMember", "Zaproś do gangu", "InviteGangMember", candidate.userId, true, false)
			end
		end
		local row = card("Rename", "Zmień nazwę", "Zmiana dostępna raz na minutę.", nil)
		local input = nameInput(row, scope, if draft ~= "" then draft else gang.gangName or "", actions)
		local rename = Components.Button(row, "Zapisz nazwę", scope, function() actions.Action("RenameGang", input.Text) end, true)
		rename.LayoutOrder = 4
		rename.Size = UDim2.new(1, 0, 0, Theme.TouchTarget)
		rename:SetAttribute("PhoneAction", true); rename:SetAttribute("Available", true)
		local colorRow = card("ChangeColor", "Zmień kolor", "Wybierz wolny kolor. Zmiana dostępna raz na minutę.", nil)
		colors(colorRow, scope, gang, function(id) actions.Action("SetGangColor", id) end)
	end
	local leave = card("LeaveGang", "Zarządzanie gangiem", if gang.isLeader then "Po wyjściu przywództwo przejmie najstarszy obecny członek." else "Możesz opuścić swój obecny gang.", nil)
	action(leave, "Leave", "Opuść gang", "LeaveGang", nil, true, false)
	territories(scope, card)
	return nil
end
return View
