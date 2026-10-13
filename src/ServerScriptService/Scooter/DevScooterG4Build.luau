--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Settings = require(script.Parent.DevScooterG4Config)
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Rig = require(script.Parent.ScooterRig)
local Geometry = require(script.Parent.ScooterRigGeometry)
local DashboardConfig = require(ReplicatedStorage.Shared.Scooter.ScooterDashboardConfig)

local Builder = {}

local function parts(container: Instance, name: string): { BasePart }
	local result: { BasePart } = {}
	for _, item in container:GetChildren() do
		if item.Name == name and item:IsA("BasePart") then table.insert(result, item) end
	end
	return result
end

local function one(container: Instance, name: string): BasePart
	local found = parts(container, name)
	assert(#found == 1, container.Name .. " requires exactly one " .. name)
	return found[1]
end

local function group(model: Model, name: string): Model
	local item = model:FindFirstChild(name)
	assert(item and item:IsA("Model"), "G4 requires " .. name .. " Model")
	return item
end

local function frame(position: Vector3, axis: Vector3): CFrame
	local reference = if math.abs(axis.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	return CFrame.fromMatrix(position, axis, (reference - axis * reference:Dot(axis)).Unit)
end

local function point(parent: BasePart, name: string, worldFrame: CFrame): Attachment
	local item = Instance.new("Attachment")
	item.Name, item.CFrame = name, parent.CFrame:ToObjectSpace(worldFrame)
	item.Parent = parent
	return item
end

local function assign(part: BasePart, assembly: string, decoration: boolean)
	part:SetAttribute("ScooterAssembly", assembly)
	part:SetAttribute("ScooterDecoration", if decoration then true else nil)
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.Massless = decoration
end

local function weld(first: BasePart, second: BasePart)
	assert(first ~= second and first:GetAttribute("ScooterAssembly") == second:GetAttribute("ScooterAssembly"),
		"G4 weld crosses moving assemblies")
	local joint = Instance.new("WeldConstraint")
	joint.Name, joint.Part0, joint.Part1 = "G4AssemblyWeld", first, second
	joint.Parent = first
end

local function decorate(part: BasePart, owner: BasePart)
	assign(part, owner:GetAttribute("ScooterAssembly") :: string, true)
	weld(owner, part)
end

local function mass(part: BasePart, value: number)
	local properties = part.CurrentPhysicalProperties
	local density = properties.Density * value / part:GetMass()
	assert(density > 0 and density <= 100, part.Name .. ": unsupported density")
	part.CustomPhysicalProperties = PhysicalProperties.new(density, properties.Friction, 0,
		properties.FrictionWeight, 100)
end

local function helper(model: Model, name: string, at: CFrame, size: Vector3, assembly: string): Part
	local item = Instance.new("Part")
	item.Name, item.CFrame, item.Size, item.Transparency = name, at, size, 1
	assign(item, assembly, true)
	item.Parent = model
	return item
end

local function extract(part: BasePart, model: Model, name: string, assembly: string, desiredMass: number?): BasePart
	part.Name, part.Parent = name, model
	assign(part, assembly, desiredMass == nil)
	if desiredMass then mass(part, desiredMass) end
	return part
end

local function paint(part: BasePart, id: string)
	part:SetAttribute("ScooterCustomGroup", id)
	part:SetAttribute("ScooterCustomSolidColor", true)
end

local function hinge(first: BasePart, second: BasePart, name: string, fixedName: string,
	movingName: string, position: Vector3, axis: Vector3): HingeConstraint
	local at = frame(position, axis)
	local joint = Instance.new("HingeConstraint")
	joint.Name = name
	joint.Attachment0 = point(first, fixedName, at)
	joint.Attachment1 = point(second, movingName, at)
	joint.ActuatorType = Enum.ActuatorType.None
	joint.Visible = false
	joint.Parent = first
	return joint
end

function Builder.ResolveScale(source: Model, reference: Model?): number
	local grips = parts(group(source, "Cockpit"), "Grip")
	assert(#grips == 2, "G4 requires two grips")
	local tape = one(group(source, "Body"), "GripTape")
	local height = (grips[1].Position.Y + grips[2].Position.Y) * 0.5
		- tape.Position.Y - tape.Size.Y * 0.5
	local target = Settings.TargetGripHeight
	if reference then
		local bar = reference:FindFirstChild("HandleBar")
		local deck = reference:FindFirstChild("FootRest")
		local left = if bar then bar:FindFirstChild("LeftHandGrip") else nil
		local right = if bar then bar:FindFirstChild("RightHandGrip") else nil
		if deck and deck:IsA("BasePart") and left and left:IsA("Attachment") and right and right:IsA("Attachment") then
			local up = if reference.PrimaryPart then reference.PrimaryPart.CFrame.UpVector else Vector3.yAxis
			local half = (math.abs(deck.CFrame.RightVector:Dot(up)) * deck.Size.X
				+ math.abs(deck.CFrame.UpVector:Dot(up)) * deck.Size.Y
				+ math.abs(deck.CFrame.LookVector:Dot(up)) * deck.Size.Z) * 0.5
			target = ((left.WorldPosition + right.WorldPosition) * 0.5 - deck.Position):Dot(up) - half
		end
	end
	assert(height > 0 and target > 0, "Cannot determine upright G4 grip height")
	return math.clamp(target / height, Settings.MinimumScale, Settings.MaximumScale)
end

-- Build a detached runtime candidate. The source, map and active template are never mutated.
function Builder.Build(source: Model, requestedScale: number?, configuration: typeof(Config)?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Build G4 in Studio Edit mode")
	assert(source:IsA("Model") and source:GetAttribute("ScooterG4Rig") ~= true, "Use the raw G4 model")
	for _, item in source:GetDescendants() do
		assert(not item:IsA("LuaSourceContainer") and not item:IsA("Constraint")
			and not item:IsA("JointInstance") and not item:IsA("WeldConstraint"), "G4 source must be a script-free, unrigged model")
	end
	local config = configuration or Config
	local scale = requestedScale or Builder.ResolveScale(source, nil)
	assert(scale == scale and scale >= Settings.MinimumScale and scale <= Settings.MaximumScale, "Invalid G4 scale")
	local model = source:Clone()
	local staged: Model? = nil
	local ok, result = pcall(function(): Model
		local bodyGroup, cockpit, stem = group(model, "Body"), group(model, "Cockpit"), group(model, "Stem")
		local frontGroup, rearGroup = group(model, "FrontSuspension"), group(model, "RearSuspension")
		local frontWheelGroup, rearWheelGroup = group(model, "FrontWheel"), group(model, "RearWheel")
		local cables = group(model, "Cables")
		local index = 0
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				index += 1
				item:SetAttribute("G4SourcePart", index)
				item.Anchored = true
			elseif item:IsA("Light") then item.Enabled = false end
		end
		model.PrimaryPart = one(bodyGroup, "Deck")
		model:ScaleTo(model:GetScale() * scale)
		model.Name = Settings.CandidateName
		local forward = (one(frontWheelGroup, "Axle").Position - one(rearWheelGroup, "Axle").Position).Unit
		assert(math.abs(forward.Y) < 0.01, "G4 source must have level axles")
		local right = forward:Cross(Vector3.yAxis).Unit
		local function sideOf(part: BasePart): string
			return if (part.Position - model:GetPivot().Position):Dot(right) < 0 then "Left" else "Right"
		end
		local visuals = Instance.new("Folder")
		visuals.Name, visuals.Parent = "G4Visuals", model
		for _, component in { bodyGroup, cockpit, stem, frontGroup, rearGroup, frontWheelGroup, rearWheelGroup, cables } do
			component.Parent = visuals
		end
		frontWheelGroup.Name, rearWheelGroup.Name = "FrontWheelVisuals", "BackWheelVisuals"
		local body = extract(one(bodyGroup, "Deck"), model, "ScooterBody", "body", nil)
		paint(body, "Deck")
		local stick = extract(one(stem, "Stem"), model, "HandleBarStick", "steering", Settings.SteeringMass)
		paint(stick, "Stem")
		local grips = parts(cockpit, "Grip")
		assert(#grips == 2, "G4 requires exactly two grips")
		local bar = helper(model, "HandleBar", CFrame.new((grips[1].Position + grips[2].Position) * 0.5), Settings.HelperSize, "steering")
		weld(stick, bar)
		for _, grip in grips do
			extract(grip, model, sideOf(grip) .. "Grip", "steering", nil)
			decorate(grip, bar)
			paint(grip, "Grips")
		end
		for _, item in bodyGroup:GetChildren() do if item:IsA("BasePart") then
			if item.Name == "TailLens" then extract(item, model, "StopLight", "body", nil) end
			decorate(item, body)
		end end
		for _, item in stem:GetChildren() do if item:IsA("BasePart") then decorate(item, stick) end end
		for _, item in cockpit:GetChildren() do if item:IsA("BasePart") then
			if item.Name == "HeadlightLens" then extract(item, model, "FrontLight", "steering", nil)
			elseif item.Name == "DisplayGlass" then extract(item, model, "Display", "steering", nil)
			elseif item.Name == "BrakeLever" or item.Name == "LeverBend" or item.Name == "LeverTip" then paint(item, "BrakeLevers")
			elseif item.Name == "Handlebar" or item.Name == "BarBend" then paint(item, "Handlebar") end
			decorate(item, bar)
		end end
		local steeringHead = one(bodyGroup, "SteeringHead")
		local steer = hinge(body, stick, "HingeConstraint", "SteerBase", "SteerPivot",
			steeringHead.Position, steeringHead.CFrame.LookVector.Unit)
		steer.ActuatorType, steer.LimitsEnabled = Enum.ActuatorType.Servo, true
		steer.LowerAngle, steer.UpperAngle = -math.deg(config.MaxHandlebarAngle), math.deg(config.MaxHandlebarAngle)
		steer.AngularSpeed, steer.ServoMaxTorque = config.SteeringServoSpeed, config.SteeringServoTorque
		steer.AngularResponsiveness = config.SteeringServoResponsiveness
		local axles: { [string]: Part } = {}
		for _, endName in { "Front", "Back" } do
			local suspension = if endName == "Front" then frontGroup else rearGroup
			local wheelGroup = if endName == "Front" then frontWheelGroup else rearWheelGroup
			local assembly = if endName == "Front" then "front" else "back"
			local base = if endName == "Front" then stick else body
			local wheel = extract(one(wheelGroup, "Tyre"), model, endName .. "Wheel", assembly .. "Wheel", Settings.WheelMass)
			local _, size = wheelGroup:GetBoundingBox()
			wheel:SetAttribute("WheelRadius", math.max(size.Y, size.Z) * 0.5)
			wheel:SetAttribute("CompoundWheelVisuals", wheelGroup.Name)
			local axle = helper(model, "Virtual" .. endName .. "Axle", CFrame.new(wheel.Position), Settings.AxleSize, assembly)
			axles[endName] = axle
			local fender = helper(model, endName .. "Fender", CFrame.new(wheel.Position), Settings.HelperSize, assembly)
			weld(axle, fender)
			local fenderVisuals = Instance.new("Model")
			fenderVisuals.Name, fenderVisuals.Parent = "FenderVisuals", fender
			local arms: { [string]: BasePart } = {}
			local pivots: { [string]: Vector3 } = {}
			for _, bolt in parts(suspension, "PivotBolt") do pivots[sideOf(bolt)] = bolt.Position end
			for _, arm in parts(suspension, if endName == "Front" then "FrontArm" else "RearArm") do
				local side = sideOf(arm)
				assert(not arms[side] and pivots[side], "G4 arms and pivot bolts must straddle the deck")
				local suffix = endName .. "Suspension" .. side
				extract(arm, model, suffix, assembly, Settings.ArmMass)
				paint(arm, "Suspension")
				arms[side] = arm
				weld(axle, arm)
				local joint = hinge(base, arm, "PivotHinge_" .. suffix, "PivotAttBase_" .. suffix,
					"PivotAtt_" .. suffix, pivots[side], right)
				local moving = assert(joint.Attachment1)
				moving:SetAttribute("AuthoredPivotCFrame", moving.CFrame)
			end
			assert(arms.Left and arms.Right and pivots.Left and pivots.Right, "G4 needs two arms per axle")
			local eyes: { [string]: { BasePart } } = { Left = {}, Right = {} }
			for _, eye in parts(suspension, "ShockEye") do table.insert(eyes[sideOf(eye)], eye) end
			local shockModels: { [string]: Model } = {}
			local upperPositions: { [string]: Vector3 } = {}
			local lowerPositions: { [string]: Vector3 } = {}
			for _, side in { "Left", "Right" } do
				assert(#eyes[side] == 2, "G4 needs two shock eyes on each side")
				table.sort(eyes[side], function(a, b) return a.Position.Y > b.Position.Y end)
				local upper, lower = eyes[side][1].Position, eyes[side][2].Position
				upperPositions[side], lowerPositions[side] = upper, lower
				local suffix = endName .. "Suspension" .. side
				local shock = Instance.new("SpringConstraint")
				shock.Name = "ShockAbsorber_" .. suffix
				shock.Attachment0 = point(base, "SpringAttBase_" .. suffix, CFrame.new(upper))
				shock.Attachment1 = point(arms[side], "SpringAtt_" .. suffix, CFrame.new(lower))
				shock.FreeLength = (upper - lower).Magnitude
				shock.Stiffness, shock.Damping, shock.MaxForce = Settings.InitialSpringStiffness,
					Settings.InitialSpringDamping, Settings.InitialSpringMaxForce
				shock.Visible, shock.Parent = false, base
				local visual = Instance.new("Model")
				visual.Name, visual.Parent = suffix .. "CoilVisuals", visuals
				visual:SetAttribute("CompoundSpringConstraint", shock.Name)
				visual.WorldPivot = CFrame.fromMatrix((upper + lower) * 0.5, right, (upper - lower).Unit)
				shockModels[side] = visual
			end
			local fixedNames = if endName == "Front" then Settings.FrontFixed else Settings.RearFixed
			for _, item in suspension:GetChildren() do if item:IsA("BasePart") then
				local side = sideOf(item)
				local owner: BasePart = axle
				if item.Name == "Coil" or item.Name == "CoilJ" then
					item.Parent = shockModels[side]
					item:SetAttribute("G4ShockSection", "Coil")
					owner = base
				elseif table.find(Settings.ShockUpper, item.Name) then
					item.Parent, owner = shockModels[side], base
					item:SetAttribute("G4ShockSection", "Upper")
				elseif table.find(Settings.ShockLower, item.Name) then
					owner = arms[side]
					if item.Name ~= "ShockBrace" and item.Name ~= "ShockLowerTab" then
						item.Parent = shockModels[side]
						item:SetAttribute("G4ShockSection", "Lower")
					end
				elseif table.find(fixedNames, item.Name) then owner = base
				elseif item.Name == "ArmDecal" then owner = arms[side]
				elseif item.Name == "ShockEye" or item.Name == "ShockEyeBolt" then
					owner = if (item.Position - upperPositions[side]).Magnitude < (item.Position - lowerPositions[side]).Magnitude then base else arms[side]
				elseif item.Name:find("Fender", 1, true) or item.Name == "RearReflector" then
					item.Parent, owner = fenderVisuals, fender
				end
				decorate(item, owner)
			end end
			for _, item in wheelGroup:GetChildren() do if item:IsA("BasePart") then
				local fixed = table.find(Settings.WheelFixed, item.Name) ~= nil
				local owner: BasePart = if fixed then axle else wheel
				if item.Name == "Caliper" then
					extract(item, model, endName .. "BrakeCaliper", assembly, nil)
					paint(item, "Calipers")
				elseif item.Name == "BrakeRotor" then paint(item, "BrakeDiscs") end
				-- Stationary axle hardware must be excluded from the spinning render model.
				if fixed and item.Parent == wheelGroup then item.Parent = suspension end
				decorate(item, owner)
			end end
			hinge(axle, wheel, "HingeConstraint", "AxlePivot", "WheelCenter", wheel.Position, right)
		end
		for _, item in cables:GetChildren() do if item:IsA("BasePart") then
			local owner: BasePart = if table.find(Settings.BodyCables, item.Name) then body else stick
			if item.Name == "FrontBrakeLine" or item.Name == "FrontBrakeLineJ" or item.Name == "CableTie" then owner = axles.Front end
			decorate(item, owner)
		end end
		local tape = one(bodyGroup, "GripTape")
		local top = tape.Position + tape.CFrame.UpVector * tape.Size.Y * 0.5
		-- Cover the battery underside as well as the standing surface; a thin top
		-- plate would let the visible battery sink into a curb before the skid contacts it.
		local thickness = math.max(Settings.DeckThickness, top.Y - (body.Position.Y - body.Size.Y * 0.5))
		local deckCenter = top - Vector3.yAxis * thickness * 0.5
		local deck = helper(model, "FootRest", CFrame.lookAt(deckCenter, deckCenter + forward),
			Vector3.new(tape.Size.Z, thickness, tape.Size.X), "body")
		for _, side in { "Left", "Right" } do
			local sign = if side == "Left" then -1 else 1
			point(deck, side .. "FootTarget", deck.CFrame * CFrame.new(sign * config.BaseRidingPose.FootLateralOffset,
				deck.Size.Y * 0.5, sign * deck.Size.Z * 0.15))
		end
		local display = model:FindFirstChild("Display") :: BasePart
		local dashboardTemplate = ReplicatedStorage:FindFirstChild(DashboardConfig.TemplateName)
		local templateScreen = if dashboardTemplate then dashboardTemplate:FindFirstChild(DashboardConfig.ScreenName) else nil
		local gui = if templateScreen then templateScreen:FindFirstChild(DashboardConfig.GuiName) else nil
		assert(gui and gui:IsA("SurfaceGui"), "Existing dashboard GUI template is required")
		local dashboard = Instance.new("Model")
		dashboard.Name, dashboard.Parent = DashboardConfig.ModelName, model
		local screen = helper(model, DashboardConfig.ScreenName,
			CFrame.fromMatrix(display.Position + display.CFrame.UpVector * (display.Size.Y * 0.5 + 0.002),
				display.CFrame.LookVector, display.CFrame.RightVector, -display.CFrame.UpVector),
			Vector3.new(display.Size.Z, display.Size.X, 0.01), "steering")
		screen.Parent, dashboard.PrimaryPart = dashboard, screen
		decorate(screen, bar)
		for _, child in display:GetChildren() do if child:IsA("SurfaceGui") then child.Enabled = false end end
		local screenGui = gui:Clone()
		screenGui.Face, screenGui.Adornee, screenGui.Parent = Enum.NormalId.Front, screen, screen
		model:SetAttribute("ScooterG4Rig", true)
		model:SetAttribute("ScooterG4Revision", Settings.Revision)
		model:SetAttribute("AuthoredSuspensionRig", true)
		model:SetAttribute("CentralShockRig", false)
		model:SetAttribute("IndependentFrontSteering", false)
		model:SetAttribute("RuntimeChassisMass", Settings.ChassisMass)
		model:SetAttribute("SuspensionRiderMass", Settings.ReferenceRiderMass)
		model:SetAttribute("ScooterDraftScale", scale)
		model:SetAttribute("SourcePath", source:GetFullName())
		model:SetAttribute("G4SourcePartCount", index)
		model:SetAttribute("MountsVerified", false)
		for _, visual in visuals:GetChildren() do
			if visual:IsA("Model") and (visual.Name == "FrontWheelVisuals" or visual.Name == "BackWheelVisuals"
				or visual:GetAttribute("CompoundSpringConstraint")) then
				local count = 0
				for _, item in visual:GetChildren() do if item:IsA("BasePart") then count += 1 end end
				visual:SetAttribute("CompoundVisualPartCount", count)
			end
		end
		local prepared = Rig.Prepare(model, config)
		staged = prepared
		prepared.Name = Settings.CandidateName
		Builder.Validate(prepared, config)
		return prepared
	end)
	model:Destroy()
	if not ok then
		if staged then staged:Destroy() end
		error(tostring(result), 2)
	end
	return result :: Model
end

function Builder.Validate(model: Model, configuration: typeof(Config)?)
	Rig.Inspect(model)
	Geometry.AssertSafe(model, configuration or Config)
	local hinges, springs, originals = 0, 0, 0
	local links: { [BasePart]: { BasePart } } = {}
	local assemblies: { [string]: { BasePart } } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local assembly = item:GetAttribute("ScooterAssembly")
			-- Existing runtime helpers have canonical names and no custom assembly tag.
			if typeof(assembly) == "string" then
				assemblies[assembly] = assemblies[assembly] or {}
				table.insert(assemblies[assembly], item)
			end
			if item:GetAttribute("G4SourcePart") then originals += 1 end
		elseif item:IsA("HingeConstraint") then hinges += 1
		elseif item:IsA("SpringConstraint") then springs += 1
		elseif item:IsA("WeldConstraint") then
			local a, b = assert(item.Part0), assert(item.Part1)
			assert(item.Enabled and a:IsDescendantOf(model) and b:IsDescendantOf(model), "Invalid G4 weld")
			links[a], links[b] = links[a] or {}, links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	assert(hinges == 7 and springs == 4, "G4 requires seven hinges and four physical shocks")
	assert(originals == model:GetAttribute("G4SourcePartCount"), "G4 lost source geometry")
	for name, members in assemblies do
		local seen: { [BasePart]: boolean } = {}
		local pending = { members[1] }
		while #pending > 0 do
			local item = table.remove(pending) :: BasePart
			if seen[item] then continue end
			seen[item] = true
			local connected: { BasePart } = links[item] or {}
			for _, other in ipairs(connected) do table.insert(pending, other) end
		end
		for _, item in members do assert(seen[item], name .. ": disconnected G4 part " .. item.Name) end
	end
end

function Builder.Preview(source: Model?): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Preview G4 in Studio Edit mode")
	local raw = source or workspace:FindFirstChild(Settings.SourceName)
	assert(raw and raw:IsA("Model"), "Missing " .. Settings.SourceName)
	local previous = workspace:FindFirstChild(Settings.PreviewName)
	assert(not previous or previous:GetAttribute("ScooterG4Rig") == true, "G4 preview name is occupied")
	local backups = ServerStorage:FindFirstChild("ScooterRigDraftBackups")
	assert(not previous or not backups or backups:IsA("Folder"), "ScooterRigDraftBackups must be a Folder")
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	local reference = if templates then templates:FindFirstChild(Config.TemplateName) else nil
	local candidate = Builder.Build(raw, Builder.ResolveScale(raw, if reference and reference:IsA("Model") then reference else nil))
	for _, item in candidate:GetDescendants() do
		if item:IsA("BasePart") then item.Anchored, item.CanCollide = true, false end
	end
	candidate.Name = Settings.PreviewName
	candidate:PivotTo(candidate:GetPivot() + Settings.PreviewOffset)
	if previous then
		if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterRigDraftBackups"; backups.Parent = ServerStorage end
		previous.Name ..= "_" .. HttpService:GenerateGUID(false)
		previous.Parent = backups
	end
	candidate.Parent = workspace
	return candidate
end

function Builder.Stage(draft: Model): Model
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stage G4 in Studio Edit mode")
	assert(draft:GetAttribute("ScooterG4Rig") == true, "Select the prepared G4 rig")
	Builder.Validate(draft)
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	assert(templates and templates:IsA("Folder"), "Missing ScooterModels folder")
	local previous = templates:FindFirstChild(Settings.CandidateName)
	assert(not previous or previous:GetAttribute("ScooterG4Rig") == true, "G4 candidate name is occupied")
	local backups = ServerStorage:FindFirstChild("ScooterRigDraftBackups")
	assert(not previous or not backups or backups:IsA("Folder"), "ScooterRigDraftBackups must be a Folder")
	local candidate = Rig.Prepare(draft)
	candidate.Name = Settings.CandidateName
	for _, item in candidate:GetDescendants() do if item:IsA("BasePart") then item.Anchored = false end end
	if previous then
		if not backups then backups = Instance.new("Folder"); backups.Name = "ScooterRigDraftBackups"; backups.Parent = ServerStorage end
		previous.Name ..= "_" .. HttpService:GenerateGUID(false)
		previous.Parent = backups
	end
	candidate.Parent = templates
	return candidate
end

return Builder
