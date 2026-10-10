--!strict
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local Scope=require(ReplicatedStorage.Shared.UI.Scope)
local Theme=require(ReplicatedStorage.Shared.UI.Theme)
local player=Players.LocalPlayer
local scope=Scope.new()
local gui=Instance.new("ScreenGui");gui.Name="PoliceNotice";gui.ResetOnSpawn=false;gui.DisplayOrder=15
local label=Instance.new("TextLabel");label.Name="Notice"
label.AnchorPoint=Vector2.new(0.5,0);label.Position=UDim2.fromScale(0.5,0.08)
label.Size=UDim2.new(0.85,0,0,60);label.BackgroundColor3=Theme.Colors.Surface
label.TextColor3=Theme.Colors.Accent;label.Font=Theme.StrongFont;label.TextSize=18
label.TextWrapped=true;label.Visible=false;label.Parent=gui
local limit=Instance.new("UISizeConstraint");limit.MaxSize=Vector2.new(520,60);limit.Parent=label
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,Theme.Radius);corner.Parent=label
gui.Parent=player:WaitForChild("PlayerGui");scope:Give(gui)
local alive=true;local generation=0
local function update()
 generation+=1;local token=generation
 if player:GetAttribute("PoliceState")=="ARRESTED" then
  label.Visible=true
  local function countdown()
   if not alive or generation~=token then return end
   local untilTime=player:GetAttribute("PoliceArrestUntil")
   local seconds=if typeof(untilTime)=="number" then math.max(0,math.ceil(untilTime-Workspace:GetServerTimeNow())) else 0
   label.Text="Zatrzymanie przez policję · Zwolnienie za "..seconds.." s"
   if seconds>0 then task.delay(1,countdown) end
  end
  countdown()
 elseif player:GetAttribute("PoliceStopRequested")~=nil then
  label.Visible=true;label.Text="POLICJA · Zwolnij i zatrzymaj hulajnogę."
 else label.Visible=false end
end
for _,name in {"PoliceState","PoliceArrestUntil","PoliceStopRequested"} do scope:Give(player:GetAttributeChangedSignal(name):Connect(update)) end
scope:Give(function() alive=false;generation+=1 end)
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
update()
