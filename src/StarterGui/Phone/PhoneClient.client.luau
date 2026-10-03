--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local Types = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local PhoneView = require(script.Parent.PhoneView)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local clientUI = player:WaitForChild("PlayerScripts"):WaitForChild("UI")
local Feedback = require(clientUI.Feedback)
local ModalInput = require(clientUI.ModalInput)
local Navigation = require(clientUI.Navigation)
local remotes = ReplicatedStorage:WaitForChild(PhoneConfig.RemoteFolderName)
local request = remotes:WaitForChild(PhoneConfig.RequestFunctionName) :: RemoteFunction
local changed = remotes:WaitForChild(PhoneConfig.StateChangedEventName) :: RemoteEvent
local scope = Scope.new()
local alive = true
local open = false
local busy = false
local ready = false
local page: Types.Page = "Home"
local draft = ""
local refreshPending = false
local renderPending = false
local lastRequest = -math.huge
local requestThread: thread? = nil
local clockThread: thread? = nil
local focusThread: thread? = nil
local releaseInput: (() -> ())? = nil
local navigation: Navigation.Lease? = nil
local state: Types.State = {
	passiveEnabled = false, passiveAvailable = false,
	gang = { canCreate = false, isLeader = false, members = {}, maxMembers = 1, candidates = {} },
	delivery = { active = false, destination = "", distance = 0 },
	daily = {}, ownedScooters = {}, loginStreak = 0, loginReward = 0,
}

