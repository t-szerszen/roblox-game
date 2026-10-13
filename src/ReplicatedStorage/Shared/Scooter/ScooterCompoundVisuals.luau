--!strict

local Workspace = game:GetService("Workspace")
local Config = require(script.Parent.ScooterConfig)
local Scope = require(script.Parent.Parent.UI.Scope)

export type Controller = { Update: (number, boolean) -> (), Destroy: () -> (), IsAlive: () -> boolean }
type Visual = { source: BasePart, copy: BasePart, rest: CFrame, size: Vector3,
	transparency: number, section: string?, rod: boolean,
	guis: { { source: SurfaceGui, copy: SurfaceGui, enabled: boolean } } }
type Wheel = { source: BasePart, anchor: Attachment, rest: CFrame, radius: number,
	parts: { Visual }, frame: CFrame, tracking: boolean, spin: number, rate: number }
type Shock = { source: Model, spring: SpringConstraint, parts: { Visual }, length: number,
	first: Vector3, second: Vector3, right: Vector3 }
local Compound = {}

local function visualParts(container: Model): { BasePart }?
	local result: { BasePart } = {}
	for _, item in container:GetChildren() do if item:IsA("BasePart") then table.insert(result, item) end end
	local expected = container:GetAttribute("CompoundVisualPartCount")
	return if typeof(expected) == "number" and #result == expected and expected > 0 then result else nil
end

