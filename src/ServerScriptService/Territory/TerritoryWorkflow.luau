--!strict
local Workflow = {}
type Tool = typeof(require(script.Parent.DevTerritoryTool))
type FlagTool = typeof(require(script.Parent.DevTerritoryFlags))
local function fresh(action: string): any
	local folder = Instance.new("Folder")
	local success, result = pcall(function(): string?
		for _, name in { "DevTerritoryTool", "DevTerritoryFlags", "TerritoryData" } do
			local module = script.Parent:FindFirstChild(name)
			assert(module and module:IsA("ModuleScript"), "Missing territory authoring module")
			module:Clone().Parent = folder
		end
		local loadFresh: any = require
		if action == "PlaceFlags" then
			local flags: FlagTool = loadFresh(folder:FindFirstChild("DevTerritoryFlags"))
			flags.PlaceFlags(); return nil
		end
		local tool: Tool = loadFresh(folder:FindFirstChild("DevTerritoryTool"))
		if action == "ConfigureSelection" then tool.ConfigureSelection(); return nil
		elseif action == "Serialize" then return tool.Serialize()
		else tool.RestoreZones(); return nil end
	end)
	folder:Destroy()
	if not success then error(result, 2) end
	return result
end
function Workflow.ConfigureSelection() fresh("ConfigureSelection") end
function Workflow.Serialize(): string return fresh("Serialize") end
function Workflow.RestoreZones() fresh("RestoreZones") end
function Workflow.PlaceFlags() fresh("PlaceFlags") end
return Workflow