local function screen(name: string, order: number, ignoreInset: boolean?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.DisplayOrder = order
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if ignoreInset then gui.IgnoreGuiInset = true end
	gui.Parent = playerGui
	scope:Give(gui)
	return gui
end
local gui = screen("PhoneGui", 200)
local hudGui = screen("PhoneHUD", 100, true)
local notifications = screen("PhoneNotifications", 305)
local feedback = Feedback.new(notifications, scope)
gui:SetAttribute("PhoneOpen", false)
gui:SetAttribute("CurrentPage", "Home")
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "TogglePhone"
toggleEvent.Parent = gui
local navigateEvent = Instance.new("BindableEvent")
navigateEvent.Name = "NavigatePhone"
navigateEvent.Parent = gui
local view: PhoneView.View
local setOpen: (boolean) -> ()
local refresh: () -> ()
local navigate: (Types.Page) -> ()
local runAction: (string, unknown) -> ()

local function shopOpen(): boolean
	local shop = playerGui:FindFirstChild("ShopGui")
	return shop ~= nil and shop:GetAttribute("ShopOpen") == true
end
local function phoneTextBox(): TextBox?
	local focused = UserInputService:GetFocusedTextBox()
	return if focused and focused:IsDescendantOf(view.Window) then focused else nil
end
local function gamepad(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end
local function cancelThread(threadToCancel: thread?)
	if threadToCancel and threadToCancel ~= coroutine.running() and coroutine.status(threadToCancel) ~= "dead" then
		task.cancel(threadToCancel)
	end
end
local function focus(selection: GuiObject?)
	cancelThread(focusThread); focusThread = nil
	local lease = navigation
	if not lease then return end
	local desired = selection or view.DefaultSelection()
	-- Newly rebuilt buttons need a layout frame before Roblox can select them.
	focusThread = task.spawn(function()
		task.wait()
		if alive and open and navigation == lease and desired.Parent then lease.Focus(desired) end
	end)
end
local function syncInput(): boolean
	local padNavigation = open and gamepad()
	local needsLock = open and (padNavigation or phoneTextBox() ~= nil)
	if needsLock and not releaseInput then
		local ok, release = pcall(ModalInput.Acquire)
		if not ok then
			feedback.Show("Sterowanie jeszcze się ładuje. Spróbuj ponownie.", true)
			return false
		end
		releaseInput = release
	elseif not needsLock and releaseInput then
		releaseInput(); releaseInput = nil
	end
	if padNavigation and not navigation then
		navigation = Navigation.Acquire(view.Window, 100, view.DefaultSelection())
	elseif not padNavigation and navigation then
		navigation.Release(); navigation = nil
	end
	return true
end
local function render()
	if not alive then return end
	renderPending = false
	local selected = view.Render(page, state, draft, busy, ready)
	focus(selected)
end
local function perform(action: string, payload: unknown)
	busy = true
	view.SetBusy(true, ready)
	if not ready then render() end
	requestThread = task.spawn(function()
		local delay = PhoneConfig.RequestCooldown - (os.clock() - lastRequest)
		if delay > 0 then task.wait(delay + 0.02) end
		if not alive then return end
		lastRequest = os.clock()
		local ok, success, message, result = pcall(function() return request:InvokeServer(action, payload) end)
		if not alive then return end
		busy = false
		if ok and typeof(result) == "table" then
			state = result :: Types.State
			ready = true
		end
		-- Do not rebuild the gang form while the user is typing in it.
		if phoneTextBox() then renderPending = true; view.SetBusy(false, ready) else render() end
		if not ok then feedback.Show("Nie udało się połączyć z serwerem. Spróbuj ponownie.", true)
		elseif typeof(message) == "string" and message ~= "" then feedback.Show(message, success ~= true) end
		if refreshPending and open and not phoneTextBox() then
			refreshPending = false
			refresh()
		end
	end)
end
refresh = function()
	if not alive then return end
	if busy or phoneTextBox() then refreshPending = true; return end
	refreshPending = false
	perform("GetState", nil)
end
runAction = function(action: string, payload: unknown)
	if not alive or not open or shopOpen() or busy or not ready then return end
	local box = phoneTextBox()
	if box then box:ReleaseFocus() end
	feedback.Click()
	perform(action, payload)
end
navigate = function(target: Types.Page)
	if not open or target == page or shopOpen() then return end
	local box = phoneTextBox()
	if box then box:ReleaseFocus() end
	feedback.Click()
	page = target
	gui:SetAttribute("CurrentPage", page)
	render()
	if refreshPending and not busy then refresh() end
end
local function back()
	if page ~= "Home" then navigate("Home") else feedback.Click(); setOpen(false) end
end
view = PhoneView.new(gui, hudGui, scope, {
	Navigate = navigate, Back = back,
	Close = function() feedback.Click(); setOpen(false) end,
	Toggle = function() feedback.Click(); setOpen(not open) end,
	Refresh = function() feedback.Click(); refresh() end,
	Action = runAction, Draft = function(value: string) draft = value end,
})
render()

setOpen = function(value: boolean)
	if not alive or value == open or (value and (shopOpen() or not gui.Enabled)) then return end
	if not value then
		local box = phoneTextBox()
		if box then box:ReleaseFocus() end
	end
	open = value
	view.SetOpen(value)
	if not syncInput() then
		open = false
		view.SetOpen(false)
		syncInput()
		return
	end
	gui:SetAttribute("PhoneOpen", value)
	cancelThread(clockThread); clockThread = nil
	if value then
		focus()
		refresh()
		clockThread = task.spawn(function()
			while alive and open do
				task.wait(Theme.Phone.ClockInterval)
				if alive and open then view.UpdateClock() end
			end
		end)
	else
		cancelThread(focusThread); focusThread = nil
		page = "Home"
		gui:SetAttribute("CurrentPage", page)
		render()
	end
end
scope:Give(toggleEvent.Event:Connect(function() feedback.Click(); setOpen(not open) end))
scope:Give(navigateEvent.Event:Connect(function(target: unknown)
	if target == "Home" or target == "Scooters" or target == "Delivery" or target == "Gang" or target == "Daily" or target == "Protection" then
		navigate(target :: Types.Page)
	end
end))
scope:Give(gui:GetPropertyChangedSignal("Enabled"):Connect(function() if not gui.Enabled then setOpen(false) end end))
scope:Give(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.M then feedback.Click(); setOpen(not open) end
end))
ContextActionService:BindActionAtPriority("PhoneNavigation", function(_, inputState, input)
	if shopOpen() or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	local toggle = input.KeyCode == Enum.KeyCode.ButtonX
	if not toggle and not open then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin then
		if toggle then feedback.Click(); setOpen(not open) else back() end
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 150, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
scope:Give(function() ContextActionService:UnbindAction("PhoneNavigation") end)
scope:Give(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	if not syncInput() then setOpen(false) end
end))
scope:Give(UserInputService.TextBoxFocused:Connect(function(box)
	if box:IsDescendantOf(view.Window) and not syncInput() then box:ReleaseFocus() end
end))
scope:Give(UserInputService.TextBoxFocusReleased:Connect(function(box)
	if not box:IsDescendantOf(view.Window) then return end
	task.defer(function()
		if not alive then return end
		syncInput()
		if renderPending and not phoneTextBox() then render() end
		if refreshPending and open and not busy then refresh() end
	end)
end))
local shopConnection: RBXScriptConnection? = nil
scope:Give(function() if shopConnection then shopConnection:Disconnect() end end)
local function watchShop(shop: Instance)
	if shop.Name ~= "ShopGui" then return end
	if shopConnection then shopConnection:Disconnect() end
	shopConnection = shop:GetAttributeChangedSignal("ShopOpen"):Connect(function()
		if shop:GetAttribute("ShopOpen") == true then setOpen(false) end
	end)
	if shop:GetAttribute("ShopOpen") == true then setOpen(false) end
end
for _, child in playerGui:GetChildren() do watchShop(child) end
scope:Give(playerGui.ChildAdded:Connect(watchShop))
scope:Give(changed.OnClientEvent:Connect(function()
	if open then refresh() else refreshPending = true; feedback.Show("Nowa informacja z gangu. Otwórz telefon.") end
end))
local function cleanup()
	if not alive then return end
	if open then setOpen(false) end
	alive = false
	cancelThread(requestThread)
	cancelThread(clockThread)
	cancelThread(focusThread)
	if navigation then navigation.Release(); navigation = nil end
	if releaseInput then releaseInput(); releaseInput = nil end
	scope:Clean()
end
scope:Give(gui.Destroying:Connect(cleanup))
scope:Give(script.Destroying:Connect(cleanup))
