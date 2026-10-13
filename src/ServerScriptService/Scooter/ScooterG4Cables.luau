--!strict

local Cables = {}
local REVISION = 1
type Segment = { part: Part, a: Vector3, b: Vector3, distance: number, length: number }

local function closestDistance(segments: { Segment }, position: Vector3): number
	local best, distance = math.huge, 0
	for _, segment in segments do
		local delta = segment.b - segment.a
		local fraction = math.clamp((position - segment.a):Dot(delta) / (segment.length * segment.length), 0, 1)
		local separation = (position - segment.a - delta * fraction).Magnitude
		if separation < best then best, distance = separation, segment.distance + fraction * segment.length end
	end
	return distance
end

-- Applied only to detached spawn/authoring copies; the authored template is retained.
function Cables.Configure(model: Model)
	if model:GetAttribute("ScooterG4Rig") ~= true or model:GetAttribute("G4CableRigRevision") == REVISION then return end
	local visuals = model:FindFirstChild("G4Visuals")
	local group = if visuals then visuals:FindFirstChild("Cables") else nil
	if not group or not group:IsA("Model") then return end
	local root = assert(model.PrimaryPart)
	local stick = model:FindFirstChild("HandleBarStick") :: BasePart
	local body = model:FindFirstChild("ScooterBody") :: BasePart
	local front = model:FindFirstChild("VirtualFrontAxle") :: BasePart
	assert(stick and body and front, "G4 cables require the articulated assemblies")
	local owners: { [BasePart]: BasePart } = {}
	local count = 0
	for _, route in {
		{ name = "FrontBrakeLine", finish = front, wrap = true },
		{ name = "RearBrakeLine", finish = body, wrap = false },
	} do
		local segments: { Segment } = {}
		local members: { Part } = {}
		for _, part in group:GetChildren() do
			if not part:IsA("Part") then continue end
			if part.Name == route.name and part.Shape == Enum.PartType.Cylinder then
				local half = part.CFrame.RightVector * part.Size.X * 0.5
				local a, b = part.Position - half, part.Position + half
				if (a - b):Dot(root.CFrame.UpVector) < 0 then a, b = b, a end
				table.insert(segments, { part = part, a = a, b = b, length = part.Size.X, distance = 0 })
			end
			if part.Name == route.name or part.Name == route.name .. "J" or (route.wrap and part.Name == "SpiralWrap") then
				table.insert(members, part)
			end
		end
		assert(#segments > 0, route.name .. " requires its authored cylinder chain")
		-- These authored brake routes descend monotonically from the column.
		table.sort(segments, function(a, b) return a.a:Dot(root.CFrame.UpVector) > b.a:Dot(root.CFrame.UpVector) end)
		local length = 0
		for _, segment in segments do segment.distance = length; length += segment.length end
		local transitionLength = length
		local tie = group:FindFirstChild("CableTie")
		if route.wrap and tie and tie:IsA("BasePart") then
			-- The lower run follows the axle rigidly after passing the actual fork clip.
			transitionLength = closestDistance(segments, tie.Position)
		end
		assert(transitionLength > 0, "G4 cable has no flexible span")
		local function weight(position: Vector3): number
			local t = math.clamp(closestDistance(segments, position) / transitionLength, 0, 1)
			return t * t * (3 - 2 * t)
		end
		for _, part in members do
			local a, b = part.Position, part.Position
			if part.Shape == Enum.PartType.Cylinder then
				local half = part.CFrame.RightVector * part.Size.X * 0.5
				a, b = part.Position - half, part.Position + half
			end
			part:SetAttribute("G4CableStartOwner", stick.Name)
			part:SetAttribute("G4CableEndOwner", route.finish.Name)
			for _, endpoint in { { name = "A", position = a }, { name = "B", position = b } } do
				part:SetAttribute("G4Cable" .. endpoint.name .. "Start", stick.CFrame:PointToObjectSpace(endpoint.position))
				part:SetAttribute("G4Cable" .. endpoint.name .. "End", route.finish.CFrame:PointToObjectSpace(endpoint.position))
				part:SetAttribute("G4Cable" .. endpoint.name .. "Weight", weight(endpoint.position))
			end
			owners[part] = if weight(part.Position) < 0.5 then stick else route.finish
			count += 1
		end
	end
	for _, part in group:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "CableGrommet" then owners[part] = stick
			elseif part.Name == "CableTie" then owners[part] = front end
		end
	end
	for _, joint in model:GetDescendants() do
		if joint:IsA("WeldConstraint") and joint.Name == "G4AssemblyWeld" and joint.Part1 then
			local owner = owners[joint.Part1]
			if owner then
				joint.Part0 = owner
				joint.Part1:SetAttribute("ScooterAssembly", owner:GetAttribute("ScooterAssembly"))
			end
		end
	end
	group:SetAttribute("G4CableVisualPartCount", count)
	model:SetAttribute("G4CableRigRevision", REVISION)
end

return Cables
