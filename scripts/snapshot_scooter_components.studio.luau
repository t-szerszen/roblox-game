-- Read-only geometry/material manifest. Run in Edit and save the returned JSON to assets/scooter.
-- The authored place retains the full dashboard UI, native mesh data and mechanical draft.
local HttpService = game:GetService("HttpService")
local source = assert(game.ServerStorage.ScooterAuthoring:FindFirstChild("ScooterLargeWheelSource"))
local function vector(value) return { value.X, value.Y, value.Z } end
local function color(value) return { value.R, value.G, value.B } end
local report = {
	version = 1,
	source = source.Name,
	playableScale = source:GetAttribute("PlayableWheelDiameter") / source.FrontWheel.Mesh_0.Size.X,
	playableWheelDiameter = source:GetAttribute("PlayableWheelDiameter"),
	frontRestRotationDegrees = source:GetAttribute("FrontRestRotationDegrees"),
	components = {},
}
for index, component in source:GetChildren() do
	local group = { index = index, name = component.Name, parts = {} }
	local items = if component:IsA("BasePart") then { component } else component:GetDescendants()
	for _, item in items do
		if item:IsA("BasePart") then
			local part = {
				name = item.Name, class = item.ClassName, size = vector(item.Size),
				cframe = { item.CFrame:GetComponents() }, color = color(item.Color),
				material = item.Material.Name, transparency = item.Transparency,
			}
			if item:IsA("Part") then part.shape = item.Shape.Name end
			if item:IsA("MeshPart") then
				part.mesh = item.MeshId
				part.texture = item.TextureID
				local appearance = item:FindFirstChildWhichIsA("SurfaceAppearance")
				if appearance then
					part.surfaceAppearance = {
						color = appearance.ColorMap, normal = appearance.NormalMap,
						metalness = appearance.MetalnessMap, roughness = appearance.RoughnessMap,
						alphaMode = appearance.AlphaMode.Name,
					}
				end
			end
			table.insert(group.parts, part)
		end
	end
	table.insert(report.components, group)
end
return HttpService:JSONEncode(report)
