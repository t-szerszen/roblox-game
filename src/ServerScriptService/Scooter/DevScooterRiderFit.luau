--!strict
-- Explicit Edit-mode remodel. Reuses the installed rig and imported components;
-- never generates assets at startup or adds another character mounting system.
local RunService = game:GetService("RunService")
local Settings = require(script.Parent.DevScooterRiderFitConfig)
local Geometry = require(script.Parent.ScooterRigGeometry)
local Rig = require(script.Parent.ScooterRig)
local RiderFit = { HandlebarOffset = Settings.HandlebarOffset }

local function part(model: Model, name: string): BasePart
	local item = model:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing " .. name)
	return item
end

local function decoration(parent: Instance, fixed: BasePart, name: string, size: Vector3,
	frame: CFrame, color: Color3, paintable: boolean?): Part
	local item = Instance.new("Part")
	item.Name, item.Size, item.CFrame = name, size, frame
	item.Color, item.Material = color, Enum.Material.Metal
	item.Massless = true
	item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
	item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	item:SetAttribute("ScooterAssembly", "body")
	item:SetAttribute("ScooterDecoration", true)
	if paintable then
		item:SetAttribute("ScooterCustomGroup", "Deck")
		item:SetAttribute("ScooterCustomSolidColor", true)
	end
	item.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1 = "RiderFitDecorationWeld", fixed, item
	weld.Parent = item
	return item
end

local function frameAlong(first: Vector3, second: Vector3, right: Vector3): CFrame
	local up = (second - first).Unit
	right = (right - up * right:Dot(up)).Unit
	return CFrame.fromMatrix((first + second) * 0.5, right, up)
end

local function buildBody(model: Model, root: BasePart, body: BasePart)
	-- Retain the imported MeshPart as the rig's stable attachment owner. Its
	-- one-piece mesh includes the obsolete neck, so it cannot remain visible.
	body.Transparency = 1
	body:SetAttribute("RiderFitMechanicalCarrier", true)
	local visuals = Instance.new("Folder")
	visuals.Name, visuals.Parent = "RiderFitBody", model
	decoration(visuals, body, "BatteryCase", Settings.BatterySize,
		root.CFrame * CFrame.new(Settings.BatteryCenter), Settings.FrameColor)
	local deck = decoration(visuals, body, "DeckSurface", Settings.DeckSize,
		root.CFrame * CFrame.new(0, Settings.DeckTop - Settings.DeckSize.Y * 0.5, 0), Settings.DeckColor)
	deck.Material = Enum.Material.Rubber
	for _, side in { -1, 1 } do
		local name = if side < 0 then "Left" else "Right"
		decoration(visuals, body, "BatteryPanel" .. name,
			Vector3.new(Settings.PanelThickness, Settings.PanelHeight, Settings.PanelLength),
			root.CFrame * CFrame.new(side * (Settings.BatterySize.X + Settings.PanelThickness) * 0.5,
				Settings.BatteryCenter.Y, Settings.BatteryCenter.Z), Settings.PanelColor, true)
		decoration(visuals, body, "DeckTrim" .. name,
			Vector3.new(Settings.TrimThickness, Settings.TrimThickness, Settings.DeckSize.Z - 0.1),
			root.CFrame * CFrame.new(side * (Settings.DeckSize.X - Settings.TrimThickness) * 0.5,
				Settings.DeckTop - Settings.TrimThickness * 0.5, 0), Settings.TrimColor)
	end
	local point = body:FindFirstChild("SteerBase")
	assert(point and point:IsA("Attachment"), "Missing steering head")
	local head = point.WorldPosition
	local axis = point.WorldAxis.Unit
	local collar = decoration(visuals, body, "SteeringHead",
		Vector3.new(Settings.CollarLength, Settings.CollarDiameter, Settings.CollarDiameter),
		CFrame.fromMatrix(head, axis, root.CFrame.RightVector), Settings.FrameColor)
	collar.Shape = Enum.PartType.Cylinder
	for _, side in { -1, 1 } do
		local start = root.CFrame:PointToWorldSpace(Settings.NeckStart + Vector3.xAxis * side * Settings.NeckHalfWidth)
		local finish = head + root.CFrame.RightVector * side * Settings.NeckHalfWidth
		decoration(visuals, body, if side < 0 then "NeckRailLeft" else "NeckRailRight",
			Vector3.new(Settings.NeckRailSize.X, (finish - start).Magnitude, Settings.NeckRailSize.Y),
			frameAlong(start, finish, root.CFrame.RightVector), Settings.FrameColor)
	end
	-- Short transverse joins connect both rails to the actual steering bearing.
	decoration(visuals, body, "HeadCrossmember",
		Vector3.new(Settings.NeckHalfWidth * 2 + Settings.NeckRailSize.X, 0.22, 0.30),
		CFrame.new(head) * root.CFrame.Rotation, Settings.FrameColor)
