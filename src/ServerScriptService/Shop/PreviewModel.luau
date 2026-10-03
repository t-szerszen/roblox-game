--!strict

local CollectionService = game:GetService("CollectionService")
local PreviewModel = {}

function PreviewModel.Build(source: Instance, name: string): Model?
	local clone = source:Clone()
	if not clone then return nil end
	local model: Model
	if clone:IsA("Model") then
		model = clone
	elseif clone:IsA("Folder") then
		model = Instance.new("Model")
		for _, child in clone:GetChildren() do child.Parent = model end
		clone:Destroy()
	else
		clone:Destroy()
		return nil
	end
	model.Name = name
	local hasVisiblePart = false
	for _, object in model:GetDescendants() do
		if not object:IsDescendantOf(model) then continue end
		-- Explicit visual whitelist: no scripts, constraints, interaction prompts,
		-- sounds or effects from the gameplay rig are published to clients.
		local visual = object:IsA("Model") or object:IsA("Folder") or object:IsA("BasePart")
			or object:IsA("DataModelMesh") or object:IsA("SurfaceAppearance")
			or object:IsA("Decal") or object:IsA("Texture")
		if not visual or (object:IsA("BasePart") and object.Transparency >= 1) then
			object:Destroy()
			continue
		end
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			if object:IsA("Seat") then object.Disabled = true
			elseif object:IsA("VehicleSeat") then object.Disabled = true end
			hasVisiblePart = true
		end
	end
	if not hasVisiblePart then model:Destroy(); return nil end
	local objects: { Instance } = model:GetDescendants()
	table.insert(objects, model)
	for _, object in objects do
		for _, tag in CollectionService:GetTags(object) do CollectionService:RemoveTag(object, tag) end
		for attribute in object:GetAttributes() do object:SetAttribute(attribute, nil) end
	end
	local bounds = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-bounds.Position) * model:GetPivot())
	return model
end

return PreviewModel
