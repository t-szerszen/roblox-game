--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
type Repair = { RepairFrontSelection: () -> Model }
local DevScooterFrontMount = {}

function DevScooterFrontMount.Apply(): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play before repairing front mounts")
	local folder = ServerScriptService:FindFirstChild("Scooter")
	local source = if folder then folder:FindFirstChild("DevScooterRepair") else nil
	assert(source and source:IsA("ModuleScript"), "Sync DevScooterRepair through Rojo first")
	-- Bypass the Command Bar cache, including a previously loaded repair wrapper.
	local fresh = source:Clone()
	fresh.Name = "_ScooterFrontMountApply"
	fresh.Parent = folder
	local ok, result = pcall(function(): Model
		return (require(fresh) :: Repair).RepairFrontSelection()
	end)
	fresh:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: Model
end

return DevScooterFrontMount
