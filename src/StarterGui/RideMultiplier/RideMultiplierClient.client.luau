--!strict
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local SharedUI=ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local UI=require(SharedUI.Components)
local Theme=require(SharedUI.Theme)
local Scope=require(SharedUI.Scope)
local Config=require(ReplicatedStorage.Shared.Activity.EconomyConfig)
local player=Players.LocalPlayer
local gui=script.Parent :: ScreenGui
gui.DisplayOrder=4
local scope=Scope.new()
local panel=UI.Frame(gui,"Multiplier")
panel.AnchorPoint=Vector2.new(0.5,0)
panel.Position=UDim2.new(0.5,0,0,16)
panel.Size=UDim2.new(0.9,0,0,48)
local size=Instance.new("UISizeConstraint");size.MaxSize=Vector2.new(240,48);size.Parent=panel
UI.Corner(panel);local border=UI.Stroke(panel)
local label=UI.Label(panel,"MULTIPLIER  x1.0",18)
label.Font=Theme.StrongFont;label.TextXAlignment=Enum.TextXAlignment.Center;label.Size=UDim2.fromScale(1,1)
local value=Instance.new("NumberValue");value.Value=1;scope:Give(value)
local tween: Tween?=nil
scope:Give(function() if tween then tween:Cancel() end end)
scope:Give(value.Changed:Connect(function(current: number) label.Text=string.format("MULTIPLIER  x%.1f",current) end))
local function update()
	panel.Visible=player:GetAttribute("RideRewardActive")==true
	local multiplier=player:GetAttribute("RideRewardMultiplier")
	local target=if typeof(multiplier)=="number" then math.clamp(multiplier,1,Config.WheelieMaxMultiplier) else 1
	local maximum=target>=Config.WheelieMaxMultiplier
	label.TextColor3=if maximum then Color3.fromRGB(255,214,90) else Theme.Colors.Text
	border.Color=if maximum then Color3.fromRGB(255,214,90) else Theme.Colors.Border
	if tween then tween:Cancel() end
	tween=TweenService:Create(value,TweenInfo.new(0.2),{Value=target});tween:Play()
end
scope:Give(player:GetAttributeChangedSignal("RideRewardActive"):Connect(update))
scope:Give(player:GetAttributeChangedSignal("RideRewardMultiplier"):Connect(update))
scope:Give(gui.Destroying:Connect(function() scope:Clean() end))
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
update()
