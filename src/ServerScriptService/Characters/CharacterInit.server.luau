--!strict
local Players = game:GetService("Players")
local Proportions = require(script.Parent.CharacterProportions)
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: RBXScriptConnection } = {}
local function hook(player: Player)
	playerConnections[player] = player.CharacterAppearanceLoaded:Connect(function(character)
		Proportions.Apply(character)
	end)
	local character = player.Character
	if character and player:HasAppearanceLoaded() then Proportions.Apply(character) end
end
for _, player in Players:GetPlayers() do hook(player) end
table.insert(connections, Players.PlayerAdded:Connect(hook))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	local connection = playerConnections[player]
	if connection then connection:Disconnect(); playerConnections[player] = nil end
end))
script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	for _, connection in playerConnections do connection:Disconnect() end
	table.clear(connections)
	table.clear(playerConnections)
end)
