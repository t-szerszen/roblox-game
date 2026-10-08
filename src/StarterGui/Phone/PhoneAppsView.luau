--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhoneConfig = require(ReplicatedStorage.Shared.Phone.PhoneConfig)
local Types = require(ReplicatedStorage.Shared.Phone.PhoneTypes)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Style = require(ReplicatedStorage.Shared.Phone.PhoneTheme)
local Components = require(script.Parent.PhoneComponents)
local GangAppView = require(script.Parent.GangAppView)

export type Actions = { Action: (string, unknown) -> (), Draft: (string) -> () }
local AppsView = {}

function AppsView.Render(parent: Instance, scope: Scope.Scope, page: Types.Page, state: Types.State, draft: string, actions: Actions): TextBox?
	local order = 0
	local palettes: { [string]: { Top: Color3, Bottom: Color3 } } = Style.Apps
	local palette = palettes[page]
	local accent = if page == "Gang" then state.gang.gangColor or Style.Apps.Gang.Top
		elseif palette then palette.Top else Style.Accent
	local function card(name: string, title: string, detail: string, rowAccent: Color3?): Frame
		order += 1
		local row = Components.Frame(parent, name)
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		Components.Corner(row, 12)
		Components.Stroke(row, nil, 0.65)
		local stripe = Components.Frame(row, "Accent", rowAccent or accent)
		stripe.AnchorPoint = Vector2.new(0, 0.5)
		stripe.Position = UDim2.fromScale(0, 0.5)
		stripe.Size = UDim2.new(0, 3, 1, -8)
		Components.Corner(stripe, 2)
		-- Keep decorations outside the list so they cannot change card measurement.
		local body = Components.Frame(row, "Details")
		body.BackgroundTransparency = 1
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 12)
		padding.PaddingBottom = UDim.new(0, 12)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = body
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 8)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = body
		local function text(value: string, size: number, muted: boolean, index: number)
			local label = Components.Label(body, value, size, muted)
			label.Size = UDim2.new(1, 0, 0, 0)
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.TextWrapped = true
			label.LayoutOrder = index
			if index == 2 then label.Name = "Detail" end
			if not muted then label.Font = Enum.Font.GothamBold end
		end
		text(title, 16, false, 1)
		text(detail, 13, true, 2)
		return body
	end
	local function action(row: Frame, name: string, text: string, command: string, payload: unknown, available: boolean, primary: boolean?): TextButton
		local button = Components.Button(row, text, scope, function() actions.Action(command, payload) end, primary, if palette then palette.Bottom else accent)
		button.BackgroundColor3 = if command == "SpawnScooter" then (if available then Color3.fromRGB(0, 140, 200) else Color3.fromRGB(50, 50, 55))
			elseif command == "SetPassive" then (if not available then Color3.fromRGB(70, 70, 75) elseif state.passiveEnabled then Style.Error else Style.Success)
			elseif command == "KickGangMember" or command == "LeaveGang" or ((command == "RespondGangInvite" or command == "RespondGangRequest") and primary == false) then Style.Error
			elseif command == "InviteGangMember" or command == "RespondGangInvite" or command == "RespondGangRequest" then Color3.fromRGB(40, 180, 60)
			else button.BackgroundColor3
		button.Name = name
		button.LayoutOrder = 4
		button.Size = UDim2.new(1, 0, 0, Theme.TouchTarget)
		button:SetAttribute("PhoneAction", true)
		button:SetAttribute("Available", available)
		Components.SetEnabled(button, available)
		return button
	end
	if page == "Scooters" then
		local owned: { [string]: boolean } = {}
		for _, name in state.ownedScooters do owned[name] = true end
		for _, product in ShopConfig.CoinProducts do
			local available = owned[product.name] == true
			local row = card(product.id, product.name, product.description, if available then Color3.fromRGB(0, 200, 245) else Color3.fromRGB(70, 70, 75))
			action(row, "Spawn", if available then "Przywołaj" else "Dostępna w sklepie", "SpawnScooter", product.name, available, true)
		end
	elseif page == "Delivery" then
		if state.delivery.active then
			card("Destination", "Cel dostawy", state.delivery.destination)
			card("Distance", "Pozostały dystans", string.format("%d studów", math.floor(state.delivery.distance)))
		else
			card("NoDelivery", "Brak zlecenia", "Znajdź punkt odbioru paczek na mapie, aby rozpocząć dostawę.")
		end
	elseif page == "Daily" then
		card("Login", "Seria logowań", string.format("Dzień %d/7", state.loginStreak))
		local byId: { [string]: number } = {}
		for _, mission in state.daily do byId[mission.id] = mission.progress end
		for _, mission in PhoneConfig.DailyMissions do
			local value = byId[mission.id] or 0
			local row = card(mission.id, mission.name, string.format("%g / %g %s", value, mission.target, mission.unit))
			local track = Components.Frame(row, "Progress", Style.Raised)
			track.Size = UDim2.new(1, 0, 0, 5)
			track.LayoutOrder = 3
			Components.Corner(track, 3)
			local fill = Components.Frame(track, "Fill", Style.Success)
			fill.Size = UDim2.fromScale(math.clamp(value / mission.target, 0, 1), 1)
			Components.Corner(fill, 3)
		end
	elseif page == "Protection" then
		local row = card("Protection", if state.passiveEnabled then "Ochrona włączona" else "Ochrona wyłączona",
			if state.passiveAvailable then "Ochrona blokuje walkę i udział w przejmowaniu flag, także w gangu." else "Poczekaj na wczytanie danych.",
			if not state.passiveAvailable then Style.Error elseif state.passiveEnabled then Style.Success else Color3.fromRGB(130, 130, 135))
		action(row, "TogglePassive", if state.passiveEnabled then "Wyłącz ochronę" else "Włącz ochronę", "SetPassive", not state.passiveEnabled, state.passiveAvailable, true)
	elseif page == "Gang" then
		return GangAppView.Render(scope, state, draft, actions, card, action)
	end
	return nil
end

return AppsView
