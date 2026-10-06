--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type Controller = {
	SetActive: (active: boolean) -> (),
	Destroy: () -> (),
}

local ScooterBrakeLight = {}

function ScooterBrakeLight.Create(model: Model): Controller?
	local dedicated = model:FindFirstChild("StopLight")
	local settings = if dedicated and dedicated:IsA("BasePart") then Config.StopLight else Config.BrakeLight
	local fender = dedicated or model:FindFirstChild("BackFender")
	if not settings.Enabled or not fender or not fender:IsA("BasePart") then return nil end
	local defaultMaterial, defaultColor = fender.Material, fender.Color
	local appearance = fender:FindFirstChildOfClass("SurfaceAppearance")
	local defaultTint = if appearance then appearance.Color else Color3.new(1, 1, 1)
	local defaultEmission = if appearance then appearance.EmissiveStrength else 0
	local defaultEmissionTint = if appearance then appearance.EmissiveTint else defaultTint
	-- PBR textures can mask the mesh material; a small light keeps braking visible
	-- without removing the authored SurfaceAppearance or inventing a diode mesh.
	local existing = fender:FindFirstChildOfClass("PointLight")
	local glow = existing or Instance.new("PointLight")
	local savedLight = { enabled = glow.Enabled, color = glow.Color, brightness = glow.Brightness, range = glow.Range, shadows = glow.Shadows }
	if not existing then glow.Name = "ScooterBrakeGlow" end
	glow.Color = settings.Color
	glow.Brightness = settings.Brightness
	glow.Range = settings.Range
	glow.Shadows = false
	glow.Enabled = false
	glow.Parent = fender
	local active: boolean? = nil
	local destroyed = false

	local function setActive(value: boolean)
		if destroyed or value == active then return end
		active = value
		fender.Material = if value then Enum.Material.Neon else if dedicated then Enum.Material.SmoothPlastic else defaultMaterial
		fender.Color = if value then settings.Color else if dedicated then Config.StopLight.OffColor else defaultColor
		if appearance then
			appearance.Color = if value then settings.Color else defaultTint
			appearance.EmissiveTint = if value then settings.Color else defaultEmissionTint
			appearance.EmissiveStrength = if value then settings.EmissiveStrength else defaultEmission
		end
		glow.Enabled = value
	end
	setActive(false)

	return {
		SetActive = setActive,
		Destroy = function()
			if destroyed then return end
			setActive(false)
			destroyed = true
			fender.Material, fender.Color = defaultMaterial, defaultColor
			if existing then
				glow.Enabled, glow.Color, glow.Brightness, glow.Range = savedLight.enabled, savedLight.color, savedLight.brightness, savedLight.range
				glow.Shadows = savedLight.shadows
			else glow:Destroy() end
		end,
	}
end

return ScooterBrakeLight
