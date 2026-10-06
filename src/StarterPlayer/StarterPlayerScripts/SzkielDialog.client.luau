-- Klasyczny dialog: wypowiedzi nad NPC, odpowiedzi jako osobne przyciski.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local npc = workspace:WaitForChild("Dialogue System"):WaitForChild("showcase npc")
local prompt = npc:WaitForChild("ProximityPrompt")
local npcGui = npc:WaitForChild("Head"):WaitForChild("gui")
local nameLabel = npcGui:WaitForChild("name")
local dialogLabel = npcGui:WaitForChild("dialog")
local arrowLabel = npcGui:WaitForChild("arrow")
local playerGui = player:WaitForChild("PlayerGui")
local questAction = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("PosterQuest"):WaitForChild("Action")

local previousGui = playerGui:FindFirstChild("SzkielDialogResponses")
if previousGui then
	previousGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SzkielDialogResponses"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local choicesFrame = Instance.new("Frame")
choicesFrame.Name = "Choices"
choicesFrame.AnchorPoint = Vector2.new(0.5, 1)
choicesFrame.Position = UDim2.new(0.5, 0, 0.91, 0)
choicesFrame.Size = UDim2.new(0.7, 0, 0, 144)
choicesFrame.BackgroundTransparency = 1
choicesFrame.Parent = screenGui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 1)
sizeConstraint.MaxSize = Vector2.new(620, 144)
sizeConstraint.Parent = choicesFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 7)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
listLayout.Parent = choicesFrame

local isOpen = false
local dialogVersion = 0
local connections = {}
local choiceConnections = {}

local function clearChoices()
	for _, connection in choiceConnections do
		connection:Disconnect()
	end
	table.clear(choiceConnections)
	for _, child in choicesFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function closeDialog()
	dialogVersion += 1
	isOpen = false
	screenGui.Enabled = false
	dialogLabel.Visible = false
	nameLabel.Visible = true
	arrowLabel.Visible = true
	npcGui.AlwaysOnTop = false
	clearChoices()
end

local showDialog
showDialog = function(text, options, typingDelay)
	dialogVersion += 1
	local version = dialogVersion
	clearChoices()
	screenGui.Enabled = true
	choicesFrame.Visible = false
	dialogLabel.Text = ""
	dialogLabel.Visible = true

	task.spawn(function()
		for bytePosition in utf8.codes(text) do
			if version ~= dialogVersion or not isOpen then
				return
			end
			dialogLabel.Text = string.sub(text, 1, bytePosition)
			task.wait(typingDelay or 0.018)
		end

		if version ~= dialogVersion or not isOpen then
			return
		end

		for index, option in ipairs(options) do
			local button = Instance.new("TextButton")
			button.Name = "Choice" .. index
			button.LayoutOrder = index
			button.Size = UDim2.new(1, 0, 0, 40)
			button.BackgroundColor3 = Color3.fromRGB(31, 48, 70)
			button.BackgroundTransparency = 0.12
			button.BorderSizePixel = 0
			button.Font = Enum.Font.GothamMedium
			button.Text = tostring(index) .. ".)  " .. option.text
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
			button.TextSize = 16
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.Parent = choicesFrame

			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 14)
			padding.Parent = button

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = button

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(130, 165, 205)
			stroke.Transparency = 0.65
			stroke.Thickness = 1
			stroke.Parent = button

			table.insert(choiceConnections, button.Activated:Connect(function()
				if not isOpen or version ~= dialogVersion then
					return
				end
				if option.action == "acceptQuest" then
					local ok, result = pcall(function() return questAction:InvokeServer("accept") end)
					if not ok or not result or not result.ok then
						showDialog((result and result.reason) or "Nie udało się przyjąć zadania. Spróbuj ponownie.", {{text = "Zamknij"}})
						return
					end
				end
				if option.next then
					showDialog(option.next.text, option.next.choices, option.next.delay)
				else
					closeDialog()
				end
			end))
		end

		choicesFrame.Visible = true
	end)
end

local function startDialog()
	if isOpen then
		return
	end
	isOpen = true
	npcGui.AlwaysOnTop = true
	nameLabel.Visible = false
	arrowLabel.Visible = false
	local status = player:GetAttribute("PosterQuestStatus")
	if status == "completed" then
		showDialog("Dobra robota! Wszystkie plakaty wiszą. Zadanie zaliczone.", {{text = "Zamknij"}})
		return
	elseif status == "active" then
		showDialog("Rozwiesiłeś już " .. tostring(player:GetAttribute("PosterQuestCount") or 0) .. "/3 plakatów. Zostały jeszcze przystanki — powodzenia!", {{text = "Zamknij"}})
		return
	end
	showDialog("Dzień dobry! W czym mogę pomóc?", {
		{
			text = "Dzień dobry.",
			next = {
				text = "Dobrze, że jesteś. Poszukujemy niebezpiecznego przestępcy: Dzordza Automatowicza.\nTrzeba rozwiesić plakaty z jego podobizną. Pomożesz?",
				delay = 0.045,
				choices = {
					{
						text = "Wchodzę w to.",
						action = "acceptQuest",
						next = {
							text = "Super! Rozwieś plakaty na trzech przystankach. Podejdź do białej ścianki i wybierz „Rozwieś plakat”.",
							choices = {{ text = "Zamknij" }},
						},
					},
					{
						text = "Nie wchodzę w to.",
						next = {
							text = "Rozumiem. Jeśli zmienisz zdanie, wróć do mnie.",
							choices = {{ text = "Zamknij" }},
						},
					},
				},
			},
		},
		{
			text = "Nie chce mi się z tobą gadać, Szkieł.",
			next = {
				text = "Uważaj na słowa, młody człowieku!",
				choices = {{ text = "Zamknij" }},
			},
		},
		{
			text = "Nie mam czasu.",
			next = {
				text = "W porządku. Wróć tu przy okazji.",
				choices = {{ text = "Zamknij" }},
			},
		},
	})
end

table.insert(connections, prompt.Triggered:Connect(startDialog))

script.Destroying:Connect(function()
	for _, connection in connections do
		connection:Disconnect()
	end
	for _, connection in choiceConnections do
		connection:Disconnect()
	end
	table.clear(choiceConnections)
	screenGui:Destroy()
	dialogLabel.Visible = false
	nameLabel.Visible = true
	arrowLabel.Visible = true
	npcGui.AlwaysOnTop = false
end)
