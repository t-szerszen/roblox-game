--!strict

export type Currency = "Coins" | "Robux"
export type ProductKind = "Scooter" | "GamePass" | "DeveloperProduct"
export type TabId = "Hulajnogi" | "Premium" | "Dopalacze" | "Kody"
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
	tab: TabId,
	speed: number?,      -- km/h display for scooters
	featured: boolean?,  -- glowing border / special card treatment
	imageId: string?,    -- TODO: Wstaw ID grafiki produktu (np. hulajnogi)
	buttonImageId: string?, -- TODO: Wstaw ID wygenerowanego przycisku z ceną
}

local ShopConfig = {}

ShopConfig.RemoteFolderName = "ShopRemotes"
ShopConfig.RequestFunctionName = "ShopRequest"
ShopConfig.RequestCooldown = 0.25

ShopConfig.Tabs = {
	{ id = "Hulajnogi" :: TabId, label = "Hulajnogi", icon = "🛴", accentColor = Color3.fromRGB(241, 196, 43) },
	{ id = "Premium" :: TabId,   label = "Premium",   icon = "💎", accentColor = Color3.fromRGB(180, 70, 220) },
	{ id = "Dopalacze" :: TabId, label = "Dopalacze", icon = "⚡", accentColor = Color3.fromRGB(60, 220, 80) },
	{ id = "Kody" :: TabId,      label = "Kody",      icon = "🎁", accentColor = Color3.fromRGB(56, 182, 255) },
}

ShopConfig.CoinProducts = {
	{
		id = "kukirin_g2_pro",
		name = "KuKirin G2 Pro",
		description = "Model startowy",
		price = 0,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Pro",
		accent = Color3.fromRGB(235, 196, 45),
		tab = "Hulajnogi" :: TabId,
		speed = 55,
	},
	{
		id = "kukirin_g2_max",
		name = "KuKirin G2 Max",
		description = "Szybszy naped",
		price = 1_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Max",
		accent = Color3.fromRGB(54, 190, 129),
		tab = "Hulajnogi" :: TabId,
		speed = 65,
	},
	{
		id = "kukirin_g2_master",
		name = "KuKirin G2 Master",
		description = "Mocny model miejski",
		price = 4_500,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Master",
		accent = Color3.fromRGB(62, 150, 224),
		tab = "Hulajnogi" :: TabId,
		speed = 72,
	},
	{
		id = "kukirin_g3_pro",
		name = "KuKirin G3 Pro",
		description = "Wyczynowa konfiguracja",
		price = 12_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG3Pro",
		accent = Color3.fromRGB(224, 91, 80),
		tab = "Hulajnogi" :: TabId,
		speed = 80,
	},
	{
		id = "kukirin_g4",
		name = "KuKirin G4",
		description = "Najwyzsza klasa",
		price = 26_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG4",
		accent = Color3.fromRGB(194, 91, 217),
		tab = "Hulajnogi" :: TabId,
		speed = 90,
		featured = true,
	},
} :: { Product }

-- Set productId to an ID owned by this experience before enabling a Robux purchase.
ShopConfig.RobuxProducts = {
	{
		id = "pepper_spray",
		name = "Gaz Pieprzowy",
		description = "Obezwladnia wroga na 5 sek",
		price = 250,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(231, 90, 67),
		tab = "Premium" :: TabId,
	},
	{
		id = "radio",
		name = "Radio",
		description = "Muzyczny boombox na ekranie",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(61, 166, 216),
		tab = "Premium" :: TabId,
	},
	{
		id = "suron",
		name = "Suron",
		description = "Specjalny pojazd premium",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(238, 155, 55),
		tab = "Premium" :: TabId,
	},
	{
		id = "the_turbo",
		name = "The Turbo",
		description = "Ekskluzywna hulajnoga premium",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(255, 80, 120),
		tab = "Premium" :: TabId,
		featured = true,
	},
	{
		id = "burnout_smoke",
		name = "RGB Dym",
		description = "Wlasny kolor dymu burnout",
		price = 100,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(205, 92, 210),
		tab = "Premium" :: TabId,
	},
	{
		id = "scooter_neons",
		name = "RGB Neony",
		description = "Kolorowe podswietlenie hulajnogi",
		price = 100,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(62, 213, 187),
		tab = "Premium" :: TabId,
	},
	{
		id = "double_coins",
		name = "2x Coiny",
		description = "Podwaja zarobki na stale",
		price = 300,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(235, 196, 45),
		tab = "Premium" :: TabId,
		featured = true,
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

function ShopConfig.GetProductsByTab(tabId: TabId): { Product }
	local results: { Product } = {}
	for _, product in ShopConfig.CoinProducts do
		if product.tab == tabId then
			table.insert(results, product)
		end
	end
	for _, product in ShopConfig.RobuxProducts do
		if product.tab == tabId then
			table.insert(results, product)
		end
	end
	return results
end

return ShopConfig
