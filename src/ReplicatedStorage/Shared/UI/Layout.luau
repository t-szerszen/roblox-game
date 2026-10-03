--!strict

local Theme = require(script.Parent.Theme)
local Layout = {}

function Layout.PhoneWindow(width: number, height: number, input: string): (number, number)
	local desiredWidth = if input == "Touch" then Theme.Phone.TouchWidth
		elseif input == "Gamepad" then Theme.Phone.GamepadWidth else Theme.Phone.Width
	local desiredHeight = if input == "Touch" then Theme.Phone.TouchHeight else Theme.Phone.Height
	-- Reflow the scrollable body instead of shrinking text and touch targets.
	return math.max(1, math.min(desiredWidth, width - Theme.Phone.Margin * 2)),
		math.max(1, math.min(desiredHeight, height - Theme.Phone.Margin * 2))
end

function Layout.ShopWindow(width: number, height: number): (number, number)
	return math.max(1, math.min(Theme.Shop.MaxWidth, width - Theme.Shop.Margin * 2)),
		math.max(1, math.min(Theme.Shop.MaxHeight, height - Theme.Shop.Margin * 2))
end

function Layout.ProductGrid(width: number): (number, number)
	local columns = math.clamp(math.floor((width + Theme.Spacing) / (Theme.Shop.CardMinWidth + Theme.Spacing)), 1, Theme.Shop.MaxColumns)
	return columns, math.max(1, math.floor((width - (columns - 1) * Theme.Spacing) / columns))
end

function Layout.PreviewDistance(size: Vector3, aspectRatio: number): number
	local verticalHalfAngle = math.rad(Theme.Shop.PreviewFieldOfView / 2)
	local halfAngle = math.atan(math.tan(verticalHalfAngle) * math.min(1, math.max(0.1, aspectRatio)))
	-- Fit the enclosing sphere so long models stay visible throughout rotation.
	return math.max(1, size.Magnitude * 0.5 / math.sin(halfAngle) * 1.08)
end

function Layout.FormatCoins(value: number): string
	local formatted = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1 %2")
		formatted = replaced
		if count == 0 then return formatted end
	end
end

return Layout
