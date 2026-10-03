--!strict

local GuiService = game:GetService("GuiService")

export type Lease = { Focus: (GuiObject?) -> (), Release: () -> () }
type Entry = { root: GuiObject, priority: number, selection: GuiObject? }
local entries: { Entry } = {}
local savedSelection: GuiObject? = nil
local savedNavigation = false
local savedAutoSelect = false
local Navigation = {}

local function top(): Entry?
	local result: Entry? = nil
	for _, entry in entries do
		if not result or entry.priority >= result.priority then result = entry end
	end
	return result
end

local function selectable(object: GuiObject?): boolean
	return object ~= nil and object.Parent ~= nil and object.Visible and object.Selectable
end

function Navigation.Acquire(root: GuiObject, priority: number, selection: GuiObject?): Lease
	if #entries == 0 then
		savedSelection = GuiService.SelectedObject
		savedNavigation = GuiService.GuiNavigationEnabled
		savedAutoSelect = GuiService.AutoSelectGuiEnabled
	end
	local entry: Entry = { root = root, priority = priority, selection = selection }
	table.insert(entries, entry)
	GuiService.GuiNavigationEnabled = true
	GuiService.AutoSelectGuiEnabled = true
	if top() == entry then GuiService.SelectedObject = if selectable(selection) then selection else nil end
	local released = false
	return {
		Focus = function(object: GuiObject?)
			if released then return end
			if object and object ~= root and not object:IsDescendantOf(root) then return end
			entry.selection = object
			if top() == entry then GuiService.SelectedObject = if selectable(object) then object else nil end
		end,
		Release = function()
			if released then return end
			released = true
			local wasTop = top() == entry
			local index = table.find(entries, entry)
			if index then table.remove(entries, index) end
			local remaining = top()
			if remaining then
				if wasTop then
					GuiService.SelectedObject = if selectable(remaining.selection) then remaining.selection else nil
				end
			else
				GuiService.SelectedObject = if selectable(savedSelection) then savedSelection else nil
				GuiService.GuiNavigationEnabled = savedNavigation
				GuiService.AutoSelectGuiEnabled = savedAutoSelect
				savedSelection = nil
			end
		end,
	}
end

return Navigation
