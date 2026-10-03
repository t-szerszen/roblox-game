local Layout = loadModule("ReplicatedStorage/Shared/UI/Layout")
local Theme = loadModule("ReplicatedStorage/Shared/UI/Theme")
local Scope = loadModule("ReplicatedStorage/Shared/UI/Scope")
local Shop = loadModule("ReplicatedStorage/Shared/Shop/ShopConfig")
local Previews = loadModule("ReplicatedStorage/Shared/Shop/PreviewConfig")

for _, screen in { {320, 568}, {375, 667}, {844, 390}, {1024, 768}, {1280, 720}, {1920, 1080}, {3840, 2160} } do
	local width, height = Layout.ShopWindow(screen[1], screen[2])
	check(width <= screen[1] - 24 and height <= screen[2] - 24, "Window fits safe content area")
	check(width <= 1000 and height <= 720, "Desktop window stays bounded")
	local available = width - 44
	local columns, cell = Layout.ProductGrid(available)
	check(columns >= 1 and columns <= 4, "Grid has bounded column count")
	check(columns * cell + (columns - 1) * Theme.Spacing <= available, "Grid never overflows horizontally")
	check(cell >= 220 or columns == 1, "Multi-column cards retain readable width")
end
check(select(1, Layout.ProductGrid(219)) == 1, "Narrow screens use one column")
for _, screen in { {320, 480}, {375, 667}, {844, 320}, {1024, 768}, {1920, 1080}, {3840, 2160} } do
	for _, input in {"KeyboardAndMouse", "Touch", "Gamepad"} do
		local width, height = Layout.PhoneWindow(screen[1], screen[2], input)
		check(width <= screen[1] - 24 and height <= screen[2] - 24, "Phone fits each safe viewport/input mode")
		check(width >= 296 and height >= 296, "Supported devices preserve room for readable controls")
		check(width <= 352 and height <= 660, "Phone remains bounded on large monitors")
	end
end
check(select(1, Layout.PhoneWindow(1024, 768, "Touch")) > select(1, Layout.PhoneWindow(1024, 768, "KeyboardAndMouse")), "Touch gets a larger panel without shrinking targets")
check(select(2, Layout.PhoneWindow(844, 320, "Touch")) == 296, "Landscape uses a shorter scrollable body")
check(select(1, Layout.ProductGrid(452)) == 2, "Two cards fit at breakpoint")
check(Layout.FormatCoins(26000) == "26 000" and Layout.FormatCoins(1234567) == "1 234 567", "Grouped currency")
for _, aspect in {0.3, 0.5, 1, 2, 4} do
	local distance = Layout.PreviewDistance({ Magnitude = 10 }, aspect)
	local halfAngle = math.atan(math.tan(math.rad(35 / 2)) * math.min(1, aspect))
	check(distance * math.sin(halfAngle) >= 5, "Camera encloses product at all rotations/aspects")
