--!strict
local Config = require(script.Parent.TrafficConfiguration)
local Trajectory=require(script.Parent.Trajectory)
local Adapter = {}
export type Vehicle = { model: Model, root: BasePart, bounds: Vector3 }
function Adapter.Placeholder(): Model
	local model=Instance.new("Model"); model.Name=Config.Vehicle.TemplateName
	local function part(name: string, size: Vector3, frame: CFrame, color: Color3): Part
		local p=Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=frame; p.Color=color
		p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Parent=model
		return p
	end
	local root=part(Config.Vehicle.RootName,Config.Vehicle.Bounds,CFrame.identity,Color3.new(0,0,0))
	root.Transparency=1; root.CanQuery=true; root.CanCollide=true; model.PrimaryPart=root
	part("Body",Vector3.new(5.8,1.6,11.5),CFrame.new(0,-0.5,0),Color3.fromRGB(66,110,150))
	part("Cabin",Vector3.new(4.8,1.7,5.4),CFrame.new(0,1,0.6),Color3.fromRGB(100,165,190))
	for _,z in {-Config.Vehicle.Wheelbase/2,Config.Vehicle.Wheelbase/2} do
		for _,x in {-2.5,2.5} do
			local wheel=part("Wheel",Vector3.new(1,2.2,2.2),CFrame.new(x,-0.9,z),Color3.fromRGB(24,24,24))
			wheel.Shape=Enum.PartType.Cylinder; wheel.Size=Vector3.new(1,2.2,2.2)
		end
	end
	for _,x in {-1.9,1.9} do
		part("Headlight",Vector3.new(1,0.5,0.15),CFrame.new(x,-0.1,-5.8),Color3.fromRGB(255,248,201))
		part("BrakeLight",Vector3.new(1,0.5,0.15),CFrame.new(x,-0.1,5.8),Color3.fromRGB(100,12,12))
	end
	local axlePositions: {[string]: number} = {FrontAxle=-Config.Vehicle.Wheelbase/2,RearAxle=Config.Vehicle.Wheelbase/2,DriverPosition=-0.8}
	for name,z in axlePositions do
		local attachment=Instance.new("Attachment"); attachment.Name=name; attachment.Position=Vector3.new(0,-0.9,z); attachment.Parent=root
	end
	model:SetAttribute("TrafficBounds",Config.Vehicle.Bounds)
	return model
end
function Adapter.Prepare(template: Model): Vehicle
	local root=template:FindFirstChild(Config.Vehicle.RootName,true)
	assert(root and root:IsA("BasePart") and template.PrimaryPart==root,"Traffic template requires configured PrimaryPart")
	assert(root.PivotOffset==CFrame.identity,"Chassis pivot offset must be identity")
	for _,name in {"FrontAxle","RearAxle"} do
		local a=root:FindFirstChild(name); assert(a and a:IsA("Attachment"),"Missing "..name)
	end
	local value=template:GetAttribute("TrafficBounds")
	assert(Trajectory.ValidVector(value),"TrafficBounds must be finite Vector3")
	local bounds=value :: Vector3
	assert(Trajectory.ValidVector(bounds) and bounds.X>0 and bounds.Y>0 and bounds.Z>0
		and bounds.Magnitude<100,"Invalid TrafficBounds")
	for _,part in template:GetDescendants() do
		if part:IsA("BasePart") then
			local relative=root.CFrame:ToObjectSpace(part.CFrame)
			for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
				local corner=relative:PointToWorldSpace(part.Size*Vector3.new(x,y,z)/2)
				assert(math.abs(corner.X)<=bounds.X/2+0.01 and math.abs(corner.Y)<=bounds.Y/2+0.01
					and math.abs(corner.Z)<=bounds.Z/2+0.01,"TrafficBounds must contain all visible parts")
			end end end
		end
	end
	local clone=template:Clone()
	for _,v in clone:GetDescendants() do
		if v:IsA("LuaSourceContainer") or v:IsA("Constraint") or v:IsA("BodyMover") then clone:Destroy(); error("Traffic template cannot contain scripts or physics actuators") end
		if v:IsA("BasePart") then v.Anchored=true; v.CanCollide=false; v.CanTouch=false; v.CanQuery=false end
	end
	local chassis=clone.PrimaryPart :: BasePart
	chassis.Size=bounds; chassis.CanCollide=true; chassis.CanQuery=true
	clone:SetAttribute("NPCVehicle",true)
	return {model=clone,root=chassis,bounds=bounds}
end
return Adapter
