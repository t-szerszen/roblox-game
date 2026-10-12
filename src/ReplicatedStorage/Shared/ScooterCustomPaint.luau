--!strict
local Config = require(script.Parent:WaitForChild("ScooterCustomConfig"))
local Paint = {}
type ColorTarget = SurfaceAppearance | BasePart
function Paint.Targets(model: Model): {[string]: {ColorTarget}}
 local targets: {[string]: {ColorTarget}} = {}
 local parts: {[string]: {BasePart}} = {}
 for _,part in model:GetDescendants() do
  if part:IsA("BasePart") then
   parts[part.Name]=parts[part.Name] or {}
   table.insert(parts[part.Name],part)
  end
 end
 for _,group in Config.Groups do
  local list: {ColorTarget} = {}
  for _,name in group.Parts do
   for _,part in parts[name] or {} do
   if part:IsA("BasePart") and (part:GetAttribute(Config.Attribute) == group.Id or (group.Mode=="WholePart" and part:GetAttribute(Config.Attribute)==nil)) then
    local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
    if part:GetAttribute("ScooterCustomSolidColor") == true then
     table.insert(list, part)
    elseif group.Mode == "WholePart" then
     -- Tint the existing texture/material; keep mesh, roughness and normal maps intact.
     table.insert(list, if appearance then appearance else part)
    elseif appearance and appearance.AlphaMode == Enum.AlphaMode.TintMask then
     table.insert(list, appearance)
    end
   end
   end
  end
  targets[group.Id] = list
 end
 return targets
end
function Paint.Read(model: Model): {[string]: Color3}
 local colors = {}
 for id, list in Paint.Targets(model) do if list[1] then colors[id] = list[1].Color end end
 return colors
end
function Paint.Apply(model: Model, colors: {[string]: Color3})
 for id, list in Paint.Targets(model) do
  local color = colors[id]
  if color then
   for _,appearance in list do
    if appearance:IsA("SurfaceAppearance") then appearance.Color = color
    else appearance.Color = color end
   end
  end
 end
end
return Paint
