--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedUI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Config = require(SharedUI:WaitForChild("CoinsHUDConfig"))
local Theme = require(SharedUI:WaitForChild("Theme"))
local UI = require(SharedUI:WaitForChild("Components"))
local Layout = require(SharedUI:WaitForChild("Layout"))
local Scope = require(SharedUI:WaitForChild("Scope"))

local player = Players.LocalPlayer
local scope = Scope.new()
local statsScope = Scope.new()
local coinsScope = Scope.new()

local gui = script.Parent :: ScreenGui
gui.ResetOnSpawn = false
gui.DisplayOrder = Config.DisplayOrder
scope:Give(gui)

local panel = UI.Frame(gui, "Balance")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, Config.Margin, 1, -Config.Margin)
panel.Size = UDim2.fromOffset(Config.Width, Config.Height)
UI.Corner(panel)
UI.Stroke(panel)

local icon = Instance.new("ImageLabel")
icon.Name = "CoinIcon"
icon.BackgroundTransparency = 1
icon.Image = Config.IconImage
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.Position = UDim2.new(0, Config.Padding, 0.5, 0)
icon.Size = UDim2.fromOffset(Config.IconSize, Config.IconSize)
icon.Parent = panel

local textInset = Config.Padding + Config.IconSize + Config.Gap
local amount = UI.Label(panel, "— Coins", Config.TextSize)
amount.Name = "Amount"
amount.Font = Theme.StrongFont
amount.Position = UDim2.fromOffset(textInset, 0)
amount.Size = UDim2.new(1, -textInset - Config.Padding, 1, 0)
amount.TextScaled = true
local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MaxTextSize = Config.TextSize
textConstraint.MinTextSize = 10
textConstraint.Parent = amount

local function bindCoins(stats: Instance?)
	coinsScope:Clean()
	coinsScope = Scope.new()
	amount.Text = "— Coins"
	local coins = if stats then stats:FindFirstChild("Coins") else nil
	if not coins or not coins:IsA("IntValue") then return end
	local function update()
		amount.Text = if player:GetAttribute("DataPersistenceAvailable")==false then "— Coins" else Layout.FormatCoins(coins.Value) .. " Coins"
	end
	coinsScope:Give(coins:GetPropertyChangedSignal("Value"):Connect(update))
	coinsScope:Give(player:GetAttributeChangedSignal("DataPersistenceAvailable"):Connect(update))
	update()
end

local function bindStats()
	statsScope:Clean()
	statsScope = Scope.new()
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		statsScope:Give(stats.ChildAdded:Connect(function(child)
			if child.Name == "Coins" then bindCoins(stats) end
		end))
		statsScope:Give(stats.ChildRemoved:Connect(function(child)
			if child.Name == "Coins" then bindCoins(stats) end
		end))
	end
	-- Profile loading can publish the folder before its Coins value exists.
	bindCoins(stats)
end

scope:Give(function()
	statsScope:Clean()
	coinsScope:Clean()
end)
scope:Give(player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then bindStats() end
end))
scope:Give(player.ChildRemoved:Connect(function(child)
	if child.Name == "leaderstats" then bindStats() end
end))
scope:Give(gui.Destroying:Connect(function() scope:Clean() end))
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
bindStats()
