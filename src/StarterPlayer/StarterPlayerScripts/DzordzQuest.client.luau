--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DzordzQuestConfig"))
local player = Players.LocalPlayer
local npc = workspace:WaitForChild(Config.NpcName)
local headGui = npc:WaitForChild("Head"):WaitForChild("gui") :: BillboardGui
local nameLabel = headGui:WaitForChild("name") :: TextLabel
local speech = headGui:WaitForChild("dialog") :: TextLabel
local arrowLabel = headGui:WaitForChild("arrow") :: GuiObject
local prompt = npc:WaitForChild("ProximityPrompt") :: ProximityPrompt
local bag = workspace:WaitForChild(Config.BenchName):WaitForChild(Config.BagName) :: Model
local bagPrompt = bag:FindFirstChild("Pickup", true) :: ProximityPrompt
local action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DzordzQuest"):WaitForChild("Action") :: RemoteFunction
local connections: {RBXScriptConnection} = {}
local choiceConnections: {RBXScriptConnection} = {}
local gui = Instance.new("ScreenGui")
gui.Name = "DzordzQuestUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, name: string, value: string, position: UDim2, size: UDim2): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name item.Text = value item.Position = position item.Size = size
	item.BackgroundTransparency = 1 item.Font = Enum.Font.GothamMedium item.TextSize = 15
	item.TextColor3 = Color3.fromRGB(240, 244, 252) item.TextWrapped = true item.Parent = parent
	return item
end
local function card(name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name frame.Size = size frame.Position = position frame.AnchorPoint = anchor
	frame.BackgroundColor3 = Color3.fromRGB(23, 29, 40) frame.BorderSizePixel = 0 frame.Parent = gui
	local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 12) corner.Parent = frame
	local stroke = Instance.new("UIStroke") stroke.Color = Color3.fromRGB(242, 191, 75) stroke.Transparency = 0.3 stroke.Parent = frame
	return frame
end
local tracker = card("Tracker", UDim2.fromOffset(300, 102), UDim2.new(1, -20, 0, 385), Vector2.new(1, 0))
label(tracker, "Title", "DZORDZ • TORBA Z PIŁKĄ", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 25)).TextColor3 = Color3.fromRGB(255, 206, 95)
local objective = label(tracker, "Objective", "", UDim2.fromOffset(14, 38), UDim2.new(1, -28, 0, 50))
local pickup = card("Pickup", UDim2.fromOffset(350, 145), UDim2.new(0.5, 0, 0.76, 0), Vector2.new(0.5, 0.5))
label(pickup, "Title", "PODNIEŚ TORBĘ", UDim2.fromOffset(15, 8), UDim2.new(1, -30, 0, 25))
local hint = label(pickup, "Hint", "Klikaj szybko E", UDim2.fromOffset(15, 39), UDim2.new(1, -30, 0, 25))
local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(18, 77) track.Size = UDim2.new(1, -36, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(58, 65, 79) track.BorderSizePixel = 0 track.Parent = pickup
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1) fill.BackgroundColor3 = Color3.fromRGB(255, 206, 95) fill.BorderSizePixel = 0 fill.Parent = track
local tapButton = Instance.new("TextButton")
tapButton.Name = "Tap" tapButton.Position = UDim2.fromOffset(18, 98) tapButton.Size = UDim2.new(1, -36, 0, 33)
tapButton.BackgroundColor3 = Color3.fromRGB(49, 61, 78) tapButton.Text = "E / DOTKNIJ   •   Esc — anuluj"
tapButton.TextColor3 = Color3.new(1, 1, 1) tapButton.Font = Enum.Font.GothamBold tapButton.TextSize = 13 tapButton.Parent = pickup
pickup.Visible = false
tracker.Visible = false
local choices = Instance.new("Frame")
choices.Name = "Choices" choices.AnchorPoint = Vector2.new(0.5, 1)
choices.Position = UDim2.fromScale(0.5, 0.91) choices.Size = UDim2.new(0.7, 0, 0, 140)
choices.BackgroundTransparency = 1 choices.Parent = gui
local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(260, 1) constraint.MaxSize = Vector2.new(620, 140) constraint.Parent = choices
local layout = Instance.new("UIListLayout")
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom layout.Padding = UDim.new(0, 7) layout.Parent = choices
local open = false
local version = 0
local busy = false
local lastTap = 0
local pickupVersion = 0
local joints: {[Motor6D]: CFrame} = {}
local tweens: {Tween} = {}
local function restorePose()
	for _, tween in tweens do tween:Cancel() end
	table.clear(tweens)
	for joint, original in joints do if joint.Parent then joint.C0 = original end end
	table.clear(joints)
