-- Contract doubles, not an engine/UI renderer. Actual Instances are tested in Studio.
local base = getfenv()
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { __type = "RBXScriptConnection", Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(callbacks, { connection, callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do if entry[1].Connected then entry[2](...) end end
		end,
	}
end
local enum = setmetatable({}, { __index = function(self, key)
	local category = setmetatable({}, { __index = function(_, name)
		return if name == "High" then { Value = 3000 } else name
	end })
	rawset(self, key, category)
	return category
end })
local function node(path)
	return setmetatable({ _path = path }, { __index = function(_, key)
		if key == "Parent" then return node(string.match(path, "^(.*)/[^/]+$") or "") end
		return node(path .. "/" .. key)
	end })
end
local function instance(name, class)
	local self = { Name = name, class = class or "Folder", children = {}, attributes = {}, ChildAdded = signal(), Parent = true }
	function self:IsA(kind) return self.class == kind end
	function self:FindFirstChild(key) return self.children[key] end
	function self:WaitForChild(key) return assert(self.children[key], "Missing mock child: " .. key) end
	function self:GetChildren()
		local result = {}
		for _, child in self.children do table.insert(result, child) end
		return result
	end
	function self:SetAttribute(key, value) self.attributes[key] = value end
	function self:GetAttribute(key) return self.attributes[key] end
	function self:GetPropertyChangedSignal(key)
		self.signals = self.signals or {}
		self.signals[key] = self.signals[key] or signal()
		return self.signals[key]
	end
	return self
end
local player = instance("Player")
local playerGui = instance("PlayerGui")
local playerScripts = instance("PlayerScripts")
player.children.PlayerGui = playerGui
player.children.PlayerScripts = playerScripts
local starterPlayer = instance("StarterPlayer")
local bindings = {}
local guiService = { GuiNavigationEnabled = false, AutoSelectGuiEnabled = false }
local services = {
	GuiService = guiService,
	Players = { LocalPlayer = player }, StarterPlayer = starterPlayer,
	ContextActionService = {
		BindActionAtPriority = function(_, name, callback) bindings[name] = callback end,
		UnbindAction = function(_, name) bindings[name] = nil end,
	},
	UserInputService = { GetFocusedTextBox = function() return nil end },
}
local cache = {}
local loadModule
loadModule = function(module)
	if type(module) == "table" and rawget(module, "api") then return module.api end
	local path = if type(module) == "string" then module else module._path
	if cache[path] then return cache[path] end
	local closure = assert(loadstring(assert(SOURCES[path]), "@src/" .. path .. ".luau"))
	local env = setmetatable({
		script = node(path), require = loadModule, Enum = enum,
		Color3 = { fromRGB = function(r, g, b) return { R = r/255, G = g/255, B = b/255 } end },
		game = { GetService = function(_, name) return assert(services[name]) end },
		typeof = function(value) return if type(value) == "table" and value.__type then value.__type else type(value) end,
		warn = function() end,
	}, { __index = base })
	setfenv(closure, env)
	local result = closure()
	cache[path] = result
	return result
end
local testCount = 0
local function check(condition, message)
	testCount += 1
	assert(condition, message)
end
