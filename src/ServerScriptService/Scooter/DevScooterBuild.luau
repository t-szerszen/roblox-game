--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local DefaultConfig = require(script.Parent.DevScooterBuildConfig)
type Configuration = typeof(DefaultConfig)

local DevScooterBuild = {}

local function part(root: Instance, name: string): BasePart
	local matches = {}
	for _, child in root:GetChildren() do if child.Name == name then table.insert(matches, child) end end
	assert(#matches == 1, "Expected exactly one component named " .. name)
	local component = matches[1]
	if component:IsA("BasePart") then return component end
	assert(component:IsA("Model") or component:IsA("Folder"), name .. " must contain a BasePart")
	local parts: { BasePart } = {}
	for _, item in component:GetDescendants() do if item:IsA("BasePart") then table.insert(parts, item) end end
	assert(#parts == 1, name .. " must contain exactly one BasePart; explicitly map compound components first")
	return parts[1]
end

local function assign(target: BasePart, group: string)
	target:SetAttribute("ScooterDraftAssembly", group)
end

local function weld(first: BasePart, second: BasePart)
	assert(first ~= second, "Cannot weld a part to itself")
	assert(first:GetAttribute("ScooterDraftAssembly") == second:GetAttribute("ScooterDraftAssembly"), "Cross-assembly weld")
	local joint = Instance.new("WeldConstraint")
	joint.Name = "DraftAssemblyWeld"
	joint.Part0, joint.Part1 = first, second
	joint.Parent = second
end

local function frame(position: Vector3, axis: Vector3): CFrame
	local up = if math.abs(axis:Dot(Vector3.yAxis)) < 0.95 then Vector3.yAxis else Vector3.zAxis
	return CFrame.fromMatrix(position, axis, (up - axis * up:Dot(axis)).Unit)
end

local function attachment(parent: BasePart, name: string, worldFrame: CFrame): Attachment
	assert(not parent:FindFirstChild(name), "Reserved attachment already exists: " .. name)
	local point = Instance.new("Attachment")
	point.Name = name
	point.CFrame = parent.CFrame:ToObjectSpace(worldFrame)
	point.Parent = parent
	return point
end

local function hinge(first: BasePart, second: BasePart, name: string, position: Vector3, axis: Vector3, visible: boolean): HingeConstraint
	local worldFrame = frame(position, axis)
	local joint = Instance.new("HingeConstraint")
	joint.Name = name
	joint.Attachment0 = attachment(first, name .. "Base", worldFrame)
	local moving = attachment(second, name .. "Pivot", worldFrame)
	joint.Attachment1 = moving
	if string.find(name, "Suspension") then
		moving:SetAttribute("AuthoredPivotCFrame", moving.CFrame)
	end
	joint.ActuatorType = Enum.ActuatorType.None
	joint.Visible = visible
	joint.Color = BrickColor.new("New Yeller")
	joint.Parent = first
	return joint
end

function DevScooterBuild.Validate(model: Model, settings: Configuration?)
	local config = settings or DefaultConfig
	local hinges, springs = 0, 0
	local axisDot = math.cos(math.rad(config.AxisToleranceDegrees))
	local groups: { [string]: { BasePart } } = {}
	local links: { [BasePart]: { BasePart } } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local group = item:GetAttribute("ScooterDraftAssembly")
			assert(typeof(group) == "string", "Unmapped part: " .. item:GetFullName())
			groups[group] = groups[group] or {}
			table.insert(groups[group], item)
		elseif item:IsA("HingeConstraint") or item:IsA("SpringConstraint") then
			local first, second = assert(item.Attachment0), assert(item.Attachment1)
			assert(first:IsDescendantOf(model) and second:IsDescendantOf(model), "External attachment")
			assert(item.Enabled, "Disabled mechanical constraint")
			if item:IsA("HingeConstraint") then
				hinges += 1
				assert((first.WorldPosition - second.WorldPosition).Magnitude <= config.PositionTolerance, item.Name .. ": hinge gap")
				assert(first.WorldAxis:Dot(second.WorldAxis) >= axisDot, item.Name .. ": hinge axis mismatch")
			else
				springs += 1
				assert((first.WorldPosition - second.WorldPosition).Magnitude > config.PositionTolerance, item.Name .. ": zero spring length")
			end
		elseif item:IsA("WeldConstraint") then
			local first, second = assert(item.Part0), assert(item.Part1)
			assert(item.Enabled, "Disabled rigid assembly weld")
			assert(first:IsDescendantOf(model) and second:IsDescendantOf(model), "External weld")
			assert(first:GetAttribute("ScooterDraftAssembly") == second:GetAttribute("ScooterDraftAssembly"), "Weld locks separate assemblies")
			links[first] = links[first] or {}
			links[second] = links[second] or {}
			table.insert(links[first], second)
			table.insert(links[second], first)
		end
	end
	for group, parts in groups do
		local seen: { [BasePart]: boolean } = {}
		local function walk(item: BasePart)
			if seen[item] then return end
			seen[item] = true
			local connected = links[item]
			if connected then for _, linked in connected do walk(linked) end end
		end
		walk(parts[1])
		for _, item in parts do assert(seen[item], group .. ": disconnected rigid part " .. item:GetFullName()) end
	end
	local expectedHinges = if model:GetAttribute("IndependentFrontSteering") == true then 8 else 7
	assert(hinges == expectedHinges and springs == 2, "Draft requires steering, paired suspension pivots, wheel hinges and two central springs")
	for _, endName in { "Front", "Back" } do
		local first = model:FindFirstChild(endName .. "SuspensionLeftHinge", true) :: HingeConstraint
		local second = model:FindFirstChild(endName .. "SuspensionRightHinge", true) :: HingeConstraint
		local a, b = assert(first.Attachment0), assert(second.Attachment0)
		local offset = b.WorldPosition - a.WorldPosition
		assert(a.WorldAxis:Dot(b.WorldAxis) >= axisDot and offset:Cross(a.WorldAxis).Magnitude <= config.PositionTolerance,
			endName .. ": paired suspension pivots must share one axis")
	end
end

function DevScooterBuild.Build(source: Instance, settings: Configuration?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Build the draft in Studio Edit mode")
	local config = settings or DefaultConfig
	assert(source:IsA("Folder") or source:IsA("Model"), "Source must be a complete Folder or Model")
	assert(source:GetAttribute("ScooterDraftRig") ~= true, "Build from the authored source, not a scaled draft")
	assert(config.Scale == config.Scale and config.Scale > 0 and config.Scale <= 1, "Invalid scale")
	for _, item in source:GetDescendants() do
		assert(not item:IsA("LuaSourceContainer"), "Source contains executable code; inspect it before building")
		assert(not item:IsA("Constraint") and not item:IsA("JointInstance"), "Source already has mechanical constraints")
	end
	local clone = assert(source:Clone(), "Source must be Archivable")
	local model: Model
	if clone:IsA("Model") then model = clone else
		model = Instance.new("Model")
		for _, child in clone:GetChildren() do child.Parent = model end
		clone:Destroy()
	end
	local ok, problem = pcall(function()
		local body, stick, bar = part(model, "ScooterBody"), part(model, "HandleBarStick"), part(model, "Handbar")
		-- Imported pivots can rotate the model bounds away from the chassis axes.
		body.PivotOffset = CFrame.identity
		model.PrimaryPart = body
		local lowest = math.huge
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				local size = item.Size
				local half = (math.abs(item.CFrame.RightVector.Y) * size.X + math.abs(item.CFrame.UpVector.Y) * size.Y
					+ math.abs(item.CFrame.LookVector.Y) * size.Z) * 0.5
				lowest = math.min(lowest, item.Position.Y - half)
				item.Anchored = true
				item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
			end
		end
		local previousScale = model:GetScale()
		local pivotY = body.Position.Y
		model:ScaleTo(previousScale * config.Scale)
		model:PivotTo(model:GetPivot() + Vector3.yAxis * ((lowest - pivotY) * (1 - config.Scale)) + config.PreviewOffset)
		model.Name = config.PreviewName
		assign(body, "Body")
		assign(stick, "Steering")
		assign(bar, "Steering")
		weld(stick, bar)
		for _, name in { "Footrest", "StopLight" } do local item = part(model, name); assign(item, "Body"); weld(body, item) end
		for _, name in { "FrontLight", "Display" } do local item = part(model, name); assign(item, "Steering"); weld(bar, item) end
		local grips = 0
		for _, child in model:GetChildren() do
			if child.Name == "Grip" then
				local mesh = child:FindFirstChildWhichIsA("MeshPart", true)
				assert(mesh and #child:GetDescendants() >= 1, "Grip requires a MeshPart")
				assign(mesh, "Steering")
				weld(bar, mesh)
				grips += 1
			end
		end
		assert(grips == 2, "Expected two Grip components")
		local dashboard = assert(model:FindFirstChild("ScooterDashboard"), "Missing ScooterDashboard")
		local screen = dashboard:FindFirstChild("DisplaySurface")
		assert(screen and screen:IsA("BasePart"), "Dashboard requires DisplaySurface")
		assert(dashboard:IsA("Model"), "ScooterDashboard requires a Model")
		dashboard.PrimaryPart = screen
		dashboard:ScaleTo(dashboard:GetScale() * config.DashboardScale)
		for _, item in dashboard:GetDescendants() do if item:IsA("BasePart") then assign(item, "Steering") end end
		-- The remodel authoring copy was deliberately stripped of all welds.
		if not dashboard:FindFirstChildWhichIsA("WeldConstraint", true) then
			for _, item in dashboard:GetDescendants() do
				if item:IsA("BasePart") and item ~= screen then weld(screen, item) end
			end
		end
		weld(bar, screen)
		local steering = hinge(body, stick, "SteeringHinge", body.CFrame * (config.Steering.PivotBodyLocal * config.Scale), stick.CFrame.UpVector.Unit, config.ShowConstraints)
		steering.ActuatorType = Enum.ActuatorType.Servo
		steering.LimitsEnabled = true
		steering.LowerAngle, steering.UpperAngle = -config.Steering.MaxAngle, config.Steering.MaxAngle
		steering.ServoMaxTorque, steering.AngularSpeed = config.Steering.ServoTorque, config.Steering.ServoSpeed
		steering.AngularResponsiveness = config.Steering.ServoResponsiveness
		local axis = body.CFrame.ZVector.Unit
		for _, endName in { "Front", "Back" } do
			local endConfig = if endName == "Front" then config.Front else config.Back
			local base = if endName == "Front" and not config.IndependentFrontSteering then stick else body
			local group = endName .. "Suspension"
			local wheel = part(model, endName .. "Wheel")
			assign(wheel, endName .. "Wheel")
			local axle = Instance.new("Part")
			axle.Name = "Virtual" .. endName .. "Axle"
			axle.Size, axle.CFrame = config.AxleSize, CFrame.new(wheel.Position)
			axle.Transparency, axle.Anchored, axle.CanCollide, axle.CanTouch, axle.CanQuery = 1, true, false, false, false
			axle.Parent = model
			assign(axle, group)
			local mount = body.CFrame * (endConfig.PivotBodyLocal * config.Scale)
			for _, side in { "Left", "Right" } do
				local arm = part(model, if side == "Left" then endConfig.LeftName else endConfig.RightName)
				assign(arm, group)
				local position = mount + axis * (arm.Position - mount):Dot(axis)
				hinge(base, arm, endName .. "Suspension" .. side .. "Hinge", position, axis, config.ShowConstraints)
				weld(axle, arm)
			end
			local wheelBase = axle
			if endName == "Front" and config.IndependentFrontSteering then
				-- Deck-side swingarms must not sweep around the steering column.
				-- A separate kingpin lets the tire steer while its axle follows suspension.
				local carrier = Instance.new("Part")
				carrier.Name = "FrontSteeringCarrier"
				carrier.Size, carrier.CFrame = config.SteeringCarrierSize, CFrame.new(wheel.Position)
				carrier.Transparency, carrier.Anchored, carrier.CanCollide, carrier.CanTouch, carrier.CanQuery = 1, true, false, false, false
				carrier.Parent = model
				assign(carrier, "FrontSteering")
				local kingpin = hinge(axle, carrier, "FrontSteeringHinge", wheel.Position, body.CFrame.UpVector.Unit, config.ShowConstraints)
				kingpin.ActuatorType = Enum.ActuatorType.Servo
				kingpin.LimitsEnabled = true
				kingpin.LowerAngle, kingpin.UpperAngle = -config.Steering.MaxAngle, config.Steering.MaxAngle
				kingpin.ServoMaxTorque, kingpin.AngularSpeed = config.Steering.ServoTorque, config.Steering.ServoSpeed
				kingpin.AngularResponsiveness = config.Steering.ServoResponsiveness
				wheelBase = carrier
			end
			hinge(wheelBase, wheel, endName .. "WheelHinge", wheel.Position, axis, config.ShowConstraints)
			local coil = part(model, endConfig.SpringName)
			assign(coil, if base == stick then "Steering" else "Body")
			coil.Massless = true
			weld(base, coil)
			local upper = coil.Position + coil.CFrame.UpVector * coil.Size.Y * 0.5
			local lower = coil.Position - coil.CFrame.UpVector * coil.Size.Y * 0.5
			local shock = Instance.new("SpringConstraint")
			shock.Name = endName .. "Shock"
			shock.Attachment0 = attachment(base, endName .. "ShockUpper", CFrame.new(upper))
			shock.Attachment1 = attachment(axle, endName .. "ShockLower", CFrame.new(lower))
			shock.FreeLength = (upper - lower).Magnitude
			shock.Stiffness, shock.Damping, shock.MaxForce = config.Spring.Stiffness, config.Spring.Damping, config.Spring.MaxForce
			shock.Visible = config.ShowConstraints
			shock.Color = BrickColor.new("New Yeller")
			shock.Parent = base
		end
		local disc = part(model, "BrakeDisc")
		assign(disc, "FrontWheel")
		weld(part(model, "FrontWheel"), disc)
		local crossbar = part(model, "BackSpringStick")
		assign(crossbar, "BackSuspension")
		weld(assert(model:FindFirstChild("VirtualBackAxle")) :: BasePart, crossbar)
		for _, entry in config.ExtraComponents do
			if model:FindFirstChild(entry.Name) then
				local item, fixed = part(model, entry.Name), part(model, entry.FixedName)
				assign(item, entry.Assembly)
				item.Massless = true
				weld(fixed, item)
			end
		end
		model:SetAttribute("ScooterDraftRig", true)
		model:SetAttribute("IndependentFrontSteering", config.IndependentFrontSteering)
		model:SetAttribute("ScooterDraftScale", config.Scale)
		model:SetAttribute("ReferenceAvatarHeight", config.ReferenceAvatarHeight)
		model:SetAttribute("MountsVerified", config.MountsVerified)
		model:SetAttribute("SuspensionCalibrated", false)
		model:SetAttribute("SourcePath", source:GetFullName())
		DevScooterBuild.Validate(model, config)
	end)
	if not ok then model:Destroy(); error(tostring(problem), 2) end
	return model
end

-- Adornments mark every mechanical endpoint without adding physical parts to the rig.
function DevScooterBuild.MarkLinks(model: Model, settings: Configuration?)
	local config = settings or DefaultConfig
	local previous = model:FindFirstChild("_ScooterRigReview")
	if previous then previous:Destroy() end
	local markers = Instance.new("Folder")
	markers.Name = "_ScooterRigReview"
	markers.Parent = model
	for _, item in model:GetDescendants() do
		if item:IsA("Attachment") and item.Parent and item.Parent:IsA("BasePart") then
			local marker = Instance.new("SphereHandleAdornment")
			marker.Name, marker.Adornee, marker.CFrame = item.Name, item.Parent, item.CFrame
			marker.Radius, marker.Color3 = config.ReviewMarkers.Radius, config.ReviewMarkers.Color
			marker.AlwaysOnTop, marker.ZIndex = true, 1
			marker.Parent = markers
		elseif item:IsA("SpringConstraint") then
			local first, second = assert(item.Attachment0), assert(item.Attachment1)
			local parent = first.Parent :: BasePart
			local from = parent.CFrame:PointToObjectSpace(first.WorldPosition)
			local to = parent.CFrame:PointToObjectSpace(second.WorldPosition)
			local line = Instance.new("LineHandleAdornment")
			line.Name, line.Adornee = item.Name, parent
			line.CFrame, line.Length = CFrame.lookAt(from, to), (to - from).Magnitude
			line.Color3, line.Thickness = config.ReviewMarkers.Color, config.ReviewMarkers.LineThickness
			line.AlwaysOnTop, line.ZIndex = true, 1
			line.Parent = markers
		end
	end
end

function DevScooterBuild.Preview(source: Instance?, settings: Configuration?): Model
	local config = settings or DefaultConfig
	local authoring = ServerStorage:FindFirstChild("ScooterAuthoring")
	local target = source or assert(workspace:FindFirstChild(config.SourceName)
		or (authoring and authoring:FindFirstChild(config.SourceName)), "Missing authored source")
	local previous = workspace:FindFirstChild(config.PreviewName)
		or (authoring and authoring:FindFirstChild(config.PreviewName))
	assert(not previous or (previous:IsA("Model") and previous:GetAttribute("ScooterDraftRig") == true), "Preview name is occupied by an unrelated object")
	local backups = ServerStorage:FindFirstChild("ScooterRigDraftBackups")
	assert(not previous or not backups or backups:IsA("Folder"), "ScooterRigDraftBackups must be a Folder")
	local model = DevScooterBuild.Build(target, config)
	DevScooterBuild.MarkLinks(model, config)
	if previous then
		if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterRigDraftBackups"; backups.Parent = ServerStorage end
		previous.Parent = backups
	end
	model.Parent = workspace
	print("ScooterFinalRig: anchored draft preview built; verify mounts before calibration and gameplay integration")
	return model
end

return DevScooterBuild
