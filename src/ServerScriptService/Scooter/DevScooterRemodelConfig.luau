--!strict

-- Dimensions below are playable studs, converted to the preserved source's scale.
return {
	SourceName = "ScooterLargeWheelSource",
	DraftName = "ScooterLargeWheelRig",
	PreviewName = "ScooterLargeWheelPreview",
	WheelSourceName = "newFrontWheel",
	PreviewOffset = Vector3.new(-60, 1.25, -22),
	MaximumWheelDiameter = 3,
	PlayableWheelDiameter = 1.95,
	MaximumFrontArmRotationDegrees = 35,
	Fender = {
		Segments = 8,
		StartAngle = -8,
		EndAngle = 68,
		Clearance = 0.15,
		Thickness = 0.07,
		WidthMargin = 0.16,
		SupportThickness = 0.055,
		Color = Color3.fromRGB(42, 45, 47),
	},
	Kickstand = {
		DeckOffset = Vector3.new(-0.35, -0.82, -0.75),
		Length = 1.15,
		Thickness = 0.09,
		FootSize = Vector3.new(0.22, 0.08, 0.17),
		Color = Color3.fromRGB(34, 37, 39),
	},
}
