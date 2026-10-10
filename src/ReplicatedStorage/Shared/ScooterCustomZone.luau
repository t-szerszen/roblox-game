--!strict
local Zone = {}
function Zone.Contains(part: BasePart, position: Vector3, margin: number?): boolean
 if not part:IsDescendantOf(workspace) then return false end
 local p = part.CFrame:PointToObjectSpace(position)
 local half = part.Size / 2 + Vector3.one * (margin or 0)
 return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end
return Zone
