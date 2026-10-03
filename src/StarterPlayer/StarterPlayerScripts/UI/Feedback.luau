--!strict

local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UI = require(ReplicatedStorage.Shared.UI.Components)
type Entry = { frame: Frame, scope: Scope.Scope }

local Feedback = {}

function Feedback.new(gui: ScreenGui, owner: Scope.Scope)
	local host = UI.Frame(gui, "Notifications")
	host.BackgroundTransparency = 1
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Position = UDim2.new(0.5, 0, 0, 12)
	host.Size = UDim2.new(1, -24, 0, 0)
	host.AutomaticSize = Enum.AutomaticSize.Y
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(430, math.huge)
	limit.Parent = host
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = host
	local click = Instance.new("Sound")
	click.Name = "UIClick"
	click.SoundId = Theme.Audio.ClickId
	click.Volume = Theme.Audio.Volume
	click.PlaybackSpeed = Theme.Audio.PlaybackSpeed
	click.Parent = SoundService
	owner:Give(click)
	local queue: { Entry } = {}
	local sequence = 0
	local alive = true
	local function playClick()
		if alive and click.SoundId ~= "" then
			click:Stop()
			click:Play()
		end
	end
	local function remove(entry: Entry)
		local index = table.find(queue, entry)
		if not index then return end
		table.remove(queue, index)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(entry.frame) then GuiService.SelectedObject = nil end
		entry.scope:Clean()
	end
	owner:Give(function()
		alive = false
		while #queue > 0 do remove(queue[1]) end
		host:Destroy()
	end)
	return {
		Click = playClick,
		Show = function(message: string, isError: boolean?)
			if not alive or message == "" then return end
			if #queue >= Theme.Toast.Maximum then remove(queue[1]) end
			sequence += 1
			local scope = Scope.new()
			local frame = UI.Frame(host, "Toast", Theme.Colors.Raised)
			frame.LayoutOrder = sequence
			frame.Size = UDim2.new(1, 0, 0, 88)
			UI.Corner(frame)
			UI.Stroke(frame, if isError then Theme.Colors.Error else Theme.Colors.Success, 0.25)
			scope:Give(frame)
			local text = UI.Label(frame, message, 14)
			text.Position = UDim2.fromOffset(16, 10)
			text.Size = UDim2.new(1, -80, 1, -20)
			text.TextWrapped = true
			local entry: Entry = { frame = frame, scope = scope }
			table.insert(queue, entry)
			local close = UI.Button(frame, "×", scope, function() playClick(); remove(entry) end)
			close.Name = "Dismiss"
			close.TextSize = 24
			close.AnchorPoint = Vector2.new(1, 0.5)
			close.Position = UDim2.new(1, -10, 0.5, 0)
			close.Size = UDim2.fromOffset(Theme.TouchTarget, Theme.TouchTarget)
			local timer = task.delay(if isError then Theme.Toast.ErrorDuration else Theme.Toast.Duration, function()
				remove(entry)
			end)
			scope:Give(function()
				if timer ~= coroutine.running() and coroutine.status(timer) ~= "dead" then task.cancel(timer) end
			end)
		end,
	}
end

return Feedback
