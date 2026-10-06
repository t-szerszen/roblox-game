--!strict

local RunService = game:GetService("RunService")
local DevRoadPaint = {}

-- Explicit authoring repair: floating paper-thin imported paint is not pavement.
-- Keep the original collision flag on each part so the edit can be reversed.
function DevRoadPaint.MakeCrosswalksDecorative(map: Instance): number
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run in Studio Edit mode")
	local changed = 0
	for _, group in map:GetDescendants() do
		if group.Name ~= "Zebra crossing lines" then continue end
		for _, part in group:GetDescendants() do
			if not part:IsA("BasePart") then continue end
			if part:GetAttribute("RoadPaintPreviousCanCollide") == nil then
				part:SetAttribute("RoadPaintPreviousCanCollide", part.CanCollide)
			end
			if part.CanCollide then changed += 1 end
			part.CanCollide = false
		end
	end
	return changed
end

return DevRoadPaint
