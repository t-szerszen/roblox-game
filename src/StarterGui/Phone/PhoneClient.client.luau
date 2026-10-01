--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

type DailyState = { id: string, progress: number, target: number }
type GangMemberState = { userId: number, displayName: string, isLeader: boolean }
type GangCandidateState = { userId: number, displayName: string }
type GangState = {
	canCreate: boolean,
	gangId: string?,
	gangName: string?,
	gangColor: Color3?,
	isLeader: boolean,
	members: { GangMemberState },
	maxMembers: number,
	invite: { gangName: string, inviterName: string, expiresAt: number }?,
	candidates: { GangCandidateState },
}
type PhoneState = {
	passiveEnabled: boolean,
	passiveAvailable: boolean,
	gangName: string?,
	gang: GangState,
	delivery: { active: boolean, destination: string, distance: number },
	daily: { DailyState },
	ownedScooters: { string },
	loginStreak: number,
	loginReward: number,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName):WaitForChild(PhoneConfig.RequestFunctionName) :: RemoteFunction
local stateChanged = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName):WaitForChild(PhoneConfig.StateChangedEventName) :: RemoteEvent

local C = {
	phone = Color3.fromRGB(230, 115, 50), -- iPhone 17 Pro Orange Titanium
	screen = Color3.fromRGB(0, 0, 0), -- OLED Black
	ink = Color3.fromRGB(255, 255, 255), -- White text for OLED
	muted = Color3.fromRGB(152, 152, 157), -- iOS Gray
	line = Color3.fromRGB(44, 44, 46), -- iOS Dark Separator
	white = Color3.fromRGB(28, 28, 30), -- iOS Dark Card Background
	green = Color3.fromRGB(48, 209, 88), -- iOS Green
	red = Color3.fromRGB(255, 69, 58), -- iOS Red
	yellow = Color3.fromRGB(255, 159, 10), -- iOS Orange
	blue = Color3.fromRGB(10, 132, 255), -- iOS Blue
	purple = Color3.fromRGB(191, 90, 242), -- iOS Purple
}

local emptyState: PhoneState = {
	passiveEnabled = false,
	passiveAvailable = true,
	gangName = nil,
	gang = {
		canCreate = false,
		gangId = nil,
		gangName = nil,
		gangColor = nil,
		isLeader = false,
		members = {},
		maxMembers = 1,
		invite = nil,
		candidates = {},
	},
	delivery = { active = false, destination = "", distance = 0 },
	daily = {},
	ownedScooters = {},
	loginStreak = 0,
	loginReward = 0,
}
local state = emptyState
local currentPage = "Home"
local busy = false
local pageConnections: { RBXScriptConnection } = {}

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number?)
	local item = Instance.new("UIStroke")
	item.Color = color
	item.Transparency = transparency or 0
	item.Thickness = 1
	item.Parent = parent
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	item.Text = text
	item.TextColor3 = color
	item.TextSize = size
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

local function makeButton(parent: Instance, text: string, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.AutoButtonColor = true
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = C.white
	item.TextSize = 12
	item.Parent = parent
	corner(item, 7)
	return item
end

local function clearPageConnections()
	for _, connection in pageConnections do
		connection:Disconnect()
	end
	table.clear(pageConnections)
end

local gui = Instance.new("ScreenGui")
gui.Name = "PhoneGui"
gui.DisplayOrder = 15
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local openButton = makeButton(gui, "TEL", C.ink)
openButton.Name = "OpenPhone"
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 24, 1, -24)
openButton.Size = UDim2.fromOffset(52, 48)

local phone = Instance.new("Frame")
phone.Name = "Phone"
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -24, 1, 30)
phone.Size = UDim2.fromOffset(382, 700)
phone.BackgroundColor3 = C.phone
phone.Visible = false
phone.ClipsDescendants = true
phone.Parent = gui
corner(phone, 44)
stroke(phone, Color3.fromRGB(255, 160, 90), 0)

