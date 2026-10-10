--!nonstrict
-- Edit mode: Run(the preserved installed large-wheel template before rider fitting).
local Fit = require(game.ServerScriptService.Scooter.DevScooterRiderFit)
local Settings = require(game.ServerScriptService.Scooter.DevScooterRiderFitConfig)
local Geometry = require(game.ServerScriptService.Scooter.ScooterRigGeometry)
local Paint = require(game.ReplicatedStorage.Shared.ScooterCustomPaint)
local Tests = {}

function Tests.Run(source)
 local count = 0
 local function check(value, message) assert(value, message); count += 1 end
 local fitted = Fit.Build(source)
 local ok, problem = pcall(function()
  for _,name in {"Root", "DriverSeat", "FootRest", "DeckCollider", "BackWheelCollider", "BackWheel", "VirtualBackAxle"} do
   local a,b = source[name], fitted[name]
   check(a.CFrame == b.CFrame and a.Size == b.Size and a.CanCollide == b.CanCollide, name .. " is preserved")
  end
  local delta = source.PrimaryPart.CFrame:VectorToWorldSpace(fitted:GetAttribute("RiderFitFrontOffset"))
  for _,name in {"FrontFork", "FrontWheel", "VirtualFrontAxle", "FrontWheelCollider", "FrontSuspensionLeft", "FrontSuspensionRight", "FrontSpringVisual"} do
   local a,b = source[name], fitted[name]
   check((b.Position-a.Position-delta).Magnitude < .0001, name .. " moves with front module")
   check(a.Size == b.Size and a.CanCollide == b.CanCollide and math.abs(a:GetMass()-b:GetMass()) < .0001,
    name .. " dimensions, collision and mass remain intact")
  end
  check((source.HandleBarStick.CFrame.UpVector-fitted.HandleBarStick.CFrame.UpVector).Magnitude < .00001,
   "Shaft retains original straight axis")
  check(math.abs(source.HandleBarStick:GetMass()-fitted.HandleBarStick:GetMass()) < .0001, "Shaft retains mass")
  for _,a in source.HandleBarStick:GetChildren() do
   if a:IsA("Attachment") then
    local b=fitted.HandleBarStick[a.Name]
    check((b.WorldPosition-a.WorldPosition-delta).Magnitude < .0001, a.Name .. " follows front module")
    check(a.WorldAxis:Dot(b.WorldAxis) > .99999, a.Name .. " axis unchanged")
   end
  end
  local upper = source.PrimaryPart.CFrame:VectorToWorldSpace(Settings.HandlebarOffset)
  for _,name in {"HandleBar", "LeftGrip", "RightGrip", "BrakeLeverLeft", "BrakeLeverRight", "Display", "FrontLight"} do
   check((fitted[name].Position-source[name].Position-upper).Magnitude < .0001, name .. " preserves accepted rider target")
  end
  check(fitted.ScooterBody.Transparency == 1, "Obsolete one-piece neck is hidden")
  check(fitted.RiderFitBody.SteeringHead ~= nil, "Single visible steering head is present")
  local root = fitted.PrimaryPart
  local deck = fitted.RiderFitBody.DeckSurface
  check(math.abs(root.CFrame:PointToObjectSpace(deck.Position).Y+deck.Size.Y*.5-Settings.DeckTop) < .0001,
   "Visible deck top matches rider support plane")
  local stem = fitted.HandleBarStick
  local pivot = fitted.ScooterBody.SteerBase.WorldPosition
  local toPivot = pivot-stem.Position
  local radial = (toPivot-stem.CFrame.UpVector*toPivot:Dot(stem.CFrame.UpVector)).Magnitude
  check(radial < Settings.CollarDiameter*.5, "Real steering axis sits inside visible collar")
  local report = Geometry.Check(fitted)
  check(#report.errors == 0, table.concat(report.errors, "; "))
  for _,item in fitted:GetDescendants() do
   if item:IsA("WeldConstraint") then
    check(item.Part0 and item.Part1 and item.Part0:IsDescendantOf(fitted) and item.Part1:IsDescendantOf(fitted),
     "Weld endpoints remain inside model")
   elseif item:IsA("HingeConstraint") or item:IsA("SpringConstraint") then
    check(item.Attachment0 and item.Attachment1, "Mechanical endpoints remain connected")
   end
  end
  for _,item in fitted.RiderFitBody:GetChildren() do
   if item:IsA("BasePart") then
    check(item.Massless and not item.CanCollide and not item.CanTouch and not item.CanQuery, "Body decoration has no contact or added mass")
   end
  end
  local neutral = {}
  for _,item in fitted:GetDescendants() do
   if item:IsA("WeldConstraint") then item.Enabled = false
   elseif item:IsA("BasePart") then
    local group = item:GetAttribute("ScooterAssembly")
    if group == "steering" or group == "front" or group == "frontWheel" or item.Name == "FrontWheelCollider" then
     neutral[item] = item.CFrame
    end
   end
  end
  local axis = fitted.ScooterBody.SteerBase.WorldAxis.Unit
  for _,angle in {-48,-20,20,48} do
   local turn = CFrame.new(pivot)*CFrame.fromAxisAngle(axis, math.rad(angle))*CFrame.new(-pivot)
   for item,frame in neutral do item.CFrame = turn*frame end
   local turned = Geometry.Check(fitted)
   check(#turned.errors == 0, "Remodeled joints remain aligned at steering angle " .. angle)
  end
  local targets = Paint.Targets(fitted)
  check(#targets.Deck >= 2, "New panels remain paintable")
  local stemColor = Paint.Read(fitted).Stem
  local color = Color3.fromRGB(80,130,190)
  Paint.Apply(fitted, {Deck=color})
  check(fitted.RiderFitBody.BatteryPanelLeft.Color == color and fitted.RiderFitBody.BatteryPanelRight.Color == color,
   "Both panels accept deck customization")
  check(Paint.Read(fitted).Stem == stemColor, "Deck painting preserves stem finish")
  check(not pcall(function() Fit.Build(fitted) end), "Repeated remodeling is rejected")
 end)
 fitted:Destroy()
 assert(ok, problem)
 print(string.format("PASS: %d native scooter rider remodel assertions",count))
 return count
end
return Tests
