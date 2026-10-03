--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

type Configuration = typeof(require(ReplicatedStorage.Shared.ScooterConfig))
type Geometry = typeof(require(script.Parent.ScooterRigGeometry))
type Collision = typeof(require(script.Parent.ScooterCollision))
type Rig = typeof(require(script.Parent.ScooterRig))
type Suspension = typeof(require(script.Parent.ScooterSuspension))
type Report = { errors: { string }, warnings: { string }, details: { string } }
local DevScooterRepair = {}

local function selectedScooter(): Instance
	assert(RunService:IsStudio(), "Scooter diagnostics are Studio-only")
	local selected = Selection:Get()
	assert(#selected == 1 and (selected[1]:IsA("Folder") or selected[1]:IsA("Model")),
		"Select the complete scooter Folder/Model, not individual parts")
	return selected[1]
end

local function cloneModule(parent: Instance, name: string, destination: Folder): ModuleScript
	local source = parent:FindFirstChild(name)
	assert(source and source:IsA("ModuleScript"), name .. " is missing; sync Rojo first")
	local clone = source:Clone()
	clone.Parent = destination
	return clone
end

local function fresh<T>(action: (Configuration, Geometry, Collision, Rig, Suspension) -> T): T
	local source = ServerScriptService:FindFirstChild("Scooter")
	assert(source, "ServerScriptService.Scooter is missing; sync Rojo first")
	local folder = Instance.new("Folder")
	folder.Name = "_ScooterRepairReload_" .. HttpService:GenerateGUID(false)
	folder.Parent = source
	local ok, result = pcall(function(): T
		local config = cloneModule(ReplicatedStorage.Shared, "ScooterConfig", folder)
		local collision = cloneModule(source, "ScooterCollision", folder)
		local suspension = cloneModule(source, "ScooterSuspension", folder)
		local geometry = cloneModule(source, "ScooterRigGeometry", folder)
		local rig = cloneModule(source, "ScooterRig", folder)
		return action(require(config) :: Configuration, require(geometry) :: Geometry,
			require(collision) :: Collision, require(rig) :: Rig, require(suspension) :: Suspension)
	end)
	folder:Destroy()
	if not ok then error(tostring(result), 2) end
	return result :: T
end