local phoneSize = Instance.new("UISizeConstraint")
phoneSize.MinSize = Vector2.new(320, 520)
phoneSize.MaxSize = Vector2.new(382, 700)
phoneSize.Parent = phone

local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.Position = UDim2.fromOffset(8, 8)
screen.Size = UDim2.new(1, -16, 1, -16)
screen.BackgroundColor3 = C.screen
screen.ClipsDescendants = true
screen.Parent = phone
corner(screen, 38)

local dynamicIsland = Instance.new("Frame")
dynamicIsland.Size = UDim2.fromOffset(110, 32)
dynamicIsland.Position = UDim2.new(0.5, 0, 0, 8)
dynamicIsland.AnchorPoint = Vector2.new(0.5, 0)
dynamicIsland.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
dynamicIsland.Parent = screen
corner(dynamicIsland, 16)
stroke(dynamicIsland, Color3.fromRGB(30, 30, 30), 0)

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 88)
topBar.BackgroundTransparency = 1
topBar.BorderSizePixel = 0
topBar.Parent = screen

local backButton = makeButton(topBar, "<", C.white)
backButton.Name = "Back"
backButton.Position = UDim2.fromOffset(16, 44)
backButton.Size = UDim2.fromOffset(34, 34)
backButton.Visible = false

local pageTitle = makeLabel(topBar, "Telefon", 24, C.ink, true)
pageTitle.Position = UDim2.fromOffset(24, 46)
pageTitle.Size = UDim2.new(1, -100, 0, 30)

local clock = makeLabel(screen, "", 13, C.ink, true)
clock.Position = UDim2.fromOffset(24, 15)
clock.Size = UDim2.fromOffset(60, 20)
clock.TextXAlignment = Enum.TextXAlignment.Center

local battery = makeLabel(screen, "100%", 12, C.ink, true)
battery.AnchorPoint = Vector2.new(1, 0)
battery.Position = UDim2.new(1, -24, 0, 15)
battery.Size = UDim2.fromOffset(60, 20)
battery.TextXAlignment = Enum.TextXAlignment.Center

local closeButton = makeButton(topBar, "X", C.white)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -16, 0, 44)
closeButton.Size = UDim2.fromOffset(34, 34)

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Position = UDim2.fromOffset(0, 88)
content.Size = UDim2.new(1, 0, 1, -112)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 3
content.ScrollBarImageColor3 = C.muted
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.Parent = screen

local pagePadding = Instance.new("UIPadding")
pagePadding.PaddingTop = UDim.new(0, 16)
pagePadding.PaddingBottom = UDim.new(0, 18)
pagePadding.PaddingLeft = UDim.new(0, 16)
pagePadding.PaddingRight = UDim.new(0, 16)
pagePadding.Parent = content

local homeBar = Instance.new("Frame")
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.Position = UDim2.new(0.5, 0, 1, -9)
homeBar.Size = UDim2.fromOffset(112, 4)
homeBar.BackgroundColor3 = C.ink
homeBar.Parent = screen
corner(homeBar, 2)

local toast = makeLabel(screen, "", 12, C.white, true)
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -28)
toast.Size = UDim2.new(1, -34, 0, 42)
toast.BackgroundTransparency = 0.05
toast.BackgroundColor3 = C.ink
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextWrapped = true
toast.Visible = false
corner(toast, 7)

local function updateClock()
	clock.Text = os.date("%H:%M")
end

local function showToast(message: string, isError: boolean)
	toast.Text = message
	toast.BackgroundColor3 = if isError then C.red else C.ink
	toast.Visible = message ~= ""
	local shownMessage = message
	task.delay(2.5, function()
		if toast.Text == shownMessage then
			toast.Visible = false
		end
	end)
end

