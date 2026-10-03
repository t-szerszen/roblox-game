--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
-- Only legacy PlayerModule exposes GetControls. Modern IAS uses InputContexts;
-- requiring its internal ControlModule can create a separate singleton/VM copy.
local loadRuntimeModule: (ModuleScript) -> any = require :: any
local count = 0
local releaseNativeControls: (() -> ())? = nil
local ModalInput = {}

local function lockNativeControls(): () -> ()
	local scripts = player:FindFirstChild("PlayerScripts")
	local legacy = if scripts then scripts:FindFirstChild("PlayerModule") else nil
	if legacy and legacy:IsA("ModuleScript") then
		local controls = loadRuntimeModule(legacy):GetControls()
		local wasEnabled = controls.controlsEnabled ~= false
		controls:Disable()
		return function() if wasEnabled then controls:Enable() end end
	end
	local modern = StarterPlayer:FindFirstChild("PlayerModule")
	local contexts = if modern then modern:FindFirstChild("InputContexts") else nil
	assert(contexts, "Roblox character controls are not ready")
	local saved: { [InputContext]: boolean } = {}
	local connections: { RBXScriptConnection } = {}
	local function lockContext(instance: Instance)
		if not instance:IsA("InputContext") or (instance.Name ~= "CharacterContext" and instance.Name ~= "VehicleContext")
			or saved[instance] ~= nil then return end
		saved[instance] = instance.Enabled
		instance.Enabled = false
		table.insert(connections, instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			-- Respawning/changing controller may re-enable the native context.
			if count > 0 and instance.Enabled then instance.Enabled = false end
		end))
	end
	local function watchFolder(folder: Instance)
		for _, context in folder:GetChildren() do lockContext(context) end
		table.insert(connections, folder.ChildAdded:Connect(lockContext))
	end
	watchFolder(contexts :: Instance)
	local replicatedInputs = player:FindFirstChild("InputContexts")
	if replicatedInputs then watchFolder(replicatedInputs) end
	table.insert(connections, player.ChildAdded:Connect(function(child)
		if child.Name == "InputContexts" then watchFolder(child) end
	end))
	return function()
		for _, connection in connections do connection:Disconnect() end
		for context, enabled in saved do if context.Parent then context.Enabled = enabled end end
		table.clear(connections)
		table.clear(saved)
	end
end

function ModalInput.Acquire(): () -> ()
	if count == 0 then releaseNativeControls = lockNativeControls() end
	count += 1
	if count == 1 then
		playerGui:SetAttribute("GameplayInputBlocked", true)
		-- ButtonA and thumbsticks remain available to Roblox GUI navigation.
		ContextActionService:BindActionAtPriority("UIModalKeyboard", function()
			if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
			Enum.KeyCode.Space, Enum.KeyCode.E, Enum.KeyCode.C, Enum.KeyCode.LeftShift)
	end
	local released = false
	return function()
		if released then return end
		released = true
		count -= 1
		if count == 0 then
			ContextActionService:UnbindAction("UIModalKeyboard")
			playerGui:SetAttribute("GameplayInputBlocked", false)
			if releaseNativeControls then releaseNativeControls(); releaseNativeControls = nil end
		end
	end
end

return ModalInput
