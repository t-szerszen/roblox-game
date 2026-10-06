--!strict

-- Studio authoring recipe; nothing invokes this at server startup.
return table.freeze({
	Version = 1,
	Seed = 73,
	TileSize = 2048,
	TilesPerAxis = 3,
	Center = Vector3.new(72, 0, -1484),
	Depth = 128,
	GrassDepth = 8,
	MountainWidth = 768,
	MountainHeight = 560,
	ChunkSize = 256,
	Resolution = 4,
	BoundaryOffset = 576,
	BoundaryHeight = 1024,
	OriginalMin = Vector3.new(-952, -128, -3532),
	OriginalMax = Vector3.new(1100, 0, 564),
})
