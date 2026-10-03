--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
type Repair = { RepairSelection: () -> Model }
local DevScooterSuspension = {}

function DevScooterSuspension.Apply(): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play and select the complete scooter template")
	local folder = ServerScriptService:FindFirstChild("Scooter")
	local source = if folder then folder:FindFirstChild("DevScooterRepair") else nil
	assert(source and source:IsA("ModuleScript"), "Sync DevScooterRepair through Rojo first")
	-- The Command Bar may still cache the repair wrapper used before suspension existed.
	local fresh = source:Clone()
	fresh.Name = "_ScooterSuspensionApply"
	fresh.Parent = folder
	local ok, result = pcall(function(): Model
		return (require(fresh) :: Repair).RepairSelection()
	end)
	fresh:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: Model
end

return DevScooterSuspension
