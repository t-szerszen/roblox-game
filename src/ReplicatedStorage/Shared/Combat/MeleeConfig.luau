--!strict
return {
	ToolName = "Pięści",
	ToolAttribute = "ServerFists",
	EffectsRemote = "MeleeEffects",
	Range = 5.5,
	FacingDot = 0.4,
	HitboxSize = Vector3.new(4.5, 5, 5),
	HitboxOffset = CFrame.new(0, 0.5, -2.5),
	SampleInterval = 0.04,
	ComboReset = 1.5,
	KillHits = 8,
	KnockHits = 4,
	KnockWindow = 4,
	KnockDuration = 2,
	RecoveryGrace = 1,
	VisualDistance = 100,
	SoundDistance = 45,
	BlurSize = 32,
	Swings = {
		{ Windup = 0.16, Window = 0.12, Cooldown = 0.48, Heavy = false },
		{ Windup = 0.18, Window = 0.12, Cooldown = 0.5, Heavy = false },
		{ Windup = 0.24, Window = 0.14, Cooldown = 0.62, Heavy = true },
		{ Windup = 0.36, Window = 0.16, Cooldown = 0.8, Heavy = true },
	},
	-- Empty IDs use the original procedural clips. Only insert animations owned by the experience creator.
	Animations = {
		R6 = { Stance = "", Punch1 = "", Punch2 = "", Punch3 = "", Punch4 = "", Miss = "", Hit = "", HeavyHit = "" },
		R15 = { Stance = "", Punch1 = "", Punch2 = "", Punch3 = "", Punch4 = "", Miss = "", Hit = "", HeavyHit = "" },
	},
	Sounds = { Light = "", Heavy = "", Miss = "", Fall = "" },
}
