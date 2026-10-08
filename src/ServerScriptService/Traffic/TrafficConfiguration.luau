--!strict
-- Distances are studs; speeds are studs/second, independent of scooter catalog km/h.
return table.freeze({
	Enabled = true,
	MaxVehicles = 10, TargetVehicles = 6, DensityMultiplier = 1,
	UpdateRate = 30, SenseRate = 10, DebugRate = 2, SpawnInterval = 3,
	SpawnMinDistance = 120, SpawnMaxDistance = 650, DespawnDistance = 850,
	DespawnGrace = 120, SpawnVisibilityDistance = 240, SpawnForwardDot = 0.4, SpawnSeparation = 32, SafeGap = 8,
	AreaRadius = 100, MaxVehiclesPerArea = 3, MaxVehiclesPerRoad = 3,
	MaxSpawnAttempts = 20, MaxRouteHops = 32,
	-- Avoid short trips; retire cars shortly after stopping at the network boundary.
	MinSpawnRouteDistance = 384, RouteEndGrace = 0.5,
	Vehicle = { TemplateName = "TemporaryCar", RootName = "Chassis",
		Bounds = Vector3.new(6, 4, 12), Wheelbase = 7.5, GroundClearance = 0.3 },
	MaxSpeed = 32, Acceleration = 5, Braking = 12, EmergencyBraking = 35,
	MinTurnSpeed = 4, LateralAcceleration = 7, Headway = 1.8,
	LookAhead = 12, SpeedLookAhead = 0.8, ObstacleRange = 100,
	MaxYawRate = math.rad(75), MaxLaneError = 4, RecoverySpeed = 2,
	GroundProbeHeight = 4, GroundProbeDepth = 9, MaxGroundChange = 1.5,
	MaxSlope = math.rad(18), FallY = -100,
	StuckTimeout = 60, MaxRecoveryAttempts = 2, MaxRecoveryLifetime = 300,
	StopDuration = 1, IntersectionWaitTimeout = 120, IntersectionClearance = 3,
	SampleSpacing = 2, MaxSamplesPerEdge = 512, MaxNodes = 6000, MaxEdges = 12000,
	Generation = { MinWidth = 14, MaxThickness = 3, JoinGap = 3,
		LateralTolerance = 8, DuplicateDistance = 12, LaneOffset = 10,
		CurveHandle = 20, MaxRoadParts = 1000, MaxTileSize = 100,
		MinTileSize = 40 },
	Debug = false, DebugSampleStride = 4,
})
