--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Gang.TerritoryConfig)
export type State = { ownerGangId: string?, capturingGangId: string?, progress: number, phase: string, advantage: number }
local Capture = {}
function Capture.New(): State return { progress = 0, phase = "idle", advantage = 0 } end
function Capture.Step(state: State, counts: { [string]: number }, delta: number)
	local total, groups, best = 0, 0, 0
	local winner: string? = nil
	for id, count in counts do
		if count > 0 then
			total += count
			groups += 1
			if count > best then best = count; winner = id end
		end
	end
	local advantage = best * 2 - total
	state.advantage = math.max(0, advantage)
	if not winner or advantage <= 0 then
		state.progress = math.max(0, state.progress - Config.DecayPerSecond * delta)
		if state.progress == 0 then state.capturingGangId = nil end
		state.phase = if groups >= 2 then "contested" elseif state.ownerGangId then "captured" else "idle"
		return
	end
	if winner == state.ownerGangId or (state.capturingGangId and state.capturingGangId ~= winner) then
		-- Rival progress must be erased before a different gang can build its own.
		local erase = advantage * delta
		local erased = math.min(state.progress, erase)
		state.progress -= erased
		delta -= erased / advantage
		if state.progress == 0 then state.capturingGangId = nil end
	end
	if winner == state.ownerGangId then state.phase = "captured"; return end
	if state.capturingGangId and state.capturingGangId ~= winner then state.phase = "contested"; return end
	state.capturingGangId = winner
	state.progress = math.min(Config.CaptureSeconds, state.progress + advantage * delta)
	state.phase = "capturing"
	if state.progress >= Config.CaptureSeconds then
		state.ownerGangId = winner
		state.capturingGangId = nil
		state.progress = 0
		state.phase = "captured"
	end
end
function Capture.RemoveGang(state: State, id: string)
	if state.ownerGangId == id then state.ownerGangId = nil end
	if state.capturingGangId == id then state.capturingGangId = nil; state.progress = 0 end
	state.advantage = 0
	state.phase = if state.capturingGangId then "capturing" elseif state.ownerGangId then "captured" else "idle"
end
return Capture