end

function RiderFit.Build(source: Model): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Remodel in Studio Edit mode")
	assert(source:GetAttribute("LargeWheelRemodel") == true, "Expected installed large-wheel scooter")
	assert(source:GetAttribute("ReferenceRiderFit") ~= true, "Use the preserved template before rider fitting")
	local model = source:Clone()
	local ok, result = pcall(function(): Model
		local root = assert(model.PrimaryPart)
		local body, stick = part(model, "ScooterBody"), part(model, "HandleBarStick")
		local upperOffset = root.CFrame:VectorToWorldSpace(Settings.HandlebarOffset)
		local up = stick.CFrame.UpVector
		local drop = up * (Settings.HandlebarOffset.Y / root.CFrame:VectorToObjectSpace(up).Y)
		-- Move the entire front module together, placing its real steering axis
		-- under the accepted grips. Shortening along that same axis lowers the bar.
		local frontOffset = upperOffset - drop
		local originalBottom = stick.Position - up * stick.Size.Y * 0.5
		local originalTop = stick.Position + up * stick.Size.Y * 0.5
		local attachments: { [Attachment]: CFrame } = {}
		for _, a in stick:GetChildren() do if a:IsA("Attachment") then attachments[a] = a.WorldCFrame + frontOffset end end
		local welds: { { weld: WeldConstraint, first: BasePart, second: BasePart } } = {}
		for _, item in model:GetDescendants() do
			if item:IsA("WeldConstraint") and item.Part0 and item.Part1 then
				table.insert(welds, { weld = item, first = item.Part0, second = item.Part1 })
				local endpoints = item :: any
				endpoints.Part0, endpoints.Part1 = nil, nil
			end
		end
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				local group = item:GetAttribute("ScooterAssembly")
				if group == "steering" or group == "front" or group == "frontWheel"
					or item.Name == "FrontWheelCollider" then item.CFrame += frontOffset end
			end
		end
		for _, name in { "HandleBar", "LeftGrip", "RightGrip", "BrakeLeverLeft", "BrakeLeverRight", "Display", "FrontLight" } do
			part(model, name).CFrame += drop
		end
		local dashboard = model:FindFirstChild("ScooterDashboard")
		assert(dashboard and dashboard:IsA("Model"), "Missing dashboard")
		dashboard:PivotTo(dashboard:GetPivot() + drop)
		local bottom, top = originalBottom + frontOffset, originalTop + upperOffset
		local mass, properties = stick:GetMass(), stick.CurrentPhysicalProperties
		stick.Size = Vector3.new(stick.Size.X, (top - bottom).Magnitude, stick.Size.Z)
		stick.CFrame = CFrame.new((bottom + top) * 0.5) * stick.CFrame.Rotation
		local density = properties.Density * mass / stick:GetMass()
		assert(density <= 100, "Shaft density exceeds engine limit")
		stick.CustomPhysicalProperties = PhysicalProperties.new(density, properties.Friction, properties.Elasticity,
			properties.FrictionWeight, properties.ElasticityWeight)
		for attachment, frame in attachments do attachment.CFrame = stick.CFrame:ToObjectSpace(frame) end
		local base = body:FindFirstChild("SteerBase")
		assert(base and base:IsA("Attachment"), "Missing steering base")
		base.CFrame = body.CFrame:ToObjectSpace(base.WorldCFrame + frontOffset)
		for _, item in welds do item.weld.Part0, item.weld.Part1 = item.first, item.second end
		buildBody(model, root, body)
		model:SetAttribute("ReferenceRiderFit", true)
		model:SetAttribute("RiderFitRevision", Settings.Revision)
		model:SetAttribute("RiderFitStraightShaft", true)
		model:SetAttribute("RiderFitHandlebarOffset", Settings.HandlebarOffset)
		model:SetAttribute("RiderFitFrontOffset", root.CFrame:VectorToObjectSpace(frontOffset))
		Rig.Inspect(model)
		Geometry.AssertSafe(model)
		return model
	end)
	if not ok then model:Destroy(); error(tostring(result), 2) end
	return result :: Model
end

return RiderFit