local function printReport(report: Report)
	print(string.format("Scooter diagnostics: %d errors, %d warnings", #report.errors, #report.warnings))
	for _, line in report.errors do warn("ERROR: " .. line) end
	for _, line in report.warnings do warn("WARNING: " .. line) end
	for _, line in report.details do print(line) end
end

function DevScooterRepair.DiagnoseSelection(): Report
	local source = selectedScooter()
	return fresh(function(config, geometry, collision, rig): Report
		local report = geometry.Check(source, config)
		local ok, problem = pcall(rig.Inspect, source)
		if not ok then table.insert(report.errors, tostring(problem)) end
		local totalMass = 0
		for _, instance in source:GetDescendants() do
			if instance:IsA("BasePart") then
				totalMass += if instance.Massless then 0 else instance:GetMass()
				table.insert(report.details, string.format("%s: anchored=%s collide=%s massless=%s mass=%.3f group=%s",
					instance.Name, tostring(instance.Anchored), tostring(instance.CanCollide),
					tostring(instance.Massless), instance:GetMass(), instance.CollisionGroup))
			end
		end
		table.insert(report.details, string.format("Non-massless part mass sum=%.3f (no seated rider)", totalMass))
		table.insert(report.details, string.format("Front rest revision=%s correction=%s mount shift=%s",
			tostring(source:GetAttribute("FrontRestPoseRevision")), tostring(source:GetAttribute("FrontRestCorrectionDegrees")),
			tostring(source:GetAttribute("FrontMountShift"))))
		local deckContact = source:FindFirstChild("DeckCollider")
		local upright = source:FindFirstChild("ScooterUpright", true)
		if upright and upright:IsA("AlignOrientation") then
			table.insert(report.details, string.format("Upright enabled=%s maxTorque=%.1f supportMass=%s; deck contact=%s",
				tostring(upright.Enabled), upright.MaxTorque, tostring(source:GetAttribute("UprightSupportMass")),
				tostring(deckContact ~= nil and deckContact:IsA("BasePart") and deckContact.CanCollide)))
		end
		for _, endName in { "Front", "Back" } do
			local wheel = source:FindFirstChild(endName .. "Wheel")
			if wheel and wheel:IsA("BasePart") then
				local radius, radiusSource = collision.ResolveRadius(source, wheel)
				table.insert(report.details, string.format("%sWheel: radius=%.3f from %s; mesh size=%s",
					endName, radius, radiusSource, tostring(wheel.Size)))
				local proxy = source:FindFirstChild(endName .. "WheelCollider")
				if source:IsDescendantOf(Workspace) and (not proxy or not proxy:IsA("BasePart") or not proxy.CanCollide) then
					table.insert(report.errors, endName .. ": live scooter is missing an enabled wheel collider")
				end
				if source:IsDescendantOf(Workspace) then
					local center = wheel:FindFirstChild("WheelCenter")
					if center and center:IsA("Attachment") then
						local params = RaycastParams.new()
						params.FilterType = Enum.RaycastFilterType.Exclude
						params.FilterDescendantsInstances = { source }
						params.RespectCanCollide = true
						if proxy and proxy:IsA("BasePart") then params.CollisionGroup = proxy.CollisionGroup end
						local hit = Workspace:Raycast(center.WorldPosition + Vector3.yAxis * radius,
							-Vector3.yAxis * math.max(radius * 4, config.ParkingGroundProbeDistance), params)
						table.insert(report.details, if hit then string.format("%s floor=%s normalY=%.3f distance=%.3f",
							endName, hit.Instance:GetFullName(), hit.Normal.Y, hit.Distance)
							else endName .. ": no collidable floor below this wheel (check road collision/group)")
					end
				end
			end
		end
		printReport(report)
		return report
	end)
end

local function ensureFolder(name: string): Folder
	local existing = ServerStorage:FindFirstChild(name)
	assert(not existing or existing:IsA("Folder"), "ServerStorage." .. name .. " must be a Folder")
	if existing then return existing :: Folder end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ServerStorage
	return folder
end

local function repairSelection(source: Instance, reference: Instance?, frontOnly: boolean): Model
	assert(not RunService:IsRunning(), "Stop Play before repairing; use the original Edit-mode model")
	return fresh(function(config, geometry, _collision, rig, suspension): Model
		for _, name in { "ScooterModels", "ScooterRepairBackups" } do
			local folder = ServerStorage:FindFirstChild(name)
			assert(not folder or folder:IsA("Folder"), "ServerStorage." .. name .. " must be a Folder")
		end
		rig.Inspect(source)
		local staged = source:Clone()
		local changes: { string } = {}
		local ok, prepared = pcall(function(): Model
			if frontOnly then
				assert(staged:IsA("Model") and staged:GetAttribute("ArticulatedScooter") == true,
					"Select the installed ServerStorage.ScooterModels.scooter template for front-only repair")
				local left = staged:FindFirstChild("FrontSuspensionLeft")
				local saved = if left then left:FindFirstChild("PivotAtt_FrontSuspensionLeft") else nil
				if reference or (saved and saved:GetAttribute("AuthoredPivotCFrame") ~= nil) then
					changes = geometry.RepairFront(staged, reference, config)
				else
					geometry.AssertSafe(staged, config)
					changes = { "Front: retained existing validated pivots; no untouched reference available" }
				end
				staged:SetAttribute("FrontRestPoseRevision", nil)
				for _, line in geometry.AlignFrontRest(staged, config) do table.insert(changes, line) end
				suspension.ConfigureFront(staged, config)
			else
				changes = geometry.Repair(staged, config)
			end
			geometry.AssertSafe(staged, config)
			return rig.Prepare(staged, config)
		end)
		staged:Destroy()
		if not ok then error(tostring(prepared), 2) end
		local model = prepared :: Model
		local templates = ensureFolder("ScooterModels")
		local backups = ensureFolder("ScooterRepairBackups")
		local previous = templates:FindFirstChild(config.TemplateName)
		local legacy = templates:FindFirstChild(config.DefaultModel)
		local saved: { [Instance]: boolean } = {}
		local originals: { Instance } = { source }
		if previous then table.insert(originals, previous) end
		if legacy then table.insert(originals, legacy) end
		-- Commit only after the replacement has passed structural and geometry checks.
		for _, original in originals do
			if not saved[original] then
				saved[original] = true
				original.Name ..= "_" .. HttpService:GenerateGUID(false)
				original.Parent = backups
			end
		end
		model.Parent = templates
		Selection:Set({ model })
		for _, change in changes do print("Scooter repair: " .. change) end
		printReport(geometry.Check(model, config))
		print("Scooter repair: installed ServerStorage.ScooterModels.scooter; originals in ScooterRepairBackups. Save and start a new Play session.")
		return model
	end)
end

function DevScooterRepair.RepairSelection(): Model
	return repairSelection(selectedScooter(), nil, false)
end

function DevScooterRepair.RepairFrontSelection(): Model
	assert(RunService:IsStudio(), "Scooter repair is Studio-only")
	local selected = Selection:Get()
	assert(#selected == 1 or #selected == 2, "Select the installed scooter template, optionally with its untouched original")
	local source, reference = selected[1], selected[2]
	if reference and reference:GetAttribute("ArticulatedScooter") == true
		and source:GetAttribute("ArticulatedScooter") ~= true then
		source, reference = reference, source
	end
	assert(not reference or reference:IsA("Model") or reference:IsA("Folder"), "Reference must be the complete original scooter")
	local arm = source:FindFirstChild("FrontSuspensionLeft")
	local saved = if arm then arm:FindFirstChild("PivotAtt_FrontSuspensionLeft") else nil
	if not reference and saved and saved:GetAttribute("AuthoredPivotCFrame") == nil then
		local candidates = ServerStorage:GetChildren()
		local backups = ServerStorage:FindFirstChild("ScooterRepairBackups")
		if backups then for _, candidate in backups:GetChildren() do table.insert(candidates, candidate) end end
		local ambiguous = false
		for _, candidate in candidates do
			if candidate ~= source and (candidate:IsA("Model") or candidate:IsA("Folder"))
				and candidate:GetAttribute("SuspensionRevision") == nil then
				local matches = true
				for _, side in { "Left", "Right" } do
					local name = "FrontSuspension" .. side
					local actual, original = source:FindFirstChild(name), candidate:FindFirstChild(name)
					local point = if original then original:FindFirstChild("PivotAtt_" .. name) else nil
					if not actual or not actual:IsA("MeshPart") or not original or not original:IsA("MeshPart")
						or actual.MeshId ~= original.MeshId or actual.Size ~= original.Size or not point or not point:IsA("Attachment") then
						matches = false
						break
					end
				end
				if matches then
					if reference then
						for _, side in { "Left", "Right" } do
							local name = "FrontSuspension" .. side
							local prior = (reference:FindFirstChild(name) :: Instance):FindFirstChild("PivotAtt_" .. name) :: Attachment
							local point = (candidate:FindFirstChild(name) :: Instance):FindFirstChild("PivotAtt_" .. name) :: Attachment
							if (prior:GetAttribute("AuthoredPivotCFrame") or prior.CFrame)
								~= (point:GetAttribute("AuthoredPivotCFrame") or point.CFrame) then ambiguous = true end
						end
					else
						reference = candidate
					end
				end
			end
		end
		if ambiguous then
			reference = nil
			warn("Front repair: multiple different original pivots found; select the intended original to restore them. Current validated mounts will be used for rest alignment.")
		elseif reference then
			print("Front repair: restoring original arm pivots from " .. reference:GetFullName())
		end
	end
	return repairSelection(source, reference, true)
end

return DevScooterRepair
