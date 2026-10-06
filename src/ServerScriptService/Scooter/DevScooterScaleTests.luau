--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.ScooterConfig)
local Server = require(script.Parent.ScooterServer)
local Collision = require(script.Parent.ScooterCollision)

local DevScooterScaleTests = {}
local display: Folder? = nil
local connections: { RBXScriptConnection } = {}

function DevScooterScaleTests.Stop()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	if display then display:Destroy(); display = nil end
end

function DevScooterScaleTests.Start()
	if not RunService:IsStudio() or not Config.StudioScaleComparisonEnabled or display then return end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local templates = ServerStorage:FindFirstChild("ScooterModels")
	if not spawn or not templates then return end
	local folder = Instance.new("Folder")
	folder.Name = "ScooterScaleTests"
	display = folder
	for _, variant in Config.StudioScaleVariants do
		local template = templates:FindFirstChild(variant.TemplateName)
		if not template or not template:IsA("Model") or template:GetAttribute("StudioScaleVariant") ~= variant.Id then continue end
		local model = template:Clone()
		model.Name = variant.Label
		local center = spawn.Position + variant.Offset
		local params = RaycastParams.new()
		params.RespectCanCollide = true
		local ground = workspace:Raycast(center + Vector3.yAxis * 8, -Vector3.yAxis * 30, params)
		local floorY = if ground then ground.Position.Y else spawn.Position.Y + spawn.Size.Y / 2
		local orientation = CFrame.new(center.X, 0, center.Z)
		model:PivotTo(orientation + Vector3.yAxis * (floorY + Collision.GetSpawnLift(model, orientation)))
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true; part.CanCollide = false; part.CanQuery = false end
			if part:IsA("Constraint") then part.Visible = false end
		end
		local root = assert(model.PrimaryPart)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ChooseScale"
		prompt.ObjectText = variant.Label
		prompt.ActionText = "Przywołaj do testu"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = Config.RidePromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		table.insert(connections, prompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			local playerRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if player.Parent ~= Players or not playerRoot or not playerRoot:IsA("BasePart")
				or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil
				or (playerRoot.Position - root.Position).Magnitude > prompt.MaxActivationDistance then return end
			Server.RequestStudioScaleForPlayer(player, variant.Id)
		end))
		model.Parent = folder
	end
	folder.Parent = workspace
end

return DevScooterScaleTests
