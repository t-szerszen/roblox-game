--!strict
-- Wheelie HUD: shows server-measured wheelie time, distance, money multiplier and personal best.
-- Visible only while wheeling; keeps the final result for Config.HideDelay before fading out.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local SharedUI=ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Scope=require(SharedUI.Scope)
local Config=require(SharedUI:WaitForChild("WheelieHUDConfig"))
local Economy=require(ReplicatedStorage.Shared.Activity.EconomyConfig)
local player=Players.LocalPlayer
local gui=script.Parent :: ScreenGui
gui.DisplayOrder=Config.DisplayOrder
gui.IgnoreGuiInset=true
local scope=Scope.new()
local Colors=Config.Colors

local panel=Instance.new("CanvasGroup")
panel.Name="Wheelie"
panel.AnchorPoint=Vector2.new(0.5,0)
panel.Position=UDim2.new(0.5,0,0,Config.TopOffset)
panel.Size=UDim2.new(Config.WidthScale,0,0,Config.Height)
panel.BackgroundColor3=Colors.Background
panel.BackgroundTransparency=Config.BackgroundTransparency
panel.BorderSizePixel=0
panel.GroupTransparency=1
panel.Visible=false
panel.Parent=gui
scope:Give(panel)
local sizeLimit=Instance.new("UISizeConstraint");sizeLimit.MaxSize=Vector2.new(Config.Width,Config.Height);sizeLimit.Parent=panel
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,Config.CornerRadius);corner.Parent=panel
local shade=Instance.new("UIGradient");shade.Rotation=90
shade.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,0.25)});shade.Parent=panel
local popScale=Instance.new("UIScale");popScale.Parent=panel
local padding=Instance.new("UIPadding")
padding.PaddingTop=UDim.new(0,Config.Padding);padding.PaddingBottom=UDim.new(0,Config.Padding);padding.Parent=panel
local list=Instance.new("UIListLayout")
list.FillDirection=Enum.FillDirection.Vertical
list.HorizontalAlignment=Enum.HorizontalAlignment.Center
list.VerticalAlignment=Enum.VerticalAlignment.Center
list.SortOrder=Enum.SortOrder.LayoutOrder
list.Padding=UDim.new(0,1)
list.Parent=panel

local function outline(label: TextLabel)
	local stroke=Instance.new("UIStroke")
	stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual
	stroke.Color=Colors.Stroke
	stroke.Thickness=Config.StrokeThickness or 1.4
	stroke.Transparency=Config.TextStrokeTransparency
	stroke.Parent=label
end
local function text(name: string, order: number, size: number, color: Color3, parent: Instance?): TextLabel
	local label=Instance.new("TextLabel")
	label.Name=name
	label.LayoutOrder=order
	label.BackgroundTransparency=1
	label.Font=Config.Font
	label.TextSize=size
	label.TextColor3=color
	label.Text=""
	label.AutomaticSize=Enum.AutomaticSize.X
	label.Size=UDim2.fromOffset(0,size+2)
	label.Parent=parent or panel
	outline(label)
	return label
end
local function bar(name: string, order: number, width: UDim, color: Color3, parent: Instance): Frame
	local frame=Instance.new("Frame")
	frame.Name=name
	frame.LayoutOrder=order
	frame.BorderSizePixel=0
	frame.BackgroundColor3=color
	frame.Size=UDim2.new(width,UDim.new(0,Config.LineThickness))
	frame.Parent=parent
	local round=Instance.new("UICorner");round.CornerRadius=UDim.new(1,0);round.Parent=frame
	return frame
end

local titleRow=Instance.new("Frame")
titleRow.Name="Title";titleRow.LayoutOrder=1;titleRow.BackgroundTransparency=1
titleRow.Size=UDim2.new(1,0,0,Config.TitleSize+4);titleRow.Parent=panel
local titleList=Instance.new("UIListLayout")
titleList.FillDirection=Enum.FillDirection.Horizontal
titleList.HorizontalAlignment=Enum.HorizontalAlignment.Center
titleList.VerticalAlignment=Enum.VerticalAlignment.Center
titleList.SortOrder=Enum.SortOrder.LayoutOrder
titleList.Padding=UDim.new(0,Config.TitlePadding or 8)
titleList.Parent=titleRow
bar("LeftLine",1,UDim.new(0,Config.LineWidth),Colors.Accent,titleRow)
local title=text("Label",2,Config.TitleSize,Colors.Accent,titleRow)
title.Text=Config.TitleText
bar("RightLine",3,UDim.new(0,Config.LineWidth),Colors.Accent,titleRow)

local timeLabel=text("Time",2,Config.TimeSize,Colors.Time)
local distanceLabel=text("Distance",3,Config.DistanceSize,Colors.Text)
local multiplierLabel=text("Multiplier",4,Config.MultiplierSize,Colors.Accent)
local bestLabel=text("Best",5,Config.BestSize,Colors.Text)
local track=Instance.new("Frame")
track.Name="Progress";track.LayoutOrder=6;track.BorderSizePixel=0
track.BackgroundColor3=Colors.Track
track.Size=UDim2.new(Config.BarWidth,0,0,Config.BarHeight);track.Parent=panel
local trackCorner=Instance.new("UICorner");trackCorner.CornerRadius=UDim.new(1,0);trackCorner.Parent=track
local fill=bar("Fill",1,UDim.new(0,0),Colors.Accent,track)
fill.Size=UDim2.new(0,0,1,0)

