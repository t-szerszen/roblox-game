--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterRig = require(script.Parent.ScooterRig)

local DevScooterAssembler = { ArticulatedRigVersion = 1 }

function DevScooterAssembler.AssembleFromSelection(configuration: typeof(Config)?): Model
	local Config = configuration or Config
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Run the assembler in Studio Edit mode")
	local selected = Selection:Get()
	assert(#selected == 1, "Select only the new scooter Folder or Model")
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	assert(not templates or templates:IsA("Folder"), "ServerStorage.ScooterModels must be a Folder")
	local model = ScooterRig.Prepare(selected[1], Config)
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "ScooterModels"
		templates.Parent = ServerStorage
	end
	assert(templates:IsA("Folder"), "ServerStorage.ScooterModels must be a Folder")
	-- Stage and validate first; replacing the old scooter is explicitly requested.
	local oldTemplate = templates:FindFirstChild(Config.TemplateName)
	local legacyTemplate = templates:FindFirstChild(Config.DefaultModel)
	model.Parent = templates
	if oldTemplate then oldTemplate:Destroy() end
	if legacyTemplate and legacyTemplate ~= oldTemplate then legacyTemplate:Destroy() end
	-- Keep the authored source out of the live world so it cannot collide with spawned rigs.
	if selected[1]:IsDescendantOf(workspace) then selected[1].Parent = ServerStorage end
	Selection:Set({ model })
	print("DevScooterAssembler: installed ServerStorage.ScooterModels.scooter; authored source retained in ServerStorage")
	return model
end

return DevScooterAssembler
