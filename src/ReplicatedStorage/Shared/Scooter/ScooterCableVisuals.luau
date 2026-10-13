--!strict

local Workspace = game:GetService("Workspace")
local Scope = require(script.Parent.Parent.UI.Scope)
export type Controller = { Update: (boolean) -> (), Destroy: () -> (), IsAlive: () -> boolean }
type Endpoint = { start: Vector3, finish: Vector3, weight: number }
type Cable = { source: Part, copy: Part, first: BasePart, last: BasePart,
	a: Endpoint, b: Endpoint, transparency: number }
local Cables = {}

local function endpoint(part: Part, name: string): Endpoint?
	local start = part:GetAttribute("G4Cable" .. name .. "Start")
	local finish = part:GetAttribute("G4Cable" .. name .. "End")
	local weight = part:GetAttribute("G4Cable" .. name .. "Weight")
	if typeof(start) ~= "Vector3" or typeof(finish) ~= "Vector3" or typeof(weight) ~= "number"
		or weight ~= weight or weight < 0 or weight > 1 then return nil end
	return { start = start, finish = finish, weight = weight }
end

function Cables.Create(model: Model, destination: Instance): Controller?
	if model:GetAttribute("ScooterG4Rig") ~= true then return nil end
	local visuals = model:FindFirstChild("G4Visuals")
	local group = if visuals then visuals:FindFirstChild("Cables") else nil
	if not group then return nil end
	local expected = group:GetAttribute("G4CableVisualPartCount")
	if typeof(expected) ~= "number" or expected <= 0 then return nil end
	local plans = {}
	for _, part in group:GetChildren() do
		if not part:IsA("Part") then continue end
		local firstName, lastName = part:GetAttribute("G4CableStartOwner"), part:GetAttribute("G4CableEndOwner")
		if typeof(firstName) ~= "string" or typeof(lastName) ~= "string" then continue end
		local first, last = model:FindFirstChild(firstName), model:FindFirstChild(lastName)
		local a, b = endpoint(part, "A"), endpoint(part, "B")
		if not first or not first:IsA("BasePart") or not last or not last:IsA("BasePart") or not a or not b then return nil end
		table.insert(plans, { source = part, first = first, last = last, a = a, b = b })
	end
	if #plans ~= expected then return nil end
	local scope = Scope.new()
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "G4CableVisuals", destination
	scope:Give(folder)
	local cables: { Cable } = {}
	local observed: { [Instance]: boolean } = {}
	local shown, destroyed = false, false
	for _, plan in plans do
		local source = plan.source
		local copy = source:Clone()
		for _, child in copy:GetChildren() do child:Destroy() end
		copy.Anchored, copy.Massless = true, true
		copy.CanCollide, copy.CanTouch, copy.CanQuery = false, false, false
		copy.Transparency, copy.Parent = 1, folder
		local cable: Cable = { source = source, copy = copy, first = plan.first, last = plan.last,
			a = plan.a, b = plan.b, transparency = source.LocalTransparencyModifier }
		table.insert(cables, cable)
		observed[source], observed[plan.first], observed[plan.last] = true, true, true
		scope:Give(source:GetPropertyChangedSignal("Color"):Connect(function() copy.Color = source.Color end))
		scope:Give(source:GetPropertyChangedSignal("Transparency"):Connect(function()
			copy.Transparency = if shown then source.Transparency else 1
		end))
	end
	scope:Give(function()
		for _, cable in cables do cable.source.LocalTransparencyModifier = cable.transparency end
	end)
	local function destroy()
		if destroyed then return end
		destroyed = true
		scope:Clean()
	end
	scope:Give(model.DescendantRemoving:Connect(function(part) if observed[part] then destroy() end end))
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local function position(cable: Cable, point: Endpoint): Vector3
		return cable.first.CFrame:PointToWorldSpace(point.start):Lerp(
			cable.last.CFrame:PointToWorldSpace(point.finish), point.weight)
	end
	return {
		IsAlive = function() return not destroyed end,
		Destroy = destroy,
		Update = function(visible: boolean)
			if destroyed then return end
			if shown ~= visible then
				shown = visible
				for _, cable in cables do
					cable.source.LocalTransparencyModifier = if visible then 1 else cable.transparency
					cable.copy.Transparency = if visible then cable.source.Transparency else 1
				end
			end
			if not visible then return end
			table.clear(parts)
			table.clear(frames)
			for _, cable in cables do
				local a, b = position(cable, cable.a), position(cable, cable.b)
				local frame = CFrame.new((a + b) * 0.5)
				if cable.source.Shape == Enum.PartType.Cylinder and (b - a).Magnitude > 0.0001 then
					local axis = (b - a).Unit
					local up = if math.abs(axis.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
					frame = CFrame.fromMatrix(frame.Position, axis, (up - axis * up:Dot(axis)).Unit)
					cable.copy.Size = Vector3.new((b - a).Magnitude, cable.source.Size.Y, cable.source.Size.Z)
				end
				table.insert(parts, cable.copy)
				table.insert(frames, frame)
			end
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end,
	}
end

return Cables
