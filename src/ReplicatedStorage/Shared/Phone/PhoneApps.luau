--!strict

local Types = require(script.Parent.PhoneTypes)
export type App = { id: Types.Page, label: string, glyph: string, imageId: string? }

-- Optional imageId replaces the original colored icon's empty artwork.
return table.freeze({
	{ id = "Scooters", label = "Hulajnoga", glyph = "H" },
	{ id = "Delivery", label = "Kurier", glyph = "K" },
	{ id = "Gang", label = "Gang", glyph = "G" },
	{ id = "Daily", label = "Misje", glyph = "M" },
	{ id = "Protection", label = "Ochrona", glyph = "O" },
} :: { App })
