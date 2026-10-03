--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local ScooterRiderPose = require(script.Parent.ScooterRiderPose)

type Controller = ScooterRiderPose.Controller
type ScooterBinding = {
	connection: RBXScriptConnection,
	controller: Controller?,
}

local bindings: { [Model]: ScooterBinding } = {}
local pending: { [Model]: boolean } = {}
local destroyed = false

local function stopPose(binding: ScooterBinding)
	if binding.controller then
		binding.controller:Destroy()
		binding.controller = nil
	end
end

local function refreshPose(scooter: Model, seat: VehicleSeat, binding: ScooterBinding)
	stopPose(binding)
	local occupant = seat.Occupant
	local character = if occupant then occupant.Parent else nil
	if character and character:IsA("Model") then
		binding.controller = ScooterRiderPose.Start(character, scooter)
	end
end

local function addScooter(instance: Instance)
	if not instance:IsA("Model") or bindings[instance] or pending[instance] then
		return
	end

	pending[instance] = true
	task.spawn(function()
		local seat = instance:FindFirstChild("DriverSeat", true) or instance:WaitForChild("DriverSeat", 5)
		pending[instance] = nil
		if destroyed or not seat or not seat:IsA("VehicleSeat") or instance.Parent == nil or bindings[instance] then
			return
		end

		local binding: ScooterBinding = {
			connection = nil :: any,
			controller = nil,
		}
		binding.connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			refreshPose(instance, seat, binding)
		end)
		bindings[instance] = binding
		refreshPose(instance, seat, binding)
	end)
end

local function removeScooter(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	pending[instance] = nil
	local binding = bindings[instance]
	if not binding then
		return
	end

	binding.connection:Disconnect()
	stopPose(binding)
	bindings[instance] = nil
end

local scooterFolder = workspace:WaitForChild(ScooterConfig.ScooterFolderName)
for _, scooter in scooterFolder:GetChildren() do
	addScooter(scooter)
end
local scooterAddedConnection = scooterFolder.ChildAdded:Connect(addScooter)
local scooterRemovedConnection = scooterFolder.ChildRemoved:Connect(removeScooter)

local renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
	for _, binding in bindings do
		if binding.controller then
			binding.controller:Update(deltaTime)
		end
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	renderConnection:Disconnect()
	scooterAddedConnection:Disconnect()
	scooterRemovedConnection:Disconnect()
	for scooter, binding in bindings do
		binding.connection:Disconnect()
		stopPose(binding)
		bindings[scooter] = nil
	end
	table.clear(pending)
end)