local function formatDistance(meters: number): string
	if meters<1000 then return string.format("%d m",math.floor(meters)) end
	return string.format("%.2f km",meters/1000)
end
local function numberAttribute(name: string): number
	local value=player:GetAttribute(name)
	return if typeof(value)=="number" and value==value then value else 0
end

-- Multiplier is authoritative on the server; the tween only smooths the 0.25 s steps.
local multiplierValue=Instance.new("NumberValue");multiplierValue.Value=1;scope:Give(multiplierValue)
local multiplierTween: Tween?=nil
local function renderMultiplier(current: number)
	local maximum=current>=Economy.WheelieMaxMultiplier-0.0001
	multiplierLabel.Text=string.format("x%.2f %s",current,Config.MoneyText)
	multiplierLabel.TextColor3=if maximum then Colors.Maximum else Colors.Accent
	fill.BackgroundColor3=multiplierLabel.TextColor3
	fill.Size=UDim2.new(math.clamp((current-1)/(Economy.WheelieMaxMultiplier-1),0,1),0,1,0)
end
scope:Give(multiplierValue.Changed:Connect(renderMultiplier))
local function updateMultiplier()
	if player:GetAttribute("RideWheelieActive")~=true then return end -- keep the final value while fading out
	local target=math.clamp(numberAttribute("RideRewardMultiplier"),1,Economy.WheelieMaxMultiplier)
	if multiplierTween then multiplierTween:Cancel() end
	multiplierTween=TweenService:Create(multiplierValue,TweenInfo.new(Config.MultiplierTween),{Value=target})
	multiplierTween:Play()
end

local serverSeconds,receivedAt,shownSeconds=0,os.clock(),0
local shownText=""
local function renderTime(seconds: number)
	shownSeconds=math.max(shownSeconds,seconds)
	local value=string.format("%.1fs",shownSeconds)
	if value~=shownText then shownText=value;timeLabel.Text=value end
end
local function updateSeconds()
	serverSeconds=numberAttribute("RideWheelieSeconds");receivedAt=os.clock()
	if player:GetAttribute("RideWheelieActive")==true then renderTime(serverSeconds) end
end
local function updateDistance()
	if player:GetAttribute("RideWheelieActive")==true then distanceLabel.Text=formatDistance(numberAttribute("RideWheelieMeters")) end
end
local function updateBest()
	local best=numberAttribute("LongestWheelie")
	bestLabel.Text=if best>0 then string.format("%s %.1fs",Config.BestText,best) else Config.BestText.." —"
end

local renderConnection: RBXScriptConnection?=nil
local hideThread: thread?=nil
local fadeTween: Tween?=nil
local function stopRender()
	if renderConnection then renderConnection:Disconnect();renderConnection=nil end
end
local function stopHide()
	if hideThread then task.cancel(hideThread);hideThread=nil end
end
local function fade(target: number, duration: number, scale: number): Tween
	if fadeTween then fadeTween:Cancel() end
	local info=TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
	TweenService:Create(popScale,info,{Scale=scale}):Play()
	local tween=TweenService:Create(panel,info,{GroupTransparency=target})
	fadeTween=tween;tween:Play()
	return tween
end
scope:Give(function()
	stopRender();stopHide()
	if fadeTween then fadeTween:Cancel() end
	if multiplierTween then multiplierTween:Cancel() end
end)

local function show()
	stopHide()
	shownSeconds=0;shownText=""
	if not panel.Visible then
		panel.Visible=true;popScale.Scale=Config.PopScale
		if multiplierTween then multiplierTween:Cancel() end
		multiplierValue.Value=1;renderMultiplier(1)
	end
	updateSeconds();updateDistance();updateMultiplier()
	fade(0,Config.FadeIn,1)
	if not renderConnection then
		-- Per-frame work exists only while the wheelie is active.
		renderConnection=RunService.RenderStepped:Connect(function()
			renderTime(serverSeconds+math.min(os.clock()-receivedAt,Config.MaxExtrapolationSeconds))
		end)
	end
end
local function finish()
	stopRender()
	if not panel.Visible or hideThread then return end
	-- Freeze on the last server value so the result never overstates the wheelie.
	shownSeconds=0;renderTime(serverSeconds)
	hideThread=task.delay(Config.HideDelay,function()
		hideThread=nil
		local tween=fade(1,Config.FadeOut,Config.PopScale)
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state==Enum.PlaybackState.Completed and player:GetAttribute("RideWheelieActive")~=true then panel.Visible=false end
		end)
	end)
end
local function updateActive()
	if player:GetAttribute("RideWheelieActive")==true then show() else finish() end
end

scope:Give(player:GetAttributeChangedSignal("RideWheelieActive"):Connect(updateActive))
scope:Give(player:GetAttributeChangedSignal("RideWheelieSeconds"):Connect(updateSeconds))
scope:Give(player:GetAttributeChangedSignal("RideWheelieMeters"):Connect(updateDistance))
scope:Give(player:GetAttributeChangedSignal("RideRewardMultiplier"):Connect(updateMultiplier))
scope:Give(player:GetAttributeChangedSignal("LongestWheelie"):Connect(updateBest))
scope:Give(gui.Destroying:Connect(function() scope:Clean() end))
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
renderMultiplier(1);updateBest()
if player:GetAttribute("RideWheelieActive")==true then show() end
