--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local BuildConfig = require(script.Parent.DevScooterBuildConfig)
local Builder = require(script.Parent.DevScooterBuild)
local Rig = require(script.Parent.ScooterRig)

local DevScooterInstall = {}
local assemblies = {
	Body = "body", Steering = "steering", FrontSuspension = "front",
	BackSuspension = "back", FrontWheel = "frontWheel", BackWheel = "backWheel",
	FrontSteering = "frontSteering",
} :: { [string]: string }

local function extract(model: Model, importedName: string, runtimeName: string): BasePart
	local container = assert(model:FindFirstChild(importedName), "Missing " .. importedName)
	local part = if container:IsA("BasePart") then container else container:FindFirstChildWhichIsA("BasePart", true)
	assert(part and part:IsA("BasePart"), importedName .. " requires a part")
	part.Name = runtimeName
	part.Parent = model
	if container ~= part then container:Destroy() end
	return part
end

local function renameLink(parent: BasePart, oldName: string, name: string, fixedName: string, movingName: string)
	local link = parent:FindFirstChild(oldName)
	assert(link and link:IsA("Constraint"), "Missing " .. oldName)
	link.Name = name
	assert(link.Attachment0).Name = fixedName
	assert(link.Attachment1).Name = movingName
end

-- Normalize names only: the accepted attachment frames and imported meshes stay intact.
function DevScooterInstall.Prepare(draft: Model, configuration: typeof(Config)?): Model
	assert(draft:GetAttribute("ScooterDraftRig") == true, "Select the approved ScooterFinalRig draft")
	assert(draft:GetAttribute("MountsVerified") == true, "Verify the draft's mounts before installing")
	Builder.Validate(draft)
	local model = draft:Clone()
	local ok, result = pcall(function(): Model
		local markers = model:FindFirstChild("_ScooterRigReview")
		if markers then markers:Destroy() end
		local independent = draft:GetAttribute("IndependentFrontSteering") == true
		local body = extract(model, "ScooterBody", "ScooterBody")
		local stick = extract(model, "HandleBarStick", "HandleBarStick")
		extract(model, "Handbar", "HandleBar")
		for _, name in { "FrontWheel", "BackWheel", "BrakeDisc", "Display", "FrontLight", "StopLight", "BackSpringStick" } do
			extract(model, name, name)
		end
		extract(model, "Footrest", "RearFootRest")
		for _, entry in BuildConfig.ExtraComponents do
			local component = model:FindFirstChild(entry.Name)
			if component then
				local count = 0
				for _, item in component:GetDescendants() do if item:IsA("BasePart") then count += 1 end end
				-- Keep compound decorations together; extracting one part would discard the others.
				if component:IsA("BasePart") or count == 1 then extract(model, entry.Name, entry.Name) end
			end
		end
		for _, endName in { "Front", "Back" } do
			for _, side in { "Left", "Right" } do
				extract(model, endName .. side .. "Suspension", endName .. "Suspension" .. side)
			end
			extract(model, endName .. "Spring", endName .. "SpringVisual")
		end
		local forward = ((model:FindFirstChild("FrontWheel") :: BasePart).Position - (model:FindFirstChild("BackWheel") :: BasePart).Position)
		local right = Vector3.new(forward.X, 0, forward.Z).Unit:Cross(Vector3.yAxis)
		local gripContainers: { Instance } = {}
		for _, item in model:GetChildren() do if item.Name == "Grip" then table.insert(gripContainers, item) end end
		for _, container in gripContainers do
			local grip = assert(container:FindFirstChildWhichIsA("MeshPart", true))
			grip.Name = if (grip.Position - stick.Position):Dot(right) < 0 then "LeftGrip" else "RightGrip"
			grip.Parent = model
			container:Destroy()
		end
		assert(model:FindFirstChild("LeftGrip") and model:FindFirstChild("RightGrip"), "Grips must straddle the steering shaft")
		renameLink(body, "SteeringHinge", "HingeConstraint", "SteerBase", "SteerPivot")
		for _, endName in { "Front", "Back" } do
			local base = if endName == "Front" and not independent then stick else body
			local axle = model:FindFirstChild("Virtual" .. endName .. "Axle") :: BasePart
			for _, side in { "Left", "Right" } do
				local suffix = endName .. "Suspension" .. side
				renameLink(base, suffix .. "Hinge", "PivotHinge_" .. suffix, "PivotAttBase_" .. suffix, "PivotAtt_" .. suffix)
			end
			local wheelBase = if endName == "Front" and independent then assert(model:FindFirstChild("FrontSteeringCarrier")) :: BasePart else axle
			renameLink(wheelBase, endName .. "WheelHinge", "HingeConstraint", "AxlePivot", "WheelCenter")
			if endName == "Front" and independent then renameLink(axle, "FrontSteeringHinge", "FrontSteeringHinge", "KingpinBase", "KingpinPivot") end
			renameLink(base, endName .. "Shock", "ShockAbsorber_" .. endName, "SpringAttBase_" .. endName, "SpringAtt_" .. endName)
		end
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				local group = item:GetAttribute("ScooterDraftAssembly")
				assert(typeof(group) == "string" and assemblies[group], "Unknown assembly for " .. item.Name)
				item:SetAttribute("ScooterAssembly", assemblies[group])
				if not table.find({ "ScooterBody", "HandleBarStick", "HandleBar", "FrontWheel", "BackWheel",
					"FrontSuspensionLeft", "FrontSuspensionRight", "BackSuspensionLeft", "BackSuspensionRight",
					"VirtualFrontAxle", "VirtualBackAxle", "FrontSteeringCarrier" }, item.Name) then item:SetAttribute("ScooterDecoration", true) end
			elseif item:IsA("WeldConstraint") then
				-- The runtime inspector looks for structural welds under their fixed part.
				item.Parent = assert(item.Part0)
			end
		end
		local scale = draft:GetAttribute("ScooterDraftScale")
		assert(typeof(scale) == "number" and scale > 0, "Draft scale is missing")
		local deck = Instance.new("Part")
		deck.Name = "FootRest"
		deck.Size = BuildConfig.Deck.Size * scale
		deck.CFrame = body.CFrame * CFrame.new(BuildConfig.Deck.CenterBodyLocal * scale)
		deck.Transparency = 1
		deck.CanCollide, deck.CanTouch, deck.CanQuery = false, false, false
		deck:SetAttribute("ScooterAssembly", "body")
		deck.Parent = model
		model:SetAttribute("CentralShockRig", true)
		model:SetAttribute("RuntimeChassisMass", BuildConfig.RuntimePhysics.ChassisMass)
		model:SetAttribute("SuspensionRiderMass", BuildConfig.RuntimePhysics.ReferenceRiderMass)
		local masses: { [string]: number } = {
			FrontSteeringCarrier = BuildConfig.RuntimePhysics.SteeringCarrierMass,
			HandleBarStick = BuildConfig.RuntimePhysics.SteeringMass,
			FrontWheel = BuildConfig.RuntimePhysics.WheelMass, BackWheel = BuildConfig.RuntimePhysics.WheelMass,
			FrontSuspensionLeft = BuildConfig.RuntimePhysics.SuspensionArmMass,
			FrontSuspensionRight = BuildConfig.RuntimePhysics.SuspensionArmMass,
			BackSuspensionLeft = BuildConfig.RuntimePhysics.SuspensionArmMass,
			BackSuspensionRight = BuildConfig.RuntimePhysics.SuspensionArmMass,
		}
		for name, mass in masses do
			local candidate = model:FindFirstChild(name)
			if name == "FrontSteeringCarrier" and not independent then continue end
			assert(candidate and candidate:IsA("BasePart"), "Missing mass target: " .. name)
			local part = candidate :: BasePart
			local properties = part.CurrentPhysicalProperties
			local density = properties.Density * mass / part:GetMass()
			assert(density > 0 and density <= 100, name .. ": mass exceeds supported density")
			part.CustomPhysicalProperties = PhysicalProperties.new(density, properties.Friction, properties.Elasticity,
				properties.FrictionWeight, properties.ElasticityWeight)
		end
		model:SetAttribute("ScooterDraftRig", nil)
		model:SetAttribute("SuspensionCalibrated", true)
		local prepared = Rig.Prepare(model, configuration or Config)
		return prepared
	end)
	model:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: Model
