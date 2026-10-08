--!strict
local Config=require(script.Parent.TrafficConfiguration)
local Types=require(script.Parent.TrafficTypes)
local Trajectory=require(script.Parent.Trajectory)
local RoadNetwork=require(script.Parent.RoadNetwork)
local Adapter=require(script.Parent.VehicleAdapter)
local Sensors=require(script.Parent.TrafficSensors)
local Intersections=require(script.Parent.IntersectionManager)
local Controller={}; Controller.__index=Controller
export type Vehicle = typeof(setmetatable({} :: {
	id: number, vehicle: Adapter.Vehicle, network: Types.Network, route: {string}, index: number,
	distance: number, traveled: number, speed: number, target: number, reason: string,
	obstacle: Instance?, targetPoint: Vector3, blockedTime: number, recoveryAttempts: number,
	blockedSince: number?, routeEndSince: number?, stoppedTime: number, irrelevantSince: number?, random: Random,
	reservations: {[string]: number}, lastFrame: CFrame, remove: boolean, exitReason: string?,
},Controller))
function Controller.new(id: number, vehicle: Adapter.Vehicle, network: Types.Network, route: {string}, random: Random): Vehicle
	assert(#route>0,"Vehicle requires route")
	return setmetatable({id=id,vehicle=vehicle,network=network,route=route,index=1,distance=0,traveled=0,
		speed=0,target=0,reason="Starting",obstacle=nil,targetPoint=vehicle.root.Position,blockedTime=0,
		recoveryAttempts=0,blockedSince=nil,routeEndSince=nil,stoppedTime=0,irrelevantSince=nil,random=random,
		reservations={},lastFrame=vehicle.root.CFrame,remove=false,exitReason=nil},Controller)
end
function Controller.Path(self: Vehicle): Types.Path?
	local id=self.route[self.index]
	return if id then self.network.paths[id] else nil
end
function Controller.Preview(self: Vehicle, distance: number): (Types.Sample?,Types.Path?)
	for i=self.index,#self.route do
		local path=self.network.paths[self.route[i]]
		if not path or path.edge.enabled==false then return nil,nil end
		local start=if i==self.index then self.distance else 0
		if distance<=path.length-start then return Trajectory.At(path,start+distance),path end
		distance-=path.length-start
	end
	return nil,nil
end
function Controller.Fail(self: Vehicle, reason: string)
	self.remove=true; self.exitReason=reason; self.speed=0; self.target=0; self.reason=reason
end
function Controller.Sense(self: Vehicle, sensor: Sensors.Sensor, intersections: Intersections.State, now: number)
	local path=self:Path()
	if not path or path.edge.enabled==false then self:Fail("InvalidRoute"); return end
	self.target=math.min(Config.MaxSpeed,path.edge.speed); self.reason="Driving"; self.obstacle=nil
	-- Refill only from connected exits; work is bounded by MaxRouteHops.
	if #self.route-self.index<3 then
		local tail=self.network.paths[self.route[#self.route]]
		if tail then
			local extension=RoadNetwork.Route(self.network,tail.edge.to,self.random)
			for _,id in extension do table.insert(self.route,id) end
		end
	end
	local remaining=0
	for i=self.index,#self.route do
		local remainingPath=self.network.paths[self.route[i]]
		if not remainingPath or remainingPath.edge.enabled==false then self:Fail("InvalidRoute"); return end
		remaining+=remainingPath.length-(if i==self.index then self.distance else 0)
	end
	local endSpeed=Trajectory.SafeSpeed(remaining,self.vehicle.bounds.Z/2+Config.SafeGap,Config.Braking)
	if endSpeed<=self.target then self.target=endSpeed; self.reason="RouteEnd" end
	local range=math.min(Config.ObstacleRange,math.max(Config.LookAhead,
		self.speed^2/(2*Config.Braking)+self.speed*Config.Headway+self.vehicle.bounds.Z))
	local gateDistance=0
	for i=self.index,math.min(#self.route,self.index+3) do
		local nextPath=self.network.paths[self.route[i]]
		if not nextPath or nextPath.edge.enabled==false then break end
		local zone=nextPath.edge.intersection
		if zone and not self.reservations[zone] and gateDistance<range then
			local node=self.network.nodes[nextPath.edge.from]
			local mustStop=node.behavior=="stop" and self.stoppedTime<Config.StopDuration
			local exitSample=self:Preview(gateDistance+nextPath.length+self.vehicle.bounds.Z+Config.IntersectionClearance)
			local exitFrame=if exitSample then Sensors.Frame(exitSample.position,exitSample.direction,self.vehicle.bounds) else nil
			local exitClear=exitFrame~=nil and sensor:Clear(self.vehicle.model,exitFrame :: CFrame,self.vehicle.bounds)
			local granted=not mustStop and intersections:Request(zone,self.id,now,exitClear)
			if granted then
				self.reservations[zone]=self.traveled+gateDistance+nextPath.length+self.vehicle.bounds.Z/2+Config.IntersectionClearance
			else
				self.target=math.min(self.target,Trajectory.SafeSpeed(gateDistance,self.vehicle.bounds.Z/2+Config.SafeGap,Config.Braking))
				self.reason=if mustStop then "StopSign" else "IntersectionYield"
			end
		end
		gateDistance+=nextPath.length-(if i==self.index then self.distance else 0)
	end
	local step=Config.SampleSpacing*2
	for d=0,range,step do
		local sample,lookPath=self:Preview(d)
		if not sample or not lookPath then
			break
		end
		local curveLimit=if sample.curvature>0.0001 then math.min(math.sqrt(Config.LateralAcceleration/sample.curvature),Config.MaxYawRate/sample.curvature) else Config.MaxSpeed
		local speedAtPoint=math.min(curveLimit,lookPath.edge.speed)
		self.target=math.min(self.target,math.sqrt(speedAtPoint^2+2*Config.Braking*d))
		local frame=Sensors.Frame(sample.position,sample.direction,self.vehicle.bounds)
		local clear,obstacle=sensor:Clear(self.vehicle.model,frame,self.vehicle.bounds,
			math.min(Config.Headway,d/math.max(self.speed,Config.MinTurnSpeed)))
		if not clear then
			local limit=Trajectory.SafeSpeed(d,Config.SafeGap+self.speed*Config.Headway,Config.Braking)
			if limit<self.target then self.target=limit; self.reason=if frame then "Obstacle" else "NoRoadSupport"; self.obstacle=obstacle end
			break
		end
	end
	local look=self:Preview(Config.LookAhead+self.speed*Config.SpeedLookAhead)
	self.targetPoint=if look then look.position else path.samples[#path.samples].position
	if self.reason=="RouteEnd" and self.target<0.1 and self.speed<0.1 then
		-- Start the short retirement grace only after stopping at the actual boundary.
		self.blockedSince=nil
		if not self.routeEndSince then self.routeEndSince=now end
		if now-(self.routeEndSince :: number)>=Config.RouteEndGrace then self:Fail("DeadEnd") end
		return
	end
	self.routeEndSince=nil
	if self.target<0.1 and self.speed<0.1 then
		if not self.blockedSince then self.blockedSince=now end
		if now-(self.blockedSince :: number)>Config.MaxRecoveryLifetime then self:Fail("RecoveryTimeout") end
	else self.blockedSince=nil end
end
function Controller.Step(self: Vehicle, dt: number, sensor: Sensors.Sensor, intersections: Intersections.State)
	if self.remove then return end
	if not self.vehicle.model.Parent then self:Fail("RemovedModel"); return end
	local root=self.vehicle.root
	if root.Position.Y<Config.FallY then self:Fail("BelowMap"); return end
	local displacement=(root.Position-self.lastFrame.Position).Magnitude
	if displacement>Config.MaxLaneError then self:Fail("LaneDisplacement"); return end
	local path=self:Path(); if not path then self:Fail("MissingRoute"); return end
	local rate=if self.target<self.speed then (if self.target==0 and self.obstacle then Config.EmergencyBraking else Config.Braking) else Config.Acceleration
	local previousSpeed=self.speed
	self.speed=Trajectory.Approach(self.speed,self.target,rate,dt)
	local advance=(previousSpeed+self.speed)*0.5*dt
	local sample,nextPath=self:Preview(advance)
	if not sample or not nextPath then
		self.speed=0; self.target=0; self.reason="RouteEnd"; advance=0
		sample=Trajectory.At(path,self.distance); nextPath=path
	end
	assert(sample and nextPath)
	-- A reservation is mandatory at the movement boundary, including between sensing ticks.
	local movementZone=nextPath.edge.intersection
	if movementZone and not self.reservations[movementZone] then
		self.speed=0; self.target=0; self.reason="IntersectionYield"; advance=0
		sample=Trajectory.At(path,self.distance)
	end
	local desired=sensor:Ground(sample.position,sample.direction,self.vehicle.bounds)
	if not desired then self.speed=0; self.reason="NoRoadSupport"; advance=0
	else
		local error=root.Position-self.lastFrame.Position
		if error.Magnitude>0.05 then
			desired+=error*math.max(0,1-Config.RecoverySpeed*dt/math.max(error.Magnitude,0.001))
			self.reason="LaneRecovery"
		end
		local clear,obstacle=sensor:Sweep(self.vehicle.model,root.CFrame,desired,self.vehicle.bounds)
		if clear then
			self.vehicle.model:PivotTo(desired)
			self.lastFrame=desired; self.distance+=advance; self.traveled+=advance
			if advance>0.001 then intersections:Progress(self.id) end
		else
			self.speed=0; self.target=0; advance=0; self.reason="EmergencyBrake"; self.obstacle=obstacle
		end
	end
	while self.distance>=path.length and self.index<#self.route do
		self.distance-=path.length; self.index+=1; path=self:Path()
		if not path then self:Fail("MissingRoute"); return end
	end
	-- Compact consumed route state rather than keeping an ever-growing history.
	if self.index>Config.MaxRouteHops then
		for _=1,self.index-1 do table.remove(self.route,1) end; self.index=1
	end
	for zone,releaseAt in self.reservations do
		if self.traveled>=releaseAt then intersections:ReleaseZone(zone,self.id); self.reservations[zone]=nil end
	end
	if advance<0.001 then
		self.stoppedTime+=dt; self.blockedTime+=dt
	else self.stoppedTime=0; self.blockedTime=0; self.recoveryAttempts=0 end
	if self.reason=="RouteEnd" and self.speed<0.1 and self.target<0.1 then
		self.blockedTime=0; self.recoveryAttempts=0
		return
	end
	if self.blockedTime>Config.StuckTimeout then
		self.blockedTime=0; self.recoveryAttempts+=1
		if self.recoveryAttempts>Config.MaxRecoveryAttempts then self:Fail("Stuck")
		else
			-- Replan only from a node before entering its movement. Never jump to another road.
			if self.distance<0.1 and not next(self.reservations) then
				local alternate=RoadNetwork.Route(self.network,path.edge.from,self.random,path.edge.id)
				if #alternate>0 then self.route=alternate; self.index=1; self.distance=0 end
			end
			self.reason="RecoveryWaiting"
		end
	end
end
function Controller.Destroy(self: Vehicle, intersections: Intersections.State)
	intersections:Release(self.id); table.clear(self.reservations); table.clear(self.route)
	self.vehicle.model:Destroy(); self.remove=true
end
return Controller
