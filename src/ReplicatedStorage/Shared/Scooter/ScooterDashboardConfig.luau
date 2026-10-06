--!strict

return table.freeze({
	TemplateName = "ScooterDashboardTemplate",
	ModelName = "ScooterDashboard",
	ScreenName = "DisplaySurface",
	GuiName = "DashboardGui",
	DecorationAttribute = "ScooterDecoration",
	SpeedAttribute = "SpeedKmh",
	BrakeAttribute = "BrakeActive",
	DriveModeAttribute = "DriveMode",
	DigitGapPixels = 20,
	EcoColor = Color3.fromRGB(104, 227, 162),
	SportColor = Color3.fromRGB(170, 136, 255),
	MaxDisplaySpeed = 999,
	SegmentOnTransparency = 0,
	SegmentOffTransparency = 0.95,
	BrakeOnTransparency = 0,
	BrakeOffTransparency = 0.84,
	HudDiameter = 236,
	HudMaxSpeed = 100,
	HudNeedleSmoothSpeed = 12,
})
