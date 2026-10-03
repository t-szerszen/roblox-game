--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RacingConfig = require(ReplicatedStorage.Shared.Phone.RacingConfig)
local PlayerDataService = require(game:GetService("ServerScriptService").Activity.PlayerDataService)

local remotes = ReplicatedStorage:FindFirstChild(RacingConfig.RemoteFolderName)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = RacingConfig.RemoteFolderName
	remotes.Parent = ReplicatedStorage
end

local function getRemote(name: string, className: string): Instance
	local existing = remotes:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local newRemote = Instance.new(className)
	newRemote.Name = name
	newRemote.Parent = remotes
	return newRemote
end

local requestChallenge = getRemote("RequestChallenge", "RemoteFunction") :: RemoteFunction
local respondChallenge = getRemote("RespondChallenge", "RemoteFunction") :: RemoteFunction
local challengePrompt = getRemote("ChallengePrompt", "RemoteEvent") :: RemoteEvent
local raceStarted = getRemote("RaceStarted", "RemoteEvent") :: RemoteEvent
local raceEnded = getRemote("RaceEnded", "RemoteEvent") :: RemoteEvent
local honkEvent = getRemote("Honk", "RemoteEvent") :: RemoteEvent

type Challenge = {
	challenger: Player,
	challenged: Player,
	expiresAt: number,
}

type Race = {
	player1: Player,
	player2: Player,
	finishLine: Vector3,
}

local challenges: { [Player]: Challenge } = {}
local activeRaces: { [Player]: Race } = {}
local cooldowns: { [Player]: { [Player]: number } } = {}

local function applyCooldown(challenger: Player, challenged: Player)
	if not cooldowns[challenger] then
		cooldowns[challenger] = {}
	end
	cooldowns[challenger][challenged] = os.clock() + RacingConfig.ChallengeCooldown
end

local function checkTimeouts()
	local now = os.clock()
	for challenged, challenge in challenges do
		if now >= challenge.expiresAt then
			applyCooldown(challenge.challenger, challenged)
			challenges[challenged] = nil
		end
	end
end

RunService.Heartbeat:Connect(function()
	checkTimeouts()
	
	local processedRaces = {}
	for player, race in activeRaces do
		if processedRaces[race] then continue end
		processedRaces[race] = true
		
		local p1 = race.player1
		local p2 = race.player2
		
		if not p1.Parent or not p2.Parent then
			activeRaces[p1] = nil
			activeRaces[p2] = nil
			raceEnded:FireClient(p1, nil)
			raceEnded:FireClient(p2, nil)
			continue
		end
		
		local c1 = p1.Character
		local c2 = p2.Character
		
		local r1 = c1 and c1.PrimaryPart
		local r2 = c2 and c2.PrimaryPart
		
		local winner: Player? = nil
		
		if r1 then
			local dist1 = (Vector3.new(r1.Position.X, 0, r1.Position.Z) - Vector3.new(race.finishLine.X, 0, race.finishLine.Z)).Magnitude
			if dist1 <= 20 then
				winner = p1
			end
		end
		
		if not winner and r2 then
			local dist2 = (Vector3.new(r2.Position.X, 0, r2.Position.Z) - Vector3.new(race.finishLine.X, 0, race.finishLine.Z)).Magnitude
			if dist2 <= 20 then
				winner = p2
			end
		end
		
		if winner then
			activeRaces[p1] = nil
			activeRaces[p2] = nil
			
			PlayerDataService.AddCurrency(winner, RacingConfig.RaceRewardCoins, RacingConfig.RaceRewardXP)
			PlayerDataService.Increment(winner, "raceWins", 1)
			PlayerDataService.IncrementDaily(winner, "DailyRaceWins", 1)
			
			raceEnded:FireClient(p1, winner)
			raceEnded:FireClient(p2, winner)
		end
	end
end)

requestChallenge.OnServerInvoke = function(challenger: Player)
	if activeRaces[challenger] then
		return false, "Juz sie scigasz."
	end
	
	local c1 = challenger.Character
	local r1 = c1 and c1.PrimaryPart
	if not r1 then return false, "Brak postaci." end
	
	local nearest: Player? = nil
	local minDist = RacingConfig.ChallengeDistance
	
	for _, p in Players:GetPlayers() do
		if p == challenger then continue end
		if activeRaces[p] then continue end
		
		local c2 = p.Character
		local r2 = c2 and c2.PrimaryPart
		if r2 then
			local dist = (r1.Position - r2.Position).Magnitude
			if dist < minDist then
				nearest = p
				minDist = dist
			end
		end
	end
	
	if not nearest then
		return false, "Brak graczy w poblizu."
	end
	
	if cooldowns[challenger] and cooldowns[challenger][nearest] and cooldowns[challenger][nearest] > os.clock() then
		return false, "Gracz niedawno odrzucil twoje wyzwanie."
	end
	
	if challenges[nearest] then
		return false, "Gracz ma juz wyzwanie."
	end
	
	challenges[nearest] = {
		challenger = challenger,
		challenged = nearest,
		expiresAt = os.clock() + RacingConfig.ChallengeTimeout,
	}
	
	challengePrompt:FireClient(nearest, challenger)
	return true, "Wyzwanie wyslane!"
end

respondChallenge.OnServerInvoke = function(challenged: Player, accept: boolean)
	local challenge = challenges[challenged]
	if not challenge then
		return false, "Brak aktywnego wyzwania."
	end
	
	challenges[challenged] = nil
	
	if not accept then
		applyCooldown(challenge.challenger, challenged)
		return true, "Odrzucono."
	end
	
	local c2 = challenged.Character
	local r2 = c2 and c2.PrimaryPart
	if not r2 then return false, "Blad postaci." end
	
	local angle = math.random() * math.pi * 2
	local dist = math.random(RacingConfig.MinFinishDistance, RacingConfig.MaxFinishDistance)
	
	local finishLine = r2.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	
	local race: Race = {
		player1 = challenge.challenger,
		player2 = challenged,
		finishLine = finishLine,
	}
	
	activeRaces[challenge.challenger] = race
	activeRaces[challenged] = race
	
	raceStarted:FireClient(challenge.challenger, finishLine)
	raceStarted:FireClient(challenged, finishLine)
	
	return true, "Zaakceptowano wyzwanie!"
end

honkEvent.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Play horn sound on character
	local sound = hrp:FindFirstChild("ScooterHorn")
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "ScooterHorn"
		sound.SoundId = "rbxassetid://6022539343" -- generic honk sound
		sound.Volume = 0.5
		sound.MaxDistance = 100
		sound.Parent = hrp
	end
	sound:Play()
end)

Players.PlayerRemoving:Connect(function(player: Player)
	challenges[player] = nil
	cooldowns[player] = nil
	activeRaces[player] = nil
	
	for challenged, challenge in challenges do
		if challenge.challenger == player then
			challenges[challenged] = nil
		end
	end
	
	for p, cd in cooldowns do
		cd[player] = nil
	end
end)
