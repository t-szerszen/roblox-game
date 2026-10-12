--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)

local remotes = ReplicatedStorage:FindFirstChild(ShopConfig.RemoteFolderName)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = ShopConfig.RemoteFolderName
	remotes.Parent = ReplicatedStorage
end

local existingRequest = remotes:FindFirstChild(ShopConfig.RequestFunctionName)
local request: RemoteFunction
if existingRequest and existingRequest:IsA("RemoteFunction") then
	request = existingRequest
else
	request = Instance.new("RemoteFunction")
	request.Name = ShopConfig.RequestFunctionName
	request.Parent = remotes
end

local Shop=require(script.Parent.ShopService)
Shop.Start()
request.OnServerInvoke=function(player: Player,action: unknown,id: unknown,...: unknown)
 if select("#",...)~=0 then return false,"Nieprawidłowe żądanie.",nil,nil end
 return Shop.Handle(player,action,id)
end

script.Destroying:Connect(function() request.OnServerInvoke=nil;Shop.Stop() end)