end
local function pulsePose()
	local character = player.Character
	if not character then return end
	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") and (joint.Name == "RootJoint" or joint.Name == "Waist" or joint.Name == "Right Shoulder" or joint.Name == "RightShoulder") then
			local original = joints[joint] or joint.C0
			joints[joint] = original
			local angle = if joint.Name == "RootJoint" or joint.Name == "Waist" then 12 else 25
			local tween = TweenService:Create(joint, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {C0 = original * CFrame.Angles(math.rad(angle), 0, 0)})
			table.insert(tweens, tween)
			tween:Play()
		end
	end
end
local function clearChoices()
	for _, connection in choiceConnections do connection:Disconnect() end
	table.clear(choiceConnections)
	for _, child in choices:GetChildren() do if child:IsA("TextButton") then child:Destroy() end end
end
local function close()
	version += 1 open = false clearChoices()
	speech.Visible = false nameLabel.Visible = true arrowLabel.Visible = true headGui.AlwaysOnTop = false
end
local function request(operation: string)
	local ok, result = pcall(function() return action:InvokeServer(operation) end)
	return ok and result and result.ok == true
end
local show
show = function(value: string, options: {{text: string, run: (() -> ())?}})
	open = true version += 1
	local current = version
	clearChoices() nameLabel.Visible = false arrowLabel.Visible = false headGui.AlwaysOnTop = true
	speech.Visible = true speech.Text = value speech.MaxVisibleGraphemes = 0
	task.spawn(function()
		local count = 0
		for _ in utf8.graphemes(value) do count += 1 end
		for index = 1, count do
			if version ~= current then return end
			speech.MaxVisibleGraphemes = index task.wait(0.025)
		end
		if version ~= current then return end
		speech.MaxVisibleGraphemes = -1
		for index, option in options do
			local button = Instance.new("TextButton")
			button.Name = "Choice" .. index button.LayoutOrder = index
			button.Size = UDim2.new(1, 0, 0, 40) button.BackgroundColor3 = Color3.fromRGB(31, 48, 70)
			button.TextColor3 = Color3.new(1, 1, 1) button.Font = Enum.Font.GothamMedium button.TextSize = 16
			button.Text = index .. ".)  " .. option.text button.Parent = choices
			local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 6) corner.Parent = button
			table.insert(choiceConnections, button.Activated:Connect(function()
				if version ~= current or busy then return end
				if option.run then option.run() else close() end
			end))
		end
	end)
end
local function update()
	local status = player:GetAttribute("DzordzQuestStatus") or "idle"
	tracker.Visible = status ~= "idle"
	objective.Text = if status == "seeking" or status == "picking" then "Odbierz torbę z ławki.\nŻółty punkt T na minimapie."
		elseif status == "carrying" then "Przywieź torbę do Dzordza.\nŻółty punkt D na minimapie." else "✓ Zaliczone • torba oddana"
	local picking = status == "picking"
	pickup.Visible = picking
	bagPrompt.Enabled = status == "seeking"
	for _, part in bag:GetDescendants() do
		if part:IsA("BasePart") then part.LocalTransparencyModifier = if status == "carrying" or status == "completed" then 1 else 0
		elseif part:IsA("SurfaceGui") then part.Enabled = status ~= "carrying" and status ~= "completed" end
	end
	local taps = player:GetAttribute("DzordzQuestTaps") or 0
	fill.Size = UDim2.fromScale(math.clamp(taps / Config.Taps, 0, 1), 1)
	if not picking then pickupVersion += 1 restorePose() end
