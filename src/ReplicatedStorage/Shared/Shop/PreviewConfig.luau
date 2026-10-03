--!strict

-- Keys are independent of product IDs and physical rig/tuning names.
return table.freeze({
	FolderName = "ShopPreviews",
	Sources = table.freeze({
		scooter = { folder = "ScooterModels", name = "scooter" },
	} :: { [string]: { folder: string, name: string } }),
})
