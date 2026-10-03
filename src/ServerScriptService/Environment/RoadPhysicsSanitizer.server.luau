--!strict

local Workspace = game:GetService("Workspace")

local ROAD_HINTS = { "road", "street", "avenue", "intersection", "asphalt", "crossing" }
local MARKING_HINTS = { "marking", "centerline", "lane", "stripe", "paint" }
local ROAD_PROPERTIES = PhysicalProperties.new(0.7, 0.25, 0, 10, 10)
local PROXY_ATTRIBUTE = "RoadCollisionProxy"

local mapDescendantConnection: RBXScriptConnection? = nil
local workspaceChildConnection: RBXScriptConnection? = nil
local destroyed = false

local function containsHint(name: string, hints: { string }): boolean
	local normalized = string.lower(name)
	for _, hint in hints do
		if string.find(normalized, hint, 1, true) then
			return true
		end
	end
	return false
end

local function belongsToRoad(instance: Instance, map: Instance): boolean
	local current: Instance? = instance
	while current and current ~= map do
		if containsHint(current.Name, ROAD_HINTS) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isRoadMarking(part: BasePart): boolean
	return containsHint(part.Name, MARKING_HINTS)
end

local function createCollisionProxy(mesh: MeshPart): Part
	local proxy = Instance.new("Part")
	proxy.Name = string.format("%s_CollisionProxy", mesh.Name)
	proxy:SetAttribute(PROXY_ATTRIBUTE, true)
	proxy.Size = mesh.Size + Vector3.new(0.04, 0, 0.04)
	proxy.CFrame = mesh.CFrame
	proxy.Transparency = 1
	proxy.CastShadow = false
	proxy.Anchored = true
	proxy.CanCollide = true
	proxy.CanTouch = false
	proxy.CanQuery = true
	proxy.CustomPhysicalProperties = ROAD_PROPERTIES
	proxy.Parent = mesh.Parent
	return proxy
end

local function sanitizePart(part: BasePart, map: Instance)
	if part:GetAttribute(PROXY_ATTRIBUTE) == true or not belongsToRoad(part, map) then
		return
	end

	part.CanTouch = false
	if isRoadMarking(part) then
		part.CanCollide = false
		part.CanQuery = false
		return
	end

	if part:IsA("MeshPart") and part.CanCollide then
		createCollisionProxy(part)
		part.CanCollide = false
		part.CanQuery = false
		return
	end

	if part.CanCollide then
		part.CustomPhysicalProperties = ROAD_PROPERTIES
	end
end

local function attachMap(map: Instance)
	if mapDescendantConnection then
		mapDescendantConnection:Disconnect()
		mapDescendantConnection = nil
	end

	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") then
			sanitizePart(descendant, map)
		end
	end
	mapDescendantConnection = map.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			sanitizePart(descendant, map)
		end
	end)
end

local existingMap = Workspace:FindFirstChild("Map")
if existingMap then
	attachMap(existingMap)
end

workspaceChildConnection = Workspace.ChildAdded:Connect(function(child: Instance)
	if not destroyed and child.Name == "Map" then
		attachMap(child)
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	if mapDescendantConnection then
		mapDescendantConnection:Disconnect()
		mapDescendantConnection = nil
	end
	if workspaceChildConnection then
		workspaceChildConnection:Disconnect()
		workspaceChildConnection = nil
	end
end)
