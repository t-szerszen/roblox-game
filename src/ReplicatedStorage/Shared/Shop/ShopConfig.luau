--!strict

export type Currency = "Coins" | "Robux"
export type ProductKind = "Scooter" | "GamePass" | "DeveloperProduct"
export type TabId = "Classic" | "Premium" | "Kody"
export type Tab = { id: TabId, label: string, icon: string, accentColor: Color3 }
export type Product = {
	id: string,
	name: string,
	description: string,
	price: number,
	currency: Currency,
	kind: ProductKind,
	productId: number?,
	stat: string?,
	modelName: string?,
	category: string?,
	coinPrice: number?,
	assetReady: boolean?,
	retired: boolean?,
	accent: Color3,
	tab: TabId,
	speed: number?,      -- km/h display for scooters
	featured: boolean?,
	imageId: string?, -- Roblox image URI for premium artwork.
	previewKey: string?, -- Key in PreviewConfig.Sources; independent of the gameplay rig.
}

local ShopConfig = {}

ShopConfig.RemoteFolderName = "ShopRemotes"
ShopConfig.RequestFunctionName = "ShopRequest"
ShopConfig.RequestCooldown = 0.25

ShopConfig.Tabs = {
	{ id = "Classic" :: TabId, label = "CLASSIC", icon = "🛴", accentColor = Color3.fromRGB(241, 196, 43) },
	{ id = "Premium" :: TabId,   label = "PREMIUM",   icon = "💎", accentColor = Color3.fromRGB(180, 70, 220) },
} :: { Tab }

ShopConfig.CoinProducts = {
	{
		id = "kukirin_g2_pro",
		previewKey = "scooter",
		name = "KuKirin 1",
		modelName = "KuKirin G2 Pro",
		category = "Pojazdy",
		description = "Darmowy pojazd podstawowy",
		price = 0,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Pro",
		accent = Color3.fromRGB(235, 196, 45),
		tab = "Classic" :: TabId,
		speed = 55,
	},
	{
		id = "kukirin_g2_max",
		previewKey = "scooter",
		name = "KuKirin 2",
		modelName = "KuKirin G2 Max",
		category = "Pojazdy",
		description = "Szybszy naped",
		price = 10_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Max",
		accent = Color3.fromRGB(54, 190, 129),
		tab = "Classic" :: TabId,
		speed = 65,
	},
	{
		id = "kukirin_g2_master",
		previewKey = "scooter",
		name = "KuKirin 3",
		modelName = "KuKirin G2 Master",
		category = "Pojazdy",
		description = "Mocny model miejski",
		price = 40_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG2Master",
		accent = Color3.fromRGB(62, 150, 224),
		tab = "Classic" :: TabId,
		speed = 72,
	},
} :: { Product }

-- Preserve old unlocks/tuning without selling removed catalog entries.
ShopConfig.LegacyScooters = {
	{
		id = "kukirin_g3_pro",
		previewKey = "scooter",
		name = "KuKirin G3 Pro",
		modelName = "KuKirin G3 Pro", retired = true,
		description = "Wyczynowa konfiguracja",
		price = 12_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG3Pro",
		accent = Color3.fromRGB(224, 91, 80),
		tab = "Classic" :: TabId,
		speed = 80,
	},
	{
		id = "kukirin_g4",
		previewKey = "scooter",
		name = "KuKirin G4",
		modelName = "KuKirin G4", retired = true,
		description = "Najwyzsza klasa",
		price = 26_000,
		currency = "Coins",
		kind = "Scooter",
		stat = "Owned_KuKirinG4",
		accent = Color3.fromRGB(194, 91, 217),
		tab = "Classic" :: TabId,
		speed = 90,
		featured = true,
	},
} :: { Product }

-- Set productId to an ID owned by this experience before enabling a Robux purchase.
ShopConfig.RobuxProducts = {
	{
		id = "pepper_spray",
		name = "Gaz",
		category = "Walka",
		description = "Obezwladnia wroga na 3 sek",
		price = 500,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(231, 90, 67),
		tab = "Premium" :: TabId,
	},
	{
		id = "radio",
		name = "Radio",
		category = "Dodatki", coinPrice = 250_000,
		description = "Trwałe odblokowanie; odtwarzanie audio jeszcze niedostępne",
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
		category = "Pojazdy", assetReady = false,
		description = "Pojazd premium — model wymaga podłączenia",
		price = 800,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(238, 155, 55),
		tab = "Premium" :: TabId,
	},
	{
		id = "burnout_smoke",
		name = "Kolorowy dym spod opon",
		category = "Dodatki do pojazdów",
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
		name = "RGB pod hulajnogą",
		category = "Dodatki do pojazdów",
		description = "Kolorowe podswietlenie hulajnogi",
		price = 100,
		currency = "Robux",
		kind = "GamePass",
		productId = 0,
		accent = Color3.fromRGB(62, 213, 187),
		tab = "Premium" :: TabId,
	},
	{ id = "rainbow_paint", name = "Tęczowy kolor malowania", description = "Specjalny wariant kolorów; osobno dla każdego pojazdu",
		category = "Dodatki do pojazdów", price = 100, currency = "Robux", kind = "GamePass", productId = 0,
		accent = Color3.fromRGB(225, 130, 230), tab = "Premium" :: TabId },
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

function ShopConfig.GetScooters(): { Product }
	local products = table.clone(ShopConfig.CoinProducts)
	for _, product in ShopConfig.LegacyScooters do table.insert(products, product) end
	return products
end

function ShopConfig.GetScooterProduct(modelName: string): Product?
	for _, product in ShopConfig.GetScooters() do
		if product.modelName == modelName then
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
