--!strict

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

export type Entry = {
	id: number,
	parentId: number?,
	depth: number,
	name: string,
	className: string,
	path: string,
	attributes: { [string]: any },
	properties: { [string]: any },
}
export type Report = {
	version: number,
	rootPath: string,
	entries: { Entry },
	counts: { [string]: number },
	warnings: { string },
}

local DevScooterInspect = {}

-- Roblox values need explicit conversion; infinity is valid for force limits but not JSON.
local function jsonValue(value: any): any
	local kind = typeof(value)
	if kind == "number" then
		return if value == value and math.abs(value) < math.huge then value else tostring(value)
	elseif kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	elseif kind == "CFrame" then
		return { value:GetComponents() }
	elseif kind == "Color3" then
		return { value.R, value.G, value.B }
	elseif kind == "PhysicalProperties" then
		return {
			density = value.Density, friction = value.Friction, elasticity = value.Elasticity,
			frictionWeight = value.FrictionWeight, elasticityWeight = value.ElasticityWeight,
		}
	elseif kind == "table" then
		local result = {}
		for key, item in value do result[key] = jsonValue(item) end
		return result
	elseif kind == "string" or kind == "boolean" or kind == "nil" then
		return value
	end
	return { type = kind, value = tostring(value) }
end

function DevScooterInspect.Read(source: Instance): Report
	assert(RunService:IsStudio(), "Run DevScooterInspect in Roblox Studio")
	assert(source:IsA("Folder") or source:IsA("Model"), "Select the complete scooter Folder or Model")
	local report: Report = { version = 1, rootPath = source:GetFullName(), entries = {}, counts = {}, warnings = {} }
	local ids: { [Instance]: number } = {}
	local instances: { Instance } = {}
	local function visit(instance: Instance, parentId: number?, depth: number)
		local id = #instances + 1
		ids[instance] = id
		table.insert(instances, instance)
		table.insert(report.entries, {
			id = id, parentId = parentId, depth = depth, name = instance.Name,
			className = instance.ClassName, path = instance:GetFullName(),
			attributes = jsonValue(instance:GetAttributes()), properties = {},
		})
		report.counts[instance.ClassName] = (report.counts[instance.ClassName] or 0) + 1
		local names: { [string]: boolean } = {}
		for _, child in instance:GetChildren() do
			if names[child.Name] then
				table.insert(report.warnings, instance:GetFullName() .. ": duplicate child name " .. child.Name .. "; use entry IDs")
			end
			names[child.Name] = true
			visit(child, id, depth + 1)
		end
	end
	visit(source, nil, 0)

	local function reference(instance: Instance?): any
		if not instance then return { missing = true } end
		return { id = ids[instance], path = instance:GetFullName(), external = ids[instance] == nil }
	end
	for id, instance in instances do
		local entry = report.entries[id]
		local properties = entry.properties
		-- Allowlisted properties span several classes; inaccessible asset IDs stay diagnostic.
		local function read(names: { string })
			for _, name in names do
				local ok, value = pcall(function() return (instance :: any)[name] end)
				if ok then properties[name] = jsonValue(value)
				else table.insert(report.warnings, entry.path .. ": cannot read " .. name) end
			end
		end
		local function endpoint(name: string, target: Instance?)
			properties[name] = reference(target)
			if target and not ids[target] then
				table.insert(report.warnings, entry.path .. ": " .. name .. " points outside the selected root")
			end
		end
		if instance:IsA("Model") then
			properties.Pivot = jsonValue(instance:GetPivot())
			endpoint("PrimaryPart", instance.PrimaryPart)
		end
		if instance:IsA("BasePart") then
			read({ "CFrame", "Size", "Anchored", "Massless", "CanCollide", "CanTouch", "CanQuery",
				"CollisionGroup", "Transparency", "Material", "CustomPhysicalProperties" })
			properties.Mass = instance:GetMass()
			if instance.Anchored then table.insert(report.warnings, entry.path .. ": anchored part") end
		end
		if instance:IsA("MeshPart") then read({ "MeshId", "TextureID", "CollisionFidelity" }) end
		if instance:IsA("Attachment") then
			read({ "CFrame", "WorldCFrame", "Axis", "SecondaryAxis", "WorldAxis", "WorldSecondaryAxis" })
		end
		if instance:IsA("Constraint") then
			read({ "Enabled", "Visible" })
			endpoint("Attachment0", instance.Attachment0)
			endpoint("Attachment1", instance.Attachment1)
			if instance:IsA("HingeConstraint") or instance:IsA("SpringConstraint") then
				if not instance.Attachment0 or not instance.Attachment1 then
					table.insert(report.warnings, entry.path .. ": missing mechanical attachment endpoint")
				else
					properties.EndpointDistance = (instance.Attachment0.WorldPosition - instance.Attachment1.WorldPosition).Magnitude
					properties.WorldAxisDot = instance.Attachment0.WorldAxis:Dot(instance.Attachment1.WorldAxis)
				end
			end
		end
		if instance:IsA("HingeConstraint") then
			read({ "ActuatorType", "LimitsEnabled", "LowerAngle", "UpperAngle", "CurrentAngle", "TargetAngle",
				"AngularSpeed", "AngularVelocity", "ServoMaxTorque", "MotorMaxTorque", "MotorMaxAcceleration", "Restitution" })
		elseif instance:IsA("SpringConstraint") then
			read({ "Stiffness", "Damping", "FreeLength", "CurrentLength", "MaxForce", "LimitsEnabled", "MinLength", "MaxLength" })
		elseif instance:IsA("WeldConstraint") or instance:IsA("JointInstance") then
			endpoint("Part0", instance.Part0)
			endpoint("Part1", instance.Part1)
			if not instance.Part0 or not instance.Part1 then table.insert(report.warnings, entry.path .. ": missing joint endpoint") end
			if instance:IsA("WeldConstraint") then read({ "Enabled" }) else read({ "C0", "C1" }) end
		end
	end
	return report
end

function DevScooterInspect.ToJSON(report: Report): string
	return HttpService:JSONEncode(jsonValue(report))
end

function DevScooterInspect.InspectSelection(): Report
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Inspect the authored scooter in Studio Edit mode")
	local selected = Selection:Get()
	assert(#selected == 1, "Select exactly one complete scooter Folder or Model")
	local report = DevScooterInspect.Read(selected[1])
	for _, entry in report.entries do
		print(string.format("%s#%d %s [%s]", string.rep("  ", entry.depth), entry.id, entry.name, entry.className))
	end
	for _, warning in report.warnings do warn("DevScooterInspect: " .. warning) end
	print("DevScooterInspect: full JSON follows (one entry per line)")
	for _, entry in report.entries do print(HttpService:JSONEncode(jsonValue(entry))) end
	return report
end

return DevScooterInspect
