--!strict
local Config=require(script.Parent.TrafficConfiguration)
local Types=require(script.Parent.TrafficTypes)
local Controller=require(script.Parent.VehicleController)
local Debug={}; Debug.__index=Debug
export type State=typeof(setmetatable({} :: {folder: Folder, vehicles: {[number]: Folder}, drawn: boolean},Debug))
local function marker(parent: Instance, name: string, position: Vector3, color: Color3, size: Vector3): Part
	local p=Instance.new("Part"); p.Name=name; p.Size=size; p.Position=position; p.Color=color
	p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Material=Enum.Material.Neon
	p.Parent=parent; return p
end
local function line(parent: Instance, a: Vector3, b: Vector3, color: Color3)
	local delta=b-a; if delta.Magnitude<0.01 then return end
	local p=marker(parent,"Lane",(a+b)/2,color,Vector3.new(0.2,0.2,delta.Magnitude))
	p.CFrame=CFrame.lookAt((a+b)/2,b)
end
function Debug.new(root: Folder): State
	local folder=Instance.new("Folder"); folder.Name="DebugVisualization"; folder.Parent=root
	return setmetatable({folder=folder,vehicles={},drawn=false},Debug)
end
function Debug.Network(self: State, network: Types.Network)
	if self.drawn then return end; self.drawn=true
	for _,node in network.nodes do
		marker(self.folder,node.id,node.position+Vector3.yAxis,Color3.fromRGB(100,180,255),Vector3.one)
	end
	for _,path in network.paths do
		local color=if path.edge.enabled==false then Color3.fromRGB(255,80,80)
			elseif path.edge.intersection then Color3.fromRGB(255,190,60) else Color3.fromRGB(40,230,120)
		for i=1,#path.samples-1,Config.DebugSampleStride do
			local nextIndex=math.min(i+Config.DebugSampleStride,#path.samples)
			line(self.folder,path.samples[i].position+Vector3.yAxis,path.samples[nextIndex].position+Vector3.yAxis,color)
		end
	end
	for _,id in network.spawns do
		marker(self.folder,"Spawn",network.nodes[id].position+Vector3.yAxis*2,
			Color3.fromRGB(190,60,255),Vector3.new(2,2,2))
	end
end
function Debug.Vehicle(self: State, car: Controller.Vehicle, enabled: boolean)
	local model=car.vehicle.model
	model:SetAttribute("TrafficState",car.reason); model:SetAttribute("TrafficSpeed",car.speed)
	local path=car:Path(); model:SetAttribute("TrafficRoute",if path then path.edge.id else "Missing")
	model:SetAttribute("TrafficRecoveryAttempts",car.recoveryAttempts)
	model:SetAttribute("TrafficObstacle",if car.obstacle then car.obstacle:GetFullName() else nil)
	local reservations={}; for zone in car.reservations do table.insert(reservations,zone) end
	model:SetAttribute("TrafficReservations",table.concat(reservations,", "))
	if not enabled then return end
	local existing=self.vehicles[car.id]
	local f: Folder=existing or Instance.new("Folder")
	if existing then f:ClearAllChildren() else f.Name=tostring(car.id); f.Parent=self.folder; self.vehicles[car.id]=f end
	local labelPart=marker(f,"State",car.vehicle.root.Position+Vector3.yAxis*4,Color3.fromRGB(255,255,255),Vector3.one*0.2)
	local gui=Instance.new("BillboardGui"); gui.Size=UDim2.fromOffset(220,45); gui.AlwaysOnTop=true; gui.Parent=labelPart
	local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=1
	label.Text=string.format("#%d %.1f stud/s %s",car.id,car.speed,car.reason); label.TextColor3=Color3.new(1,1,1); label.Parent=gui
	for zone in car.reservations do
		for _,movement in car.network.paths do
			if movement.edge.intersection==zone then
				local sample=movement.samples[math.ceil(#movement.samples/2)]
				marker(f,"Reserved_"..zone,sample.position+Vector3.yAxis*3,Color3.fromRGB(230,60,255),Vector3.one*3)
				break
			end
		end
	end
	marker(f,"Target",car.targetPoint+Vector3.yAxis*2,Color3.fromRGB(255,255,70),Vector3.one)
	line(f,model:GetPivot().Position,car.targetPoint,Color3.fromRGB(255,255,70))
	local box=marker(f,"FollowingBoundary",car.vehicle.root.Position+car.vehicle.root.CFrame.LookVector*(Config.SafeGap+car.speed*Config.Headway),
		Color3.fromRGB(255,150,60),Vector3.new(car.vehicle.bounds.X,1,0.3)); box.CFrame=CFrame.new(box.Position)*car.vehicle.root.CFrame.Rotation
	if car.obstacle then
		local pos=if car.obstacle:IsA("BasePart") then car.obstacle.Position elseif car.obstacle:IsA("Model") then car.obstacle:GetPivot().Position else nil
		if pos then marker(f,"Obstacle",pos,Color3.fromRGB(255,20,20),Vector3.one*2) end
	end
end
function Debug.Remove(self: State, id: number)
	local f=self.vehicles[id]; if f then f:Destroy(); self.vehicles[id]=nil end
end
function Debug.Clear(self: State)
	self.folder:ClearAllChildren(); table.clear(self.vehicles); self.drawn=false
end
function Debug.Destroy(self: State) self:Clear(); self.folder:Destroy() end
return Debug
