--!strict
-- This test double supplies only the Roblox APIs used by the exercised modules.
-- Physics integration, replication, Marketplace networking and DataStore failures
-- still require the Studio checks described in tests/README.md.

local baseEnvironment = getfenv()
local Vector = {}
local vectorMethods = {}
local vectorMetatable = {}
function Vector.new(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z, __type = "Vector3" }, vectorMetatable)
end
function vectorMethods:Dot(other)
	return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end
function vectorMethods:Cross(other)
	return Vector.new(self.Y * other.Z - self.Z * other.Y,
		self.Z * other.X - self.X * other.Z, self.X * other.Y - self.Y * other.X)
end
vectorMetatable.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self:Dot(self)) end
	if key == "Unit" then return self / self.Magnitude end
	return vectorMethods[key]
end
vectorMetatable.__add = function(a, b) return Vector.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMetatable.__sub = function(a, b) return Vector.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMetatable.__unm = function(a) return Vector.new(-a.X, -a.Y, -a.Z) end
vectorMetatable.__mul = function(a, b)
	if type(a) == "number" then return Vector.new(a * b.X, a * b.Y, a * b.Z) end
	return Vector.new(a.X * b, a.Y * b, a.Z * b)
end
vectorMetatable.__div = function(a, b) return Vector.new(a.X / b, a.Y / b, a.Z / b) end
Vector.zero = Vector.new(0, 0, 0)
Vector.yAxis = Vector.new(0, 1, 0)
Vector.xAxis = Vector.new(1, 0, 0)
Vector.zAxis = Vector.new(0, 0, 1)

local Frame = {}
local frameMethods = {}
local frameMetatable = { __index = frameMethods }
local function quaternion(x, y, z, w)
	return setmetatable({ x = x, y = y, z = z, w = w, __type = "CFrame" }, frameMetatable)
end
function Frame.fromAxisAngle(axis, angle)
	local sine = math.sin(angle / 2)
	return quaternion(axis.X * sine, axis.Y * sine, axis.Z * sine, math.cos(angle / 2))
end
frameMetatable.__index = function(self, key)
	return if key == "Rotation" then self else frameMethods[key]
end
frameMetatable.__mul = function(a, b)
	return quaternion(
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
	)
end
function frameMethods:Inverse() return quaternion(-self.x, -self.y, -self.z, self.w) end
function frameMethods:ToAxisAngle()
	local sine = math.sqrt(math.max(0, 1 - self.w * self.w))
	local axis = if sine < 0.000001 then Vector.xAxis else Vector.new(self.x, self.y, self.z) / sine
	return axis, 2 * math.acos(math.clamp(self.w, -1, 1))
end
function frameMethods:VectorToWorldSpace(value)
	local axis, angle = self:ToAxisAngle()
	return value * math.cos(angle) + axis:Cross(value) * math.sin(angle)
		+ axis * axis:Dot(value) * (1 - math.cos(angle))
end
Frame.identity = Frame.fromAxisAngle(Vector.yAxis, 0)

