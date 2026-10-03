--!strict

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local ShopView = require(script.Parent.ShopView)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local clientUI = player:WaitForChild("PlayerScripts"):WaitForChild("UI")
local Feedback = require(clientUI.Feedback)
local ModalInput = require(clientUI.ModalInput)
local Navigation = require(clientUI.Navigation)
local ProductPreview = require(clientUI.ProductPreview)
local request = ReplicatedStorage:WaitForChild(ShopConfig.RemoteFolderName):WaitForChild(ShopConfig.RequestFunctionName) :: RemoteFunction
type Product = ShopConfig.Product
type TabId = ShopConfig.TabId
type ShopState = { coins: number, coinSystemReady: boolean, owned: { [string]: boolean } }

local scope = Scope.new()
local alive = true
local isOpen = false
local busy = false
local currentTab: TabId = "Hulajnogi"
local state: ShopState = { coins = 0, coinSystemReady = false, owned = {} }
local pendingProduct: Product? = nil
local awaitingPass: { id: number, product: Product }? = nil
local lastRequestAt = -math.huge
local releaseInput: (() -> ())? = nil
local navigation: Navigation.Lease? = nil
local transition: Tween? = nil
local transitionTimer: thread? = nil
local requestThread: thread? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.DisplayOrder = 240
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
gui:SetAttribute("ShopOpen", false)
scope:Give(gui)
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "ShopNotifications"
toastGui.DisplayOrder = 310
toastGui.ResetOnSpawn = false
toastGui.Parent = playerGui
scope:Give(toastGui)
local feedback = Feedback.new(toastGui, scope)
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "ToggleShop"
toggleEvent.Parent = gui

local setOpen: (boolean) -> ()
local cancelConfirmation: () -> ()
local purchase: (Product) -> ()
local refresh: () -> ()
local view: ShopView.View
local previews: ProductPreview.Controller

