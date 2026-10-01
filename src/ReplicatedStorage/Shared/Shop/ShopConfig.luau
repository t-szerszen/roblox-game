--!strict

export type Currency = "Coins" | "Robux"
export type ProductKind = "Scooter" | "GamePass" | "DeveloperProduct"
export type Product = {
	id: string,
	name: string,
	description: string,
	price: number,
	currency: Currency,
	kind: ProductKind,
	productId: number?,
	stat: string?,
	accent: Color3,
}

local ShopConfig = {}

ShopConfig.RemoteFolderName = "ShopRemotes"
ShopConfig.RequestFunctionName = "ShopRequest"
ShopConfig.RequestCooldown = 0.25

ShopConfig.CoinProducts = {
	{
		id = "kukirin_g2_pro",
		name = "KuKirin G2 Pro",
		description = "Model startowy | 45 km/h",
		price = 0,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Pro",
		accent = Color3.fromRGB(235, 196, 45),
	},
	{
		id = "kukirin_g2_max",
		name = "KuKirin G2 Max",
		description = "Szybszy naped | 55 km/h",
		price = 1_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Max",
		accent = Color3.fromRGB(54, 190, 129),
	},
	{
		id = "kukirin_g2_master",
		name = "KuKirin G2 Master",
		description = "Mocny model miejski | 60 km/h",
		price = 4_500,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Master",
		accent = Color3.fromRGB(62, 150, 224),
	},
	{
		id = "kukirin_g3_pro",
		name = "KuKirin G3 Pro",
		description = "Wyczynowa konfiguracja | 65 km/h",
		price = 12_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG3Pro",
		accent = Color3.fromRGB(224, 91, 80),
	},
	{
		id = "kukirin_g4",
		name = "KuKirin G4",
		description = "Najwyzsza klasa | 70 km/h",
		price = 26_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG4",
		accent = Color3.fromRGB(194, 91, 217),
	},
} :: { Product }

-- Set productId to an ID owned by this experience before enabling a Robux purchase.
ShopConfig.RobuxProducts = {
	{
		id = "pepper_spray",
		name = "Gaz pieprzowy",
		description = "Staly przedmiot w ekwipunku",
		price = 250,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(231, 90, 67),
	},
	{
		id = "radio",
		name = "Radio",
		description = "Muzyka dostepna z ekranu glownego",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(61, 166, 216),
	},
	{
		id = "burnout_smoke",
		name = "Kolorowy dym",
		description = "Wlasny kolor dymu podczas burnoutu",
		price = 100,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(205, 92, 210),
	},
	{
		id = "scooter_neons",
		name = "Neony",
		description = "Kolorowe podswietlenie hulajnogi",
		price = 100,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(62, 213, 187),
	},
	{
		id = "premium_vehicle",
		name = "Pojazd premium",
		description = "Suron lub The Turbo",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(238, 155, 55),
	},
	{
		id = "double_coins",
		name = "2x Coiny",
		description = "Podwaja zarobki z aktywnosci",
		price = 300,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(235, 196, 45),
	},
} :: { Product }

function ShopConfig.GetProduct(id: string): Product?
	for _, product in ShopConfig.CoinProducts do
		if product.id == id then
			return product
		end
	end
	for _, product in ShopConfig.RobuxProducts do
		if product.id == id then
			return product
		end
	end
	return nil
end

function ShopConfig.GetScooterProduct(modelName: string): Product?
	for _, product in ShopConfig.CoinProducts do
		if product.kind == "Scooter" and product.name == modelName then
			return product
		end
	end
	return nil
end

return ShopConfig
