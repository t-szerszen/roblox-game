--!strict

-- Original phone palette, independent of the shop's shared neutral theme.
return table.freeze({
	Body = Color3.fromRGB(18, 18, 20),
	Border = Color3.fromRGB(42, 42, 48),
	WallpaperTop = Color3.fromRGB(8, 12, 28),
	WallpaperBottom = Color3.fromRGB(55, 18, 88),
	AppBackground = Color3.fromRGB(18, 20, 26),
	AppBackgroundBottom = Color3.fromRGB(12, 14, 20),
	Row = Color3.fromRGB(28, 30, 38),
	Raised = Color3.fromRGB(44, 46, 54),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(160, 160, 170),
	Dimmed = Color3.fromRGB(100, 100, 108),
	Accent = Color3.fromRGB(0, 180, 255),
	Success = Color3.fromRGB(40, 200, 100),
	Error = Color3.fromRGB(200, 40, 40),
	HomeBar = Color3.fromRGB(200, 200, 210),
	ScreenInset = 6,
	BodyRadius = 30,
	ScreenRadius = 26,
	IconSize = 56,
	Apps = table.freeze({
		Scooters = table.freeze({ Top = Color3.fromRGB(0, 210, 245), Bottom = Color3.fromRGB(0, 130, 190) }),
		Delivery = table.freeze({ Top = Color3.fromRGB(255, 175, 45), Bottom = Color3.fromRGB(235, 95, 0) }),
		Gang = table.freeze({ Top = Color3.fromRGB(195, 35, 65), Bottom = Color3.fromRGB(115, 18, 95) }),
		Daily = table.freeze({ Top = Color3.fromRGB(40, 230, 110), Bottom = Color3.fromRGB(8, 155, 55) }),
		Protection = table.freeze({ Top = Color3.fromRGB(75, 115, 155), Bottom = Color3.fromRGB(35, 65, 95) }),
	}),
})
