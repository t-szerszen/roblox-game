--!strict

-- Remodeled 2026-10-05: mesh-local arm/shaft pivots transferred from the approved rig.
-- The user approved the new fork/whole-front steering mounts on 2026-10-05.
return {
	SourceName = "ScooterFinal",
	PreviewName = "ScooterFinalRig",
	Scale = 0.25,
	MountsVerified = true,
	ReferenceAvatarHeight = 8,
	PreviewOffset = Vector3.new(0, 1.25, 20),
	AxleSize = Vector3.new(0.12, 0.12, 0.12),
	SteeringCarrierSize = Vector3.new(0.25, 0.25, 0.25),
	ShowConstraints = true,
	IndependentFrontSteering = false,
	ReviewMarkers = { Color = Color3.fromRGB(255, 221, 0), Radius = 0.08, LineThickness = 2 },
	PositionTolerance = 0.001,
	AxisToleranceDegrees = 0.1,
	Steering = {
		PivotBodyLocal = Vector3.new(13.481873, 4.332480, -0.044452),
		MaxAngle = 48,
		ServoTorque = 50000,
		ServoSpeed = 2,
		ServoResponsiveness = 100,
	},
	Front = {
		LeftName = "FrontLeftSuspension",
		RightName = "FrontRightSuspension",
		PivotBodyLocal = Vector3.new(10.599335, -3.635489, -0.028695),
		SpringName = "FrontSpring",
	},
	Back = {
		LeftName = "BackLeftSuspension",
		RightName = "BackRightSuspension",
		PivotBodyLocal = Vector3.new(-11.522461, -3.402217, -0.120220),
		SpringName = "BackSpring",
	},
	-- Draft values permit articulation checks; loaded travel/calibration comes next.
	Spring = { Stiffness = 1000, Damping = 60, MaxForce = 50000 },
	-- Optional, explicitly mapped imports. Suspension supports must move with their axle.
	ExtraComponents = {
		{ Name = "FrontFork", Assembly = "Steering", FixedName = "HandleBarStick" },
		{ Name = "BrakeLeverLeft", Assembly = "Steering", FixedName = "Handbar" },
		{ Name = "BrakeLeverRight", Assembly = "Steering", FixedName = "Handbar" },
		{ Name = "FrontSpringStick", Assembly = "FrontSuspension", FixedName = "VirtualFrontAxle" },
		{ Name = "FrontBrakeCaliper", Assembly = "FrontSuspension", FixedName = "VirtualFrontAxle" },
	},
	-- The imported Footrest is the rear kick plate. The riding deck is inside ScooterBody.
	Deck = {
		-- Measured on the remodeled deck's flat surface, with margins inside its edges.
		CenterBodyLocal = Vector3.new(-2.715057, -2.812065, 0),
		Size = Vector3.new(15.75, 0.95, 5.25),
	},
	-- Scaled imported meshes have tiny default mass; balance the articulated assemblies.
	RuntimePhysics = {
		ChassisMass = 12, SteeringMass = 2, WheelMass = 2, SuspensionArmMass = 0.5,
		SteeringCarrierMass = 1,
		ReferenceRiderMass = 40,
	},
	DashboardScale = 1.48,
}
