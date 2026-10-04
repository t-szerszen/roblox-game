--!strict

local RunService = game:GetService("RunService")
type Tool = { UpdateSelection: () -> SurfaceGui }
local Workflow = {}

function Workflow.Update(): SurfaceGui
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play before updating the dashboard")
	-- Reload the tool because earlier Create/Mount calls may cache its old version.
	local source = script.Parent:FindFirstChild("DevScooterDashboard")
	assert(source and source:IsA("ModuleScript"), "Sync DevScooterDashboard through Rojo first")
	local fresh = source:Clone()
	fresh.Parent = script.Parent
	local ok, result = pcall(function(): SurfaceGui
		return (require(fresh) :: Tool).UpdateSelection()
	end)
	fresh:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: SurfaceGui
end

return Workflow
