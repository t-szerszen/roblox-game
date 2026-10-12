--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(script.Parent.Parent.Activity.PlayerDataService)
local Paint = require(ReplicatedStorage.Shared.ScooterCustomPaint)
local CustomConfig = require(ReplicatedStorage.Shared.ScooterCustomConfig)
local Effects = require(script.Parent.ScooterEffects)

local Cosmetics = {}
local defaults: { [Model]: { [string]: Color3 } } = {}

function Cosmetics.GetVisuals(player: Player, modelName: string): Effects.Visuals
	local profile = Data.GetProfile(player)
	local visual = if profile then profile.visualsByModel[modelName] else nil
	local smoke = if visual then visual.Smoke else nil
	local neon = if visual then visual.Neon else nil
	return {
		smokeEnabled = Data.OwnsProduct(player, "burnout_smoke") and smoke ~= nil and smoke.enabled,
		smokeColor = if smoke then Color3.new(smoke.color[1], smoke.color[2], smoke.color[3]) else Color3.new(1, 1, 1),
		neonEnabled = Data.OwnsProduct(player, "scooter_neons") and neon ~= nil and neon.enabled,
		neonColor = if neon then Color3.new(neon.color[1], neon.color[2], neon.color[3]) else Color3.new(0, 1, 1),
	}
end

function Cosmetics.ApplyPaint(player: Player, model: Model)
	local profile = Data.GetProfile(player)
	local modelName = model:GetAttribute("ScooterModel")
	if not profile or typeof(modelName) ~= "string" then return end
	if not defaults[model] then
		defaults[model] = Paint.Read(model)
		local connection: RBXScriptConnection? = nil
		connection = model.Destroying:Connect(function()
			defaults[model] = nil
			if connection then connection:Disconnect() end
		end)
	end
	local colors = table.clone(defaults[model])
	for id, rgb in profile.paintByModel[modelName] or {} do
		colors[id] = Color3.new(rgb[1], rgb[2], rgb[3])
	end
	if Data.OwnsProduct(player, "rainbow_paint") and profile.rainbowModels[modelName] then
		for index, group in CustomConfig.Groups do
			colors[group.Id] = Color3.fromHSV((index - 1) / #CustomConfig.Groups, 0.8, 1)
		end
	end
	Paint.Apply(model, colors)
end

return Cosmetics