end
local function tap()
	if player:GetAttribute("DzordzQuestStatus") ~= "picking" or busy or os.clock() - lastTap < Config.TapCooldown then return end
	lastTap = os.clock()
	pulsePose()
	task.spawn(function() request("tap") end)
end
table.insert(connections, tapButton.Activated:Connect(tap))
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.E then tap()
	elseif input.KeyCode == Enum.KeyCode.Escape and player:GetAttribute("DzordzQuestStatus") == "picking" then
		task.spawn(function() request("cancel") end)
	end
end))
table.insert(connections, bagPrompt.Triggered:Connect(function()
	if busy then return end
	busy = true close()
	local accepted = request("begin")
	busy = false
	if not accepted then return end
	pickupVersion += 1
	local current = pickupVersion
	local started = os.clock()
	task.spawn(function()
		while current == pickupVersion and player:GetAttribute("DzordzQuestStatus") == "picking" do
			local taps = player:GetAttribute("DzordzQuestTaps") or 0
			hint.Text = "Klikaj szybko E • " .. taps .. "/" .. Config.Taps .. " • " .. math.max(0, math.ceil(Config.PickupWindow - (os.clock() - started))) .. " s"
			task.wait(0.1)
		end
	end)
end))
table.insert(connections, prompt.Triggered:Connect(function()
	if open or busy or player:GetAttribute("DzordzQuestStatus") == "picking" then return end
	local status = player:GetAttribute("DzordzQuestStatus") or "idle"
	if status == "carrying" then
		show("Masz moją torbę? Elegancko, zaraz lecę na sztuczną trawę!", {
			{text = "Proszę, torba z piłką.", run = function()
				busy = true local accepted = request("deliver") busy = false
				if accepted then show("Dzięki, uratowałeś mi mecz! Jak kiedyś wpadniesz na boisko, gramy razem.", {{text = "Do zobaczenia!"}})
				else show("Podejdź bliżej, żebym mógł odebrać torbę.", {{text = "Zamknij"}}) end
			end},
			{text = "Jeszcze chwila."},
		})
	elseif status == "completed" then
		show("Dzięki jeszcze raz za torbę. Do zobaczenia na sztucznej trawie!", {{text = "Siema!"}})
	elseif status == "seeking" then
		show("Torba została na ławce. W środku jest piłka. Czekam tutaj, tylko nie zgub jej po drodze!", {{text = "Już jadę."}})
	else
		show("Siema! Idę na sztuczną trawę, ale zostawiłem torbę z piłką na ławce.\nNie pojadę po nią, bo mnie Szkieły Sprinterem zawiną. Przywieziesz?", {
			{text = "Dobra, przywiozę.", run = function()
				busy = true local accepted = request("accept") busy = false
				if accepted then show("Dzięki! Zaznaczyłem ci ławkę na mapie. Złap torbę i wracaj do mnie.", {{text = "Lecę!"}})
				else show("Podejdź bliżej i zagadaj jeszcze raz.", {{text = "Zamknij"}}) end
			end},
			{text = "Nie mam teraz czasu."},
		})
	end
end))
for _, attribute in {"DzordzQuestStatus", "DzordzQuestTaps"} do
	table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(update))
end
table.insert(connections, player.CharacterRemoving:Connect(function() close() restorePose() end))
update()
script.Destroying:Connect(function()
	close() restorePose()
	for _, connection in connections do connection:Disconnect() end
	gui:Destroy()
end)
