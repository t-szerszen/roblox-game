--!strict

local AssetRegistry = require(script.Parent.AssetRegistry)
local MapData = require(script.Parent.MapData)

type Placement = {
	asset: string,
	position: Vector3,
	rotation: Vector3,
	scale: number,
}

local MapBuilder = {}

local function transformFor(placement: Placement): CFrame
	local radians = Vector3.new(
		math.rad(placement.rotation.X),
		math.rad(placement.rotation.Y),
		math.rad(placement.rotation.Z)
	)
	return CFrame.new(placement.position) * CFrame.fromOrientation(radians.X, radians.Y, radians.Z)
end

function MapBuilder.Build(): Folder
	local stagedMap = Instance.new("Folder")
	stagedMap.Name = "Map_Staging"

	local success, result = pcall(function()
		for index, placement in ipairs(MapData :: { Placement }) do
			assert(typeof(placement.asset) == "string", "Map placement asset must be a string")
			assert(typeof(placement.position) == "Vector3", "Map placement position must be a Vector3")
			assert(typeof(placement.rotation) == "Vector3", "Map placement rotation must be a Vector3")
			assert(typeof(placement.scale) == "number" and placement.scale > 0, "Map placement scale must be positive")

			local model = AssetRegistry.Create(placement.asset)
			model.Name = string.format("%s_%02d", placement.asset, index)
			model:ScaleTo(placement.scale)
			model:PivotTo(transformFor(placement))
			model.Parent = stagedMap
		end
	end)

	if not success then
		stagedMap:Destroy()
		error(result, 2)
	end

	local workspaceMap = workspace:FindFirstChild("Map")
	if workspaceMap then
		workspaceMap:Destroy()
	end

	stagedMap.Name = "Map"
	stagedMap.Parent = workspace
	return stagedMap
end

return MapBuilder
