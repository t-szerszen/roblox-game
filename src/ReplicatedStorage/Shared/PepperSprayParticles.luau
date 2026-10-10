--!strict
local Particles = {}
local Config = require(script.Parent:WaitForChild("PepperSprayConfig"))
function Particles.Create(): ParticleEmitter
 local emitter = Instance.new("ParticleEmitter")
 emitter.Name = "GasCloud"
 emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
 emitter.Enabled = false
 emitter.Rate = Config.ParticleRate
 emitter.EmissionDirection = Enum.NormalId.Front
 emitter.Lifetime = NumberRange.new(Config.Range / Config.Speed * .75, Config.Range / Config.Speed)
 emitter.Speed = NumberRange.new(Config.Speed, Config.Speed)
 emitter.SpreadAngle = Vector2.new(Config.ParticleSpread, Config.ParticleSpread)
 emitter.Drag = 0
 emitter.Acceleration = Vector3.zero
 emitter.WindAffectsDrag = false
 emitter.Rotation = NumberRange.new(0, 360)
 emitter.RotSpeed = NumberRange.new(-35, 35)
 emitter.Size = NumberSequence.new({
  NumberSequenceKeypoint.new(0, .55), NumberSequenceKeypoint.new(.3, 2.3), NumberSequenceKeypoint.new(1, 4.4),
 })
 emitter.Transparency = NumberSequence.new({
  NumberSequenceKeypoint.new(0, .08), NumberSequenceKeypoint.new(.55, .28), NumberSequenceKeypoint.new(1, 1),
 })
 emitter.Color = ColorSequence.new(Color3.fromRGB(231, 182, 66), Color3.fromRGB(222, 147, 54))
 emitter.LightEmission = .2
 emitter.LightInfluence = .35
 emitter.LockedToPart = false
 emitter.VelocityInheritance = 0
 return emitter
end
return Particles
