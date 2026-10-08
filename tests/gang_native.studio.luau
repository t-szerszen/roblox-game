--!strict
-- Edit-mode structural checks use detached Instances and do not change Workspace.Map.
local Tests = {}
function Tests.Run(): number
	assert(not game:GetService("RunService"):IsRunning(), "Run detached fixtures in Edit mode")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Scope = require(ReplicatedStorage.Shared.UI.Scope)
	local PhoneTypes = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
	local PhoneView = require(game:GetService("StarterGui").Phone.PhoneView)
	local Tags = require(ServerScriptService.Gang.GangTags)
	local Capture = require(ServerScriptService.Territory.TerritoryCapture)
	local count = 0
	local function check(condition: boolean, message: string) count += 1; assert(condition, message) end
	local owner = Scope.new()
	local gui = Instance.new("ScreenGui"); owner:Give(gui)
	local hud = Instance.new("ScreenGui"); owner:Give(hud)
	local model = Instance.new("Model"); owner:Give(model)
	local head = Instance.new("Part"); head.Name = "Head"; head.Parent = model
	local humanoid = Instance.new("Humanoid"); humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject; humanoid.Parent = model
	local player = { Character = model, DisplayName = "Fixture" } :: any
	local ok, problem = pcall(function(): string?
		Tags.Apply(player, "Alfa", Color3.fromRGB(255, 90, 90))
		local tag = head:FindFirstChild("GangTag") :: BillboardGui?
		check(tag ~= nil and (tag :: BillboardGui).Adornee == head, "Native gang tag attaches to head")
		check(humanoid.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None, "Native nickname replaced once")
		Tags.Apply(player, "Beta", Color3.fromRGB(90, 255, 90))
		check(#head:GetChildren() == 1, "Rename replaces rather than duplicates tag")
		Tags.Apply(player, nil, nil)
		check(not head:FindFirstChild("GangTag") and humanoid.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.Subject, "Leave restores authored nickname settings")
		local function nothing() end
		local view = PhoneView.new(gui, hud, owner, { Navigate = nothing, Back = nothing, Close = nothing, Toggle = nothing, Refresh = nothing, Action = nothing, Draft = nothing })
		local state: PhoneTypes.State = {
			passiveEnabled = false, passiveAvailable = true,
			gang = { canCreate = true, isLeader = false, members = {}, maxMembers = 10, candidates = {},
				invites = { { id = "invite", gangId = "rival", gangName = "Rival", inviterName = "Owner", expiresAt = 100 } },
				requests = {}, directory = { { id = "rival", name = "Rival", color = Color3.new(0, 1, 0), memberCount = 2, maxMembers = 10, requested = false } },
				colors = { {id = 1, color = Color3.new(1, 0, 0), available = false}, {id = 2, color = Color3.new(0, 1, 0), available = true} },
				flagsOwned = 0, incomePerMinute = 0 },
			delivery = {active = false, destination = "", distance = 0}, daily = {}, ownedScooters = {}, loginStreak = 0, loginReward = 0,
		}
		view.SetOpen(true); view.Render("Gang", state, "Draft", false, true)
		local function find(name: string): Instance return assert(view.Scroll:FindFirstChild(name, true), name) end
		check(not (find("Color_1") :: TextButton).Active and (find("Color_2") :: TextButton).Active, "Taken RGB color disabled")
		check((find("Create") :: TextButton).Active, "Free creation enabled with available color")
		check((find("GangName") :: TextBox).Text == "Draft", "Name draft preserved")
		check((find("Accept") :: TextButton).Active and (find("RequestJoin") :: TextButton).Active, "Invite and request entry points coexist")
		view.SetBusy(true, true)
		check(not (find("Color_2") :: TextButton).Active and not (find("Create") :: TextButton).Active, "Palette and create guarded while request pending")
		state.gang.gangId = "own"; state.gang.gangName = "Own"; state.gang.isLeader = true
		state.gang.members = { {userId = 1, displayName = "Owner", isLeader = true, online = true}, {userId = 2, displayName = "Member", isLeader = false, online = true} }
		state.gang.requests = { {id = "request", userId = 3, displayName = "Applicant", expiresAt = 100} }
		view.Render("Gang", state, "", false, true)
		check(find("Rename"):IsA("Frame") and find("ChangeColor"):IsA("Frame"), "Owner identity management rendered")
		check((find("AcceptRequest") :: TextButton).Active and (find("RejectRequest") :: TextButton).Active, "Owner can respond both ways")
		state.gang.isLeader = false
		view.Render("Gang", state, "", false, true)
		check(not view.Scroll:FindFirstChild("Rename", true) and not view.Scroll:FindFirstChild("AcceptRequest", true), "Member cannot manage identity or requests")
		view.Render("Protection", state, "", false, true)
		check((find("TogglePassive") :: TextButton).Active, "Gang member protection available")
		local resources = #owner._tasks
		for _ = 1, 25 do view.Render("Gang", state, "", false, true); view.Render("Home", state, "", false, true) end
		check(#owner._tasks == resources, "Repeated page rebuilds do not grow owner resources")
		local capture = Capture.New()
		Capture.Step(capture, {A = 2, B = 1}, 45)
		check(capture.ownerGangId == "A", "Native module evaluates net capture advantage")
		local frame = CFrame.new(10, 5, -20) * CFrame.Angles(0, math.pi / 4, 0)
		local inside = frame:PointToObjectSpace(frame:PointToWorldSpace(Vector3.new(3, 0, 3)))
		check(math.abs(inside.X) <= 5 and math.abs(inside.Z) <= 5, "Rotated-zone coordinate conversion matches local bounds")
		return nil
	end)
	owner:Clean()
	assert(ok, tostring(problem))
	check(#owner._tasks == 0 and gui.Parent == nil and model.Parent == nil, "Native fixtures dispose all Instances and connections")
	return count
end
return Tests
