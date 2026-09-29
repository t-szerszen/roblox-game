--!strict

export type Placement = {
	asset: string,
	position: Vector3,
	rotation: Vector3,
	scale: number,
}

local placements: { Placement } = {
	-- Skrzyżowanie w centrum miasta
	{ asset = "Road", position = Vector3.new(0, 0, 0), rotation = Vector3.new(0, 0, 0), scale = 1 },
	{ asset = "Road", position = Vector3.new(-24, 0, 0), rotation = Vector3.new(0, 90, 0), scale = 1 },
	{ asset = "Road", position = Vector3.new(24, 0, 0), rotation = Vector3.new(0, 90, 0), scale = 1 },
	{ asset = "Road", position = Vector3.new(0, 0, -24), rotation = Vector3.new(0, 0, 0), scale = 1 },
	{ asset = "Road", position = Vector3.new(0, 0, 24), rotation = Vector3.new(0, 0, 0), scale = 1 },

	-- Podwójny park na północy
	{ asset = "Park_Grass", position = Vector3.new(24, 0, -24), rotation = Vector3.new(0, 0, 0), scale = 1.2 },
	{ asset = "Park_Grass", position = Vector3.new(-24, 0, -24), rotation = Vector3.new(0, 0, 0), scale = 1.2 },

	-- Dzielnica biznesowa po południowej stronie skrzyżowania
	{ asset = "Building_Tall", position = Vector3.new(-24, 0, 24), rotation = Vector3.new(0, 0, 0), scale = 1.6 },
	{ asset = "Building_Tall", position = Vector3.new(-48, 0, 24), rotation = Vector3.new(0, 15, 0), scale = 1.8 },
	{ asset = "Building_Tall", position = Vector3.new(24, 0, 24), rotation = Vector3.new(0, -90, 0), scale = 1.4 },

	-- Mniejsze budynki na obrzeżach i rogatkach
	{ asset = "Building_Small", position = Vector3.new(-48, 0, -24), rotation = Vector3.new(0, -180, 0), scale = 1 },
	{ asset = "Building_Small", position = Vector3.new(48, 0, 24), rotation = Vector3.new(0, 90, 0), scale = 1.1 },
	{ asset = "Building_Small", position = Vector3.new(48, 0, -24), rotation = Vector3.new(0, -45, 0), scale = 1 },

	-- Punkt startowy (zakładając, że dodałeś mock "Spawn" do AssetRegistry)
	{ asset = "Spawn", position = Vector3.new(0, 1, 0), rotation = Vector3.new(0, 0, 0), scale = 1 },
}

return placements
