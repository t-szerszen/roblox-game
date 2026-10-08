-- Extend the existing service doubles; no live Players, DataStore or Marketplace calls.
getfenv().Enum = setmetatable({}, { __index = function(self, category)
	local values = setmetatable({}, { __index = function(_, name) return name end })
	rawset(self, category, values)
	return values
end })
getfenv().Vector2 = { new = function(x, y) return { Magnitude = math.sqrt(x*x + y*y) } end }
getfenv().RaycastParams = { new = function() return {} end }
getfenv().OverlapParams = { new = function() return {} end }
getfenv().UDim2 = { fromScale = function(x, y) return {x, y} end, fromOffset = function(x, y) return {x, y} end }
getfenv().ColorSequence = { new = function(...) return {...} end }
local timers = {}
function taskMock.delay(duration, callback, ...)
	local args = table.pack(...)
	table.insert(timers, { at = testClock + duration, callback = function() callback(table.unpack(args, 1, args.n)) end })
end
local deferred = {}
function taskMock.defer(callback, ...) local args = table.pack(...); table.insert(deferred, function() callback(table.unpack(args, 1, args.n)) end) end
local function flush()
	local pending = deferred; deferred = {}
	for _, callback in pending do callback() end
end
function Color.fromHSV(h, s, v)
	local hue = h * 6
	local c, x = v*s, v*s*(1-math.abs(hue%2-1))
	local sector = math.floor(hue)%6
	local values = { {c,x,0}, {x,c,0}, {0,c,x}, {0,x,c}, {x,0,c}, {c,0,x} }
	local rgb = values[sector+1]; local m = v-c
	return Color.new(rgb[1]+m, rgb[2]+m, rgb[3]+m)
end
function instanceMethods:GetDescendants()
	local result = {}
	for _, child in self:GetChildren() do
		table.insert(result, child)
		for _, descendant in child:GetDescendants() do table.insert(result, descendant) end
	end
	return result
end
function instanceMethods:FindFirstChildOfClass(class)
	for _, child in self:GetChildren() do if child:IsA(class) then return child end end
	return nil
end
function instanceMethods:WaitForChild(name) return assert(self:FindFirstChild(name), "Missing fixture child: " .. name) end
function instanceMethods:IsDescendantOf(parent)
	local current = self.Parent
	while current do if current == parent then return true end; current = current.Parent end
	return false
end
function instanceMethods:GetFullName() return self.Name end
local originalIsA = instanceMethods.IsA
function instanceMethods:IsA(class) return originalIsA(self, class) or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "SpawnLocation")) end
local originalNew = InstanceMock.new
function instanceMethods:Emit(count) self.emitted = count end
function InstanceMock.new(class)
	local instance = originalNew(class)
	instance.Destroying = signal(); instance.AncestryChanged = signal()
	if class == "RemoteEvent" then
		instance.OnServerEvent = signal()
		instance.FireClient = function(self, player) self.published = (self.published or 0) + 1 end
	end
	return instance
end
local originalDestroy = instanceMethods.Destroy
function instanceMethods:Destroy()
	if self.Destroying then self.Destroying:Fire() end
	originalDestroy(self)
end
services.ReplicatedStorage = InstanceMock.new("ReplicatedStorage")
services.ReplicatedStorage.Shared = node("ReplicatedStorage/Shared")
services.Workspace = InstanceMock.new("Workspace")
services.Workspace.DescendantAdded = signal()
function services.Workspace:GetServerTimeNow() return testClock end
function services.Workspace:Raycast() return nil end
function services.Workspace:GetPartBoundsInRadius() return {} end
playersService.MaxPlayers = 30
function playersService:GetPlayerByUserId(id)
	for _, player in players do if player.UserId == id and player.Parent == self then return player end end
	return nil
end
local serial = 0
services.HttpService = { GenerateGUID = function() serial += 1; return "fixture-" .. serial end }
services.RunService = { Heartbeat = signal() }
local tagged = {}
local added, removed = signal(), signal()
services.CollectionService = {
	GetTagged = function(_, tag) return tagged[tag] or {} end,
	GetInstanceAddedSignal = function() return added end,
	GetInstanceRemovedSignal = function() return removed end,
	AddTag = function(_, instance, tag)
		tagged[tag] = tagged[tag] or {}; table.insert(tagged[tag], instance); added:Fire(instance)
	end,
	RemoveTag = function(_, instance, tag)
		local list = tagged[tag] or {}; local index = table.find(list, instance); if index then table.remove(list, index) end
		removed:Fire(instance)
	end,
}
services.Debris = { AddItem = function(_, instance, duration) taskMock.delay(duration, function() instance:Destroy() end) end }
services.TextService = { fail = false, censored = false, hook = nil, calls = 0 }
function services.TextService:FilterStringAsync(name)
	self.calls += 1
	if self.fail then error("Injected filter outage") end
	if self.hook then local callback = self.hook; self.hook = nil; callback() end
	return { GetNonChatStringForBroadcastAsync = function() return if self.censored then "###" else name end }
end
-- Billboard geometry is exercised with native Instances in gang_native.studio.luau.
moduleCache["ServerScriptService/Gang/GangTags"] = { Apply = function(player, name, color) player.tag = {name, color} end }
moduleCache["ServerScriptService/Scooter/ScooterServer"] = { RequestSpawnForPlayer = function() return false, "Fixture" end }
local function character(player, x, z)
	local model = InstanceMock.new("Model"); model.Name = player.Name; model.Parent = services.Workspace
	local humanoid = InstanceMock.new("Humanoid"); humanoid.Health = 100; humanoid.MaxHealth = 100; humanoid.Parent = model
	humanoid.ChangeState = function() end
	humanoid.TakeDamage = function(self, amount) self.Health = math.max(0, self.Health-amount) end
	local root = InstanceMock.new("Part"); root.Name = "HumanoidRootPart"; root.Position = Vector.new(x or 0, 1, z or 0)
	root.CFrame = { LookVector = Vector.new(0, 0, -1) }; root.Parent = model
	local head = InstanceMock.new("Part"); head.Name = "Head"; head.Parent = model
	player.Character = model
	return humanoid, root
end
local function gangPlayer(id)
	local player = makePlayer(id)
	player.DisplayName = "Gracz " .. id
	player.CharacterAdded = signal()
	character(player)
	return player
end
local function advance(seconds)
	testClock += seconds
	for index = #timers, 1, -1 do
		if timers[index].at <= testClock then local item = table.remove(timers, index); item.callback() end
	end
	services.RunService.Heartbeat:Fire(seconds)
	flush()
end
local function disconnectPlayer(player)
	playersService.PlayerRemoving:Fire(player)
	local index = table.find(players, player); if index then table.remove(players, index) end
	player.Parent = nil
	flush()
end
local function reconnectPlayer(id)
	local player = gangPlayer(id)
	playersService.PlayerAdded:Fire(player)
	flush()
	return player
end