end

function DevScooterInstall.Install(draft: Model?, configuration: typeof(Config)?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Install in Studio Edit mode")
	local authoring = ServerStorage:FindFirstChild("ScooterAuthoring")
	assert(not authoring or authoring:IsA("Folder"), "ScooterAuthoring must be a Folder")
	local selected = draft or workspace:FindFirstChild(BuildConfig.PreviewName)
		or (authoring and authoring:FindFirstChild(BuildConfig.PreviewName))
	assert(selected and selected:IsA("Model"), "Build and approve ScooterFinalRig first")
	local config = configuration or Config
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	assert(templates and templates:IsA("Folder"), "Missing scooter template folder")
	local previous = templates:FindFirstChild(config.TemplateName)
	assert(not previous or previous:IsA("Model"), "Template name is occupied by an unrelated object")
	local backups = ServerStorage:FindFirstChild("ScooterTemplateBackups")
	assert(not backups or backups:IsA("Folder"), "ScooterTemplateBackups must be a Folder")
	local prepared = DevScooterInstall.Prepare(selected, config)
	if previous then
		if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterTemplateBackups"; backups.Parent = ServerStorage end
		previous.Name = config.TemplateName .. "_" .. game:GetService("HttpService"):GenerateGUID(false)
		previous.Parent = backups
	end
	prepared.Parent = templates
	-- Loose imported meshes must stay out of Play; retain the entire authoring copy.
	if not authoring then authoring = Instance.new("Folder"); authoring.Name = "ScooterAuthoring"; authoring.Parent = ServerStorage end
	local source = workspace:FindFirstChild(BuildConfig.SourceName)
	if source then
		-- A remodel must replace the canonical source, while retaining its predecessor.
		local archived = authoring:FindFirstChild(BuildConfig.SourceName)
		if archived and archived ~= source then
			archived.Name = BuildConfig.SourceName .. "_" .. game:GetService("HttpService"):GenerateGUID(false)
		end
		source.Parent = authoring
		prepared:SetAttribute("SourcePath", source:GetFullName())
		selected:SetAttribute("SourcePath", source:GetFullName())
	end
	if selected:IsDescendantOf(workspace) then selected.Parent = authoring end
	return prepared
end

return DevScooterInstall