local Color = {}
function Color.new(r, g, b) return { R = r, G = g, B = b, __type = "Color3" } end
function Color.fromRGB(r, g, b) return Color.new(r / 255, g / 255, b / 255) end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(callbacks, { connection = connection, callback = callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, item in callbacks do
				if item.connection.Connected then item.callback(...) end
			end
		end,
	}
end

local instanceMethods = {}
local InstanceMock = {}
function InstanceMock.new(className)
	local values = { ClassName = className, Name = className, Value = 0, Changed = signal() }
	local children, attributes = {}, {}
	return setmetatable({ _values = values, _children = children, _attributes = attributes, _attributeSignals = {} }, {
		__index = function(_, key) return instanceMethods[key] or values[key] or children[key] end,
		__newindex = function(self, key, value)
			local old = values[key]
			if key == "Parent" then
				if old and old._children[values.Name] == self then old._children[values.Name] = nil end
				if value then value._children[values.Name] = self end
			end
			values[key] = value
			if key == "Value" and old ~= value then values.Changed:Fire(value) end
		end,
	})
end
function instanceMethods:IsA(className) return self.ClassName == className or className == "Instance" end
function instanceMethods:FindFirstChild(name) return self._children[name] end
function instanceMethods:SetAttribute(name, value)
	local changed = self._attributes[name] ~= value
	self._attributes[name] = value
	if changed and self._attributeSignals[name] then self._attributeSignals[name]:Fire() end
end
function instanceMethods:GetAttribute(name) return self._attributes[name] end
function instanceMethods:GetAttributeChangedSignal(name)
	if not self._attributeSignals[name] then self._attributeSignals[name] = signal() end
	return self._attributeSignals[name]
end
function instanceMethods:GetChildren()
	local children = {}
	for _, child in self._children do table.insert(children, child) end
	return children
end
function instanceMethods:Destroy() self.Parent = nil end

local function node(path)
	return setmetatable({ _path = path }, { __index = function(_, key)
		if key == "Parent" then return node(string.match(path, "^(.*)/[^/]+$") or "") end
		return node(path .. "/" .. key)
	end })
end

local savedProfiles = {}
local writes = {}
local players = {}
local playersService = InstanceMock.new("Players")
playersService.PlayerAdded = signal()
playersService.PlayerRemoving = signal()
function playersService:GetPlayers() return players end
local marketplaceService = {
	PromptGamePassPurchaseFinished = signal(),
	ownership = {},
	ownershipCalls = 0,
	failRequests = false,
}
function marketplaceService:UserOwnsGamePassAsync(userId, passId)
	self.ownershipCalls += 1
	if self.failRequests then error("mock marketplace unavailable") end
	return self.ownership[tostring(userId) .. ":" .. tostring(passId)] == true
end
local dataStoreService = {}
dataStoreService.failLoads = {}
function dataStoreService:GetDataStore(_)
	return {
		GetAsync = function(_, id)
			if dataStoreService.failLoads[id] then error("mock DataStore unavailable") end
			return savedProfiles[id]
		end,
		SetAsync = function(_, id, value) writes[id] = value end,
	}
end
local services = {
	ReplicatedStorage = node("ReplicatedStorage"),
	ServerScriptService = node("ServerScriptService"),
	DataStoreService = dataStoreService,
	Players = playersService,
	MarketplaceService = marketplaceService,
}
local gameMock = {}
function gameMock:GetService(name)
	assert(services[name], "Unsupported mocked service: " .. name)
	return services[name]
end
function gameMock:BindToClose(callback) self.close = callback end
local taskMock = {}
function taskMock.spawn(callback, ...)
	local thread = coroutine.create(callback)
	local ok, result = coroutine.resume(thread, ...)
	assert(ok, result)
	return thread
end
taskMock.defer = taskMock.spawn
function taskMock.wait(_) return coroutine.yield() end
function taskMock.delay(_, callback, ...) return taskMock.spawn(callback, ...) end

local moduleCache = {}
local testClock = 1000
local mockOs = table.clone(os)
mockOs.clock = function() return testClock end
local loadModule
loadModule = function(module)
	local path = if type(module) == "string" then module else module._path
	if moduleCache[path] then return moduleCache[path] end
	local source = assert(SOURCES[path], "Missing module: " .. path)
	local closure, problem = loadstring(source, "@src/" .. path .. ".luau")
	assert(closure, problem)
	local environment = setmetatable({
		script = node(path), require = loadModule, game = gameMock, task = taskMock, os = mockOs,
		Vector3 = Vector, CFrame = Frame, Color3 = Color, Instance = InstanceMock,
		NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end },
		typeof = function(value)
			return if type(value) == "table" and value.__type then value.__type else type(value)
		end,
		warn = function(...) print("WARN", ...) end,
	}, { __index = baseEnvironment })
	setfenv(closure, environment)
	local result = closure()
	moduleCache[path] = result
	return result
end

local function makePlayer(userId, saved)
	local player = InstanceMock.new("Player")
	player.Name = "Test" .. userId
	player.UserId = userId
	player.Parent = playersService
	savedProfiles[tostring(userId)] = saved
	table.insert(players, player)
	return player
end

local testCount = 0
local function check(condition, message)
	testCount += 1
	assert(condition, message)
end
local function near(actual, expected, message)
	check(math.abs(actual - expected) < 0.00001, message .. ": got " .. tostring(actual)
		.. ", expected " .. tostring(expected))
end