local function callServer(action: string, payload: unknown): (boolean, string, PhoneState)
	local ok, success, message, newState = pcall(function()
		return request:InvokeServer(action, payload)
	end)
	if not ok or typeof(success) ~= "boolean" or typeof(newState) ~= "table" then
		return false, "Telefon nie moze polaczyc sie z serwerem.", state
	end
	return success, if typeof(message) == "string" then message else "", newState :: PhoneState
end

local function clearContent()
	clearPageConnections()
	for _, child in content:GetChildren() do
		if not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	content.CanvasPosition = Vector2.zero
end

local function verticalLayout(parent: Instance, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function sectionTitle(text: string): TextLabel
	local item = makeLabel(content, text, 13, C.muted, true)
	item.Size = UDim2.new(1, 0, 0, 22)
	return item
end

local function infoRow(titleText: string, detail: string, accent: Color3): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 76)
	row.BackgroundColor3 = C.white
	row.Parent = content
	corner(row, 8)
	stroke(row, C.line, 0.2)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, 0)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.Parent = row

	local titleLabel = makeLabel(row, titleText, 14, C.ink, true)
	titleLabel.Position = UDim2.fromOffset(18, 13)
	titleLabel.Size = UDim2.new(1, -34, 0, 21)
	local detailLabel = makeLabel(row, detail, 12, C.muted)
	detailLabel.Position = UDim2.fromOffset(18, 39)
	detailLabel.Size = UDim2.new(1, -34, 0, 24)
	detailLabel.TextWrapped = true
	return row
end

local renderPage: () -> ()

local function runAction(action: string, payload: unknown)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local success, message, newState = callServer(action, payload)
		state = newState
		busy = false
		showToast(message, not success)
		renderPage()
	end)
end

local apps = {
	{ id = "Scooters", name = "Hulajnogi", caption = "Przywol pojazd", color = C.yellow, glyph = "K" },
	{ id = "Delivery", name = "Dostawy", caption = "Aktywne zlecenie", color = C.blue, glyph = "D" },
	{ id = "Gang", name = "Gang", caption = "Czlonkowie i status", color = C.purple, glyph = "G" },
	{ id = "Daily", name = "Dzienne", caption = "Postep misji", color = C.green, glyph = "M" },
	{ id = "Protection", name = "Ochrona", caption = "Tryb pasywny", color = C.red, glyph = "O" },
}

local function renderHome()
	pageTitle.Text = "Telefon"
	backButton.Visible = false
	local greeting = makeLabel(content, string.format("Czesc, %s", player.DisplayName), 21, C.ink, true)
	greeting.Size = UDim2.new(1, 0, 0, 32)

	local protectionText = if not state.passiveAvailable
		then "Ochrona niedostepna w gangu"
		else if state.passiveEnabled then "Tryb ochronny wlaczony" else "Tryb ochronny wylaczony"
	local summary = infoRow("Status", protectionText, if state.passiveEnabled then C.green else C.red)
	summary.Size = UDim2.new(1, 0, 0, 68)

	sectionTitle("APLIKACJE")
	local appGrid = Instance.new("Frame")
	appGrid.Size = UDim2.new(1, 0, 0, 294)
	appGrid.BackgroundTransparency = 1
	appGrid.Parent = content

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.CellSize = UDim2.new(0.5, -5, 0, 88)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = appGrid

	for index, app in apps do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.BackgroundColor3 = C.white
		button.Text = ""
		button.AutoButtonColor = true
		button.Parent = appGrid
		corner(button, 8)
		stroke(button, C.line, 0.2)

		local glyph = makeLabel(button, app.glyph, 18, C.white, true)
		glyph.Position = UDim2.fromOffset(12, 11)
		glyph.Size = UDim2.fromOffset(34, 34)
		glyph.BackgroundTransparency = 0
		glyph.BackgroundColor3 = app.color
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		corner(glyph, 7)

		local name = makeLabel(button, app.name, 13, C.ink, true)
		name.Position = UDim2.fromOffset(12, 51)
		name.Size = UDim2.new(1, -24, 0, 18)
		local caption = makeLabel(button, app.caption, 10, C.muted)
		caption.Position = UDim2.fromOffset(12, 69)
		caption.Size = UDim2.new(1, -24, 0, 14)
		caption.TextTruncate = Enum.TextTruncate.AtEnd

		table.insert(pageConnections, button.Activated:Connect(function()
			currentPage = app.id
			renderPage()
		end))
	end
