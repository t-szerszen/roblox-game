--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type Visuals = {
	smokeColor: Color3,
	smokeEnabled: boolean,
	neonColor: Color3,
	neonEnabled: boolean,
}

export type Effects = {
	smoke: ParticleEmitter,
	neon: Part,
	light: PointLight,
}

local ScooterEffects = {}

function ScooterEffects.Create(model: Model, root: BasePart, rearPoint: Attachment, smoke: ParticleEmitter): Effects
	local existing = model:FindFirstChild("RearWheelAttachment", true)
	local rearAttachment = if existing and existing:IsA("Attachment") then existing else Instance.new("Attachment")
	-- Use the axle on the stable chassis so visual wheel spin cannot rotate the emitter.
	rearAttachment.Name = "RearWheelAttachment"
	rearAttachment.Parent = root
	rearAttachment.Position = root.CFrame:PointToObjectSpace(rearPoint.WorldPosition)
	smoke.Parent = rearAttachment

	local neon = Instance.new("Part")
	neon.Name = "GarageUnderglow"
	neon.Size = Vector3.new(0.7, 0.08, 2.2)
	neon.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.5 - 0.05, 0)
	neon.Material = Enum.Material.Neon
	neon.Transparency = 1
	neon.CanCollide = false
	neon.CanTouch = false
	neon.CanQuery = false
	neon.Massless = true
	neon.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = neon
	weld.Parent = neon

	local light = Instance.new("PointLight")
	light.Name = "UnderglowLight"
	light.Enabled = false
	light.Brightness = ScooterConfig.NeonBrightness
	light.Range = ScooterConfig.NeonRange
	light.Shadows = false
	light.Parent = neon
	return { smoke = smoke, neon = neon, light = light }
end

function ScooterEffects.Apply(effects: Effects, visuals: Visuals)
	-- Entitlement verification and RGB validation happen in GarageService.
	effects.smoke.Color = ColorSequence.new(if visuals.smokeEnabled then visuals.smokeColor else Color3.new(1, 1, 1))
	effects.neon.Color = visuals.neonColor
	effects.neon.Transparency = if visuals.neonEnabled then 0 else 1
	effects.light.Color = visuals.neonColor
	effects.light.Enabled = visuals.neonEnabled
end

return ScooterEffects
