--!strict
export type Zone = { id: string, name: string, modelPath: { string }, cframe: CFrame, size: Vector3 }
return {
	{ id = "boisko_kamienice", name = "Boisko przy Kamienicach", modelPath = {"Territories", "BoiskoKamienice"}, cframe = CFrame.new(850, 17.3435612, -460, 1, 0, 0, 0, 1, 0, 0, 0, 1), size = Vector3.new(36, 24, 36) },
	{ id = "park_zachodni", name = "Park Zachodni", modelPath = {"Territories", "ParkZachodni"}, cframe = CFrame.new(-440, 13.6717148, 45, 1, 0, 0, 0, 1, 0, 0, 0, 1), size = Vector3.new(36, 24, 36) },
	{ id = "skwer_osiedlowy", name = "Skwer Osiedlowy", modelPath = {"Territories", "SkwerOsiedlowy"}, cframe = CFrame.new(-514, 12.3199968, -664, 1, 0, 0, 0, 1, 0, 0, 0, 1), size = Vector3.new(36, 24, 36) },
} :: { Zone }
