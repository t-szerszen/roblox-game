--!strict
-- Explicit client fixtures: no purchases, persistent rewards or production map edits.
local Tests = {}

-- Install only in a solo Studio Play server, then stop Play to restore transport.
-- Only the UI response grants the create form; no entitlement/profile is changed.
function Tests.InstallTransport()
	assert(game:GetService("RunService"):IsStudio(), "Studio only")
	assert(#game:GetService("Players"):GetPlayers() == 1, "Solo fixture only")
	local storage = game:GetService("ReplicatedStorage")
	assert(not storage:FindFirstChild("PhoneUITransportFixture"), "Transport already installed")
	local request = storage.PhoneRemotes.PhoneRequest :: RemoteFunction
	local changed = storage.PhoneRemotes.PhoneStateChanged :: RemoteEvent
	local fixture = Instance.new("Folder")
	fixture.Name = "PhoneUITransportFixture"
	fixture:SetAttribute("Requests", 0)
	fixture:SetAttribute("Active", 0)
	fixture:SetAttribute("Maximum", 0)
	fixture.Parent = storage
	local push = Instance.new("RemoteEvent")
	push.Name = "Push"
	push.Parent = fixture
	local requests = 0
	local active = 0
	request.OnServerInvoke = function(player: Player, action: unknown, payload: unknown)
		requests += 1
		active += 1
		fixture:SetAttribute("Requests", requests)
		fixture:SetAttribute("Active", active)
		fixture:SetAttribute("Maximum", math.max(active, fixture:GetAttribute("Maximum") :: number))
		task.wait(0.15)
		active -= 1
		fixture:SetAttribute("Active", active)
		assert(action == "GetState", "Fixture refuses gameplay mutations")
		return true, "", {
			passiveEnabled = false, passiveAvailable = true,
			gang = { canCreate = true, isLeader = false, members = {}, maxMembers = 5, candidates = {}, invites = {}, requests = {}, directory = {}, colors = { { id = 1, color = Color3.fromRGB(224, 76, 70), available = true } }, flagsOwned = 0, incomePerMinute = 0 },
			delivery = { active = false, destination = "", distance = 0 },
			daily = {}, ownedScooters = {}, loginStreak = 0, loginReward = 0,
		}
	end
	push.OnServerEvent:Connect(function(player)
		changed:FireClient(player)
	end)
end

function Tests.Typing(): number
	local player = assert(game:GetService("Players").LocalPlayer)
	local playerGui = player.PlayerGui
	local gui = assert(playerGui:WaitForChild("PhoneGui", 5))
	local fixture = assert(game:GetService("ReplicatedStorage"):WaitForChild("PhoneUITransportFixture", 5))
	local push = assert(fixture:FindFirstChild("Push")) :: RemoteEvent
	local toggle = assert(gui:FindFirstChild("TogglePhone")) :: BindableEvent
	local navigate = assert(gui:FindFirstChild("NavigatePhone")) :: BindableEvent
	if gui:GetAttribute("PhoneOpen") then toggle:Fire(); task.wait(0.25) end
	toggle:Fire(); task.wait(0.6)
	navigate:Fire("Gang"); task.wait(0.1)
	local window = assert(assert(gui:FindFirstChild("SafeArea")):FindFirstChild("Phone"))
	local input = assert(window:FindFirstChild("GangName", true)) :: TextBox
	local count = 0
	local function check(condition: boolean, message: string) count += 1; assert(condition, message) end
	input:CaptureFocus(); task.wait(0.05)
	check(game:GetService("UserInputService"):GetFocusedTextBox() == input, "Gang form accepts real text focus")
	check(playerGui:GetAttribute("GameplayInputBlocked") == true, "Typing acquires native/scooter movement lock")
	input.Text = "Moja nazwa"
	local before = fixture:GetAttribute("Requests") :: number
	for _ = 1, 5 do push:FireServer() end
	task.wait(0.2)
	check(fixture:GetAttribute("Requests") == before and input.Text == "Moja nazwa", "Push events preserve focus/draft and defer refresh while typing")
	input:ReleaseFocus(); task.wait(0.5)
	check(playerGui:GetAttribute("GameplayInputBlocked") ~= true, "Leaving text entry restores movement")
	check(fixture:GetAttribute("Requests") == before + 1 and fixture:GetAttribute("Maximum") == 1, "Burst notifications coalesce into one serialized refresh")
	navigate:Fire("Home"); task.wait(0.025)
	navigate:Fire("Gang"); task.wait(0.05)
	input = assert(window:FindFirstChild("GangName", true)) :: TextBox
	check(input.Text == "Moja nazwa", "Draft survives navigation and server refresh")
	input:CaptureFocus(); task.wait(0.025)
	gui.Enabled = false; task.wait(0.05)
	check(playerGui:GetAttribute("GameplayInputBlocked") ~= true and game:GetService("UserInputService"):GetFocusedTextBox() ~= input, "Disabling a focused phone releases text and movement")
	gui.Enabled = true
	return count
end

function Tests.View(): number
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GuiService = game:GetService("GuiService")
	local player = Players.LocalPlayer
	assert(player, "Run View checks in the client datamodel")
	local Scope = require(ReplicatedStorage.Shared.UI.Scope)
	local Theme = require(ReplicatedStorage.Shared.UI.Theme)
	assert(player.PlayerGui:WaitForChild("Phone", 5), "Phone source modules did not replicate")
	local PhoneView = require(player.PlayerGui.Phone.PhoneView)
	local Types = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
	local owner = Scope.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PhoneUITest"
	gui.DisplayOrder = 320
	gui.Parent = player.PlayerGui
	owner:Give(gui)
	local hud = Instance.new("ScreenGui")
	hud.Parent = player.PlayerGui
	owner:Give(hud)
	local count = 0
	local function check(condition: boolean, message: string)
		count += 1
		assert(condition, message)
	end
	local function nothing() end
	local draft = ""
	local view = PhoneView.new(gui, hud, owner, {
		Navigate = nothing, Back = nothing, Close = nothing, Toggle = nothing, Refresh = nothing, Action = nothing,
		Draft = function(value: string) draft = value end,
	})
	local state: Types.State = {
		passiveEnabled = false, passiveAvailable = true,
		gang = { canCreate = false, isLeader = false, members = {}, maxMembers = 5, candidates = {}, invites = {}, requests = {}, directory = {}, colors = { { id = 1, color = Color3.fromRGB(224, 76, 70), available = true } }, flagsOwned = 0, incomePerMinute = 0 },
		delivery = { active = false, destination = "", distance = 0 },
		daily = { { id = "distance", progress = 2.5, target = 5 } },
		ownedScooters = { "KuKirin G2 Pro" }, loginStreak = 3, loginReward = 0,
	}
	local function find(name: string): Instance
		return assert(view.Scroll:FindFirstChild(name, true), "Missing " .. name)
	end
	local function button(name: string): TextButton return find(name) :: TextButton end
	local beforeSelection = GuiService.SelectedObject
	local beforeNavigation = GuiService.GuiNavigationEnabled
	local beforeAutoSelect = GuiService.AutoSelectGuiEnabled
	GuiService.GuiNavigationEnabled = true
	GuiService.AutoSelectGuiEnabled = false
	local initialResources = #owner._tasks
	local ok, problem = pcall(function()
		view.SetOpen(true)
		view.Render("Home", state, draft, false, true)
		task.wait(0.25)
		check(#assert(view.Scroll:FindFirstChild("Page")):GetChildren() == 6, "Five apps and exactly one grid layout")
		check(not view.Back.Active, "Home disables redundant back navigation")
		view.Render("Scooters", state, draft, false, true)
		task.wait(0.05)
		local first = find("kukirin_g2_pro")
		local spawn = assert(first:FindFirstChild("Spawn", true)) :: TextButton
		check(spawn.Active, "Owned scooter can be summoned")
		check(not (assert(find("kukirin_g2_max"):FindFirstChild("Spawn", true)) :: TextButton).Active, "Unowned scooter cannot be summoned")
		check(spawn.AbsoluteSize.Y >= Theme.TouchTarget, "Phone actions retain 44px touch targets")
		view.SetBusy(true, true)
		check(not spawn.Active and not spawn.Selectable, "Pending request disables duplicate actions and focus")
		view.SetBusy(false, true)
		check(spawn.Active, "Action restores after the pending request")
		view.Render("Daily", state, draft, false, true)
		local fill = assert(assert(find("distance"):FindFirstChild("Progress", true)):FindFirstChild("Fill")) :: Frame
		check(fill.Size.X.Scale == 0.5, "Mission bar uses server progress")
		view.Render("Delivery", state, draft, false, true)
		check(find("NoDelivery"):IsA("Frame"), "Inactive delivery has map pickup guidance")
		state.delivery = { active = true, destination = "Długa nazwa punktu dostawy na drugim końcu miasta", distance = 1234 }
		view.Render("Delivery", state, draft, false, true)
		check(find("Destination"):IsA("Frame") and find("Distance"):IsA("Frame"), "Active delivery retains destination and distance")
		state.passiveAvailable = false
		view.Render("Protection", state, draft, false, true)
		check(not button("TogglePassive").Active, "Unavailable transport state disables protection")
		state.passiveAvailable = true
		view.Render("Protection", state, draft, false, true)
		task.wait(0.05)
		local focusTarget = button("TogglePassive")
		local deadline = os.clock() + 1
		repeat
			GuiService.SelectedObject = focusTarget
			task.wait(0.05)
		until GuiService.SelectedObject == focusTarget or os.clock() >= deadline
		assert(GuiService.SelectedObject == focusTarget, "Fixture must wait for a selectable layout")
		local restored = view.Render("Protection", state, draft, false, true)
		check(restored == button("TogglePassive"), "State refresh can restore the same action's gamepad focus")
		view.Render("Gang", state, draft, false, true)
		check(find("NoGang"):IsA("Frame"), "Membership cooldown disables creation")
		state.gang.invite = { id = "invite-test", gangId = "test", gangName = "Test", inviterName = "Gracz", expiresAt = workspace:GetServerTimeNow() + 30 }
		state.gang.invites = { assert(state.gang.invite) }
		view.Render("Gang", state, draft, false, true)
		check(button("Accept").Active and button("Decline").Active, "Invite supports both responses")
		state.gang.canCreate = true
		view.Render("Gang", state, "Zapamiętana nazwa", false, true)
		local input = find("GangName") :: TextBox
		check(input.Text == "Zapamiętana nazwa", "Gang draft survives navigation")
		input.Text = "Nowa nazwa"
		task.wait()
		check(draft == "Nowa nazwa", "Editing updates the draft without server traffic")
		state.gang.gangId = "test"
		state.gang.gangName = "Test"
		state.gang.isLeader = true
		state.gang.members = { { userId = 1, displayName = "Lider", isLeader = true, online = true }, { userId = 2, displayName = "Członek", isLeader = false, online = true } }
		state.gang.candidates = { { userId = 3, displayName = "Kandydat" } }
		view.Render("Gang", state, draft, false, true)
		check(find("Member_1"):FindFirstChild("Kick", true) == nil, "Leader cannot kick themselves")
		check(button("Kick").Active and button("InviteMember").Active, "Leader sees member management")
		state.gang.isLeader = false
		view.Render("Gang", state, draft, false, true)
		check(view.Scroll:FindFirstChild("Kick", true) == nil and view.Scroll:FindFirstChild("InviteMember", true) == nil, "Regular members cannot manage members")
		check(button("Leave").Active, "Members retain the leave action")
		view.Render("Gang", state, draft, true, false)
		check(not button("Retry").Active, "Loading state prevents duplicate retries")
		view.Render("Gang", state, draft, false, false)
		check(button("Retry").Active, "Failed initial fetch has a retry")
		local safe = assert(gui:FindFirstChild("SafeArea")) :: Frame
		for _, size in { Vector2.new(320, 480), Vector2.new(844, 320), Vector2.new(1024, 768) } do
			safe.Size = UDim2.fromOffset(size.X, size.Y)
			view.Render("Home", state, draft, false, true)
			task.wait(0.05)
			check(view.Window.AbsoluteSize.X <= size.X - 24 and view.Window.AbsoluteSize.Y <= size.Y - 24, "Responsive phone fits simulated safe area")
			local default = view.DefaultSelection()
			check(default.AbsoluteSize.Y >= 44 and default.AbsoluteSize.X >= 44, "Responsive home tiles retain usable targets")
		end
		for _ = 1, 30 do
			view.Render("Gang", state, draft, false, true)
			view.Render("Home", state, draft, false, true)
		end
		check(#owner._tasks == initialResources, "Switching applications does not grow root resources")
		check(#assert(view.Scroll:FindFirstChild("Page")):GetChildren() == 6, "App transitions do not accumulate layouts")
		for _ = 1, 8 do view.SetOpen(false); view.SetOpen(true) end
		view.SetOpen(false)
		view.Render("Home", state, draft, false, true)
		check(not (view.DefaultSelection() :: TextButton).Interactable and not view.DefaultSelection().Selectable, "Closing immediately disables new page interactions")
		task.wait(0.25)
		check(not view.Window.Visible, "Rapid transitions end hidden")
	end)
	GuiService.SelectedObject = if beforeSelection and beforeSelection.Parent then beforeSelection else nil
	GuiService.GuiNavigationEnabled = beforeNavigation
	GuiService.AutoSelectGuiEnabled = beforeAutoSelect
	owner:Clean()
	assert(ok, tostring(problem))
	check(gui.Parent == nil and #owner._tasks == 0, "Fixture teardown releases instances and resources")
	return count
end

function Tests.Controller(): number
	local player = assert(game:GetService("Players").LocalPlayer)
	local playerGui = player.PlayerGui
	local gui = assert(playerGui:WaitForChild("PhoneGui", 5))
	local toggle = assert(gui:FindFirstChild("TogglePhone")) :: BindableEvent
	local navigate = assert(gui:FindFirstChild("NavigatePhone")) :: BindableEvent
	local shop = assert(playerGui:WaitForChild("ShopGui", 5))
	local shopToggle = assert(shop:FindFirstChild("ToggleShop")) :: BindableEvent
	if shop:GetAttribute("ShopOpen") then shopToggle:Fire(); task.wait(0.3) end
	if gui:GetAttribute("PhoneOpen") then toggle:Fire(); task.wait(0.3) end
	assert(game:GetService("UserInputService").PreferredInput ~= Enum.PreferredInput.Gamepad, "Run pointer controller checks in keyboard/touch mode")
	local count = 0
	local function check(condition: boolean, message: string) count += 1; assert(condition, message) end
	for _ = 1, 12 do
		toggle:Fire(); task.wait(0.025)
		check(gui:GetAttribute("PhoneOpen") == true and playerGui:GetAttribute("GameplayInputBlocked") ~= true, "Pointer phone leaves movement available")
		toggle:Fire(); task.wait(0.025)
		check(gui:GetAttribute("PhoneOpen") == false, "Phone closes repeatedly")
	end
	task.wait(0.3)
	local window = assert(assert(gui:FindFirstChild("SafeArea")):FindFirstChild("Phone")) :: CanvasGroup
	check(not window.Visible, "Controller transition timer finishes hidden")
	toggle:Fire(); task.wait(0.4)
	navigate:Fire("Daily"); task.wait(0.05)
	check(gui:GetAttribute("CurrentPage") == "Daily", "Real controller navigates to apps")
	shopToggle:Fire(); task.wait(0.05)
	check(gui:GetAttribute("PhoneOpen") == false and playerGui:GetAttribute("GameplayInputBlocked") == true, "Shop closes phone and keeps its own movement lock")
	toggle:Fire(); task.wait(0.025)
	check(gui:GetAttribute("PhoneOpen") == false, "Phone cannot reopen over the shop")
	shopToggle:Fire(); task.wait(0.05)
	check(playerGui:GetAttribute("GameplayInputBlocked") == false, "Closing shop restores movement")
	toggle:Fire(); task.wait(0.05)
	gui.Enabled = false; task.wait(0.05)
	check(gui:GetAttribute("PhoneOpen") == false and playerGui:GetAttribute("GameplayInputBlocked") ~= true, "Disabling phone closes and restores input")
	gui.Enabled = true
	return count
end

return Tests
