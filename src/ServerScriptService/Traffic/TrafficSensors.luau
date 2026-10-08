--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Config = require(script.Parent.TrafficConfiguration)
local Sensors = {}
Sensors.__index = Sensors
export type Body = { model: Model, frame: CFrame, size: Vector3, velocity: Vector3 }
export type Sensor = typeof(setmetatable({} :: {cast: RaycastParams, overlap: OverlapParams,
	ground: RaycastParams, bodies: {Body}, ignored: {Instance}, filteringModel: Model?, filtered: boolean}, Sensors))
function Sensors.new(roads: {Instance}, ignored: {Instance}): Sensor
	local self = setmetatable({cast=RaycastParams.new(),overlap=OverlapParams.new(),
		ground=RaycastParams.new(),bodies={},ignored=ignored,filteringModel=nil,filtered=false},Sensors)
	self.cast.FilterType=Enum.RaycastFilterType.Exclude; self.cast.RespectCanCollide=true
	self.overlap.FilterType=Enum.RaycastFilterType.Exclude; self.overlap.RespectCanCollide=true
	self.ground.FilterType=Enum.RaycastFilterType.Include
	self.ground.FilterDescendantsInstances=roads
	self.ground.RespectCanCollide=true
	return self
end
function Sensors.RefreshBodies(self: Sensor, cars: {Body})
	table.clear(self.bodies)
	for _,body in cars do table.insert(self.bodies,body) end
	local scooters=Workspace:FindFirstChild(ScooterConfig.ScooterFolderName)
	if scooters then
		for _,model in scooters:GetChildren() do
			if model:IsA("Model") and model.PrimaryPart then
				local frame,size=model:GetBoundingBox()
				table.insert(self.bodies,{model=model,frame=frame,size=size,velocity=model.PrimaryPart.AssemblyLinearVelocity})
			end
		end
	end
	for _,player in Players:GetPlayers() do
		local character=player.Character
		if character and character.PrimaryPart then
			local frame,size=character:GetBoundingBox()
			table.insert(self.bodies,{model=character,frame=frame,size=size,velocity=character.PrimaryPart.AssemblyLinearVelocity})
		end
	end
end
function Sensors.Filter(self: Sensor, model: Model?)
	if self.filtered and self.filteringModel==model then return end
	self.filtered=true; self.filteringModel=model
	local ignored=table.clone(self.ignored)
	if model then table.insert(ignored,model) end
	self.cast.FilterDescendantsInstances=ignored
	self.overlap.FilterDescendantsInstances=ignored
end
function Sensors.Frame(position: Vector3, direction: Vector3, size: Vector3): CFrame
	local p=position+Vector3.yAxis*(size.Y/2+Config.Vehicle.GroundClearance)
	return CFrame.lookAt(p,p+direction)
end
function Sensors.Ground(self: Sensor, position: Vector3, direction: Vector3, size: Vector3): CFrame?
	local right=direction:Cross(Vector3.yAxis).Unit
	local front=position+direction*Config.Vehicle.Wheelbase/2
	local back=position-direction*Config.Vehicle.Wheelbase/2
	local points={front,back,position+right*size.X/2,position-right*size.X/2}
	for _,x in {-1,1} do for _,z in {-1,1} do
		table.insert(points,position+right*size.X/2*x+direction*size.Z/2*z)
	end end
	local heights: {number} = {}
	for _,p in points do
		local hit=Workspace:Raycast(p+Vector3.yAxis*Config.GroundProbeHeight,
			-Vector3.yAxis*Config.GroundProbeDepth,self.ground)
		if not hit or hit.Normal.Y<math.cos(Config.MaxSlope) or math.abs(hit.Position.Y-position.Y)>Config.MaxGroundChange then return nil end
		table.insert(heights,hit.Position.Y)
	end
	local pitch=(heights[1]-heights[2])/Config.Vehicle.Wheelbase
	local roll=(heights[3]-heights[4])/size.X
	if math.abs(pitch)>math.tan(Config.MaxSlope) or math.abs(roll)>math.tan(Config.MaxSlope) then return nil end
	local forward=Vector3.new(direction.X,pitch,direction.Z).Unit
	local surfaceRight=Vector3.new(right.X,roll,right.Z).Unit
	local up=surfaceRight:Cross(forward).Unit
	local y=math.max(table.unpack(heights))+size.Y/2+Config.Vehicle.GroundClearance
	return CFrame.lookAt(Vector3.new(position.X,y,position.Z),Vector3.new(position.X,y,position.Z)+forward,up)
end
local function intersects(frame: CFrame, size: Vector3, body: Body, prediction: number): boolean
	-- Conservative oriented footprint; includes query-disabled scooter meshes.
	local p=frame:PointToObjectSpace(body.frame.Position+body.velocity*prediction)
	local relative=frame:ToObjectSpace(body.frame)
	local half=body.size/2
	local extent=Vector3.new(
		math.abs(relative.RightVector.X)*half.X+math.abs(relative.UpVector.X)*half.Y+math.abs(relative.LookVector.X)*half.Z,
		math.abs(relative.RightVector.Y)*half.X+math.abs(relative.UpVector.Y)*half.Y+math.abs(relative.LookVector.Y)*half.Z,
		math.abs(relative.RightVector.Z)*half.X+math.abs(relative.UpVector.Z)*half.Y+math.abs(relative.LookVector.Z)*half.Z)
	return math.abs(p.X)<size.X/2+extent.X and math.abs(p.Y)<size.Y/2+extent.Y and math.abs(p.Z)<size.Z/2+extent.Z
end
function Sensors.Clear(self: Sensor, model: Model?, frame: CFrame, size: Vector3, prediction: number?): (boolean, Instance?)
	self:Filter(model)
	local parts=Workspace:GetPartBoundsInBox(frame,size,self.overlap)
	if #parts>0 then return false,parts[1] end
	for _,body in self.bodies do
		if body.model~=model and (intersects(frame,size,body,0) or intersects(frame,size,body,prediction or 0)) then
			return false,body.model
		end
	end
	return true,nil
end
function Sensors.Sweep(self: Sensor, model: Model, from: CFrame, to: CFrame, size: Vector3): (boolean, Instance?)
	local clear,obstacle=self:Clear(model,to,size)
	if not clear then return false,obstacle end
	self:Filter(model)
	local delta=to.Position-from.Position
	-- Inflate for the corner swept by rotation, which a translational blockcast omits.
	local angle=math.acos(math.clamp(from.LookVector:Dot(to.LookVector),-1,1))
	local padding=size.Magnitude*math.sin(angle/2)
	local sweptSize=size+Vector3.new(padding,0,padding)
	if delta.Magnitude>0.0001 then
		local hit=Workspace:Blockcast(from,sweptSize,delta,self.cast)
		if hit then return false,hit.Instance end
	end
	for _,body in self.bodies do
		if body.model~=model and intersects(from:Lerp(to,0.5),sweptSize+Vector3.new(0,0,delta.Magnitude),body,0) then return false,body.model end
	end
	return true,nil
end
return Sensors
