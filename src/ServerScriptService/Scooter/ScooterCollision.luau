--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type Contacts = { frontRadius: number, backRadius: number }
local ScooterCollision = {}

local function positive(value: unknown): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge
end

function ScooterCollision.ResolveRadius(model: Instance, wheel: BasePart): (number, string)
	local override = wheel:GetAttribute("WheelRadius")
	if positive(override) then return override :: number, "wheel attribute" end
	override = model:GetAttribute("WheelRadius")
	if positive(override) then return override :: number, "template attribute" end
	-- The smallest mesh dimension is normally tire thickness. The other two
	-- describe its diameter independently of the part's world orientation.
	local dimensions = { wheel.Size.X, wheel.Size.Y, wheel.Size.Z }
	table.sort(dimensions)
	return dimensions[2] * 0.5, "mesh bounds (verify in Studio)"
end

local function contact(model: Model, wheel: MeshPart, name: string, radius: number, configuration: typeof(Config))
	local center = wheel:FindFirstChild("WheelCenter")
	assert(center and center:IsA("Attachment"), wheel.Name .. " requires WheelCenter")
	local existing = model:FindFirstChild(name)
	assert(not existing or (existing:IsA("Part") and existing:GetAttribute("RuntimeCollisionProxy") == true),
		name .. " is reserved for the runtime wheel collider")
	local collider = (existing or Instance.new("Part")) :: Part
	local joint = collider:FindFirstChild("WheelColliderWeld")
	assert(not joint or joint:IsA("WeldConstraint"), "WheelColliderWeld must be a WeldConstraint")
	local weld = (joint or Instance.new("WeldConstraint")) :: WeldConstraint
	-- Disable before repositioning so an existing weld does not drag the wheel.
	weld.Enabled = false
	for _, instance in model:GetDescendants() do
		if instance:IsA("WeldConstraint") and instance ~= weld
			and ((instance.Part0 == wheel and instance.Part1 == collider)
				or (instance.Part1 == wheel and instance.Part0 == collider)) then
			-- Earlier runtime templates stored the proxy weld under the wheel.
			instance.Enabled = false
		end
	end
	collider.Name = name
	collider:SetAttribute("RuntimeCollisionProxy", true)
	collider.Shape = Enum.PartType.Ball
	local collisionRadius = math.max(radius * 0.5, radius - configuration.WheelColliderClearance)
	collider.Size = Vector3.one * collisionRadius * 2
	collider.CFrame = CFrame.new(center.WorldPosition)
	collider.Anchored = false
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CanQuery = false
	collider.Massless = true
	collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, configuration.GroundColliderFriction, 0, 100, 10)
	collider.Parent = model
	weld.Name = "WheelColliderWeld"
	weld.Part0, weld.Part1 = wheel, collider
	weld.Parent = collider
	weld.Enabled = true
end

local function deckContact(model: Model, configuration: typeof(Config))
	local deck = model:FindFirstChild("FootRest")
	assert(deck and deck:IsA("BasePart"), "Scooter requires FootRest")
	local existing = model:FindFirstChild("DeckCollider")
	assert(not existing or (existing:IsA("Part") and existing:GetAttribute("RuntimeCollisionProxy") == true),
		"DeckCollider is reserved for the runtime deck contact")
	local collider = (existing or Instance.new("Part")) :: Part
	local joint = collider:FindFirstChild("DeckColliderWeld")
	assert(not joint or joint:IsA("WeldConstraint"), "DeckColliderWeld must be a WeldConstraint")
	local weld = (joint or Instance.new("WeldConstraint")) :: WeldConstraint
	weld.Enabled = false
	collider.Name = "DeckCollider"
	collider:SetAttribute("RuntimeCollisionProxy", true)
	collider.Shape = Enum.PartType.Block
	local inset = configuration.DeckColliderInset * 2
	collider.Size = Vector3.new(math.max(0.05, deck.Size.X - inset),
		math.max(0.05, deck.Size.Y - inset), math.max(0.05, deck.Size.Z - inset))
	collider.CFrame = deck.CFrame
	collider.Anchored = false
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CanQuery = false
	collider.Massless = true
	collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, configuration.GroundColliderFriction, 0, 100, 10)
	collider.Parent = model
	weld.Name = "DeckColliderWeld"
	weld.Part0, weld.Part1 = deck, collider
	weld.Parent = collider
	weld.Enabled = true
	-- A road contact on the deck must not become a stop against its own tires.
	for _, endName in { "Front", "Back" } do
		local name = endName .. "WheelNoCollision"
		local found = collider:FindFirstChild(name)
		assert(not found or found:IsA("NoCollisionConstraint"), name .. " must be a NoCollisionConstraint")
		local pair = (found or Instance.new("NoCollisionConstraint")) :: NoCollisionConstraint
		pair.Name = name
		pair.Part0 = collider
		pair.Part1 = model:FindFirstChild(endName .. "WheelCollider") :: BasePart
		pair.Enabled = true
		pair.Parent = collider
	end
end

function ScooterCollision.Configure(model: Model, configuration: typeof(Config)?): Contacts
	local settings = configuration or Config
	local front = model:FindFirstChild("FrontWheel")
	local back = model:FindFirstChild("BackWheel")
	assert(front and front:IsA("MeshPart") and back and back:IsA("MeshPart"), "Scooter requires both authored wheels")
	local frontRadius, frontSource = ScooterCollision.ResolveRadius(model, front)
	local backRadius, backSource = ScooterCollision.ResolveRadius(model, back)
	contact(model, front, "FrontWheelCollider", frontRadius, settings)
	contact(model, back, "BackWheelCollider", backRadius, settings)
	deckContact(model, settings)
	model:SetAttribute("ResolvedFrontWheelRadius", frontRadius)
	model:SetAttribute("ResolvedBackWheelRadius", backRadius)
	model:SetAttribute("FrontWheelRadiusSource", frontSource)
	model:SetAttribute("BackWheelRadiusSource", backSource)
	model:SetAttribute("CollisionProxyMode", "ArticulatedWheelSpheresAndDeck")
	return { frontRadius = frontRadius, backRadius = backRadius }
end

function ScooterCollision.GetSpawnLift(model: Model, orientation: CFrame): number
	local root = model.PrimaryPart
	assert(root, "Prepared scooter requires PrimaryPart")
	local lowest = math.huge
	for _, name in { "FrontWheelCollider", "BackWheelCollider", "DeckCollider" } do
		local part = model:FindFirstChild(name)
		assert(part and part:IsA("BasePart"), "Prepared scooter requires " .. name)
		local offset = orientation:VectorToWorldSpace(root.CFrame:PointToObjectSpace(part.Position))
		local halfHeight = part.Size.Y * 0.5
		if name == "DeckCollider" then
			local rotation = orientation * root.CFrame:ToObjectSpace(part.CFrame).Rotation
			halfHeight = (math.abs(rotation.RightVector.Y) * part.Size.X
				+ math.abs(rotation.UpVector.Y) * part.Size.Y + math.abs(rotation.LookVector.Y) * part.Size.Z) * 0.5
		end
		lowest = math.min(lowest, offset.Y - halfHeight)
	end
	return math.max(0, -lowest)
end

return ScooterCollision
