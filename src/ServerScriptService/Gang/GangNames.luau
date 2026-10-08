--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Config = require(ReplicatedStorage.Shared.Gang.GangConfig)
local GangNames = {}

function GangNames.Normalize(name: string): string
	return string.lower((string.gsub(name, "%s+", " ")):match("^%s*(.-)%s*$") or "")
end

function GangNames.Filter(player: Player, requested: unknown): (string?, string)
	if typeof(requested) ~= "string" or #requested > Config.MaxNameLength + 16 then
		return nil, "Nieprawidłowa nazwa gangu."
	end
	local name = (string.gsub(requested, "%s+", " ")):match("^%s*(.-)%s*$") or ""
	if #name < Config.MinNameLength or #name > Config.MaxNameLength or not string.match(name, "^[%w ]+$") then
		return nil, "Nazwa musi mieć 3–20 znaków: litery A–Z, cyfry i spacje."
	end
	local success, filtered = pcall(function(): string
		return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	-- Never publish the original name when filtering fails or censors it.
	if not success then return nil, "Filtrowanie nazwy jest chwilowo niedostępne." end
	if string.find(filtered, "#", 1, true) or GangNames.Normalize(filtered) == "" then
		return nil, "Wybierz inną nazwę gangu."
	end
	return filtered, ""
end

return GangNames
