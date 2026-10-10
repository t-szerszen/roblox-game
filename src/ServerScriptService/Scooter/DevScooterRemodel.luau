--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local BuildConfig = require(script.Parent.DevScooterBuildConfig)
local Settings = require(script.Parent.DevScooterRemodelConfig)
local Builder = require(script.Parent.DevScooterBuild)
local Installer = require(script.Parent.DevScooterInstall)

local DevScooterRemodel = {}

local function singlePart(root: Instance, name: string): BasePart
	local component = assert(root:FindFirstChild(name), "Missing component: " .. name)
	if component:IsA("BasePart") then return component end
	local found: BasePart? = nil
	for _, item in component:GetDescendants() do
		if item:IsA("BasePart") then
			assert(not found, name .. " must have exactly one physical part")
			found = item
		end
	end
	return assert(found, name .. " requires a physical part")
end

local function decoration(parent: Model, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local item = Instance.new("Part")
	item.Name, item.Size, item.CFrame = name, size, cframe
	item.Color, item.Material = color, Enum.Material.Metal
	item.Anchored, item.Massless = true, true
	item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
	item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function rod(parent: Model, name: string, first: Vector3, second: Vector3, thickness: number, color: Color3): Part
	local direction = (second - first).Unit
	local up = if math.abs(direction:Dot(Vector3.yAxis)) < 0.95 then Vector3.yAxis else Vector3.zAxis
	up = (up - direction * up:Dot(direction)).Unit
	local item = decoration(parent, name, Vector3.new((second - first).Magnitude, thickness, thickness),
		CFrame.fromMatrix((first + second) * 0.5, direction, up), color)
	item.Shape = Enum.PartType.Cylinder
	return item
end

local function addDecorations(source: Model, body: BasePart, back: BasePart, diameter: number, scale: number)
	local fenderConfig, standConfig = Settings.Fender, Settings.Kickstand
	local radius = (diameter * 0.5 + fenderConfig.Clearance) / scale
	local width = back.Size.Z + fenderConfig.WidthMargin / scale
	local fender = Instance.new("Model")
	fender.Name, fender.Parent = "BackFender", source
	local startAngle, endAngle = math.rad(fenderConfig.StartAngle), math.rad(fenderConfig.EndAngle)
	local step = (endAngle - startAngle) / fenderConfig.Segments
	for index = 1, fenderConfig.Segments do
		local angle = startAngle + (index - 0.5) * step
		local offset = Vector3.new(-math.sin(angle) * radius, math.cos(angle) * radius, 0)
		local position = back.Position + body.CFrame:VectorToWorldSpace(offset)
		decoration(fender, "Arch" .. index,
			Vector3.new(2 * radius * math.tan(step * 0.5) + 0.015 / scale, fenderConfig.Thickness / scale, width),
			CFrame.new(position) * body.CFrame.Rotation * CFrame.Angles(0, 0, angle), fenderConfig.Color)
	end
	for _, side in { -1, 1 } do
		local from = back.Position + body.CFrame:VectorToWorldSpace(Vector3.new(0, 0.12 / scale, side * width * 0.5))
		local to = back.Position + body.CFrame:VectorToWorldSpace(Vector3.new(-math.sin(endAngle) * radius,
			math.cos(endAngle) * radius, side * width * 0.5))
		rod(fender, if side < 0 then "LeftSupport" else "RightSupport", from, to,
			fenderConfig.SupportThickness / scale, fenderConfig.Color)
	end
	local stand = Instance.new("Model")
	stand.Name, stand.Parent = "Kickstand", source
	local mount = body.CFrame:PointToWorldSpace(BuildConfig.Deck.CenterBodyLocal + standConfig.DeckOffset / scale)
	local tip = mount + body.CFrame:VectorToWorldSpace(Vector3.new(-standConfig.Length, -0.06, -0.035) / scale)
	rod(stand, "Mount", mount - body.CFrame.ZVector * 0.08 / scale,
		mount + body.CFrame.ZVector * 0.08 / scale, standConfig.Thickness * 2 / scale, standConfig.Color)
	rod(stand, "FoldedLeg", mount, tip, standConfig.Thickness / scale, standConfig.Color)
	decoration(stand, "Foot", standConfig.FootSize / scale, CFrame.new(tip) * body.CFrame.Rotation, standConfig.Color)
end

-- Remodel a detached authoring copy; gameplay and the two input sources remain untouched.
function DevScooterRemodel.BuildSource(original: Instance, wheelSource: Instance): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Remodel in Studio Edit mode")
	assert(original:IsA("Folder") or original:IsA("Model"), "Expected the unscaled component source")
	assert(original:GetAttribute("LargeWheelRemodel") ~= true and original:GetAttribute("ScooterDraftRig") ~= true,
		"Use the original unscaled ScooterFinal source")
	for _, item in original:GetDescendants() do
		assert(not item:IsA("LuaSourceContainer") and not item:IsA("Constraint") and not item:IsA("JointInstance"),
			"Expected a constraint-free authoring source")
	end
	local imported: BasePart? = if wheelSource:IsA("MeshPart") then wheelSource else nil
	if not imported then
		for _, item in wheelSource:GetDescendants() do
			if item:IsA("BasePart") then
				assert(not imported, "newFrontWheel must contain exactly one physical part")
				imported = item
			end
		end
	end
	assert(imported, "newFrontWheel requires a MeshPart")
	assert(imported:IsA("MeshPart"), "newFrontWheel must contain one MeshPart")
	assert(math.abs(imported.Size.X - imported.Size.Y) < 0.01 and imported.Size.Z < imported.Size.X,
		"Expected a wheel with its axle along mesh-local Z")
	assert(imported.Size.X > 0 and imported.Size.X <= Settings.MaximumWheelDiameter,
		"Imported wheel diameter is outside the supported range")
	local diameter = Settings.PlayableWheelDiameter
	assert(diameter > 0 and diameter <= Settings.MaximumWheelDiameter, "Playable wheel diameter is outside the supported range")
	local wheelScale = diameter / imported.Size.X
	local clone = assert(original:Clone(), "Source must be Archivable")
	local source: Model
	if clone:IsA("Model") then source = clone else
		source = Instance.new("Model")
		for _, item in clone:GetChildren() do item.Parent = source end
		clone:Destroy()
	end
	local ok, problem = pcall(function()
		local body = singlePart(source, "ScooterBody")
		local oldWheel, back = singlePart(source, "FrontWheel"), singlePart(source, "BackWheel")
		local scale = BuildConfig.Scale
		assert(diameter > math.max(oldWheel.Size.X, back.Size.X) * scale, "The replacement must enlarge both tires")
		local pivot = body.CFrame:PointToWorldSpace(BuildConfig.Front.PivotBodyLocal)
		local offset = body.CFrame:VectorToObjectSpace(oldWheel.Position - pivot)
		local reach = Vector2.new(offset.X, offset.Y).Magnitude
		local targetY = body.CFrame:VectorToObjectSpace(back.Position - pivot).Y
		assert(math.abs(targetY) < reach, "Front swingarm cannot reach the rear axle's rest height")
		local angle = math.asin(targetY / reach) - math.atan2(offset.Y, offset.X)
		assert(math.abs(math.deg(angle)) <= Settings.MaximumFrontArmRotationDegrees, "Front rest adjustment exceeds its safe range")
		local rotation = CFrame.new(pivot) * CFrame.fromAxisAngle(body.CFrame.ZVector.Unit, angle) * CFrame.new(-pivot)
		local thicknessChange = imported.Size.Z * wheelScale / scale - oldWheel.Size.Z
		local originalCenter = oldWheel.Position
		for _, name in { "FrontLeftSuspension", "FrontRightSuspension", "FrontSpringStick", "FrontBrakeCaliper", "BrakeDisc" } do
			local item = singlePart(source, name)
			item.CFrame = rotation * item.CFrame
			if name ~= "FrontSpringStick" then
				local lateral = body.CFrame:VectorToObjectSpace(item.Position - rotation * originalCenter).Z
				item.CFrame += body.CFrame.ZVector * math.sign(lateral) * thicknessChange * 0.5
			else
				item.Size += Vector3.new(0, 0, thicknessChange)
			end
		end
		local coil = singlePart(source, "FrontSpring")
		local upper = coil.Position + coil.CFrame.UpVector * coil.Size.Y * 0.5
		local lower = rotation * (coil.Position - coil.CFrame.UpVector * coil.Size.Y * 0.5)
		local up = (upper - lower).Unit
		local right = (body.CFrame.RightVector - up * body.CFrame.RightVector:Dot(up)).Unit
		coil.Size = Vector3.new(coil.Size.X, (upper - lower).Magnitude, coil.Size.Z)
		coil.CFrame = CFrame.fromMatrix((upper + lower) * 0.5, right, up)
		local wheel = imported:Clone()
		wheel.Name = oldWheel.Name
		wheel.Size = imported.Size * wheelScale / scale
		wheel.CFrame = CFrame.new(rotation * originalCenter) * oldWheel.CFrame.Rotation
		wheel.Parent = oldWheel.Parent
		oldWheel:Destroy()
		back.Size = Vector3.new(diameter / scale, diameter / scale, back.Size.Z)
		-- Clear stale absolute overrides so contact proxies are inferred from the enlarged meshes.
		wheel:SetAttribute("WheelRadius", nil)
		back:SetAttribute("WheelRadius", nil)
		source:SetAttribute("WheelRadius", nil)
		for _, item in source:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery = true, false, false, false
			end
		end
		addDecorations(source, body, back, diameter, scale)
		source.Name, source.PrimaryPart = Settings.SourceName, body
		source:SetAttribute("LargeWheelRemodel", true)
		source:SetAttribute("PlayableWheelDiameter", diameter)
		source:SetAttribute("FrontRestRotationDegrees", math.deg(angle))
		source:SetAttribute("OriginalSourcePath", original:GetFullName())
	end)
	if not ok then source:Destroy(); error(tostring(problem), 2) end
	return source
end

function DevScooterRemodel.Preview(): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play before creating the preview")
	local authoring = assert(ServerStorage:FindFirstChild("ScooterAuthoring"), "Missing preserved authoring sources")
	local original = assert(authoring:FindFirstChild(BuildConfig.SourceName), "Missing unscaled ScooterFinal")
	local wheel = assert(workspace:FindFirstChild(Settings.WheelSourceName), "Missing Workspace.newFrontWheel")
	local previous = workspace:FindFirstChild(Settings.PreviewName)
	assert(not previous or previous:GetAttribute("LargeWheelRemodel") == true, "Preview name belongs to an unrelated object")
	local source = DevScooterRemodel.BuildSource(original, wheel)
	local draft: Model? = nil
	local preview: Model? = nil
	local ok, problem = pcall(function()
		local options = table.clone(BuildConfig)
		options.PreviewName, options.PreviewOffset = Settings.DraftName, Settings.PreviewOffset
		draft = Builder.Build(source, options)
		preview = Installer.Prepare(assert(draft))
		local model = assert(preview)
		model.Name = Settings.PreviewName
		model:SetAttribute("LargeWheelRemodel", true)
		model:SetAttribute("PlayableWheelDiameter", source:GetAttribute("PlayableWheelDiameter"))
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then item.Anchored, item.CanCollide = true, false end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local map = workspace:FindFirstChild("Map")
		params.FilterDescendantsInstances = if map then { map, workspace.Terrain } else { workspace.Terrain }
		local lift: number? = nil
		for _, name in { "FrontWheelCollider", "BackWheelCollider" } do
			local tire = assert(model:FindFirstChild(name)) :: BasePart
			local hit = workspace:Raycast(tire.Position + Vector3.yAxis * 100, -Vector3.yAxis * 200, params)
			if hit and hit.Normal.Y > 0.8 then
				local correction = hit.Position.Y + 0.05 - (tire.Position.Y - tire.Size.Y * 0.5)
				lift = math.max(lift or correction, correction)
			end
		end
		if lift then model:PivotTo(model:GetPivot() + Vector3.yAxis * lift) end
	end)
	if not ok then
		source:Destroy()
		if draft then draft:Destroy() end
		if preview then preview:Destroy() end
		error(tostring(problem), 2)
	end
	local backups = ServerStorage:FindFirstChild("ScooterRigDraftBackups")
	if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterRigDraftBackups"; backups.Parent = ServerStorage end
	for _, name in { Settings.SourceName, Settings.DraftName } do
		local old = authoring:FindFirstChild(name)
		if old then old.Name ..= "_" .. HttpService:GenerateGUID(false); old.Parent = backups end
	end
	if previous then previous.Name ..= "_" .. HttpService:GenerateGUID(false); previous.Parent = backups end
	source.Parent = authoring
	assert(draft):SetAttribute("SourcePath", source:GetFullName())
	assert(draft).Parent = authoring
	local model = assert(preview)
	model:SetAttribute("SourcePath", source:GetFullName())
	model.Parent = workspace
	return model
end

return DevScooterRemodel
