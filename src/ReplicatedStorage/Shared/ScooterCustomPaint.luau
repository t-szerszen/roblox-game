--!strict
local Config = require(script.Parent:WaitForChild("ScooterCustomConfig"))
local Paint = {}
type ColorTarget = SurfaceAppearance | BasePart
function Paint.Targets(model: Model): {[string]: {ColorTarget}}
 local targets: {[string]: {ColorTarget}} = {}
 local parts: {BasePart} = {}
 for _,part in model:GetDescendants() do
  if part:IsA("BasePart") then
   table.insert(parts,part)
  end
 end
 for _,group in Config.Groups do
  local list: {ColorTarget} = {}
  local ordered: {BasePart} = {}
  local seen: {[BasePart]: boolean} = {}
  -- Preserve legacy primary-color ordering, then include tagged compound parts.
  for _,name in group.Parts do
   for _,part in parts do
    if part.Name==name and not seen[part] then table.insert(ordered,part); seen[part]=true end
   end
  end
  for _,part in parts do
   if part:GetAttribute(Config.Attribute)==group.Id and not seen[part] then table.insert(ordered,part); seen[part]=true end
  end
  for _,part in ordered do
   local tag = part:GetAttribute(Config.Attribute)
   if tag == group.Id or (tag == nil and group.Mode=="WholePart" and table.find(group.Parts,part.Name)) then
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
