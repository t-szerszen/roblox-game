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

function ScooterWorkflow.PreviewNewModel(sourceModel: Instance?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run ScooterWorkflow in Studio Edit mode")
	local source = assert(ServerScriptService:FindFirstChild("Scooter"), "Sync Rojo first")
	local reloadFolder = Instance.new("Folder")
	reloadFolder.Name = "_ScooterDraftReload_" .. HttpService:GenerateGUID(false)
	local success, result = pcall(function(): Model
		cloneModule(source, "DevScooterBuildConfig", reloadFolder)
		local module = cloneModule(source, "DevScooterBuild", reloadFolder)
		local builder = require(module) :: { Preview: (Instance?) -> Model }
		return builder.Preview(sourceModel)
	end)
	reloadFolder:Destroy()
	if not success then error(tostring(result), 2) end
	return result :: Model
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

function ScooterWorkflow.PreviewLargeWheels(): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run ScooterWorkflow in Studio Edit mode")
	local source = assert(ServerScriptService:FindFirstChild("Scooter"), "Sync Rojo first")
	local reload = Instance.new("Folder")
	local ok, result = pcall(function(): Model
		for _, name in { "DevScooterBuildConfig", "DevScooterBuild", "DevScooterRemodelConfig", "ScooterCollision",
			"ScooterSuspension", "ScooterRigGeometry", "ScooterRig", "DevScooterInstall", "DevScooterRemodel" } do
			cloneModule(source, name, reload)
		end
		local module = assert(reload:FindFirstChild("DevScooterRemodel")) :: ModuleScript
		return (require(module) :: typeof(require(script.Parent.DevScooterRemodel))).Preview()
	end)
	reload:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: Model
end

function ScooterWorkflow.InstallNewModel(draft: Model?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run ScooterWorkflow in Studio Edit mode")
	local source = assert(ServerScriptService:FindFirstChild("Scooter"), "Sync Rojo first")
	local reloadFolder = Instance.new("Folder")
	reloadFolder.Name = "_ScooterInstallReload_" .. HttpService:GenerateGUID(false)
	local success, result = pcall(function(): Model
		for _, name in { "DevScooterBuildConfig", "DevScooterBuild", "ScooterCollision", "ScooterSuspension",
			"ScooterRigGeometry", "ScooterRig" } do cloneModule(source, name, reloadFolder) end
		local configModule = cloneModule(ReplicatedStorage.Shared, "ScooterConfig", reloadFolder)
		local module = cloneModule(source, "DevScooterInstall", reloadFolder)
		local config = require(configModule) :: Configuration
		local installer = require(module) :: { Install: (Model?, Configuration?) -> Model }
		return installer.Install(draft, config)
	end)
	reloadFolder:Destroy()
	if not success then error(tostring(result), 2) end
	return result :: Model
end

function ScooterWorkflow.InstallScaleVariants(): { Model }
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run ScooterWorkflow in Studio Edit mode")
	local ServerStorage = game:GetService("ServerStorage")
	local modules = assert(ServerScriptService:FindFirstChild("Scooter"), "Sync Rojo first")
	local authoring = assert(ServerStorage:FindFirstChild("ScooterAuthoring"), "Preserved source is missing")
	local raw = assert(authoring:FindFirstChild("ScooterFinal"), "Preserved ScooterFinal source is missing")
	local reload = Instance.new("Folder")
	local staged: { Model } = {}
	local ok, problem = pcall(function()
		local settingsModule = cloneModule(modules, "DevScooterBuildConfig", reload)
		local builderModule = cloneModule(modules, "DevScooterBuild", reload)
		for _, name in { "ScooterCollision", "ScooterSuspension", "ScooterRigGeometry", "ScooterRig" } do
			cloneModule(modules, name, reload)
		end
		local installerModule = cloneModule(modules, "DevScooterInstall", reload)
		local configModule = cloneModule(ReplicatedStorage.Shared, "ScooterConfig", reload)
		local config = require(configModule) :: Configuration
		local settings = require(settingsModule) :: typeof(require(script.Parent.DevScooterBuildConfig))
		local builder = require(builderModule) :: typeof(require(script.Parent.DevScooterBuild))
		local installer = require(installerModule) :: typeof(require(script.Parent.DevScooterInstall))
		for _, variant in config.StudioScaleVariants do
			local options = table.clone(settings)
			options.Scale = variant.Scale
			local draft = builder.Build(raw, options)
			local prepared, result = pcall(installer.Prepare, draft, config)
			draft:Destroy()
			assert(prepared, tostring(result))
			local model = result :: Model
			model.Name = variant.TemplateName
			model:SetAttribute("StudioScaleVariant", variant.Id)
			table.insert(staged, model)
		end
	end)
	reload:Destroy()
	if not ok then
		for _, model in staged do model:Destroy() end
		error(tostring(problem), 2)
	end
	-- Prepare every size before replacing any working template.
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	if not templates then templates = Instance.new("Folder"); templates.Name = "ScooterModels"; templates.Parent = ServerStorage end
	local backups = ServerStorage:FindFirstChild("ScooterTemplateBackups")
	if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterTemplateBackups"; backups.Parent = ServerStorage end
	for _, model in staged do
		local previous = templates:FindFirstChild(model.Name)
		if previous then
			previous.Name ..= "_" .. HttpService:GenerateGUID(false)
			previous.Parent = backups
		end
		model.Parent = templates
	end
	return staged
end

return ScooterWorkflow