function Compound.Create(model: Model, destination: Instance): Controller?
	if model:GetAttribute("ScooterG4Rig") ~= true or not model.PrimaryPart then return nil end
	local root = model.PrimaryPart
	local sourceVisuals = model:FindFirstChild("G4Visuals")
	if not sourceVisuals then return nil end
	-- Wait for complete visual groups instead of capturing half of a streamed wheel.
	local wheelPlans: { { source: BasePart, parts: { BasePart }, anchor: Attachment, point: Attachment } } = {}
	local shockPlans: { { source: Model, parts: { BasePart }, spring: SpringConstraint } } = {}
	for _, endName in { "Front", "Back" } do
		local wheel = model:FindFirstChild(endName .. "Wheel")
		local group = sourceVisuals:FindFirstChild(endName .. "WheelVisuals")
		local axle = model:FindFirstChild("Virtual" .. endName .. "Axle")
		local anchor = if axle then axle:FindFirstChild("AxlePivot") else nil
		local point = if wheel then wheel:FindFirstChild("WheelCenter") else nil
		if not wheel or not wheel:IsA("BasePart") or not group or not group:IsA("Model")
			or not anchor or not anchor:IsA("Attachment") or not point or not point:IsA("Attachment") then return nil end
		local members = visualParts(group)
		local radius = wheel:GetAttribute("WheelRadius")
		if not members or typeof(radius) ~= "number" or radius <= 0 or radius == math.huge then return nil end
		table.insert(members, wheel)
		table.insert(wheelPlans, { source = wheel, parts = members, anchor = anchor, point = point })
	end
	for _, group in sourceVisuals:GetChildren() do
		local name = group:GetAttribute("CompoundSpringConstraint")
		if not group:IsA("Model") or typeof(name) ~= "string" then continue end
		local spring = model:FindFirstChild(name, true)
		local members = visualParts(group)
		if not members or not spring or not spring:IsA("SpringConstraint")
			or not spring.Attachment0 or not spring.Attachment1 then return nil end
		table.insert(shockPlans, { source = group, parts = members, spring = spring })
	end
	if #shockPlans ~= 4 then return nil end
	local cleanup = Scope.new()
	local container = Instance.new("Folder")
	container.Name, container.Parent = "G4RideVisuals", destination
	cleanup:Give(container)
	local wheels: { Wheel } = {}
	local shocks: { Shock } = {}
	local all: { Visual } = {}
	local shown, destroyed = false, false
	local function copy(part: BasePart, rest: CFrame): Visual
		local clone = part:Clone()
		local guis: { { source: SurfaceGui, copy: SurfaceGui, enabled: boolean } } = {}
		for _, child in clone:GetChildren() do
			if not child:IsA("SurfaceAppearance") and not child:IsA("Decal") and not child:IsA("Texture")
				and not child:IsA("SurfaceGui") then child:Destroy() end
			if child:IsA("SurfaceGui") then
				local original = part:FindFirstChild(child.Name)
				assert(original and original:IsA("SurfaceGui"), "G4 wheel label is missing")
				table.insert(guis, { source = original, copy = child, enabled = original.Enabled })
				child.Enabled, child.Adornee = false, clone
			end
		end
		clone.Anchored, clone.Massless = true, true
		clone.CanCollide, clone.CanTouch, clone.CanQuery = false, false, false
		clone.Transparency = 1
		clone.Parent = container
		local entry: Visual = { source = part, copy = clone, rest = rest, size = part.Size,
			transparency = part.LocalTransparencyModifier,
			section = part:GetAttribute("G4ShockSection") :: string?,
			rod = part:IsA("Part") and part.Shape == Enum.PartType.Cylinder, guis = guis }
		table.insert(all, entry)
		cleanup:Give(part:GetPropertyChangedSignal("Color"):Connect(function() clone.Color = part.Color end))
		cleanup:Give(part:GetPropertyChangedSignal("Size"):Connect(function()
			entry.size, clone.Size = part.Size, part.Size
		end))
		cleanup:Give(part:GetPropertyChangedSignal("Transparency"):Connect(function()
			clone.Transparency = if shown then part.Transparency else 1
		end))
		return entry
	end
	for _, plan in wheelPlans do
		local members: { Visual } = {}
		for _, part in plan.parts do table.insert(members, copy(part, plan.source.CFrame:ToObjectSpace(part.CFrame))) end
		local radius = plan.source:GetAttribute("WheelRadius")
		assert(typeof(radius) == "number" and radius > 0, "G4 wheel radius is missing")
		table.insert(wheels, { source = plan.source, anchor = plan.anchor, rest = plan.point.CFrame:Inverse(),
			radius = radius, parts = members, frame = root.CFrame:ToObjectSpace(plan.anchor.WorldCFrame),
			tracking = false, spin = 0, rate = 0 })
	end
	for _, plan in shockPlans do
		local first, second = assert(plan.spring.Attachment0).WorldPosition, assert(plan.spring.Attachment1).WorldPosition
		local at = plan.source:GetPivot()
		local members: { Visual } = {}
		for _, part in plan.parts do table.insert(members, copy(part, at:ToObjectSpace(part.CFrame))) end
		table.insert(shocks, { source = plan.source, spring = plan.spring, parts = members,
			length = (first - second).Magnitude, first = root.CFrame:PointToObjectSpace(first),
			second = root.CFrame:PointToObjectSpace(second), right = root.CFrame:VectorToObjectSpace(at.RightVector) })
	end
	cleanup:Give(function()
		for _, part in all do
			part.source.LocalTransparencyModifier = part.transparency
			for _, gui in part.guis do gui.source.Enabled = gui.enabled end
		end
	end)
	local moving: { BasePart } = {}
	local frames: { CFrame } = {}
	local function destroy()
		if destroyed then return end
		destroyed = true
		cleanup:Clean()
	end
	local observed: { [Instance]: boolean } = {}
	for _, part in all do observed[part.source] = true end
	cleanup:Give(model.DescendantRemoving:Connect(function(item)
		if observed[item] then destroy() end
	end))
	return {
		IsAlive = function() return not destroyed end,
		Update = function(deltaTime: number, visible: boolean)
			if destroyed or not model.PrimaryPart then return end
			local dt = math.clamp(deltaTime, 0, 0.1)
			local alpha = 1 - math.exp(-Config.RideVisuals.SuspensionResponse * dt)
			if visible ~= shown then
				shown = visible
				for _, item in all do
					if item.source.Parent then item.source.LocalTransparencyModifier = if visible then 1 else item.transparency end
					item.copy.Transparency = if visible then item.source.Transparency else 1
					-- SurfaceGui stays visible on transparent geometry unless explicitly hidden.
					for _, gui in item.guis do
						gui.source.Enabled = if visible then false else gui.enabled
						gui.copy.Enabled = visible and gui.enabled
					end
				end
			end
			if not visible then for _, wheel in wheels do wheel.tracking, wheel.rate = false, 0 end; return end
			table.clear(moving)
			table.clear(frames)
			for _, wheel in wheels do
				if not wheel.source.Parent or not wheel.anchor.Parent then continue end
				local target = root.CFrame:ToObjectSpace(wheel.anchor.WorldCFrame)
				if not wheel.tracking then wheel.frame, wheel.tracking = target, true end
				local filtered = wheel.frame:Lerp(target, alpha)
				local shift = filtered.Position - wheel.frame.Position
				local limit = Config.RideVisuals.MaxSuspensionSpeed * dt
				if shift.Magnitude > limit then shift = shift.Unit * limit end
				wheel.frame = CFrame.new(wheel.frame.Position + shift) * filtered.Rotation
				local sign = if wheel.anchor.WorldAxis:Dot(root.CFrame.RightVector) >= 0 then -1 else 1
				local rate = sign * root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector) / wheel.radius
				if model:GetAttribute("BurnoutActive") == true then rate = wheel.source.AssemblyAngularVelocity:Dot(wheel.anchor.WorldAxis) end
				wheel.rate += (rate - wheel.rate) * (1 - math.exp(-Config.RideVisuals.SpinResponse * dt))
				wheel.spin = (wheel.spin + wheel.rate * dt) % (math.pi * 2)
				local at = root.CFrame * wheel.frame * CFrame.Angles(wheel.spin, 0, 0) * wheel.rest
				for _, part in wheel.parts do
					table.insert(moving, part.copy)
					table.insert(frames, at * part.rest)
				end
			end
			for _, shock in shocks do
				local a, b = shock.spring.Attachment0, shock.spring.Attachment1
				if not shock.spring.Parent or not a or not b then continue end
				shock.first = shock.first:Lerp(root.CFrame:PointToObjectSpace(a.WorldPosition), alpha)
				shock.second = shock.second:Lerp(root.CFrame:PointToObjectSpace(b.WorldPosition), alpha)
				local first, second = root.CFrame:PointToWorldSpace(shock.first), root.CFrame:PointToWorldSpace(shock.second)
				local delta = first - second
				if delta.Magnitude < 0.001 then continue end
				local up = delta.Unit
				local right = root.CFrame:VectorToWorldSpace(shock.right)
				right = (right - up * right:Dot(up)).Unit
				local at = CFrame.fromMatrix((first + second) * 0.5, right, up)
				local ratio = delta.Magnitude / shock.length
				local stretch = (delta.Magnitude - shock.length) * 0.5
				for _, part in shock.parts do
					local position = part.rest.Position
					local y = if part.section == "Upper" then position.Y + stretch
						else if part.section == "Lower" then position.Y - stretch else position.Y * ratio
					local rotation = part.rest.Rotation
					if part.section == "Coil" and part.rod then
						local axis = part.rest.RightVector
						local scaled = Vector3.new(axis.X, axis.Y * ratio, axis.Z)
						local secondary = part.rest.UpVector - scaled.Unit * part.rest.UpVector:Dot(scaled.Unit)
						rotation = CFrame.fromMatrix(Vector3.zero, scaled.Unit, secondary.Unit)
						local size = Vector3.new(part.size.X * scaled.Magnitude, part.size.Y, part.size.Z)
						if (part.copy.Size - size).Magnitude > 0.0001 then part.copy.Size = size end
					end
					table.insert(moving, part.copy)
					table.insert(frames, at * CFrame.new(position.X, y, position.Z) * rotation)
				end
			end
			-- One native batch avoids a property/event update per decorative segment.
			if #moving > 0 then Workspace:BulkMoveTo(moving, frames, Enum.BulkMoveMode.FireCFrameChanged) end
		end,
		Destroy = destroy,
	}
end

return Compound