end

local function renderScooters()
	sectionTitle("TWOJE MODELE")
	local owned: { [string]: boolean } = {}
	for _, name in state.ownedScooters do
		owned[name] = true
	end
	for _, product in ShopConfig.CoinProducts do
		local isOwned = owned[product.name] == true
		local row = infoRow(product.name, product.description, product.accent)
		row.Size = UDim2.new(1, 0, 0, 94)
		local action = makeButton(row, if isOwned then "PRZYWOLAJ" else "ZABLOKOWANA", if isOwned then C.ink else C.muted)
		action.AnchorPoint = Vector2.new(1, 1)
		action.Position = UDim2.new(1, -12, 1, -12)
		action.Size = UDim2.fromOffset(112, 30)
		action.Active = isOwned
		action.AutoButtonColor = isOwned
		if isOwned then
			table.insert(pageConnections, action.Activated:Connect(function()
				runAction("SpawnScooter", product.name)
			end))
		end
	end
end

local function renderDelivery()
	if state.delivery.active then
		sectionTitle("AKTYWNA DOSTAWA")
		infoRow("Cel", state.delivery.destination, C.blue)
		infoRow("Pozostaly dystans", string.format("%d studow", math.floor(state.delivery.distance)), C.yellow)
	else
		sectionTitle("DOSTAWY")
		local row = infoRow("Brak aktywnej dostawy", "Zlecenie rozpoczniesz w punkcie odbioru na mapie.", C.blue)
		row.Size = UDim2.new(1, 0, 0, 96)
	end
end

