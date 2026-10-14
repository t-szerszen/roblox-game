--!strict

local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UI = require(ReplicatedStorage.Shared.UI.Components)

type Entry = {
	frame: Frame,
	card: CanvasGroup,
	text: TextLabel,
	scope: Scope.Scope,
	resetTimer: (customDuration: number?) -> (),
}

local Feedback = {}

-- Wheelie HUD aesthetic styling:
local ToastColors = table.freeze({
	Background = Color3.fromRGB(16, 44, 70),
	Border = Color3.fromRGB(64, 120, 150),
	Accent = Color3.fromRGB(110, 236, 170),
	Error = Color3.fromRGB(255, 110, 110),
	Text = Color3.fromRGB(245, 248, 255),
	Stroke = Color3.fromRGB(14, 22, 30),
})

function Feedback.new(gui: ScreenGui, owner: Scope.Scope)
	local host = UI.Frame(gui, "Notifications")
	host.BackgroundTransparency = 1
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Position = UDim2.new(0.5, 0, 0, 14)
	host.Size = UDim2.new(1, -24, 0, 0)
	host.AutomaticSize = Enum.AutomaticSize.Y
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, math.huge)
	limit.Parent = host
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
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

	local function show(message: string, isError: boolean?, durationSec: number?)
		if not alive or message == "" then return end
		if #queue >= Theme.Toast.Maximum then remove(queue[1]) end
		sequence += 1
		local scope = Scope.new()
		local accentColor = if isError then ToastColors.Error else ToastColors.Accent

		-- Root frame satisfies UI contract tests (child:IsA("Frame")) and auto-layouts cleanly
		local frame = Instance.new("Frame")
		frame.Name = "Toast"
		frame.LayoutOrder = sequence
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.Parent = host
		scope:Give(frame)

		-- Sleek card styled like the wheelie HUD with canvas group for smooth animations
		local card = Instance.new("CanvasGroup")
		card.Name = "Card"
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, -18)
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = ToastColors.Background
		card.BackgroundTransparency = 0.22
		card.BorderSizePixel = 0
		card.GroupTransparency = 1
		card.Parent = frame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0.25),
		})
		gradient.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = accentColor
		stroke.Thickness = 1.4
		stroke.Transparency = 0.3
		stroke.Parent = card

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.Parent = card

		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.Size = UDim2.new(1, 0, 0, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
		content.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.Parent = content

		local function makeLine(name: string)
			local line = Instance.new("Frame")
			line.Name = name
			line.BorderSizePixel = 0
			line.BackgroundColor3 = accentColor
			line.Size = UDim2.fromOffset(16, 3)
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(1, 0)
			round.Parent = line
			line.Parent = content
			return line
		end

		makeLine("LeftLine")

		local text = Instance.new("TextLabel")
		text.Name = "Message"
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextSize = 13
		text.TextColor3 = ToastColors.Text
		text.RichText = true
		text.Text = message
		text.TextWrapped = true
		text.AutomaticSize = Enum.AutomaticSize.XY
		text.Size = UDim2.new(0, 0, 0, 0)
		text.Parent = content

		local textStroke = Instance.new("UIStroke")
		textStroke.Color = ToastColors.Stroke
		textStroke.Thickness = 1.2
		textStroke.Transparency = 0.3
		textStroke.Parent = text

		makeLine("RightLine")

		local clickArea = Instance.new("TextButton")
		clickArea.Name = "DismissArea"
		clickArea.BackgroundTransparency = 1
		clickArea.Size = UDim2.fromScale(1, 1)
		clickArea.Text = ""
		clickArea.Parent = card

		-- Smooth entrance animation: slides down from top while fading in
		local enterTween = TweenService:Create(
			card,
			TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 0), GroupTransparency = 0 }
		)
		enterTween:Play()

		-- Smooth auto-dismissal animation: slides up while fading out
		local isDismissing = false
		local activeExitTween: Tween? = nil

		local function dismiss()
			if isDismissing or not alive then return end
			isDismissing = true
			if activeExitTween then
				activeExitTween:Cancel()
				activeExitTween = nil
			end
			local tween = TweenService:Create(
				card,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, -18), GroupTransparency = 1 }
			)
			activeExitTween = tween
			tween:Play()

			local cleaned = false
			local function doCleanup()
				if cleaned then return end
				cleaned = true
				if isDismissing and alive then
					remove(entry)
					if frame.Parent then
						frame:Destroy()
					end
				end
			end

			tween.Completed:Once(doCleanup)
			task.delay(0.26, doCleanup)
		end

		scope:Give(clickArea.Activated:Connect(function()
			playClick()
			dismiss()
		end))

		local timer: thread? = nil
		local function startTimer(customDuration: number?)
			if timer and coroutine.status(timer) ~= "dead" then task.cancel(timer) end
			if activeExitTween then
				activeExitTween:Cancel()
				activeExitTween = nil
			end
			isDismissing = false
			card.GroupTransparency = 0
			card.Position = UDim2.new(0.5, 0, 0, 0)

			local targetDuration = customDuration or (if isError then Theme.Toast.ErrorDuration else 2.0)
			timer = task.delay(targetDuration, dismiss)
		end

		startTimer(durationSec or (if isError then nil else 2.0))

		scope:Give(function()
			if timer and coroutine.status(timer) ~= "dead" then task.cancel(timer) end
			if activeExitTween then activeExitTween:Cancel() end
		end)

		local entry: Entry = {
			frame = frame,
			card = card,
			text = text,
			scope = scope,
			resetTimer = startTimer,
		}
		table.insert(queue, entry)
	end

	local function replace(message: string, isError: boolean?, durationSec: number?)
		if not alive or message == "" then return end
		if #queue > 0 then
			local currentEntry = queue[#queue]
			if currentEntry and currentEntry.card.Parent and currentEntry.frame.Parent then
				currentEntry.text.Text = message
				local accentColor = if isError then ToastColors.Error else ToastColors.Accent
				local stroke = currentEntry.card:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Color = accentColor end
				for _, line in currentEntry.card:GetDescendants() do
					if line.Name == "LeftLine" or line.Name == "RightLine" then
						line.BackgroundColor3 = accentColor
					end
				end
				currentEntry.resetTimer(durationSec or 2.0)
				currentEntry.card.Position = UDim2.new(0.5, 0, 0, -4)
				currentEntry.card.GroupTransparency = 0
				TweenService:Create(
					currentEntry.card,
					TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.new(0.5, 0, 0, 0), GroupTransparency = 0 }
				):Play()
				return
			end
		end
		show(message, isError, durationSec or 2.0)
	end

	return {
		Click = playClick,
		Show = show,
		Replace = replace,
		Clear = function()
			while #queue > 0 do remove(queue[1]) end
		end,
	}
end

return Feedback
