--!strict
-- Store entrances were inspected in the authored map. No map objects are renamed.
return table.freeze({
	Stores = {
		{Id="ShopWest",Name="Sklep przy przejściu",Position=Vector3.new(62,0.94,-229)},
		{Id="ShopNorth",Name="Sklep północny",Position=Vector3.new(174,0,-2976)},
		{Id="ShopEast",Name="Sklep wschodni",Position=Vector3.new(468,0,-600)},
	},
	BuildingFolders = {{"Budynki"},{"Osiedle_Parkowe","Bloki"}},
	MinimumBuildingHeight = 30,
	MinimumBuildingWidth = 15,
	BuildingMargin = 5,
	MaxGroundDifference = 4,
	MaxDestinations = 48,
	StoreSearchRadius = 120,
})
