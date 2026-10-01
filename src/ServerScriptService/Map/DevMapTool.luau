--!strict

local AssetRegistry = require(script.Parent.AssetRegistry)
local MapData = require(script.Parent.MapData)

type Placement = {
	asset: string,
	position: Vector3,
	rotation: Vector3,
	scale: number,
}

type ModelSnapshot = {
	model: Model,
	pivot: CFrame,
}

local DevMapTool = {}
local ROUNDING_FACTOR = 1000

local function mapFolder(createIfMissing: boolean): Folder
	local existing = workspace:FindFirstChild("Map")
	if existing then
		if not existing:IsA("Folder") then
			error("Workspace.Map exists but is not a Folder")
		end
		return existing
	end

	if not createIfMissing then
		error("Workspace.Map does not exist; run DevBuildMap() first")
	end

	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = workspace
	return folder
end

local function placementCFrame(placement: Placement): CFrame
	local rotation = placement.rotation
	return CFrame.new(placement.position)
		* CFrame.fromOrientation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

local function roundedNumber(value: number): string
	local scaled = value * ROUNDING_FACTOR
	local rounded: number
	if scaled >= 0 then
		rounded = math.floor(scaled + 0.5) / ROUNDING_FACTOR
	else
		rounded = math.ceil(scaled - 0.5) / ROUNDING_FACTOR
	end

	local formatted = string.format("%.3f", rounded):gsub("0+$", ""):gsub("%.$", "")
	if formatted == "-0" or formatted == "" then
		return "0"
	end
	return formatted
end

local function vectorExpression(vector: Vector3): string
	return string.format(
		"Vector3.new(%s, %s, %s)",
		roundedNumber(vector.X),
		roundedNumber(vector.Y),
		roundedNumber(vector.Z)
	)
end

function DevMapTool.DevBuildMap(): ()
	local folder = mapFolder(true)
	folder:ClearAllChildren()

	for _, placement in ipairs(MapData :: { Placement }) do
		local model = AssetRegistry.Create(placement.asset)
		model.Name = placement.asset
		model:ScaleTo(placement.scale)
		model:PivotTo(placementCFrame(placement))
		model.Parent = folder
	end

	print(string.format("DevMapTool: built %d map models in Workspace.Map", #folder:GetChildren()))
end

function DevMapTool.DevSerializeMap(): string
	local folder = mapFolder(false)
	local snapshots: { ModelSnapshot } = {}

	local function collectModels(container: Instance): ()
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Folder") then
				collectModels(child)
			elseif child:IsA("Model") then
				table.insert(snapshots, {
					model = child,
					pivot = child:GetPivot(),
				})
			else
				error(string.format("%s child %q is not a Model or Folder", container:GetFullName(), child.Name))
			end
		end
	end
	collectModels(folder)

	table.sort(snapshots, function(left: ModelSnapshot, right: ModelSnapshot): boolean
		if left.model.Name ~= right.model.Name then
			return left.model.Name < right.model.Name
		end
		local leftPosition = left.pivot.Position
		local rightPosition = right.pivot.Position
		if leftPosition.X ~= rightPosition.X then
			return leftPosition.X < rightPosition.X
		elseif leftPosition.Y ~= rightPosition.Y then
			return leftPosition.Y < rightPosition.Y
		end
		return leftPosition.Z < rightPosition.Z
	end)

	local lines = { "return {" }
	for _, snapshot in ipairs(snapshots) do
		local orientationX, orientationY, orientationZ = snapshot.pivot:ToOrientation()
		local rotation = Vector3.new(math.deg(orientationX), math.deg(orientationY), math.deg(orientationZ))
		table.insert(lines, string.format("\t{ asset = %q,", snapshot.model.Name))
		table.insert(lines, string.format("\t\tposition = %s,", vectorExpression(snapshot.pivot.Position)))
		table.insert(lines, string.format("\t\trotation = %s,", vectorExpression(rotation)))
		table.insert(lines, string.format("\t\tscale = %s, },", roundedNumber(snapshot.model:GetScale())))
	end
	table.insert(lines, "}")

	local source = table.concat(lines, "\n")
	print(source)
	return source
end

return DevMapTool
