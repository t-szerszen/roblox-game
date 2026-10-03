--!strict
-- Run explicitly in a Studio test session. No purchases, DataStore writes or map edits.
local StudioTests = {}

function StudioTests.Controller(): number
	local player = game:GetService("Players").LocalPlayer
	assert(player, "Run Controller checks in the client datamodel")
	local gui = player.PlayerGui:WaitForChild("ShopGui", 5)
	assert(gui, "Shop controller did not initialize")
	if gui:GetAttribute("ShopOpen") then gui.ToggleShop:Fire(); task.wait(0.25) end
	local module = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
	local contexts = if module then module:FindFirstChild("InputContexts") else nil
	local characterContext = if contexts then contexts:FindFirstChild("CharacterContext") :: InputContext else nil
	local previous = if characterContext then characterContext.Enabled else false
	local count = 0
	for _ = 1, 12 do
		gui.ToggleShop:Fire()
		task.wait(0.025)
		assert(gui:GetAttribute("ShopOpen") == true and player.PlayerGui:GetAttribute("GameplayInputBlocked") == true, "Open lock invariant")
		if characterContext then assert(not characterContext.Enabled, "Native context must be blocked") end
		count += 1
		gui.ToggleShop:Fire()
		task.wait(0.025)
		assert(gui:GetAttribute("ShopOpen") == false and player.PlayerGui:GetAttribute("GameplayInputBlocked") == false, "Close restore invariant")
		if characterContext then assert(characterContext.Enabled == previous, "Context must restore") end
		count += 1
	end
	task.wait(0.3)
	assert(not gui.Overlay.Visible, "Rapid transitions must finish with a hidden overlay")
	local viewport = gui.Overlay.ShopWindow.Products.kukirin_g2_pro.Artwork.ModelPreview
	local before = viewport.CurrentCamera.CFrame
	task.wait(0.15)
	assert(viewport.CurrentCamera.CFrame == before, "Closed shop must stop preview rotation")
	return count + 2
end

