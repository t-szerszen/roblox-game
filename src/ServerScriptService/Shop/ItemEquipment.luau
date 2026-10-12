--!strict
local Players=game:GetService("Players")
local ServerStorage=game:GetService("ServerStorage")
local StarterPack=game:GetService("StarterPack")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.PepperSprayConfig)
local Data=require(script.Parent.Parent.Activity.PlayerDataService)
local Equipment={}
local function template(): Tool
	local versioned=ServerStorage:FindFirstChild("PepperSprayTemplate")
	if versioned and versioned:IsA("Tool") then return versioned end
	for _,container in {ServerStorage,StarterPack} do
		local existing=container:FindFirstChild(Config.ToolName,true)
		if existing and existing:IsA("Tool") then return existing end
	end
	-- Minimal reusable tool when no authored gas model is present. Uses the existing spray controller.
	local tool=Instance.new("Tool");tool.Name=Config.ToolName;tool.CanBeDropped=false
	tool:SetAttribute(Config.ToolAttribute,true)
	local handle=Instance.new("Part");handle.Name="Handle";handle.Size=Vector3.new(0.4,0.8,0.4)
	handle.Color=Color3.fromRGB(26,31,38);handle.CanCollide=false;handle.Massless=true;handle.Parent=tool
	local nozzle=Instance.new("Attachment");nozzle.Name=Config.OriginName;nozzle.Position=Vector3.new(0,0.3,-0.2);nozzle.Parent=handle
	tool.Parent=ServerStorage
	return tool
end
function Equipment.Sync(player: Player)
	local profile=Data.GetProfile(player)
	local equipped=profile~=nil and profile.equippedItems.pepper_spray==true and Data.OwnsProduct(player,"pepper_spray")
	local backpack=player:FindFirstChildOfClass("Backpack")
	local found=false
	for _,container in {player.Character,backpack} do
		if not container then continue end
		for _,item in container:GetChildren() do
			if item:IsA("Tool") and item.Name==Config.ToolName then
				if not equipped or found then item:Destroy() else found=true end
			end
		end
	end
	if equipped and backpack and not found then
		local tool=template():Clone();tool.Name=Config.ToolName;tool.CanBeDropped=false;tool:SetAttribute(Config.ToolAttribute,true);tool.Parent=backpack
	end
end
function Equipment.Bind(player: Player): {RBXScriptConnection}
	local connections: {RBXScriptConnection}={}
	table.insert(connections,player.CharacterAdded:Connect(function()
		task.defer(function() if player.Parent==Players then Equipment.Sync(player) end end)
	end))
	table.insert(connections,player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then Equipment.Sync(player) end
	end))
	table.insert(connections,player:GetAttributeChangedSignal("DataLoaded"):Connect(function() Equipment.Sync(player) end))
	Equipment.Sync(player)
	return connections
end
return Equipment
