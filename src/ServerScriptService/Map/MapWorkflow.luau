--!strict

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

type DevMapToolApi = {
	DevBuildMap: () -> (),
	DevSerializeMap: () -> string,
}

local MapWorkflow = {}

local function withFreshDevMapTool<T>(action: (DevMapToolApi) -> T): T
	local sourceFolder = ServerScriptService:WaitForChild("Map")
	local reloadFolder = Instance.new("Folder")
	reloadFolder.Name = "_MapReload_" .. HttpService:GenerateGUID(false)
	reloadFolder.Parent = ServerScriptService

	local succeeded, result = pcall(function()
		for _, moduleName in ipairs({ "MapData", "AssetRegistry", "DevMapTool" }) do
			local sourceModule = sourceFolder:WaitForChild(moduleName)
			assert(sourceModule:IsA("ModuleScript"), string.format("Map.%s must be a ModuleScript", moduleName))

			local freshModule = sourceModule:Clone()
			freshModule.Parent = reloadFolder
		end

		local devMapTool = require(reloadFolder:WaitForChild("DevMapTool")) :: DevMapToolApi
		return action(devMapTool)
	end)

	reloadFolder:Destroy()
	if not succeeded then
		error(result, 2)
	end

	return result :: T
end

function MapWorkflow.Build(): ()
	withFreshDevMapTool(function(devMapTool)
		devMapTool.DevBuildMap()
	end)
end

function MapWorkflow.Serialize(): string
	return withFreshDevMapTool(function(devMapTool)
		return devMapTool.DevSerializeMap()
	end)
end

return MapWorkflow
