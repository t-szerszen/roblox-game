--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.ScooterConfig)
local FirstPerson = {}

function FirstPerson.Start(character: Model): { Destroy: () -> () }
	local player = Players.LocalPlayer
	local head = character:FindFirstChild("Head")
	if not player or player.Character ~= character or not head or not head:IsA("BasePart")
		or not Config.FirstPersonArms.Enabled then return { Destroy = function() end } end
	local arms: { [BasePart]: number } = {}
	for _, side in { "Left", "Right" } do
		for _, suffix in { "UpperArm", "LowerArm", "Hand", " Arm" } do
			local part = character:FindFirstChild(side .. suffix)
			if part and part:IsA("BasePart") then arms[part] = part.LocalTransparencyModifier end
		end
	end
	local binding = "ScooterFirstPersonArms_" .. player.UserId
	local visible = false
	local destroyed = false
	RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local firstPerson = camera ~= nil and (camera.CFrame.Position - head.Position).Magnitude < Config.FirstPersonArms.HeadDistance
		if firstPerson then
			for part in arms do if part.Parent then part.LocalTransparencyModifier = 0 end end
		elseif visible then
			for part, original in arms do if part.Parent then part.LocalTransparencyModifier = original end end
		end
		visible = firstPerson
	end)
	return { Destroy = function()
		if destroyed then return end
		destroyed = true
		RunService:UnbindFromRenderStep(binding)
		for part, original in arms do if part.Parent then part.LocalTransparencyModifier = original end end
		table.clear(arms)
	end }
end

return FirstPerson
