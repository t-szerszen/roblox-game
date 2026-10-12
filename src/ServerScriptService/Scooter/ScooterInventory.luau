--!strict
local Players = game:GetService("Players")
local Inventory = {}

function Inventory.Lock(humanoid: Humanoid): () -> ()
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then return function() end end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return function() end end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return function() end end
	local active = true
	local states: {[Tool]: boolean} = {}
	local connections: {RBXScriptConnection} = {}
	local function block(item: Instance)
		if not active or not item:IsA("Tool") then return end
		if states[item] == nil then states[item] = item.Enabled end
		item.Enabled = false
		if item.Parent == character then
			humanoid:UnequipTools()
			if item.Parent == character then item.Parent = backpack end
		end
	end
	player:SetAttribute("ScooterInventoryLocked", true)
	table.insert(connections, character.ChildAdded:Connect(block))
	table.insert(connections, backpack.ChildAdded:Connect(block))
	for _, item in backpack:GetChildren() do block(item) end
	for _, item in character:GetChildren() do block(item) end
	return function()
		if not active then return end
		active = false
		for _, connection in connections do connection:Disconnect() end
		for tool, enabled in states do
			if tool.Parent and tool.Enabled == false then tool.Enabled = enabled end
		end
		table.clear(states)
		if player.Parent == Players then player:SetAttribute("ScooterInventoryLocked", nil) end
	end
end

return Inventory
