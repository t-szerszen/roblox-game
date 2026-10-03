--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Configuration = typeof(require(ReplicatedStorage.Shared.ScooterConfig))
type Assembler = {
	ArticulatedRigVersion: number,
	AssembleFromSelection: (configuration: Configuration?) -> Model,
}

local ScooterWorkflow = {}

local function cloneModule(parent: Instance, name: string, destination: Folder): ModuleScript
	local source = parent:FindFirstChild(name)
	assert(source and source:IsA("ModuleScript"), name .. " is missing; sync the current project through Rojo first")
	local clone = source:Clone()
	clone.Parent = destination
	return clone
end

function ScooterWorkflow.Assemble(): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run ScooterWorkflow in Studio Edit mode")
	local source = ServerScriptService:FindFirstChild("Scooter")
	assert(source, "ServerScriptService.Scooter is missing; sync Rojo first")
	local reloadFolder = Instance.new("Folder")
	reloadFolder.Name = "_ScooterReload_" .. HttpService:GenerateGUID(false)
	reloadFolder.Parent = ServerScriptService
	local success, result = pcall(function(): Model
		local configModule = cloneModule(ReplicatedStorage.Shared, "ScooterConfig", reloadFolder)
		cloneModule(source, "ScooterCollision", reloadFolder)
		cloneModule(source, "ScooterSuspension", reloadFolder)
		cloneModule(source, "ScooterRigGeometry", reloadFolder)
		cloneModule(source, "ScooterRig", reloadFolder)
		local assemblerModule = cloneModule(source, "DevScooterAssembler", reloadFolder)
		local config = require(configModule) :: Configuration
		local assembler = require(assemblerModule) :: Assembler
		assert(assembler.ArticulatedRigVersion == 1 and typeof(config.TemplateName) == "string",
			"Studio still has the old scooter sources; reconnect Rojo and sync before assembling")
		return assembler.AssembleFromSelection(config)
	end)
	reloadFolder:Destroy()
	if not success then error(tostring(result), 2) end
	return result :: Model
end

return ScooterWorkflow
