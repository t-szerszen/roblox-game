--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local BEACON_NAME = "czerwonabulba"
local BEACON_TAG = "TowerBeacon"
local BLINK_INTERVAL = 30
local BLINK_DURATION = 0.5

local beacons: { [BasePart]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local running = true

local function isBeacon(instance: Instance): boolean
	return instance:IsA("BasePart")
		and (string.lower(instance.Name) == BEACON_NAME or CollectionService:HasTag(instance, BEACON_TAG))
end

local function track(instance: Instance)
	if isBeacon(instance) then
		beacons[instance :: BasePart] = true
	end
end

local function untrack(instance: Instance)
	if instance:IsA("BasePart") then
		beacons[instance] = nil
	end
end

local function setBeaconEnabled(part: BasePart, enabled: boolean)
	if part.Parent == nil then
		beacons[part] = nil
		return
	end

	part.Transparency = if enabled then 0 else 1
	part.Material = if enabled then Enum.Material.Neon else Enum.Material.Plastic
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("PointLight") then
			descendant.Enabled = enabled
		end
	end
end

for _, descendant in Workspace:GetDescendants() do
	track(descendant)
end

table.insert(connections, Workspace.DescendantAdded:Connect(track))
table.insert(connections, Workspace.DescendantRemoving:Connect(untrack))
table.insert(connections, CollectionService:GetInstanceAddedSignal(BEACON_TAG):Connect(track))
table.insert(connections, CollectionService:GetInstanceRemovedSignal(BEACON_TAG):Connect(function(instance: Instance)
	if string.lower(instance.Name) ~= BEACON_NAME then
		untrack(instance)
	end
end))

script.Destroying:Connect(function()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(beacons)
end)

task.spawn(function()
	while running do
		task.wait(BLINK_INTERVAL)
		if not running then
			break
		end

		for part in beacons do
			setBeaconEnabled(part, false)
		end
		task.wait(BLINK_DURATION)
		for part in beacons do
			setBeaconEnabled(part, true)
		end
	end
end)
