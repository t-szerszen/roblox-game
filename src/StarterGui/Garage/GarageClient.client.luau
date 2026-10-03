--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ScooterConfig = require(ReplicatedStorage.Shared.ScooterConfig)
if not ScooterConfig.GarageEnabled then return end
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(ScooterConfig.RemoteFolderName)
	:WaitForChild(ScooterConfig.GarageRequestFunctionName) :: RemoteFunction

type ModelState = { owned: boolean, speedTier: number, maxSpeed: number, nextUpgradeCost: number? }
type GarageState = {
	coins: number,
	dataReady: boolean,
	models: { [string]: ModelState },
	visuals: { smokeEnabled: boolean, smokeColor: Color3, neonEnabled: boolean, neonColor: Color3 },
	smokeOwned: boolean,
	neonOwned: boolean,
}

local connections: { RBXScriptConnection } = {}
local alive = true
local busy = false
local lastRequestAt = -math.huge
local state: GarageState? = nil
local selectedModel = ScooterConfig.DefaultModel
local selectedVisual: "Smoke" | "Neon" = "Smoke"
local visualEnabled = false
local rgbInputs: { TextBox } = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GarageGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function round(instance: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = instance
end

local function label(parent: Instance, text: string, y: number, height: number): TextLabel
	local result = Instance.new("TextLabel")
	result.Position = UDim2.fromOffset(24, y)
	result.Size = UDim2.new(1, -48, 0, height)
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = Color3.fromRGB(235, 244, 255)
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextWrapped = true
	result.Text = text
	result.Parent = parent
	return result
end

local function button(parent: Instance, text: string, position: UDim2, size: UDim2): TextButton
	local result = Instance.new("TextButton")
	result.Position = position
	result.Size = size
	result.BackgroundColor3 = Color3.fromRGB(48, 121, 183)
	result.Font = Enum.Font.GothamBold
	result.TextSize = 17
	result.TextColor3 = Color3.new(1, 1, 1)
	result.Text = text
	result.Parent = parent
	round(result)
	return result
end

local openButton = button(gui, "Garaż [B]", UDim2.new(1, -160, 1, -130), UDim2.fromOffset(136, 44))
local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Visible = false
overlay.Active = true
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(520, 500)
panel.BackgroundColor3 = Color3.fromRGB(30, 42, 61)
panel.Parent = overlay
round(panel)
local scale = Instance.new("UIScale")
scale.Parent = panel

local heading = label(panel, "GARAŻ", 18, 30)
heading.Font = Enum.Font.GothamBold
heading.TextSize = 24
local closeButton = button(panel, "X", UDim2.new(1, -58, 0, 16), UDim2.fromOffset(34, 34))
local coinsLabel = label(panel, "Ładowanie danych…", 53, 26)
local modelButton = button(panel, selectedModel .. "  >", UDim2.fromOffset(24, 91), UDim2.new(1, -48, 0, 42))
local speedLabel = label(panel, "", 141, 28)
local purchaseButton = button(panel, "Wczytaj garaż", UDim2.fromOffset(24, 177), UDim2.new(1, -48, 0, 42))
label(panel, "Wygląd premium · kolor RGB (0–255)", 235, 24)
local kindButton = button(panel, "Dym  >", UDim2.fromOffset(24, 270), UDim2.fromOffset(168, 36))
local enabledButton = button(panel, "Wyłączony", UDim2.fromOffset(202, 270), UDim2.fromOffset(144, 36))
local preview = Instance.new("Frame")
preview.Position = UDim2.fromOffset(362, 270)
preview.Size = UDim2.fromOffset(134, 36)
preview.BackgroundColor3 = Color3.new(1, 1, 1)
preview.Parent = panel
round(preview)
for index, name in { "R", "G", "B" } do
	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(24 + (index - 1) * 160, 318)
	input.Size = UDim2.fromOffset(152, 38)
	input.BackgroundColor3 = Color3.fromRGB(54, 67, 88)
	input.TextColor3 = Color3.new(1, 1, 1)
	input.Font = Enum.Font.GothamMedium
	input.TextSize = 18
	input.PlaceholderText = name .. " 0–255"
	input.ClearTextOnFocus = false
	input.Text = "255"
	input.Parent = panel
	round(input)
	table.insert(rgbInputs, input)
end
local saveVisualButton = button(panel, "Zapisz wygląd", UDim2.fromOffset(24, 368), UDim2.fromOffset(228, 38))
local shopButton = button(panel, "Premium · sklep", UDim2.fromOffset(268, 368), UDim2.fromOffset(228, 38))
local status = label(panel, "", 418, 62)
status.TextSize = 15
status.TextYAlignment = Enum.TextYAlignment.Top

local messages = {
	Purchased = "Ulepszenie kupione. Nowa prędkość jest aktywna.",
	VisualUpdated = "Wygląd zapisany.",
	InsufficientCoins = "Brakuje Coinów na to ulepszenie.",
	MaximumTier = "Ten model ma już wszystkie ulepszenia.",
	StaleTier = "Poziom już się zmienił. Sprawdź aktualną cenę.",
	NotOwned = "Najpierw odblokuj ten model w sklepie.",
	DataUnavailable = "Dane gracza są niedostępne. Spróbuj ponownie później.",
	GamePassRequired = "Ten wygląd wymaga odpowiedniego produktu Premium w sklepie.",
	Busy = "Dane Premium są sprawdzane. Otwórz garaż ponownie za chwilę.",
	RateLimited = "Odczekaj chwilę przed kolejną zmianą.",
} :: { [string]: string }

local function hasSelectedVisual(current: GarageState): boolean
	return if selectedVisual == "Smoke" then current.smokeOwned else current.neonOwned
end

local function render(resetColor: boolean)
	local current = state
	if not current then
		return
	end
	coinsLabel.Text = string.format("%d Coins", current.coins)
	local model = current.models[selectedModel]
	modelButton.Text = selectedModel .. "  >"
	if model then
		speedLabel.Text = string.format("Ulepszenie %d/3  ·  %.1f km/h", model.speedTier, model.maxSpeed)
		purchaseButton.Text = if model.nextUpgradeCost then string.format("+1,5 km/h · %d Coins", model.nextUpgradeCost) else "Maksymalne ulepszenie"
		purchaseButton.Active = not busy and current.dataReady and model.owned and model.nextUpgradeCost ~= nil
		purchaseButton.AutoButtonColor = purchaseButton.Active
	end
	if resetColor then
		local color = if selectedVisual == "Smoke" then current.visuals.smokeColor else current.visuals.neonColor
		visualEnabled = if selectedVisual == "Smoke" then current.visuals.smokeEnabled else current.visuals.neonEnabled
		for index, channel in { color.R, color.G, color.B } do
			rgbInputs[index].Text = tostring(math.floor(channel * 255 + 0.5))
		end
		preview.BackgroundColor3 = color
	end
	kindButton.Text = if selectedVisual == "Smoke" then "Dym  >" else "Neony  >"
	enabledButton.Text = if visualEnabled then "Włączony" else "Wyłączony"
	saveVisualButton.Text = if hasSelectedVisual(current) then "Zapisz wygląd" else "Wymaga Premium"
	saveVisualButton.Active = not busy and current.dataReady and hasSelectedVisual(current)
	saveVisualButton.AutoButtonColor = saveVisualButton.Active
	if not current.dataReady then
		status.Text = messages.DataUnavailable
	end
end

local function callServer(action: string, modelName: string?, payload: unknown)
	if not alive or busy then
		return
	end
	busy = true
	render(false)
	local delay = ScooterConfig.GarageRequestCooldown - (os.clock() - lastRequestAt)
	if delay > 0 then
		task.wait(delay + 0.02)
	end
	if not alive then
		return
	end
	lastRequestAt = os.clock()
	local ok, success, reason, result = pcall(function()
		return request:InvokeServer(action, modelName, payload)
	end)
	if not alive then
		return
	end
	busy = false
	if ok and typeof(result) == "table" then
		state = result :: GarageState
	end
	status.Text = if ok and success == true then (messages[reason] or "") else (messages[reason] or "Nie można połączyć się z garażem.")
	render(true)
end

local function setOpen(open: boolean)
	overlay.Visible = open
	gui:SetAttribute("GarageOpen", open)
	if open then
		callServer("GetState", nil, nil)
	end
end

local function readColor(): Color3?
	local channels: { number } = {}
	for _, input in rgbInputs do
		local value = tonumber(input.Text)
		if not value or value ~= value or value < 0 or value > 255 or value % 1 ~= 0 then
			status.Text = "Wpisz dla R, G i B liczby całkowite od 0 do 255."
			return nil
		end
		table.insert(channels, value)
	end
	return Color3.fromRGB(channels[1], channels[2], channels[3])
end

table.insert(connections, openButton.Activated:Connect(function()
	setOpen(not overlay.Visible)
end))
table.insert(connections, closeButton.Activated:Connect(function()
	setOpen(false)
end))
table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.B and not UserInputService:GetFocusedTextBox() then
		setOpen(not overlay.Visible)
	end
end))
table.insert(connections, modelButton.Activated:Connect(function()
	local current = state
	if not current or busy then
		return
	end
	local owned: { string } = {}
	for _, product in ShopConfig.CoinProducts do
		local model = current.models[product.name]
		if model and model.owned then
			table.insert(owned, product.name)
		end
	end
	if #owned > 0 then
		local index = table.find(owned, selectedModel) or 0
		selectedModel = owned[index % #owned + 1]
		render(false)
	end
end))
table.insert(connections, purchaseButton.Activated:Connect(function()
	local current = state
	local model = if current then current.models[selectedModel] else nil
	if current and current.dataReady and model and model.owned and model.nextUpgradeCost then
		callServer("PurchaseSpeed", selectedModel, model.speedTier)
	end
end))
table.insert(connections, kindButton.Activated:Connect(function()
	selectedVisual = if selectedVisual == "Smoke" then "Neon" else "Smoke"
	render(true)
end))
table.insert(connections, enabledButton.Activated:Connect(function()
	visualEnabled = not visualEnabled
	render(false)
end))
table.insert(connections, saveVisualButton.Activated:Connect(function()
	local current = state
	local color = readColor()
	if current and current.dataReady and hasSelectedVisual(current) and color then
		callServer("SetVisual", nil, { kind = selectedVisual, enabled = visualEnabled, color = color })
	end
end))
for _, input in rgbInputs do
	table.insert(connections, input.FocusLost:Connect(function()
		local color = readColor()
		if color then
			preview.BackgroundColor3 = color
		end
	end))
end
table.insert(connections, shopButton.Activated:Connect(function()
	local shop = playerGui:FindFirstChild("ShopGui")
	local toggle = if shop then shop:FindFirstChild("ToggleShop") else nil
	if toggle and toggle:IsA("BindableEvent") then
		setOpen(false)
		if shop and shop:GetAttribute("ShopOpen") ~= true then
			toggle:Fire()
		end
	else
		status.Text = "Sklep jeszcze się ładuje. Spróbuj za chwilę."
	end
end))

local function updateScale()
	scale.Scale = math.max(0.1, math.min(1, (gui.AbsoluteSize.X - 24) / 520, (gui.AbsoluteSize.Y - 24) / 500))
end
table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))
updateScale()

local function cleanup()
	if not alive then
		return
	end
	alive = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	gui:Destroy()
end
table.insert(connections, gui.Destroying:Connect(cleanup))
table.insert(connections, script.Destroying:Connect(cleanup))
