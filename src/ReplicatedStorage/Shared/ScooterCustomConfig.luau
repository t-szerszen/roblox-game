--!strict
return table.freeze({
 RequestCooldown = .15,
 GarageName = "garage",
 ScooterFolderName = "Scooters",
 StationName = "ScooterCustomStation",
 AccessModelName = "ScooterCustomAccess",
 ZoneWallInset = 4,
 ZoneHeight = 22,
 ZoneExitMargin = 1,
 AccessInterval = .25,
 Groups = {
  {Id = "Deck", Label = "Deck", Parts = {"BatteryPanelLeft", "BatteryPanelRight", "ScooterBody"}},
  {Id = "Stem", Label = "Słupek", Parts = {"HandleBarStick"}},
  {Id = "Suspension", Label = "Amortyzatory", Parts = {"FrontSuspensionLeft", "FrontSuspensionRight", "BackSuspensionLeft", "BackSuspensionRight"}},
  {Id = "Grips", Label = "Gripy", Mode = "WholePart", Parts = {"LeftGrip", "RightGrip"}},
  {Id = "BrakeLevers", Label = "Klamki", Mode = "WholePart", Parts = {"BrakeLeverLeft", "BrakeLeverRight"}},
  {Id = "Calipers", Label = "Zaciski", Mode = "WholePart", Parts = {"FrontBrakeCaliper"}},
  {Id = "BrakeDiscs", Label = "Tarcze", Mode = "WholePart", Parts = {"BrakeDisc"}},
 },
 Textures = {
  Deck = "rbxassetid://103643149735238", -- User RGBA map: dark pixels have zero tint alpha.
  Stem = "rbxassetid://75617142388881",
  Suspension = "rbxassetid://131172382801480",
 },
 Attribute = "ScooterCustomGroup",
 ActionName = "ScooterCustomize",
})