function StudioTests.Client(): number
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")
	local player = Players.LocalPlayer
	assert(player, "Run Client checks in the client datamodel")
	local playerGui = player:WaitForChild("PlayerGui")
	local Scope = require(ReplicatedStorage.Shared.UI.Scope)
	local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
	local Theme = require(ReplicatedStorage.Shared.UI.Theme)
	local ShopView = require(playerGui.Shop.ShopView)
	local Feedback = require(player.PlayerScripts.UI.Feedback)
	local Preview = require(player.PlayerScripts.UI.ProductPreview)
	local count = 0
	local function check(condition: boolean, message: string)
		count += 1
		assert(condition, message)
	end
	local owner = Scope.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopUITest"
	gui.DisplayOrder = 320
	gui.Parent = playerGui
	owner:Give(gui)
	local function nothing() end
	local view = ShopView.new(gui, owner, {
		Toggle = nothing, Close = nothing, Tab = nothing, Purchase = nothing,
		Confirm = nothing, Cancel = nothing, Refresh = nothing,
	})
	local previews = Preview.new(owner, view.Scroll)
	local feedback = Feedback.new(gui, owner)
	local before = #owner._tasks
	local function purchaseButton(id: string): TextButton
		local card = assert(view.Scroll:FindFirstChild(id))
		return assert(card:FindFirstChild("Purchase")) :: TextButton
	end
	view.Overlay.Visible = true
	previews.SetActive(true)
	local state = { coins = 2000, coinSystemReady = true, owned = { kukirin_g2_pro = true } }
	local ok, problem = pcall(function()
		view.Render("Hulajnogi", previews.Mount)
		view.Update(state, false)
		task.wait(0.2)
		check(not purchaseButton("kukirin_g2_pro").Active, "Owned products cannot be purchased")
		check(purchaseButton("kukirin_g2_max").Active, "Affordable product is actionable")
		check(not purchaseButton("kukirin_g2_master").Active, "Insufficient Coins are explained without a request")
		local art = assert(assert(view.Scroll:FindFirstChild("kukirin_g2_max")):FindFirstChild("Artwork"))
		check(assert(art:FindFirstChild("ModelPreview")):FindFirstChildOfClass("WorldModel") ~= nil, "Viewport uses an isolated world")
		local windowRight = view.Window.AbsolutePosition.X + view.Window.AbsoluteSize.X
		for _, child in view.Scroll:GetChildren() do
			if child:IsA("Frame") then
				check(child.AbsolutePosition.X >= view.Scroll.AbsolutePosition.X, "Cards stay inside the left edge")
				check(child.AbsolutePosition.X + child.AbsoluteSize.X <= windowRight, "Cards stay inside the right edge")
			end
		end
		view.Update(state, true)
		check(not purchaseButton("kukirin_g2_max").Active, "Pending request disables duplicate activation")
		view.SetConfirmation(ShopConfig.CoinProducts[2], state.coins)
		check(view.Dialog.Visible, "Coins purchase opens confirmation")
		local details = assert(assert(view.Dialog:FindFirstChild("Confirmation")):FindFirstChild("Details")) :: TextLabel
		check(string.find(details.Text, "1 000 Coins", 1, true) ~= nil, "Confirmation shows cost and resulting balance")
		view.SetConfirmation(nil, state.coins)
		check(not view.Dialog.Visible, "Cancel closes confirmation")
		for index = 1, 60 do
			if index % 3 == 1 then view.Render("Hulajnogi", previews.Mount)
			elseif index % 3 == 2 then view.Render("Premium", previews.Mount)
			else view.Render("Kody", previews.Mount) end
			view.Update(state, false)
		end
		check(#owner._tasks == before, "Tab churn does not retain retired card scopes")
		view.Render("Premium", previews.Mount)
		view.Update(state, false)
		check(not purchaseButton("pepper_spray").Active, "Unconfigured premium stays unavailable")
		check(view.Scroll:FindFirstChild("kukirin_g2_pro") == nil, "Retired product cards are destroyed")
		view.Render("Kody", previews.Mount)
		check(view.Scroll:FindFirstChild("Codes") ~= nil and view.Scroll:FindFirstChildOfClass("UIGridLayout") == nil, "Codes placeholder is not squeezed into a product grid")
		for index = 1, 8 do feedback.Show("Test notification " .. index, index % 2 == 0) end
		local frames = 0
		for _, child in assert(gui:FindFirstChild("Notifications")):GetChildren() do if child:IsA("Frame") then frames += 1 end end
		check(frames == Theme.Toast.Maximum, "Toast queue stays bounded")
		check(#owner._tasks == before, "Toast churn does not grow the parent cleanup list")
		feedback.Click()
		task.wait(0.3)
		check(SoundService:FindFirstChild("UIClick") ~= nil, "Click sound exists locally")
	end)
	owner:Clean()
	check(gui.Parent == nil and #owner._tasks == 0, "Fixture resources are fully released")
	if not ok then error(problem) end
	return count
end

function StudioTests.Server(): number
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CollectionService = game:GetService("CollectionService")
	local Builder = require(game.ServerScriptService.Shop.PreviewModel)
	local count = 0
	local function check(condition: boolean, message: string)
		count += 1
		assert(condition, message)
	end
	local fixture = Instance.new("Model")
	fixture.Name = "PreviewSanitizationFixture"
	local visible = Instance.new("Part")
	visible.Name = "Body"
	visible.CFrame = CFrame.new(35, 10, 20)
	visible.Parent = fixture
	visible:SetAttribute("OwnerUserId", 123)
	CollectionService:AddTag(visible, "TestGameplayTag")
	for _, class in { "Script", "LocalScript", "ProximityPrompt", "Sound", "ParticleEmitter", "Attachment", "WeldConstraint" } do
		local child = Instance.new(class)
		child.Parent = visible
	end
	local invisible = Instance.new("Part")
	invisible.Name = "Collider"
	invisible.Transparency = 1
	invisible.Parent = fixture
	local appearance = Instance.new("Decal")
	appearance.Parent = visible
	local descendantCount = #fixture:GetDescendants()
	local model = Builder.Build(fixture, "test")
	assert(model)
	local ok, problem = pcall(function()
		check(#fixture:GetDescendants() == descendantCount and not visible.Anchored, "Source remains untouched")
		check(visible:GetAttribute("OwnerUserId") == 123 and CollectionService:HasTag(visible, "TestGameplayTag"), "Source metadata is preserved")
		check(#model:GetDescendants() == 2, "Only visible part and appearance are published")
		local part = model:FindFirstChild("Body") :: BasePart
		check(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery, "Preview cannot participate in gameplay physics")
		check(part:GetAttribute("OwnerUserId") == nil and #CollectionService:GetTags(part) == 0, "Preview cannot activate gameplay metadata listeners")
		check(part:FindFirstChildOfClass("Decal") ~= nil, "Visual appearance is retained")
		local bounds = model:GetBoundingBox()
		check(bounds.Position.Magnitude < 0.001, "Preview bounds are centered for camera framing")
		local published = ReplicatedStorage:FindFirstChild("ShopPreviews")
		check(published ~= nil and published:FindFirstChild("scooter") ~= nil, "Authored scooter is published automatically")
		if published then
			for _, object in published:GetDescendants() do
				check(not object:IsA("LuaSourceContainer") and not object:IsA("Constraint"), "Published catalog has no executable code or actuators")
			end
		end
	end)
	model:Destroy()
	fixture:Destroy()
	if not ok then error(problem) end
	return count
end

return StudioTests
