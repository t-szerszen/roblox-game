--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local GangService = require(script.Parent.Parent.Gang.GangService)

type Connections = { RBXScriptConnection }

local CombatService = {}
local started = false
local connections: Connections = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local lastRemoteAt: { [Player]: number } = {}
local lastMeleeAt: { [Player]: number } = {}
local lastPepperAt: { [Player]: number } = {}
local lastPassiveAt: { [Player]: number } = {}
local ramCooldowns: { [string]: number } = {}
local stunTokens: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local stunExpiresAt: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local actionRemote: RemoteEvent
local cachedSafeZoneCenter: Vector3? = nil
local safeZoneResolved = false
local lastRamCleanupAt = 0

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getCharacterState(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return character, nil, nil
	end
	return character, humanoid, root
end

local function safeZoneCenter(): Vector3?
	if safeZoneResolved then
		return cachedSafeZoneCenter
	end
	safeZoneResolved = true
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			cachedSafeZoneCenter = descendant.Position
			break
		end
	end
	return cachedSafeZoneCenter
end

local function isInSafeZone(position: Vector3): boolean
	local center = safeZoneCenter()
	if not center then
		return false
	end
	local offset = position - center
	return Vector2.new(offset.X, offset.Z).Magnitude <= CombatConfig.SafeZoneRadius
end

local function hasSpawnProtection(player: Player): boolean
	local expiresAt = player:GetAttribute("InvulnerableUntil")
	return typeof(expiresAt) == "number" and expiresAt > Workspace:GetServerTimeNow()
end

local function isStunned(player: Player): boolean
	local expiresAt = player:GetAttribute("StunnedUntil")
	return typeof(expiresAt) == "number" and expiresAt > Workspace:GetServerTimeNow()
end

function CombatService.GetTerritoryPosition(player: Player): Vector3?
	if player.Parent ~= Players or player:GetAttribute("PassiveMode") == true then return nil end
	local _, _, root = getCharacterState(player)
	-- A living stunned rider still occupies the territory, including after a fall.
	return if root then root.Position else nil
end

function CombatService.SetPassive(player: Player, enabled: boolean): (boolean, string)
	local _, humanoid = getCharacterState(player)
	if player.Parent ~= Players or not humanoid then return false, "Poczekaj na odrodzenie postaci." end
	local timestamp = Workspace:GetServerTimeNow()
	if timestamp - (lastPassiveAt[player] or -math.huge) < CombatConfig.ProtectionToggleCooldown then
		return false, "Odczekaj chwilę przed zmianą ochrony."
	end
	local combatUntil = player:GetAttribute("CombatUntil")
	if enabled and typeof(combatUntil) == "number" and combatUntil > timestamp then
		return false, "Ochronę możesz włączyć 5 sekund po zakończeniu walki."
	end
	lastPassiveAt[player] = timestamp
	player:SetAttribute("PassiveMode", enabled)
	return true, if enabled then "Ochrona włączona: nie walczysz ani nie przejmujesz flag." else "Ochrona wyłączona."
end

local function markCombat(attacker: Player, target: Player)
	local deadline = Workspace:GetServerTimeNow() + CombatConfig.ProtectionCombatLock
	attacker:SetAttribute("CombatUntil", deadline)
	target:SetAttribute("CombatUntil", deadline)
end

function CombatService.CanDamage(attacker: Player, target: Player): boolean
	local _, _, attackerRoot = getCharacterState(attacker)
	local _, _, targetRoot = getCharacterState(target)
	if not attackerRoot or not targetRoot then
		return false
	end
	if hasSpawnProtection(target) then
		return false
	end
	if isInSafeZone(attackerRoot.Position) or isInSafeZone(targetRoot.Position) then
		return false
	end
	if attacker:GetAttribute("PassiveMode") == true or target:GetAttribute("PassiveMode") == true then
		return false
	end
	return GangService.CanDamage(attacker, target)
end

local function hasLineOfSight(attackerCharacter: Model, targetCharacter: Model, origin: Vector3, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	local result = Workspace:Raycast(origin, target - origin, params)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

local function findTarget(attacker: Player, range: number, facingDot: number): Player?
	local character, _, root = getCharacterState(attacker)
	if not character or not root then
		return nil
	end
	local bestTarget: Player? = nil
	local bestDistance = range + 1
	for _, target in Players:GetPlayers() do
		if target == attacker or not CombatService.CanDamage(attacker, target) then
			continue
		end
		local targetCharacter, _, targetRoot = getCharacterState(target)
		if not targetCharacter or not targetRoot then
			continue
		end
		local offset = targetRoot.Position - root.Position
		local distance = offset.Magnitude
		if distance <= range and distance < bestDistance then
			local direction = if distance > 0.01 then offset.Unit else root.CFrame.LookVector
			if root.CFrame.LookVector:Dot(direction) >= facingDot
				and hasLineOfSight(character, targetCharacter, root.Position + Vector3.new(0, 1.5, 0), targetRoot.Position)
			then
				bestTarget = target
				bestDistance = distance
			end
		end
	end
	return bestTarget
end

function CombatService.StunPlayer(player: Player, duration: number)
	local character, humanoid, _root = getCharacterState(player)
	if not character or not humanoid then
		return
	end
	local token = (stunTokens[humanoid] or 0) + 1
	local now = Workspace:GetServerTimeNow()
	local expiresAt = math.max(stunExpiresAt[humanoid] or 0, now + duration)
	stunTokens[humanoid] = token
	stunExpiresAt[humanoid] = expiresAt
	humanoid.Sit = false
	local seatWeld = character:FindFirstChild("SeatWeld", true)
	if seatWeld then
		seatWeld:Destroy()
	end
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	player:SetAttribute("StunnedUntil", expiresAt)

	task.delay(expiresAt - now, function()
		if stunTokens[humanoid] ~= token then
			return
		end
		stunTokens[humanoid] = nil
		stunExpiresAt[humanoid] = nil
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if player.Parent == Players and player.Character == character then
			player:SetAttribute("StunnedUntil", nil)
		end
	end)
end

local function applyDamage(attacker: Player, target: Player, amount: number): boolean
	if amount <= 0 or not CombatService.CanDamage(attacker, target) then
		return false
	end
	local _, humanoid = getCharacterState(target)
	if not humanoid then
		return false
	end
	humanoid:TakeDamage(amount)
	markCombat(attacker, target)
	return true
end

function CombatService.DamagePlayer(attacker: Player, target: Player, amount: number): boolean
	if amount ~= amount or amount <= 0 or amount > CombatConfig.MaxHealth then
		return false
	end
	return applyDamage(attacker, target, amount)
end

local function emitPepperSpray(attacker: Player)
	local character, _, root = getCharacterState(attacker)
	if not character or not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PepperSprayEffect"
	attachment.Position = Vector3.new(0, 1, -1)
	attachment.Parent = root
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(239, 178, 54), Color3.fromRGB(210, 75, 43))
	particles.Lifetime = NumberRange.new(0.25, 0.45)
	particles.Speed = NumberRange.new(18, 24)
	particles.SpreadAngle = Vector2.new(10, 10)
	particles.Drag = 4
	particles.Rate = 0
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Parent = attachment
	particles:Emit(22)
	Debris:AddItem(attachment, 1)
end

local function handleMelee(player: Player)
	if isStunned(player) then
		return
	end
	local now = os.clock()
	if now - (lastMeleeAt[player] or 0) < CombatConfig.MeleeCooldown then
		return
	end
	lastMeleeAt[player] = now
	local target = findTarget(player, CombatConfig.MeleeRange, CombatConfig.MeleeFacingDot)
	if target then
		applyDamage(player, target, CombatConfig.MeleeDamage)
	end
end

local function handlePepper(player: Player)
	if isStunned(player) or player:GetAttribute(CombatConfig.PepperOwnershipAttribute) ~= true then
		return
	end
	local now = os.clock()
	if now - (lastPepperAt[player] or 0) < CombatConfig.PepperCooldown then
		return
	end
	lastPepperAt[player] = now
	emitPepperSpray(player)
	local target = findTarget(player, CombatConfig.PepperRange, CombatConfig.PepperFacingDot)
	if target then
		markCombat(player, target)
		CombatService.StunPlayer(target, CombatConfig.PepperStunDuration)
	end
end

local function playerFromCharacterPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function ramKey(attacker: Player, target: Player): string
	return string.format("%d:%d", attacker.UserId, target.UserId)
end

local function checkScooterRams()
	local scooterFolder = Workspace:FindFirstChild(ScooterConfig.ScooterFolderName)
	if not scooterFolder then
		return
	end
	local now = os.clock()
	if now - lastRamCleanupAt >= 30 then
		lastRamCleanupAt = now
		for key, timestamp in ramCooldowns do
			if now - timestamp >= CombatConfig.RamPairCooldown then
				ramCooldowns[key] = nil
			end
		end
	end
	for _, scooter in scooterFolder:GetChildren() do
		if not scooter:IsA("Model") then
			continue
		end
		local root = scooter.PrimaryPart
		local ownerUserId = scooter:GetAttribute("OwnerUserId")
		if not root or typeof(ownerUserId) ~= "number" or root.AssemblyLinearVelocity.Magnitude < CombatConfig.RamMinimumSpeed then
			continue
		end
		local attacker = Players:GetPlayerByUserId(ownerUserId)
		local seat = scooter:FindFirstChild("DriverSeat", true)
		if not attacker or not seat or not seat:IsA("VehicleSeat") or not seat.Occupant or seat.Occupant.Parent ~= attacker.Character then
			continue
		end

		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { scooter, attacker.Character :: Model }
		local seen: { [Player]: boolean } = {}
		for _, part in Workspace:GetPartBoundsInRadius(root.Position, CombatConfig.RamHitRadius, overlap) do
			local target = playerFromCharacterPart(part)
			if not target or seen[target] then
				continue
			end
			seen[target] = true
			local key = ramKey(attacker, target)
			if now - (ramCooldowns[key] or 0) < CombatConfig.RamPairCooldown then
				continue
			end
			if applyDamage(attacker, target, CombatConfig.RamDamage) then
				ramCooldowns[key] = now
				CombatService.StunPlayer(attacker, CombatConfig.RamStunDuration)
				CombatService.StunPlayer(target, CombatConfig.RamStunDuration)
				root.AssemblyLinearVelocity *= 0.25
				break
			end
		end
	end
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Parent ~= Players or player.Character ~= character then
		return
	end
	humanoid.MaxHealth = CombatConfig.MaxHealth
	humanoid.Health = CombatConfig.MaxHealth
	player:SetAttribute("StunnedUntil", nil)
	player:SetAttribute("CombatUntil", nil)
	local protectionEnds = Workspace:GetServerTimeNow() + CombatConfig.SpawnProtectionDuration
	player:SetAttribute("InvulnerableUntil", protectionEnds)
	local forceField = Instance.new("ForceField")
	forceField.Name = "SpawnProtection"
	forceField.Visible = false
	forceField.Parent = character
	Debris:AddItem(forceField, CombatConfig.SpawnProtectionDuration)
end

local function hookPlayer(player: Player)
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.defer(setupCharacter, player, player.Character)
	end
end

function CombatService.Start()
	if started then
		return
	end
	started = true
	GangService.Start()
	local remotes = getOrCreateFolder(ReplicatedStorage, CombatConfig.RemoteFolderName)
	actionRemote = getOrCreateRemote(remotes, CombatConfig.ActionRemoteName)

	table.insert(connections, actionRemote.OnServerEvent:Connect(function(player: Player, action: unknown)
		if typeof(action) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (lastRemoteAt[player] or 0) < CombatConfig.RemoteRateLimit then
			return
		end
		lastRemoteAt[player] = now
		if action == "Melee" then
			handleMelee(player)
		elseif action == "Pepper" then
			handlePepper(player)
		end
	end))

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(hookPlayer))
	table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			cachedSafeZoneCenter = descendant.Position
			safeZoneResolved = true
		end
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
		lastRemoteAt[player] = nil
		lastMeleeAt[player] = nil
		lastPepperAt[player] = nil
		lastPassiveAt[player] = nil
	end))

	local accumulated = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated >= CombatConfig.RamCheckInterval then
			accumulated = 0
			checkScooterRams()
		end
	end))
end

return CombatService
