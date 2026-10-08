--!strict
-- Run in the Command Bar after Rojo sync. Uses unparented fixtures and fresh modules;
-- it does not replace Workspace.Map or the authored traffic network.
local function run(source: Instance): number
	local folder=Instance.new("Folder")
	for _,module in source:GetChildren() do if module:IsA("ModuleScript") then module:Clone().Parent=folder end end
	local count=0
	local function check(condition: boolean, message: string)
		assert(condition,message); count+=1
	end
	local ok,err=pcall(function()
		local Config=require(folder.TrafficConfiguration)
		local Trajectory=require(folder.Trajectory)
		local Network=require(folder.RoadNetwork)
		local Intersections=require(folder.IntersectionManager)
		local Adapter=require(folder.VehicleAdapter)
		local Controller=require(folder.VehicleController)
		local Spawner=require(folder.TrafficSpawner)
		local Types=require(folder.TrafficTypes)
		local Sensors=require(folder.TrafficSensors)
		local data: Types.Data={version=1,approved=true,nodes={},edges={},spawns={"N0"},review={}}
		for i=0,4 do
			table.insert(data.nodes,{id="N"..i,position=Vector3.new(0,0,-100*i),direction=-Vector3.zAxis,
				road="road"..i,speed=Config.MaxSpeed,lane="right",outgoing=if i<4 then {"E"..i} else {}})
			if i<4 then table.insert(data.edges,{id="E"..i,from="N"..i,to="N"..(i+1),
				control1=Vector3.new(0,0,-100*i-30),control2=Vector3.new(0,0,-100*i-70),
				speed=Config.MaxSpeed,lane="right",road="road"..i}) end
		end
		local network=Network.Load(data)
		check(#network.spawns==1,"Valid spawn")
		check(#Network.Components(network)==1,"Connected directed chain")
		check(#Network.Route(network,"N0",Random.new(1))==4,"Bounded route reaches dead end")
		check(#Network.Route(network,"N4",Random.new(1))==0,"Dead end cannot invent connection")
		check(#Network.Route(network,"missing",Random.new(1))==0,"Unknown node is bounded")
		local function rejects(mutator: (any)->())
			local bad={version=1,approved=true,nodes={},edges={},spawns={"N0"},review={}}
			for _,n in data.nodes do local c=table.clone(n); c.outgoing=table.clone(n.outgoing); table.insert(bad.nodes,c) end
			for _,e in data.edges do table.insert(bad.edges,table.clone(e)) end
			mutator(bad); check(not pcall(Network.Load,bad),"Malformed network must fail")
		end
		rejects(function(d) d.edges[1].to="missing" end)
		rejects(function(d) table.insert(d.nodes,table.clone(d.nodes[1])) end)
		rejects(function(d) d.nodes[1].position=Vector3.new(0/0,0,0) end)
		rejects(function(d) d.edges[1].speed=math.huge end)
		rejects(function(d) d.spawns={"N4"} end)
		rejects(function(d) d.nodes[1].outgoing={"E2"} end)
		rejects(function(d) d.edges[1].control1=Vector3.new(0,0,10) end)
		rejects(function(d) d.edges[1].control1=Vector3.new(0,0,-100000) end)
		check(math.abs(network.paths.E0.length-100)<0.001,"Straight arc length")
		check(Trajectory.At(network.paths.E0,50).direction:Dot(-Vector3.zAxis)>0.99,"Forward orientation")
		check(math.abs(Trajectory.At(network.paths.E0,50).position.Z+50)<0.1,"Arc interpolation")
		local curve,length,curvature=Trajectory.Sample(Vector3.zero,Vector3.new(0,0,-30),Vector3.new(30,0,-40),Vector3.new(40,0,-40),2,512)
		check(length>50 and curvature>0,"Turn trajectory")
		check(curve[1].direction:Dot(-Vector3.zAxis)>0.99 and curve[#curve].direction:Dot(Vector3.xAxis)>0.99,"Continuous entry/exit tangent")
		check(Trajectory.Approach(0,20,5,0.1)==0.5,"Acceleration bounded")
		check(Trajectory.SafeSpeed(5,8,12)==0,"Blocked safe speed")
		local junction=Intersections.new()
		check(junction:Request("crossing",1,0,true),"First reservation")
		check(not junction:Request("crossing",2,0,true),"Conflicting turn held")
		check(not junction:Request("crossing",3,0,true),"FIFO queue")
		check(junction:Request("crossing",1,1,true),"Owner retains reservation")
		check(#junction:Expired(Config.IntersectionWaitTimeout+1)==1,"Stale owner reported without unsafe release")
		junction:Progress(1)
		check(#junction:Expired(Config.IntersectionWaitTimeout+2)==0,"Progress preserves a long intersection crossing")
		check(#junction:Expired(Config.IntersectionWaitTimeout*2+3)==1,"No-progress intersection recovery remains bounded")
		junction:Release(1)
		check(not junction:Request("crossing",3,2,true),"No queue overtaking")
		check(not junction:Request("crossing",2,2,false),"Blocked exit denies reservation")
		check(junction:Request("crossing",2,2,true),"FIFO owner resumes")
		junction:Release(2); junction:Release(3)
		check(next(junction.held)==nil and next(junction.queues)==nil,"Reservation cleanup")
		local template=Adapter.Placeholder(); template.Parent=folder
		local prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		check(prepared.bounds==Config.Vehicle.Bounds,"Adapter bounds")
		check(prepared.root.CanCollide and prepared.root.Anchored,"Anchored collision chassis")
		check(prepared.root:FindFirstChild("FrontAxle").Position.Z<0,"Front axle is -Z")
		local wheels=0; for _,p in prepared.model:GetChildren() do if p.Name=="Wheel" then wheels+=1 end end
		check(wheels==4,"Four-wheel placeholder")
		local invalid=template:Clone(); invalid.PrimaryPart=nil
		check(not pcall(Adapter.Prepare,invalid),"Malformed root denied"); invalid:Destroy()
		invalid=template:Clone(); Instance.new("Script").Parent=invalid
		check(not pcall(Adapter.Prepare,invalid),"Executable model denied"); invalid:Destroy()
		invalid=template:Clone(); invalid:SetAttribute("TrafficBounds",Vector3.new(1,1,1))
		check(not pcall(Adapter.Prepare,invalid),"Undersized collision envelope denied"); invalid:Destroy()
		local snapshot=Network.Load(require(folder.RoadNetworkData))
		check(#snapshot.spawns>0,"City snapshot can be required in native engine")
		local blocked=false
		local fakeSensor: any={}
		function fakeSensor:Ground(p,dir,size) return CFrame.lookAt(p+Vector3.yAxis*(size.Y/2+Config.Vehicle.GroundClearance),p+Vector3.yAxis*(size.Y/2+Config.Vehicle.GroundClearance)+dir) end
		function fakeSensor:Clear(_model,frame,_size,_prediction) return not (blocked and frame.Position.Z<-35),nil end
		function fakeSensor:Sweep(_model,_from,to,_size) return not (blocked and to.Position.Z<-35),nil end
		prepared.model:PivotTo(fakeSensor:Ground(Vector3.zero,-Vector3.zAxis,prepared.bounds))
		local car=Controller.new(1,prepared,network,{"E0","E1","E2"},Random.new(2))
		junction=Intersections.new()
		for tick=1,60 do car:Sense(fakeSensor,junction,tick/30); car:Step(1/30,fakeSensor,junction) end
		check(car.speed>5 and car.speed<=Config.MaxSpeed,"Continuous acceleration")
		check(car.vehicle.root.Position.Z<0 and car.vehicle.root.Position.Z>-30,"Continuous bounded movement")
		check(car.vehicle.root.CFrame.LookVector:Dot(-Vector3.zAxis)>0.99,"Correct driving direction")
		blocked=true
		for tick=1,180 do car:Sense(fakeSensor,junction,2+tick/30); car:Step(1/30,fakeSensor,junction) end
		check(car.speed<0.1 and car.vehicle.root.Position.Z>-35,"Obstacle stop without clipping")
		local stopped=car.vehicle.root.Position
		for tick=1,30 do car:Sense(fakeSensor,junction,8+tick/30); car:Step(1/30,fakeSensor,junction) end
		check((stopped-car.vehicle.root.Position).Magnitude<0.01,"Stationary obstacle does not trigger repeated impacts")
		blocked=false
		for tick=1,60 do car:Sense(fakeSensor,junction,9+tick/30); car:Step(1/30,fakeSensor,junction) end
		check(car.speed>5,"Resume after obstacle clears")
		car.vehicle.model:PivotTo(car.vehicle.root.CFrame+Vector3.xAxis*10); car:Step(1/30,fakeSensor,junction)
		check(car.remove and car.exitReason=="LaneDisplacement","Unsafe displacement removed")
		car:Destroy(junction)
		check(car.vehicle.model.Parent==nil and #car.route==0,"Controller cleanup")
		-- Seeing the end within look-ahead must not delete a newly stopped car.
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		local terminalDistance=network.paths.E3.length-Config.Vehicle.Bounds.Z/2-Config.SafeGap
		local stoppedSample=Trajectory.At(network.paths.E3,terminalDistance)
		prepared.model:PivotTo(fakeSensor:Ground(stoppedSample.position,stoppedSample.direction,prepared.bounds))
		car=Controller.new(2,prepared,network,{"E3"},Random.new(1)); car.distance=terminalDistance
		car:Sense(fakeSensor,junction,0); car:Step(1/30,fakeSensor,junction)
		check(not car.remove and car.reason=="RouteEnd","Terminal car waits instead of disappearing immediately")
		car:Sense(fakeSensor,junction,Config.RouteEndGrace/2); car:Step(1/30,fakeSensor,junction)
		check(not car.remove and car.recoveryAttempts==0,"Route-end grace is not bypassed by stuck recovery")
		car:Sense(fakeSensor,junction,Config.RouteEndGrace)
		car:Step(1/30,fakeSensor,junction)
		check(car.remove and car.exitReason=="DeadEnd","Terminal car retires when the short grace expires")
		car:Destroy(junction)
		-- Restore a valid continuation during the grace period; the same car resumes.
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		prepared.model:PivotTo(fakeSensor:Ground(stoppedSample.position,stoppedSample.direction,prepared.bounds))
		car=Controller.new(3,prepared,network,{"E3"},Random.new(1)); car.distance=terminalDistance
		car:Sense(fakeSensor,junction,0)
		local resumedData=table.clone(data); resumedData.nodes=table.clone(data.nodes); resumedData.edges=table.clone(data.edges)
		resumedData.nodes[5]=table.clone(data.nodes[5]); resumedData.nodes[5].outgoing={"E4"}
		table.insert(resumedData.nodes,{id="N5",position=Vector3.new(0,0,-500),direction=-Vector3.zAxis,road="road5",speed=32,lane="right",outgoing={}})
		table.insert(resumedData.edges,{id="E4",from="N4",to="N5",control1=Vector3.new(0,0,-430),control2=Vector3.new(0,0,-470),speed=32,lane="right",road="road4"})
		car.network=Network.Load(resumedData); car:Sense(fakeSensor,junction,Config.RouteEndGrace/2); car:Step(1/30,fakeSensor,junction)
		check(not car.remove and car.routeEndSince==nil and car.distance>terminalDistance,"Connected continuation resumes without a respawn")
		car:Destroy(junction)
		-- At rest with a route ending farther ahead, still accelerate towards it.
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		local approachSample=Trajectory.At(network.paths.E3,network.paths.E3.length-20)
		prepared.model:PivotTo(fakeSensor:Ground(approachSample.position,approachSample.direction,prepared.bounds))
		car=Controller.new(4,prepared,network,{"E3"},Random.new(1)); car.distance=network.paths.E3.length-20
		car:Sense(fakeSensor,junction,0); car:Step(1/30,fakeSensor,junction)
		check(not car.remove and car.speed>0 and car.routeEndSince==nil,"Look-ahead end cannot delete a car before its safe stop")
		car:Destroy(junction)
		-- Follow a true curved trajectory with the controller; no node-facing shortcut.
		local turnData: Types.Data={version=1,approved=true,nodes={
			{id="A",position=Vector3.zero,direction=-Vector3.zAxis,road="turn",speed=32,lane="right",outgoing={"turn"}},
			{id="B",position=Vector3.new(40,0,-40),direction=Vector3.xAxis,road="turn",speed=32,lane="right",outgoing={"exit"}},
			{id="C",position=Vector3.new(140,0,-40),direction=Vector3.xAxis,road="exit",speed=32,lane="right",outgoing={}},
		},edges={
			{id="turn",from="A",to="B",control1=Vector3.new(0,0,-30),control2=Vector3.new(30,0,-40),speed=32,lane="right",road="turn"},
			{id="exit",from="B",to="C",control1=Vector3.new(70,0,-40),control2=Vector3.new(110,0,-40),speed=32,lane="right",road="exit"},
		},spawns={"A"},review={}}
		local turnNetwork=Network.Load(turnData)
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		prepared.model:PivotTo(fakeSensor:Ground(Vector3.zero,-Vector3.zAxis,prepared.bounds))
		car=Controller.new(10,prepared,turnNetwork,{"turn","exit"},Random.new(3))
		local maxHeadingChange=0; local previous=car.vehicle.root.CFrame.LookVector
		for tick=1,210 do
			car:Sense(fakeSensor,junction,tick/30); car:Step(1/30,fakeSensor,junction)
			local heading=car.vehicle.root.CFrame.LookVector
			maxHeadingChange=math.max(maxHeadingChange,math.acos(math.clamp(previous:Dot(heading),-1,1))); previous=heading
		end
		check(car.vehicle.root.Position.X>20 and car.vehicle.root.Position.Z<0,"Curved route turns and advances")
		check(maxHeadingChange<0.1,"Corner heading remains continuous")
		car:Destroy(junction)
		-- Mandatory gate stops movement even between sensing updates.
		local turn=turnData.edges[1]; turn.intersection="junction"
		turnNetwork=Network.Load(turnData)
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		prepared.model:PivotTo(fakeSensor:Ground(Vector3.zero,-Vector3.zAxis,prepared.bounds))
		car=Controller.new(11,prepared,turnNetwork,{"turn","exit"},Random.new(3))
		car.target=20; car:Step(1/30,fakeSensor,junction)
		check(car.distance==0 and car.speed==0,"Cannot enter junction without reservation")
		car:Sense(fakeSensor,junction,1); car:Step(1/30,fakeSensor,junction)
		check(car.distance>0 and car.reservations.junction~=nil,"Clear exit grants movement")
		car:Destroy(junction)
		check(next(junction.held)==nil,"Removed turning car releases zone")
		local real=Sensors.new({},{}); local scooter=Instance.new("Model"); scooter.Parent=folder
		local obstacle=Instance.new("Part"); obstacle.CanQuery=false; obstacle.Parent=scooter
		real.bodies={{model=scooter,frame=CFrame.new(50000,1000,50000),size=Vector3.new(2,3,4),velocity=Vector3.zero}}
		check(not real:Clear(nil,CFrame.new(50000,1000,50000),Config.Vehicle.Bounds),"Explicit query-disabled scooter detection")
		check(real:Clear(nil,CFrame.new(50020,1000,50000),Config.Vehicle.Bounds),"Scooter beside lane is clear")
		real.bodies[1].velocity=Vector3.new(20,0,0)
		check(not real:Clear(nil,CFrame.new(50020,1000,50000),Config.Vehicle.Bounds,1),"Crossing scooter predicted")
		local spawned=Spawner.Spawn(90,network,template,folder,fakeSensor,{}, {Vector3.new(300,0,0)},Random.new(1))
		check(spawned~=nil,"Valid distributed spawn")
		check(spawned.vehicle.root.CFrame.LookVector:Dot(-Vector3.zAxis)>0.99,"Spawn orientation follows directed lane")
		check(Spawner.Spawn(91,network,template,folder,fakeSensor,{spawned}, {Vector3.new(300,0,0)},Random.new(1))==nil,"Occupied spawn denied")
		spawned:Destroy(junction)
		check(real:Ground(Vector3.new(50000,1000,50000),-Vector3.zAxis,Config.Vehicle.Bounds)==nil,"Unsupported road fails ground checks")
		-- A moving leader and follower share the route without rear-end contact.
		local followerVehicle=Adapter.Prepare(template); followerVehicle.model.Parent=folder
		followerVehicle.model:PivotTo(fakeSensor:Ground(Vector3.zero,-Vector3.zAxis,followerVehicle.bounds))
		local leader=Instance.new("Part"); leader.Size=Config.Vehicle.Bounds; leader.Anchored=true
		leader.CFrame=CFrame.new(0,Config.Vehicle.Bounds.Y/2+Config.Vehicle.GroundClearance,-45); leader.Parent=folder
		local follower=Controller.new(20,followerVehicle,network,{"E0","E1","E2"},Random.new(4))
		local followingSensor: any={Ground=fakeSensor.Ground}
		function followingSensor:Clear(_model,frame,size,_prediction)
			return math.abs(frame.Position.Z-leader.Position.Z)>(size.Z+leader.Size.Z)/2,nil
		end
		function followingSensor:Sweep(model,_from,to,size) return self:Clear(model,to,size) end
		local minimumGap=math.huge
		for tick=1,300 do
			if tick>60 and tick<240 then leader.CFrame+=Vector3.new(0,0,-5/30) end
			follower:Sense(followingSensor,junction,tick/30); follower:Step(1/30,followingSensor,junction)
			minimumGap=math.min(minimumGap,follower.vehicle.root.Position.Z-leader.Position.Z)
		end
		check(minimumGap>=Config.Vehicle.Bounds.Z,"Moving following behavior keeps collision envelopes separate")
		follower:Destroy(junction); leader:Destroy()
		-- Several minutes and many laps must not exhaust the planning horizon.
		local loopData: Types.Data={version=1,approved=true,nodes={},edges={},spawns={"L1"},review={}}
		local positions={Vector3.zero,Vector3.new(40,0,-40),Vector3.new(80,0,0),Vector3.new(40,0,40)}
		local directions={-Vector3.zAxis,Vector3.xAxis,Vector3.zAxis,-Vector3.xAxis}
		for i=1,4 do
			local nextIndex=i%4+1
			table.insert(loopData.nodes,{id="L"..i,position=positions[i],direction=directions[i],road="loop",speed=32,lane="right",outgoing={"LE"..i}})
			table.insert(loopData.edges,{id="LE"..i,from="L"..i,to="L"..nextIndex,control1=positions[i]+directions[i]*22,
				control2=positions[nextIndex]-directions[nextIndex]*22,speed=32,lane="right",road="loop"})
		end
		local loopNetwork=Network.Load(loopData)
		prepared=Adapter.Prepare(template); prepared.model.Parent=folder
		prepared.model:PivotTo(fakeSensor:Ground(Vector3.zero,-Vector3.zAxis,prepared.bounds))
		car=Controller.new(30,prepared,loopNetwork,Network.Route(loopNetwork,"L1",Random.new(8)),Random.new(8))
		for tick=1,7200 do
			car:Sense(fakeSensor,junction,tick/30); car:Step(1/30,fakeSensor,junction)
			if tick%300==0 then task.wait() end
		end
		check(not car.remove and car.speed>0,"Connected loop keeps the same car driving for four simulated minutes")
		check(car.traveled>Config.MinSpawnRouteDistance*2,"Sustained lifetime includes travel, not just waiting")
		check(#car.route<=Config.MaxRouteHops*2+2,"Repeated route renewal keeps memory bounded")
		car:Destroy(junction)
		local shortData=table.clone(data); shortData.nodes=table.clone(data.nodes); shortData.edges=table.clone(data.edges)
		shortData.nodes[3]=table.clone(data.nodes[3]); shortData.nodes[3].outgoing={}
		shortData.nodes={shortData.nodes[1],shortData.nodes[2],shortData.nodes[3]}; shortData.edges={shortData.edges[1],shortData.edges[2]}
		check(Spawner.Spawn(92,Network.Load(shortData),template,folder,fakeSensor,{}, {Vector3.new(300,0,0)},Random.new(1))==nil,"Short dead-end trips are not spawned")
		local fleet: any={}; for i=1,Config.MaxVehicles do fleet[i]={} end
		check(Spawner.Spawn(99,network,template,folder,fakeSensor,fleet,{Vector3.zero},Random.new(1))==nil,"Shared active cap")
		check(Spawner.Spawn(99,network,template,folder,fakeSensor,{}, {},Random.new(1))==nil,"No players no fleet")
		check(Spawner.NearPlayers(Vector3.zero,{Vector3.new(20,0,0),Vector3.new(5,0,0)})==5,"Multiplayer nearest distance")
	end)
	folder:Destroy(); if not ok then error(err,2) end
	print(string.format("Traffic native suite passed: %d assertions",count))
	return count
end
return run(game.ServerScriptService.Traffic)
