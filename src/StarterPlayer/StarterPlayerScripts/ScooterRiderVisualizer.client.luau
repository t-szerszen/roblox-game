--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterAnimator = require(script.Parent.ScooterAnimator)

type Binding = {
	seat: VehicleSeat,
	animator: ScooterAnimator.Animator,
	connections: { RBXScriptConnection },
	mounted: boolean,
	retryConnection: RBXScriptConnection?,
}

local bindings: { [Model]: Binding } = {}
local destroyed = false

local function refresh(binding: Binding)
	if binding.retryConnection then
		binding.retryConnection:Disconnect()
		binding.retryConnection = nil
	end
	binding.animator.dismount()
	binding.mounted = false
	local rider = binding.seat.Occupant
	local character = if rider then rider.Parent else nil
	if character and character:IsA("Model") then
		binding.mounted = binding.animator.mount(character)
		if not binding.mounted then
			binding.retryConnection = character.DescendantAdded:Connect(function()
				refresh(binding)
			end)
		end
	end
end

local function removeScooter(instance: Instance)
	if not instance:IsA("Model") then return end
	local binding = bindings[instance]
	if not binding then return end
	bindings[instance] = nil
	for _, connection in binding.connections do connection:Disconnect() end
	if binding.retryConnection then binding.retryConnection:Disconnect() end
	binding.animator.dismount()
end

local function addScooter(instance: Instance)
	if destroyed or not instance:IsA("Model") then return end
	local existing = bindings[instance]
	if existing then
		if not existing.mounted then refresh(existing) end
		return
	end
	local seat = instance:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") then return end
	local binding: Binding = {
		seat = seat, animator = ScooterAnimator.new(instance), connections = {}, mounted = false, retryConnection = nil,
	}
	bindings[instance] = binding
	table.insert(binding.connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		refresh(binding)
	end))
	table.insert(binding.connections, instance.Destroying:Connect(function() removeScooter(instance) end))
	refresh(binding)
end

local folder = workspace:WaitForChild(Config.ScooterFolderName)
local added = folder.ChildAdded:Connect(addScooter)
local removed = folder.ChildRemoved:Connect(removeScooter)
-- Replication can deliver DriverSeat and grip attachments after the model itself.
local descendantAdded = folder.DescendantAdded:Connect(function(instance: Instance)
	local ancestor = instance.Parent
	while ancestor and ancestor.Parent ~= folder do ancestor = ancestor.Parent end
	if ancestor then addScooter(ancestor) end
end)
for _, scooter in folder:GetChildren() do addScooter(scooter) end

script.Destroying:Connect(function()
	destroyed = true
	added:Disconnect()
	removed:Disconnect()
	descendantAdded:Disconnect()
	for scooter in bindings do removeScooter(scooter) end
end)
