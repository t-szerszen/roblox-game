--!strict

local Collection = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Activity.ActivityConfig)
local Locations = require(ReplicatedStorage.Shared.Activity.DeliveryLocations)
local map = Workspace:WaitForChild("Map", 10)
if not map then warn("Delivery: authored map is unavailable; no stations created"); return end

-- All markers belong to the runtime system, outside the manually authored map.
local existing = Workspace:FindFirstChild("DeliveryStations")
if existing then warn("DeliveryStations already exists; preserving authored content"); return end
local root = Instance.new("Folder")
root.Name = "DeliveryStations"
root:SetAttribute("DeliveryOwned", true)
root.Parent = Workspace
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {map, Workspace.Terrain}
local positions: {Vector3} = {}
local function ground(position: Vector3, checkClearance: boolean?): Vector3?
	local hit = Workspace:Raycast(position + Vector3.yAxis * 16, -Vector3.yAxis * 32, params)
	if not hit or hit.Normal.Y < 0.8 or math.abs(hit.Position.Y-position.Y)>Locations.MaxGroundDifference then return nil end
	if checkClearance==false then return hit.Position end
	-- An empty volume above the ground prevents placing a handover inside walls.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {map}
	for _,part in Workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.yAxis*3),Vector3.new(3,4,3),overlap) do
		if part.CanCollide then return nil end
	end
	return hit.Position
end
local function create(id: string, name: string, position: Vector3, pickup: boolean, source: Instance)
	for _,used in positions do if (used-position).Magnitude<3 then return end end
	table.insert(positions,position)
	local marker = Instance.new("Part")
	marker.Name=id; marker.Size=Vector3.new(1.5,1.5,1.5)
	marker.Anchored=true; marker.CanCollide=false; marker.CanTouch=false; marker.CanQuery=false
	marker.Position=position+Vector3.yAxis*1.3
	marker.Color=if pickup then Color3.fromRGB(255,209,82) else Color3.fromRGB(100,207,160)
	marker:SetAttribute("DeliveryName",name); marker.Parent=root
	local reference=Instance.new("ObjectValue");reference.Name="DeliveryBuilding";reference.Value=source;reference.Parent=marker
	local bindings: {RBXScriptConnection}={}
	table.insert(bindings,source.Destroying:Connect(function() marker:Destroy() end))
	table.insert(bindings,source.AncestryChanged:Connect(function() if not source:IsDescendantOf(map) then marker:Destroy() end end))
	local cleanup: RBXScriptConnection?=nil
	cleanup=marker.Destroying:Connect(function()
		for _,connection in bindings do connection:Disconnect() end
		if cleanup then cleanup:Disconnect() end
	end)
	local gui=Instance.new("BillboardGui")
	gui.Size=UDim2.fromOffset(200,52); gui.StudsOffset=Vector3.new(0,2,0); gui.MaxDistance=80; gui.Parent=marker
	local label=Instance.new("TextLabel")
	label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=0.2
	label.BackgroundColor3=Color3.fromRGB(27,30,37); label.TextColor3=Color3.fromRGB(242,244,248)
	label.Font=Enum.Font.GothamMedium; label.TextSize=14; label.TextWrapped=true; label.Text=name; label.Parent=gui
	Collection:AddTag(marker,if pickup then Config.PickupTag else Config.DestinationTag)
end
local buildings: {Instance} = {}
for _,path in Locations.BuildingFolders do
	local folder: Instance? = map
	for _,name in path do folder=if folder then folder:FindFirstChild(name) else nil end
	if folder then for _,child in folder:GetChildren() do table.insert(buildings,child) end end
end
-- Authored tags take priority over generated points, separately for each role.
if #Collection:GetTagged(Config.PickupTag)==0 then
	for _,store in Locations.Stores do
		local nearby: Model?=nil
		for _,building in buildings do
			if building:IsA("Model") and string.find(string.lower(building.Name),"sklep",1,true) then
				local cf=building:GetBoundingBox()
				if (Vector3.new(cf.Position.X,store.Position.Y,cf.Position.Z)-store.Position).Magnitude<=Locations.StoreSearchRadius then nearby=building;break end
			end
		end
		local point=if nearby then ground(store.Position,false) else nil
		if point and nearby then create(store.Id,store.Name,point,true,nearby) else warn("Delivery: unavailable store entrance "..store.Id) end
	end
end
if #Collection:GetTagged(Config.DestinationTag)==0 then
	local count=0
	for _,building in buildings do
		if count>=Locations.MaxDestinations then break end
		if not building:IsA("Model") and not building:IsA("BasePart") then continue end
		local cf,size
		if building:IsA("Model") then cf,size=building:GetBoundingBox() else cf,size=building.CFrame,building.Size end
		if size.Y<Locations.MinimumBuildingHeight or math.min(size.X,size.Z)<Locations.MinimumBuildingWidth then continue end
		local bottom=cf.Position.Y-size.Y*0.5
		for _,offset in {Vector3.new(size.X*0.5+Locations.BuildingMargin,0,0),Vector3.new(-size.X*0.5-Locations.BuildingMargin,0,0),Vector3.new(0,0,size.Z*0.5+Locations.BuildingMargin),Vector3.new(0,0,-size.Z*0.5-Locations.BuildingMargin)} do
			local side=cf:PointToWorldSpace(offset)
			local point=ground(Vector3.new(side.X,bottom,side.Z))
			if point then
				count+=1
				create("Building_"..count,"Adres "..count,point,false,building)
				break
			end
		end
	end
	if count==0 then warn("Delivery: no accessible buildings; add DeliveryDestination tags to entrance parts") end
end
local cleanup: RBXScriptConnection? = nil
cleanup=script.Destroying:Connect(function() root:Destroy();if cleanup then cleanup:Disconnect() end end)
