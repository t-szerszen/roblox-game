--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local RacingConfig = require(ReplicatedStorage.Shared.Phone.RacingConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local remotes = ReplicatedStorage:WaitForChild(RacingConfig.RemoteFolderName)

local respondChallenge = remotes:WaitForChild("RespondChallenge") :: RemoteFunction
local challengePrompt = remotes:WaitForChild("ChallengePrompt") :: RemoteEvent
local raceStarted = remotes:WaitForChild("RaceStarted") :: RemoteEvent
local raceEnded = remotes:WaitForChild("RaceEnded") :: RemoteEvent

-- UI Setup
local gui = Instance.new("ScreenGui")
gui.Name = "RacingGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local promptFrame = Instance.new("Frame")
promptFrame.Size = UDim2.fromOffset(250, 100)
promptFrame.AnchorPoint = Vector2.new(0.5, 0)
promptFrame.Position = UDim2.new(0.5, 0, 0, -150)
promptFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
promptFrame.Visible = false
promptFrame.Parent = gui

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0, 8)
uicorner.Parent = promptFrame

local uistroke = Instance.new("UIStroke")
uistroke.Color = Color3.fromRGB(255, 180, 0)
uistroke.Thickness = 2
uistroke.Parent = promptFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 40)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "Wyzwanie od Gracza!"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextSize = 14
titleLabel.Parent = promptFrame

local acceptBtn = Instance.new("TextButton")
acceptBtn.Size = UDim2.new(0.4, 0, 0, 30)
acceptBtn.Position = UDim2.new(0.06, 0, 0.6, 0)
acceptBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
acceptBtn.Font = Enum.Font.GothamBold
acceptBtn.Text = "Akceptuj"
acceptBtn.TextColor3 = Color3.new(1, 1, 1)
acceptBtn.TextSize = 14
acceptBtn.Parent = promptFrame
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 6)

local declineBtn = Instance.new("TextButton")
declineBtn.Size = UDim2.new(0.4, 0, 0, 30)
declineBtn.Position = UDim2.new(0.54, 0, 0.6, 0)
declineBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
declineBtn.Font = Enum.Font.GothamBold
declineBtn.Text = "Odrzuc"
declineBtn.TextColor3 = Color3.new(1, 1, 1)
declineBtn.TextSize = 14
declineBtn.Parent = promptFrame
Instance.new("UICorner", declineBtn).CornerRadius = UDim.new(0, 6)

local chime = Instance.new("Sound")
chime.SoundId = "rbxassetid://4590657391" -- custom chime sound
chime.Parent = SoundService

local promptActive = false
local currentFinishLine: Part? = nil

local function hidePrompt()
	promptActive = false
	TweenService:Create(promptFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -150)
	}):Play()
	task.delay(0.3, function()
		if not promptActive then
			promptFrame.Visible = false
		end
	end)
end

challengePrompt.OnClientEvent:Connect(function(challenger: Player)
	titleLabel.Text = "Wyzwanie od " .. challenger.DisplayName .. "!"
	promptActive = true
	promptFrame.Visible = true
	chime:Play()
	
	TweenService:Create(promptFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 50)
	}):Play()
end)

acceptBtn.Activated:Connect(function()
	if not promptActive then return end
	hidePrompt()
	respondChallenge:InvokeServer(true)
end)

declineBtn.Activated:Connect(function()
	if not promptActive then return end
	hidePrompt()
	respondChallenge:InvokeServer(false)
end)

raceStarted.OnClientEvent:Connect(function(finishLine: Vector3)
	if currentFinishLine then
		currentFinishLine:Destroy()
	end
	
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(2, 50, 2)
	part.Position = finishLine
	part.Color = Color3.fromRGB(255, 215, 0)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.5
	part.Parent = workspace
	
	local pointLight = Instance.new("PointLight")
	pointLight.Color = part.Color
	pointLight.Range = 20
	pointLight.Parent = part
	
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	
	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment
	-- Optional: attach to player, but simple static column works fine
	beam.Color = ColorSequence.new(part.Color)
	beam.FaceCamera = true
	beam.Width0 = 3
	beam.Width1 = 3
	beam.Parent = part
	
	currentFinishLine = part
	
	-- Toast UI or alert
	titleLabel.Text = "Wyscig rozpoczeety!"
	promptActive = true
	promptFrame.Visible = true
	acceptBtn.Visible = false
	declineBtn.Visible = false
	
	TweenService:Create(promptFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 50)
	}):Play()
	
	task.delay(2, function()
		hidePrompt()
		acceptBtn.Visible = true
		declineBtn.Visible = true
	end)
end)

raceEnded.OnClientEvent:Connect(function(winner: Player?)
	if currentFinishLine then
		currentFinishLine:Destroy()
		currentFinishLine = nil
	end
	
	local msg = "Wyscig przerwany!"
	if winner then
		if winner == player then
			msg = "Wygrales!"
		else
			msg = winner.DisplayName .. " wygrywa!"
		end
	end
	
	titleLabel.Text = msg
	promptActive = true
	promptFrame.Visible = true
	acceptBtn.Visible = false
	declineBtn.Visible = false
	
	TweenService:Create(promptFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 50)
	}):Play()
	
	task.delay(3, function()
		hidePrompt()
		acceptBtn.Visible = true
		declineBtn.Visible = true
	end)
end)
