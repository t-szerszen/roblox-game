--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MinimapConfig"))
local DzordzConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DzordzQuestConfig"))
local player = Players.LocalPlayer
local connections: {RBXScriptConnection} = {}
local zoom = 1
local hovered: string? = nil
local gui = Instance.new("ScreenGui")
gui.Name = "CityMinimap"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "MapWindow"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 18, 1, -18)
panel.Size = UDim2.fromOffset(224, 224)
panel.BackgroundColor3 = Color3.fromRGB(19, 28, 40)
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(79, 111, 143)
stroke.Transparency = 0.15
stroke.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel

local map = Instance.new("Frame")
map.Name = "Map"
map.Position = UDim2.fromOffset(8, 8)
map.Size = UDim2.fromOffset(208, 208)
map.BackgroundColor3 = Color3.fromRGB(45, 61, 51)
map.BorderSizePixel = 0
map.ClipsDescendants = true
map.Parent = panel
local picture = Instance.new("ImageLabel")
picture.Name = "City"
picture.BackgroundTransparency = 1
picture.Image = Config.Image
picture.ResampleMode = Enum.ResamplerMode.Pixelated
picture.Parent = map

local function text(parent: Instance, name: string, value: string, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = value
	label.Size = size
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(17, 26, 38)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(241, 247, 255)
	label.ZIndex = 6
	label.Parent = parent
	return label
end
text(map, "Heading", "MAPA   •   N ↑", UDim2.fromOffset(119, 23), UDim2.fromOffset(0, 0))
local footer = text(map, "Legend", "P policja  •  $ sklep  •  R remiza", UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 1, -24))
footer.TextSize = 10
local zoomButton = Instance.new("TextButton")
zoomButton.Name = "Zoom"
zoomButton.Size = UDim2.fromOffset(84, 23)
zoomButton.Position = UDim2.new(1, -84, 0, 0)
zoomButton.Text = "700 m  ⊕"
zoomButton.Font = Enum.Font.GothamBold
zoomButton.TextSize = 11
zoomButton.TextColor3 = Color3.fromRGB(184, 216, 244)
zoomButton.BackgroundColor3 = Color3.fromRGB(17, 26, 38)
zoomButton.BorderSizePixel = 0
zoomButton.ZIndex = 7
zoomButton.Parent = map
table.insert(connections, zoomButton.Activated:Connect(function()
	zoom = zoom % #Config.Spans + 1
end))

local colors = {
	police = Color3.fromRGB(83, 162, 246),
	spawn = Color3.fromRGB(119, 225, 169),
	shop = Color3.fromRGB(209, 184, 249),
	fire = Color3.fromRGB(250, 115, 103),
}
local markers = {}
local function marker(label: string, icon: string, x: number, z: number, color: Color3, questId: string?, stage: string?)
	local pin = text(map, questId or label, icon, UDim2.fromOffset(19, 19), UDim2.fromScale(0.5, 0.5))
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.BackgroundColor3 = color
	pin.BackgroundTransparency = 0
	pin.TextColor3 = Color3.fromRGB(16, 26, 36)
	pin.ZIndex = if questId then 5 else 3
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = pin
	table.insert(connections, pin.MouseEnter:Connect(function() hovered = label end))
	table.insert(connections, pin.MouseLeave:Connect(function() hovered = nil end))
	table.insert(markers, {pin = pin, x = x, z = z, id = questId, label = label, stage = stage})
end
for _, point in Config.Landmarks do
	marker(point.label, point.icon, point.x, point.z, colors[point.kind], nil)
end
for index, point in Config.QuestPoints do
	marker("Plakat • przystanek " .. index, tostring(index), point.x, point.z, Color3.fromRGB(255, 204, 83), point.id)
end
marker("Dzordz Automatowicz", "D", DzordzConfig.NpcPosition.X, DzordzConfig.NpcPosition.Z, Color3.fromRGB(209, 184, 249), nil)
marker("Torba Dzordza", "T", DzordzConfig.BagPosition.X, DzordzConfig.BagPosition.Z, Color3.fromRGB(255, 204, 83), "DzordzBagPickup", "seeking")
marker("Oddaj torbę Dzordzowi", "D", DzordzConfig.NpcPosition.X, DzordzConfig.NpcPosition.Z, Color3.fromRGB(255, 204, 83), "DzordzBagReturn", "carrying")
local arrow = text(map, "Player", "▲", UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5))
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.TextSize = 20
arrow.TextColor3 = Color3.fromRGB(255, 255, 255)
arrow.BackgroundTransparency = 1
arrow.ZIndex = 4

local elapsed = 0
table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < Config.UpdateInterval then return end
	elapsed = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	local camera = workspace.CurrentCamera
	scale.Scale = if camera then math.clamp(math.min(camera.ViewportSize.X / 900, camera.ViewportSize.Y / 600), 0.7, 1) else 1
	local span = Config.Spans[zoom]
	local centerX = if zoom == #Config.Spans then Config.MinX + Config.Width / 2 else root.Position.X
	local centerZ = if zoom == #Config.Spans then Config.MinZ + Config.Height / 2 else root.Position.Z
	zoomButton.Text = if zoom == #Config.Spans then "CAŁA  ⊕" else (if zoom == 1 then "BLISKO  ⊕" else "DALEKO  ⊕")
	picture.Size = UDim2.fromScale(Config.Width / span, Config.Height / span)
	picture.Position = UDim2.fromScale(0.5 + (Config.MinX - centerX) / span, 0.5 + (Config.MinZ - centerZ) / span)
	arrow.Position = UDim2.fromScale(0.5 + (root.Position.X - centerX) / span, 0.5 + (root.Position.Z - centerZ) / span)
	arrow.Rotation = math.deg(math.atan2(root.CFrame.LookVector.X, -root.CFrame.LookVector.Z))
	local active = player:GetAttribute("PosterQuestStatus") == "active"
	local dzordzStatus = player:GetAttribute("DzordzQuestStatus")
	local nearest = math.huge
	local nearestName = ""
	local edgePositions = {}
	for _, item in markers do
		local dx, dz = item.x - centerX, item.z - centerZ
		local x, y = 0.5 + dx / span, 0.5 + dz / span
		local inside = x >= 0.06 and x <= 0.94 and y >= 0.15 and y <= 0.83
		local visible = if item.id then active and player:GetAttribute("PosterQuest_" .. item.id) ~= true else inside
		if item.stage then
			visible = dzordzStatus == item.stage or (item.stage == "seeking" and dzordzStatus == "picking")
		end
		item.pin.Visible = visible
		if not visible then continue end
		if item.id then
			local distance = Vector2.new(item.x - root.Position.X, item.z - root.Position.Z).Magnitude
			if distance < nearest then nearest = distance nearestName = item.pin.Text end
			-- Preserve the bearing when a task target is outside this local map window.
			if not inside then
				local factor = math.max(math.abs(dx) / (span * 0.42), math.abs(dz) / (span * 0.33), 1)
				x, y = 0.5 + dx / span / factor, 0.49 + dz / span / factor
				for _, other in edgePositions do
					if math.abs(x - other.X) < 0.09 and math.abs(y - other.Y) < 0.09 then
						x = math.clamp(other.X + 0.1, 0.06, 0.94)
					end
				end
				table.insert(edgePositions, Vector2.new(x, y))
			end
		end
		item.pin.Position = UDim2.fromScale(x, y)
	end
	footer.Text = hovered or (if nearest < math.huge then "CEL " .. nearestName .. "  •  " .. math.round(nearest) .. " studów" else "P policja  •  $ sklep  •  R remiza")
end))

script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	gui:Destroy()
end)
