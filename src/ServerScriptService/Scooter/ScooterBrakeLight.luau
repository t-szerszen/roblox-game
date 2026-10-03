--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type Controller = {
	SetActive: (active: boolean) -> (),
	Destroy: () -> (),
}

local ScooterBrakeLight = {}

function ScooterBrakeLight.Create(model: Model): Controller?
	local fender = model:FindFirstChild("BackFender")
	if not Config.BrakeLight.Enabled or not fender or not fender:IsA("MeshPart") then return nil end
	local defaultMaterial, defaultColor = fender.Material, fender.Color
	local appearance = fender:FindFirstChildOfClass("SurfaceAppearance")
	local defaultTint = if appearance then appearance.Color else Color3.new(1, 1, 1)
	local defaultEmission = if appearance then appearance.EmissiveStrength else 0
	local defaultEmissionTint = if appearance then appearance.EmissiveTint else defaultTint
	-- PBR textures can mask the mesh material; a small light keeps braking visible
	-- without removing the authored SurfaceAppearance or inventing a diode mesh.
	local glow = Instance.new("PointLight")
	glow.Name = "ScooterBrakeGlow"
	glow.Color = Config.BrakeLight.Color
	glow.Brightness = Config.BrakeLight.Brightness
	glow.Range = Config.BrakeLight.Range
	glow.Shadows = false
	glow.Enabled = false
	glow.Parent = fender
	local active, destroyed = false, false

	local function setActive(value: boolean)
		if destroyed or value == active then return end
		active = value
		fender.Material = if value then Enum.Material.Neon else defaultMaterial
		fender.Color = if value then Config.BrakeLight.Color else defaultColor
		if appearance then
			appearance.Color = if value then Config.BrakeLight.Color else defaultTint
			appearance.EmissiveTint = if value then Config.BrakeLight.Color else defaultEmissionTint
			appearance.EmissiveStrength = if value then Config.BrakeLight.EmissiveStrength else defaultEmission
		end
		glow.Enabled = value
	end

	return {
		SetActive = setActive,
		Destroy = function()
			if destroyed then return end
			setActive(false)
			destroyed = true
			glow:Destroy()
		end,
	}
end

return ScooterBrakeLight