local function useGamepad(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

local function focusShop()
	if not isOpen or not useGamepad() then return end
	if navigation then navigation.Focus(if pendingProduct then view.CancelButton else view.Tabs[currentTab]) end
end

local function update()
	view.Update(state, busy)
end

local function runRequest(callback: () -> ())
	requestThread = task.spawn(callback)
end

scope:Give(function()
	if requestThread and requestThread ~= coroutine.running() and coroutine.status(requestThread) ~= "dead" then
		task.cancel(requestThread)
	end
	requestThread = nil
end)

local function serverCall(action: string, id: string?): (boolean, string, number?)
	local waitTime = ShopConfig.RequestCooldown - (os.clock() - lastRequestAt)
	if waitTime > 0 then task.wait(waitTime + 0.02) end
	if not alive then return false, "", nil end
	lastRequestAt = os.clock()
	local ok, success, message, result, productId = pcall(function()
		return request:InvokeServer(action, id)
	end)
	if not alive then return false, "", nil end
	if not ok or typeof(success) ~= "boolean" then return false, "Nie można połączyć się ze sklepem.", nil end
	if typeof(result) == "table" and typeof(result.coins) == "number"
		and typeof(result.coinSystemReady) == "boolean" and typeof(result.owned) == "table" then
		state = result :: ShopState
	end
	return success, if typeof(message) == "string" then message else "", if typeof(productId) == "number" then productId else nil
end

refresh = function()
	if busy or not alive then return end
	busy = true
	update()
	runRequest(function()
		local success, message = serverCall("GetState", nil)
		if not alive then return end
		busy = false
		update()
		if not success then feedback.Show(message, true) end
	end)
end

cancelConfirmation = function()
	pendingProduct = nil
	view.SetConfirmation(nil, state.coins)
	focusShop()
end

purchase = function(product: Product)
	if busy or not alive then return end
	busy = true
	update()
	runRequest(function()
		local success, message, productId = serverCall(if product.currency == "Coins" then "PurchaseCoins" else "PrepareRobux", product.id)
		if not alive then return end
		if success and product.currency == "Robux" and productId then
			awaitingPass = { id = productId, product = product }
			local prompted, problem = pcall(function() MarketplaceService:PromptGamePassPurchase(player, productId) end)
			if prompted then return end
			awaitingPass = nil
			warn("Shop prompt: " .. tostring(problem))
			message = "Nie można otworzyć okna zakupu. Spróbuj ponownie."
			success = false
		end
		busy = false
		update()
		feedback.Show(message, not success)
		focusShop()
	end)
end

view = ShopView.new(gui, scope, {
	Toggle = function() feedback.Click(); setOpen(not isOpen) end,
	Close = function() feedback.Click(); setOpen(false) end,
	Tab = function(tabId: TabId)
		if pendingProduct or tabId == currentTab then return end
		feedback.Click()
		currentTab = tabId
		view.Render(tabId, previews.Mount)
		update()
		focusShop()
	end,
	Purchase = function(product: Product)
		if busy or pendingProduct then return end
		feedback.Click()
		if product.currency == "Coins" then
			pendingProduct = product
			view.SetConfirmation(product, state.coins)
			-- Cancel is the initial gamepad selection to prevent accidental purchases.
			focusShop()
		else purchase(product) end
	end,
	Confirm = function()
		local product = pendingProduct
		if not product or busy then return end
		feedback.Click()
		cancelConfirmation()
		purchase(product)
	end,
	Cancel = function() feedback.Click(); cancelConfirmation() end,
	Refresh = function() feedback.Click(); refresh() end,
})
previews = ProductPreview.new(scope, view.Scroll)
view.Render(currentTab, previews.Mount)
update()

local function stopTransition()
	if transitionTimer then
		if coroutine.status(transitionTimer) ~= "dead" then task.cancel(transitionTimer) end
		transitionTimer = nil
	end
	if transition then transition:Cancel(); transition = nil end
end

setOpen = function(open: boolean)
	if not alive or open == isOpen then return end
	if open then
		local ok, release = pcall(ModalInput.Acquire)
		if not ok then
			feedback.Show("Sterowanie jeszcze się ładuje. Spróbuj ponownie.", true)
			return
		end
		releaseInput = release
	end
	isOpen = open
	gui:SetAttribute("ShopOpen", open)
	stopTransition()
	if open then
		view.Overlay.Visible = true
		navigation = Navigation.Acquire(view.Window, 200, if useGamepad() then view.Tabs[currentTab] else nil)
		view.Window.GroupTransparency = 1
		previews.SetActive(true)
		local tween = TweenService:Create(view.Window, TweenInfo.new(Theme.Motion.Panel), { GroupTransparency = 0 })
		transition = tween
		tween:Play()
		focusShop()
		refresh()
	else
		cancelConfirmation()
		previews.SetActive(false)
		if releaseInput then releaseInput(); releaseInput = nil end
		if navigation then navigation.Release(); navigation = nil end
		local tween = TweenService:Create(view.Window, TweenInfo.new(Theme.Motion.Panel), { GroupTransparency = 1 })
		transition = tween
		tween:Play()
		-- A rapid reopen/close can produce a no-op tween. Visibility must not
		-- depend on a renderer completion signal in that case.
		transitionTimer = task.delay(Theme.Motion.Panel, function()
			transitionTimer = nil
			if alive and not isOpen then view.Overlay.Visible = false end
		end)
	end
end

scope:Give(toggleEvent.Event:Connect(function() setOpen(not isOpen) end))
scope:Give(gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not gui.Enabled then setOpen(false) end
end))
scope:Give(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.B then feedback.Click(); setOpen(not isOpen) end
end))
ContextActionService:BindActionAtPriority("ShopNavigation", function(_, inputState, input)
	if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	local toggle = input.KeyCode == Enum.KeyCode.ButtonY
	if not toggle and not isOpen then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin then
		feedback.Click()
		if toggle then setOpen(not isOpen)
		elseif pendingProduct then cancelConfirmation()
		else setOpen(false) end
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 200, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
scope:Give(function() ContextActionService:UnbindAction("ShopNavigation") end)
local function updateInputHint()
	view.HUD.Text = if useGamepad() then "Sklep  ·  Y" elseif UserInputService.PreferredInput == Enum.PreferredInput.Touch then "Sklep" else "Sklep  ·  B"
	focusShop()
end
scope:Give(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(updateInputHint))
updateInputHint()
scope:Give(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(buyer, passId, wasPurchased)
	local pending = awaitingPass
	if buyer ~= player or not pending or pending.id ~= passId then return end
	awaitingPass = nil
	runRequest(function()
		local success, message = serverCall("GetState", nil)
		if not alive then return end
		busy = false
		update()
		if not success then feedback.Show(message, true)
		elseif state.owned[pending.product.id] then feedback.Show("Odblokowano: " .. pending.product.name)
		elseif wasPurchased then feedback.Show("Zakup jest weryfikowany. Odśwież sklep za chwilę.")
		else feedback.Show("Zakup anulowany.") end
		focusShop()
	end)
end))

local function cleanup()
	if not alive then return end
	if isOpen then setOpen(false) end
	alive = false
	stopTransition()
	if releaseInput then releaseInput(); releaseInput = nil end
	scope:Clean()
end
scope:Give(gui.Destroying:Connect(cleanup))
scope:Give(script.Destroying:Connect(cleanup))
