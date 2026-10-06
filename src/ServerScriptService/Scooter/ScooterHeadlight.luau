--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type Controller = { SetActive: (boolean) -> (), Destroy: () -> () }
local ScooterHeadlight = {}

function ScooterHeadlight.Create(model: Model): Controller?
	local lamp = model:FindFirstChild("FrontLight")
	local root = model.PrimaryPart
	if not lamp or not lamp:IsA("BasePart") or not root then return nil end
	local material, color = lamp.Material, lamp.Color
	local appearance = lamp:FindFirstChildOfClass("SurfaceAppearance")
	local tint = if appearance then appearance.Color else Color3.new(1, 1, 1)
	local emission = if appearance then appearance.EmissiveStrength else 0
	local emissionTint = if appearance then appearance.EmissiveTint else tint
	local attachment = Instance.new("Attachment")
	attachment.Name = "HeadlightBeamAttachment"
	-- Mesh axes come from the import. Orient the beam along the scooter's forward
	-- direction; the attachment then turns naturally with the steering assembly.
	attachment.CFrame = CFrame.lookAt(Vector3.zero, lamp.CFrame:VectorToObjectSpace(root.CFrame.LookVector))
	attachment.Parent = lamp
	local beam = Instance.new("SpotLight")
	beam.Name = "HeadlightBeam"
	beam.Color = Config.Headlight.Color
	beam.Brightness = Config.Headlight.Brightness
	beam.Range = Config.Headlight.Range
	beam.Angle = Config.Headlight.Angle
	beam.Shadows = true
	beam.Enabled = false
	beam.Parent = attachment
	local active, destroyed = false, false
	local function setActive(value: boolean)
		if destroyed or value == active then return end
		active = value
		beam.Enabled = value
		lamp.Material = if value then Enum.Material.Neon else material
		lamp.Color = if value then Config.Headlight.Color else color
		if appearance then
			appearance.Color = if value then Config.Headlight.Color else tint
			appearance.EmissiveTint = if value then Config.Headlight.Color else emissionTint
			appearance.EmissiveStrength = if value then Config.Headlight.EmissiveStrength else emission
		end
	end
	return {
		SetActive = setActive,
		Destroy = function()
			if destroyed then return end
			setActive(false)
			destroyed = true
			attachment:Destroy()
		end,
	}
end

return ScooterHeadlight
