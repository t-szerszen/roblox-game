--!strict

local GangTags = {}

function GangTags.Apply(player: Player, name: string?, color: Color3?)
	local character = player.Character
	if not character then return end
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local old = if head then head:FindFirstChild("GangTag") else nil
	if old then old:Destroy() end
	if humanoid then
		if name then
			if humanoid:GetAttribute("GangOriginalDisplay") == nil then
				humanoid:SetAttribute("GangOriginalDisplay", humanoid.DisplayDistanceType.Name)
			end
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		else
			local original = humanoid:GetAttribute("GangOriginalDisplay")
			if original == "None" then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			elseif original == "Subject" then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
			elseif original == "Viewer" then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end
			humanoid:SetAttribute("GangOriginalDisplay", nil)
		end
	end
	if not name or not color or not head or not head:IsA("BasePart") then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GangTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(200, 28)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 80
	gui.Parent = head
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.Text = string.format("[%s] %s", name, player.DisplayName)
	text.TextColor3 = color
	text.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	text.TextStrokeTransparency = 0.35
	text.TextScaled = true
	text.Parent = gui
end

return GangTags
