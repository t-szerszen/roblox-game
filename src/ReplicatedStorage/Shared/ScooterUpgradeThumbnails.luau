--!strict
-- Static viewport renders reuse the player's meshes without frame loops or uploaded images.
local Catalog=require(script.Parent.ScooterUpgradeCatalog)
local Thumbnails={}
local targets={
	Vesc={ScooterBody=true},
	WeightReduction={ScooterBody=true,FootRest=true},
	WheelieMode={BackFender=true,FrontFender=true,RearFootRest=true,BackWheel=true},
	DualMotor={BackWheel=true},
	Brakes={BrakeDisc=true,FrontBrakeCaliper=true},
	Battery1Kw={ScooterBody=true},
}
local function selected(part: BasePart, model: Model, names: {[string]: boolean}): boolean
	local cursor: Instance?=part
	while cursor and cursor~=model do
		if names[cursor.Name] then return true end
		cursor=cursor.Parent
	end
	return false
end
function Thumbnails.Clear(view: any)
	for _,card in view.Cards do card.World:ClearAllChildren() end
end
function Thumbnails.Build(view: any, model: Model)
	Thumbnails.Clear(view)
	local root=model.PrimaryPart
	local angle=if root then root.CFrame.RightVector*1.2-root.CFrame.LookVector*.8+Vector3.yAxis*.55 else Vector3.new(1,.5,1)
	for _,item in Catalog.Items do
		local card=view.Cards[item.Id]
		if not card then continue end
		local names=targets[item.Id] or {}
		local full=item.Id=="WeightReduction"
		local group=Instance.new("Model")
		group.Name="CardGeometry"
		for _,part in model:GetDescendants() do
			if not part:IsA("BasePart") or part:IsA("Seat") or part:IsA("VehicleSeat") then continue end
			local target=selected(part,model,names)
			if not target and (not full or part.Transparency>=1) then continue end
			if part.Name=="UpgradeFrontMotorVisual" then continue end
			local clone=part:Clone()
			if not clone then continue end
			for _,child in clone:GetChildren() do
				if not child:IsA("SurfaceAppearance") and not child:IsA("DataModelMesh") then child:Destroy() end
			end
			clone.Anchored=true clone.CanCollide=false clone.CanTouch=false clone.CanQuery=false
			clone.LocalTransparencyModifier=0 clone.Transparency=0
			if target then
				local appearance=clone:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then appearance:Destroy() end
				if clone:IsA("MeshPart") then clone.TextureID="" end
				clone.Color=Color3.fromRGB(255,183,62)
				clone.Material=Enum.Material.SmoothPlastic
			end
			clone.Parent=group
		end
		if #group:GetChildren()==0 then group:Destroy() continue end
		local bounds,size=group:GetBoundingBox()
		for _,part in group:GetChildren() do
			if part:IsA("BasePart") then part.CFrame-=bounds.Position end
		end
		group.Parent=card.World
		local distance=size.Magnitude/(2*math.tan(math.rad(card.Camera.FieldOfView/2)))*1.08
		card.Camera.CFrame=CFrame.lookAt(angle.Unit*math.max(distance,.5),Vector3.zero)
	end
end
return Thumbnails