local function renderGang()
	local gang = state.gang
	if gang.invite and not gang.gangId then
		sectionTitle("ZAPROSZENIE")
		local inviteRow = infoRow(
			gang.invite.gangName,
			string.format("Zaprasza: %s", gang.invite.inviterName),
			C.purple
		)
		inviteRow.Size = UDim2.new(1, 0, 0, 118)
		local accept = makeButton(inviteRow, "DOLACZ", C.green)
		accept.Position = UDim2.new(0, 18, 1, -44)
		accept.Size = UDim2.new(0.5, -23, 0, 32)
		local decline = makeButton(inviteRow, "ODRZUC", C.red)
		decline.Position = UDim2.new(0.5, 5, 1, -44)
		decline.Size = UDim2.new(0.5, -23, 0, 32)
		table.insert(pageConnections, accept.Activated:Connect(function()
			runAction("RespondGangInvite", true)
		end))
		table.insert(pageConnections, decline.Activated:Connect(function()
			runAction("RespondGangInvite", false)
		end))
	end

	sectionTitle("TWOJ GANG")
	if not gang.gangId then
		if not gang.canCreate then
			local row = infoRow("Nie nalezysz do gangu", "Prawo do zalozenia gangu wymaga stalego odblokowania za Coiny.", C.purple)
			row.Size = UDim2.new(1, 0, 0, 96)
			return
		end

		local createRow = infoRow("Zaloz gang", "Wybierz unikalna nazwe.", C.purple)
		createRow.Size = UDim2.new(1, 0, 0, 136)
		local nameInput = Instance.new("TextBox")
		nameInput.Position = UDim2.new(0, 18, 1, -76)
		nameInput.Size = UDim2.new(1, -134, 0, 36)
		nameInput.BackgroundColor3 = C.screen
		nameInput.Font = Enum.Font.Gotham
		nameInput.PlaceholderText = "Nazwa gangu"
		nameInput.PlaceholderColor3 = C.muted
		nameInput.Text = ""
		nameInput.TextColor3 = C.ink
		nameInput.TextSize = 13
		nameInput.ClearTextOnFocus = false
		nameInput.Parent = createRow
		corner(nameInput, 7)
		stroke(nameInput, C.line)
		local create = makeButton(createRow, "UTWORZ", C.purple)
		create.AnchorPoint = Vector2.new(1, 0)
		create.Position = UDim2.new(1, -12, 1, -76)
		create.Size = UDim2.fromOffset(96, 36)
		table.insert(pageConnections, create.Activated:Connect(function()
			runAction("CreateGang", nameInput.Text)
		end))
		return
	end

	local gangColor = gang.gangColor or C.purple
	infoRow(
		gang.gangName or "Gang",
		string.format("%d / %d czlonkow | ochrona wylaczona", #gang.members, gang.maxMembers),
		gangColor
	)

	sectionTitle("CZLONKOWIE")
	for _, member in gang.members do
		local detail = if member.isLeader then "Lider" else "Czlonek"
		local row = infoRow(member.displayName, detail, if member.isLeader then gangColor else C.ink)
		if gang.isLeader and not member.isLeader then
			local kick = makeButton(row, "WYRZUC", C.red)
			kick.AnchorPoint = Vector2.new(1, 0.5)
			kick.Position = UDim2.new(1, -12, 0.5, 0)
			kick.Size = UDim2.fromOffset(82, 30)
			table.insert(pageConnections, kick.Activated:Connect(function()
				runAction("KickGangMember", member.userId)
			end))
		end
	end

	if gang.isLeader and #gang.candidates > 0 and #gang.members < gang.maxMembers then
		sectionTitle("ZAPROS GRACZA")
		for _, candidate in gang.candidates do
			local row = infoRow(candidate.displayName, "Dostepny", C.green)
			local invite = makeButton(row, "ZAPROS", C.green)
			invite.AnchorPoint = Vector2.new(1, 0.5)
			invite.Position = UDim2.new(1, -12, 0.5, 0)
			invite.Size = UDim2.fromOffset(82, 30)
			table.insert(pageConnections, invite.Activated:Connect(function()
				runAction("InviteGangMember", candidate.userId)
			end))
		end
	end

	local leave = makeButton(content, if gang.isLeader then "ROZWIAZ GANG" else "OPUSC GANG", C.red)
	leave.Size = UDim2.new(1, 0, 0, 40)
	table.insert(pageConnections, leave.Activated:Connect(function()
		runAction("LeaveGang", nil)
	end))
end

local function renderDaily()
	sectionTitle("SERIA LOGOWAN")
	local loginDetail = string.format("Dzien %d / 7", state.loginStreak)
	if state.loginReward > 0 then
		loginDetail ..= string.format(" | +%d Coins", state.loginReward)
	end
	infoRow("Daily Login", loginDetail, C.yellow)
	sectionTitle("DZISIAJ")
	local byId: { [string]: DailyState } = {}
	for _, progress in state.daily do
		byId[progress.id] = progress
	end
	for _, mission in PhoneConfig.DailyMissions do
		local progress = byId[mission.id]
		local value = if progress then progress.progress else 0
		local row = infoRow(mission.name, string.format("%g / %g %s", value, mission.target, mission.unit), C.green)
		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 18, 1, -14)
		bar.Size = UDim2.new(1, -36, 0, 5)
		bar.BackgroundColor3 = C.line
		bar.BorderSizePixel = 0
		bar.Parent = row
		corner(bar, 3)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(math.clamp(value / mission.target, 0, 1), 1)
		fill.BackgroundColor3 = C.green
		fill.BorderSizePixel = 0
		fill.Parent = bar
		corner(fill, 3)
	end
end

