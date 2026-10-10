--!strict

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Scooter.ScooterConfig)

export type Controller = {
	Update: (eligible: boolean, pitch: number, speed: number, params: RaycastParams) -> (),
	Destroy: () -> (),
}
local ScooterScrape = {}

function ScooterScrape.Create(model: Model, root: BasePart, rearPoint: Attachment): Controller
	local settings = Config.WheelieSparks
	local point = Instance.new("Attachment")
	point.Name = "WheelieScrapePoint"
	-- A chassis attachment follows pitch but does not rotate with the rear tire.
	local rear = root.CFrame:PointToObjectSpace(rearPoint.WorldPosition)
	point.Position = rear + Vector3.new(0, 0.15, 0.65)
	point.Parent = root
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "WheelieSparks"
	sparks.Texture = settings.Texture
	sparks.Enabled = false
	sparks.Rate = settings.Rate
	sparks.Lifetime = settings.Lifetime
	sparks.Speed = settings.Speed
	sparks.EmissionDirection = Enum.NormalId.Back
	sparks.SpreadAngle = Vector2.new(28, 18)
	sparks.Acceleration = Vector3.new(0, -35, 0)
	sparks.Drag = 3
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150), Color3.fromRGB(255, 100, 15))
	sparks.Size = NumberSequence.new(settings.Size, 0)
	sparks.Transparency = NumberSequence.new(0, 1)
	sparks.Parent = point
	model:SetAttribute("WheelieSparksActive", false)
	local active, destroyed = false, false
	return {
		Update = function(eligible, pitch, speed, params)
			if destroyed then return end
			local threshold = if active then settings.StopPitch else settings.StartPitch
			local enabled = eligible and pitch >= threshold and speed >= settings.MinSpeed
			if enabled then
				local probePosition = root.CFrame:PointToWorldSpace(rear + Vector3.new(0, 0.15, 0.65))
				local hit = Workspace:Raycast(probePosition + Vector3.yAxis * 0.1,
					-Vector3.yAxis * (settings.ContactDistance + 0.1), params)
				enabled = hit ~= nil and hit.Normal.Y >= Config.GroundMinNormalY
				if hit then point.Position = root.CFrame:PointToObjectSpace(hit.Position + Vector3.yAxis * 0.04) end
			end
			-- Recompute from the chassis each update; the previous ground hit must
			-- not become the next frame's probe origin as the scooter rises.
			if enabled ~= active then
				active = enabled
				sparks.Enabled = enabled
				model:SetAttribute("WheelieSparksActive", enabled)
			end
			if not enabled then point.Position = rear + Vector3.new(0, 0.15, 0.65) end
		end,
		Destroy = function()
			if destroyed then return end
			destroyed = true
			model:SetAttribute("WheelieSparksActive", false)
			point:Destroy()
		end,
	}
end

return ScooterScrape
