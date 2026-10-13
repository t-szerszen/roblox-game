--!strict
local Catalog = require(game:GetService("ReplicatedStorage").Shared.ScooterUpgradeCatalog)
local Visuals = {}

function Visuals.Create(model: Model)
 local saved: {[Instance]: any} = {}
 local motorVisual: MeshPart? = nil
 local function remember(part: BasePart)
  if not saved[part] then saved[part] = {transparency=part.Transparency, size=part.Size} end
 end
 local function hide(root: Instance?, hidden: boolean)
  if not root then return end
  local objects = root:GetDescendants()
  table.insert(objects, root)
  for _,part in objects do
   if part:IsA("BasePart") then
    remember(part)
    part.Transparency = if hidden then 1 else saved[part].transparency
   elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") then
    if not saved[part] then saved[part] = {enabled=part.Enabled} end
    local state: any = saved[part]
    local gui = part :: LayerCollector
    gui.Enabled = if hidden then false else state.enabled
   end
  end
 end
 return {
  Apply=function(equipped: {[string]: boolean})
   for _,name in {"BackFender", "FrontFender"} do hide(model:FindFirstChild(name), equipped.WheelieMode == true) end
   for _,name in {"Display", "ScooterDashboard", "FrontLight"} do hide(model:FindFirstChild(name), false) end
   for _,part in model:GetDescendants() do
    if part:IsA("BasePart") and (part.Name == "BrakeDisc" or part.Name:find("BrakeCaliper",1,true)
     or part:GetAttribute("ScooterCustomGroup") == "BrakeDiscs") then
     remember(part)
     local disc = part.Name == "BrakeDisc" or part:GetAttribute("ScooterCustomGroup") == "BrakeDiscs"
     local factor = if equipped.Brakes then (if disc then Catalog.BrakeVisualScale else Catalog.CaliperVisualScale) else 1
     part.Size = saved[part].size * factor
    end
   end
   local front, rear = model:FindFirstChild("FrontWheel"), model:FindFirstChild("BackWheel")
   if front and front:IsA("MeshPart") and rear and rear:IsA("MeshPart") then
    if equipped.DualMotor and not motorVisual then
     local clone = rear:Clone()
     for _,child in clone:GetChildren() do
      if not child:IsA("SurfaceAppearance") then child:Destroy() end
     end
     clone.Name="UpgradeFrontMotorVisual"
     clone.CFrame=front.CFrame
     clone.Size=Vector3.new(front.Size.X,front.Size.Y,rear.Size.Z)
     clone.Massless=true
     clone.Anchored=false
     clone.CanCollide=false
     clone.CanTouch=false
     clone.CanQuery=false
     local weld=Instance.new("WeldConstraint")
     weld.Part0=front
     weld.Part1=clone
     weld.Parent=clone
     clone.Parent=model
     motorVisual=clone
    elseif not equipped.DualMotor and motorVisual then
     motorVisual:Destroy()
     motorVisual=nil
    end
    hide(front,equipped.DualMotor == true)
   end
  end,
  Destroy=function()
   if motorVisual then
    motorVisual:Destroy()
    motorVisual=nil
   end
   table.clear(saved)
  end,
 }
end

return Visuals