local function renderProtection()
	sectionTitle("TRYB OCHRONNY")
	local titleText = if state.passiveEnabled then "Ochrona aktywna" else "Ochrona nieaktywna"
	local detail = if state.passiveAvailable
		then "Blokuje udzial w PvP."
		else "Czlonkowie gangu nie moga korzystac z ochrony."
	local row = infoRow(titleText, detail, if state.passiveEnabled then C.green else C.red)
	row.Size = UDim2.new(1, 0, 0, 118)
	local toggle = makeButton(
		row,
		if state.passiveEnabled then "WYLACZ" else "WLACZ",
		if state.passiveAvailable then (if state.passiveEnabled then C.red else C.green) else C.muted
	)
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 18, 1, -12)
	toggle.Size = UDim2.new(1, -36, 0, 34)
	toggle.Active = state.passiveAvailable
	toggle.AutoButtonColor = state.passiveAvailable
	if state.passiveAvailable then
		table.insert(pageConnections, toggle.Activated:Connect(function()
			runAction("SetPassive", not state.passiveEnabled)
		end))
	end
end

renderPage = function()
	clearContent()
	verticalLayout(content, 10)
	backButton.Visible = currentPage ~= "Home"
	pageTitle.Position = if currentPage == "Home" then UDim2.fromOffset(24, 46) else UDim2.fromOffset(64, 46)
	pageTitle.Text = currentPage

	if currentPage == "Home" then
		renderHome()
	elseif currentPage == "Scooters" then
		pageTitle.Text = "Hulajnogi"
		renderScooters()
	elseif currentPage == "Delivery" then
		pageTitle.Text = "Dostawy"
		renderDelivery()
	elseif currentPage == "Gang" then
		pageTitle.Text = "Gang"
		renderGang()
	elseif currentPage == "Daily" then
		pageTitle.Text = "Misje dzienne"
		renderDaily()
	elseif currentPage == "Protection" then
		pageTitle.Text = "Ochrona"
		renderProtection()
	end
end

local function refresh()
	task.spawn(function()
		local success, message, newState = callServer("GetState", nil)
		state = newState
		if not success then
			showToast(message, true)
		end
		renderPage()
	end)
end

local function setOpen(open: boolean)
	phone.Visible = open
	openButton.Visible = not open
	if open then
		currentPage = "Home"
		phone.Position = UDim2.new(1, -24, 1, 30)
		TweenService:Create(phone, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -24, 1, -20),
		}):Play()
		refresh()
	end
end

openButton.Activated:Connect(function()
	setOpen(true)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
backButton.Activated:Connect(function()
	currentPage = "Home"
	renderPage()
end)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.M then
		setOpen(not phone.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and phone.Visible then
		setOpen(false)
	end
end)
stateChanged.OnClientEvent:Connect(function()
	if phone.Visible then
		refresh()
	else
		showToast("Nowa aktywnosc w aplikacji Gang.", false)
	end
end)
local activityMessageConnection = player:GetAttributeChangedSignal("ActivityMessageNonce"):Connect(function()
	local message = player:GetAttribute("ActivityMessage")
	local success = player:GetAttribute("ActivityMessageSuccess") == true
	if typeof(message) == "string" then
		showToast(message, not success)
	end
	if phone.Visible then
		refresh()
	end
end)

local function resizePhone()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X < 600 or viewport.Y < 760 then
		phone.Size = UDim2.fromOffset(math.min(350, viewport.X - 24), math.min(620, viewport.Y - 30))
	else
		phone.Size = UDim2.fromOffset(382, 700)
	end
end

local cameraConnection: RBXScriptConnection? = nil
local function hookCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resizePhone)
	end
	resizePhone()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()
updateClock()
task.spawn(function()
	while gui.Parent do
		task.wait(15)
		updateClock()
	end
end)
renderPage()

script.Destroying:Connect(function()
	clearPageConnections()
	activityMessageConnection:Disconnect()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	gui:Destroy()
end)
