--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Activity.EconomyConfig)
local Persistence = {}

function Persistence.Copy(value: any): any
	if typeof(value) ~= "table" then return value end
	local result = {}
	for key, child in value do result[key] = Persistence.Copy(child) end
	return result
end

function Persistence.Token(): string
	return HttpService:GenerateGUID(false)
end

function Persistence.Acquire(store: GlobalDataStore, key: string, token: string): (boolean, any)
	local failure: any = "SessionLocked"
	for attempt = 1, Config.SaveAttempts do
		local blocked = false
		local ok, value = pcall(function()
			return store:UpdateAsync(key, function(old)
				if old ~= nil and typeof(old) ~= "table" then blocked = true; return nil end
				local session = if old then old._session else nil
				if typeof(session) == "table" and session.token ~= token
					and typeof(session.expires) == "number" and session.expires > os.time() then
					blocked = true; return nil
				end
				local data = Persistence.Copy(old or {})
				data._session = { token = token, expires = os.time() + Config.SessionLeaseSeconds }
				return data
			end)
		end)
		if ok and not blocked and typeof(value) == "table" then return true, value end
		failure = if blocked then "SessionLockedOrInvalidData" else value
		if attempt < Config.SaveAttempts then task.wait(Config.SaveRetrySeconds * attempt) end
	end
	return false, failure
end

function Persistence.Save(store: GlobalDataStore, key: string, token: string, profile: any, release: boolean): (boolean, string)
	local snapshot = Persistence.Copy(profile)
	for attempt = 1, Config.SaveAttempts do
		local lost = false
		local ok = pcall(function()
			store:UpdateAsync(key, function(old)
				local session = if typeof(old) == "table" then old._session else nil
				if typeof(session) ~= "table" or session.token ~= token then lost = true; return nil end
				-- Preserve unrelated fields written by older/newer project modules.
				local data = Persistence.Copy(old)
				for name,value in snapshot do if name~="_session" then data[name]=Persistence.Copy(value) end end
				data._session = if release then nil else { token = token, expires = os.time() + Config.SessionLeaseSeconds }
				return data
			end)
		end)
		if lost then return false, "SessionLost" end
		if ok then return true, "Saved" end
		if attempt < Config.SaveAttempts then task.wait(Config.SaveRetrySeconds * attempt) end
	end
	return false, "SaveFailed"
end

return Persistence
