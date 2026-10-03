--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PreviewConfig = require(ReplicatedStorage.Shared.Shop.PreviewConfig)
local PreviewModel = require(script.Parent.PreviewModel)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)

local previews = Instance.new("Folder")
previews.Name = PreviewConfig.FolderName
previews.Parent = ReplicatedStorage
local connections: { RBXScriptConnection } = {}
local watched: { [Instance]: Scope.Scope } = {}

local function publish(key: string, source: Instance?)
	local previous = previews:FindFirstChild(key)
	if not source then
		if previous then previous:Destroy() end
		return
	end
	local ok, model = pcall(PreviewModel.Build, source, key)
	if not ok or not model then
		warn("Shop preview unavailable: " .. key)
		return
	end
	if previous then previous:Destroy() end
	model.Parent = previews
end

local function watchFolder(folder: Instance)
	if watched[folder] then return end
	local relevant = false
	for _, source in PreviewConfig.Sources do if folder.Name == source.folder then relevant = true; break end end
	if not relevant then return end
	local scope = Scope.new()
	watched[folder] = scope
	for key, source in PreviewConfig.Sources do
		if folder.Name ~= source.folder then continue end
		publish(key, folder:FindFirstChild(source.name))
		scope:Give(folder.ChildAdded:Connect(function(child)
			if child.Name == source.name then publish(key, child) end
		end))
		scope:Give(folder.ChildRemoved:Connect(function(child)
			if child.Name == source.name then publish(key, folder:FindFirstChild(source.name)) end
		end))
	end
end

table.insert(connections, ServerStorage.ChildAdded:Connect(watchFolder))
table.insert(connections, ServerStorage.ChildRemoved:Connect(function(folder)
	local scope = watched[folder]
	if scope then scope:Clean(); watched[folder] = nil end
	for key, source in PreviewConfig.Sources do
		if folder.Name == source.folder then publish(key, nil) end
	end
end))
for _, folder in ServerStorage:GetChildren() do watchFolder(folder) end
script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	for _, scope in watched do scope:Clean() end
	table.clear(connections)
	table.clear(watched)
	previews:Destroy()
end)