end
check(Layout.PreviewDistance({ Magnitude = 10 }, 0.5) > Layout.PreviewDistance({ Magnitude = 10 }, 2), "Narrow preview fits horizontal field of view")
check(#Shop.Tabs == 3 and Shop.GetProductsByTab("Dopalacze")[1] == nil, "Only approved categories remain")
for index, product in Shop.CoinProducts do
	check(Previews.Sources[product.previewKey] ~= nil, "Each scooter resolves a visual source")
	check(product.price == ({0, 1000, 4500, 12000, 26000})[index], "Redesign preserves the economy")
end

local scope = Scope.new()
local order = {}
scope:Give(function() table.insert(order, 1) end)
scope:Give(function() error("Expected cleanup failure") end)
scope:Give(function() table.insert(order, 3) end)
scope:Clean()
scope:Clean()
check(#order == 2 and order[1] == 3 and order[2] == 1, "Cleanup is reversed, resilient and idempotent")
scope:Give(function() table.insert(order, 4) end)
check(order[3] == 4 and #scope._tasks == 0, "Late resources are disposed immediately")
local connection = signal():Connect(function() end)
local connectionScope = Scope.new()
connectionScope:Give(connection)
connectionScope:Clean()
check(not connection.Connected, "Connections are disconnected")

local controls = { controlsEnabled = true, disableCount = 0, enableCount = 0 }
function controls:Disable() self.controlsEnabled = false; self.disableCount += 1 end
function controls:Enable() self.controlsEnabled = true; self.enableCount += 1 end
local legacy = instance("PlayerModule", "ModuleScript")
legacy.api = { GetControls = function() return controls end }
playerScripts.children.PlayerModule = legacy
local Modal = loadModule("StarterPlayer/StarterPlayerScripts/UI/ModalInput")
local first = Modal.Acquire()
local second = Modal.Acquire()
check(not controls.controlsEnabled and controls.disableCount == 1, "Nested modals share one native lock")
check(playerGui:GetAttribute("GameplayInputBlocked") and bindings.UIModalKeyboard ~= nil, "Scooter/keyboard see the lock")
first(); first()
check(not controls.controlsEnabled and controls.enableCount == 0, "Idempotent release does not unlock another modal")
second()
check(controls.controlsEnabled and controls.enableCount == 1 and bindings.UIModalKeyboard == nil, "Last modal restores movement")
check(playerGui:GetAttribute("GameplayInputBlocked") == false, "Last modal clears the input contract")
controls.controlsEnabled = false
local originallyDisabled = Modal.Acquire()
originallyDisabled()
check(not controls.controlsEnabled, "Pre-existing disabled controls stay disabled")

playerScripts.children.PlayerModule = nil
local modern = instance("PlayerModule", "ModuleScript")
local contexts = instance("InputContexts")
modern.children.InputContexts = contexts
starterPlayer.children.PlayerModule = modern
local character = instance("CharacterContext", "InputContext")
local vehicle = instance("VehicleContext", "InputContext")
local camera = instance("CameraContext", "InputContext")
character.Enabled, vehicle.Enabled, camera.Enabled = true, false, true
contexts.children = { CharacterContext = character, VehicleContext = vehicle, CameraContext = camera }
local releaseModern = Modal.Acquire()
check(not character.Enabled and not vehicle.Enabled and camera.Enabled, "Modern lock targets gameplay contexts and preserves camera")
character.Enabled = true
character:GetPropertyChangedSignal("Enabled"):Fire()
check(not character.Enabled, "Native re-enabling cannot bypass an active modal")
local lateFolder = instance("InputContexts")
local lateContext = instance("CharacterContext", "InputContext")
lateContext.Enabled = true
lateFolder.children.CharacterContext = lateContext
player.children.InputContexts = lateFolder
player.ChildAdded:Fire(lateFolder)
check(not lateContext.Enabled, "Late replicated input contexts are blocked")
releaseModern()
check(character.Enabled and not vehicle.Enabled and camera.Enabled and lateContext.Enabled, "Context snapshots restore exactly")
character.Enabled = false
character:GetPropertyChangedSignal("Enabled"):Fire()
check(not character.Enabled, "Released modal listeners no longer modify native contexts")
starterPlayer.children.PlayerModule = nil
check(not pcall(Modal.Acquire), "Missing native controls fail explicitly without a hanging require")
check(playerGui:GetAttribute("GameplayInputBlocked") == false, "Failed acquisition leaves movement unlocked")

local Navigation = loadModule("StarterPlayer/StarterPlayerScripts/UI/Navigation")
local root = instance("Phone")
local shopRoot = instance("Shop")
local function selectable(name, parent)
	local object = instance(name)
	object.Parent = parent
	object.Visible = true
	object.Selectable = true
	function object:IsDescendantOf(ancestor) return self.Parent == ancestor end
	return object
end
local original = selectable("HUD", instance("HUDRoot"))
local phoneButton = selectable("App", root)
local shopButton = selectable("Tab", shopRoot)
guiService.SelectedObject = original
local phoneLease = Navigation.Acquire(root, 100, phoneButton)
local shopLease = Navigation.Acquire(shopRoot, 200, shopButton)
check(guiService.SelectedObject == shopButton, "Shop takes focus above the phone")
phoneLease.Focus(phoneButton)
phoneLease.Release(); phoneLease.Release()
check(guiService.SelectedObject == shopButton and guiService.GuiNavigationEnabled, "Releasing the phone cannot restore flags over an open shop")
shopLease.Release()
check(guiService.SelectedObject == original and not guiService.GuiNavigationEnabled and not guiService.AutoSelectGuiEnabled, "Last panel restores original focus and flags")
phoneLease = Navigation.Acquire(root, 100, phoneButton)
shopLease = Navigation.Acquire(shopRoot, 200, shopButton)
shopLease.Release()
check(guiService.SelectedObject == phoneButton, "Closing the top panel resumes lower navigation")
phoneLease.Focus(shopButton)
check(guiService.SelectedObject == phoneButton, "A panel cannot select another panel's control")
phoneButton.Parent = nil
phoneLease.Release()
check(guiService.SelectedObject == original, "Destroyed panel controls do not prevent final restoration")

print(string.format("PASS: %d UI contract assertions", testCount))
