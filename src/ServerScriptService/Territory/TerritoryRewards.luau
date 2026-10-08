--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
local GangService = require(script.Parent.Parent.Gang.GangService)
local PlayerDataService = require(script.Parent.Parent.Activity.PlayerDataService)
local Rewards = {}
local remainders: { [string]: number } = {}

function Rewards.Pay(flagCounts: { [string]: number })
	for id in remainders do if not GangService.Exists(id) then remainders[id] = nil end end
	for id, flagCount in flagCounts do
		local recipients: { Player } = {}
		for _, player in GangService.GetOnlineMembers(id) do
			if player:GetAttribute("DataLoaded") == true and player:GetAttribute("DataPersistenceAvailable") == true then table.insert(recipients, player) end
		end
		if #recipients == 0 then continue end
		local pool = flagCount * Config.CoinsPerFlag + (remainders[id] or 0)
		local share = math.floor(pool / #recipients)
		remainders[id] = pool - share * #recipients
		for _, player in recipients do PlayerDataService.AddCurrency(player, share, 0) end
	end
end
function Rewards.Clear() table.clear(remainders) end
return Rewards
