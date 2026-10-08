--!strict
-- Production source is loaded unchanged; only vector arithmetic and random choices are doubles.
function vectorMethods:Lerp(other, alpha) return self+(other-self)*alpha end
local Config=loadModule("ServerScriptService/Traffic/TrafficConfiguration")
local Data=loadModule("ServerScriptService/Traffic/RoadNetworkData")
local Trajectory=loadModule("ServerScriptService/Traffic/Trajectory")
local Network=loadModule("ServerScriptService/Traffic/RoadNetwork")
local Intersections=loadModule("ServerScriptService/Traffic/IntersectionManager")
local random={NextInteger=function(_, low, _) return low end}
local network=Network.Load(Data)
check(Data.approved,"City-derived snapshot is enabled")
check(#Data.nodes>0 and #Data.edges>0 and #network.spawns>0,"Real snapshot contains traffic")
check(Config.MaxVehicles==10 and Config.TargetVehicles==6,"Requested initial shared budget")
check(Config.SpawnMaxDistance<Config.DespawnDistance,"Spawn/despawn hysteresis")
check(Config.SpawnMinDistance>Config.Vehicle.Bounds.Z*5,"No close materialization")
local excluded,turns=0,0
for _,edge in Data.edges do
	local path=network.paths[edge.id]
	check(path~=nil and network.nodes[edge.from]~=nil and network.nodes[edge.to]~=nil,"Valid edge reference")
	check(path.length>0 and #path.samples<=Config.MaxSamplesPerEdge+1,"Finite sampled path")
	check(path.samples[1].direction:Dot(network.nodes[edge.from].direction.Unit)>0.95,"Entry tangent matches lane")
	check(path.samples[#path.samples].direction:Dot(network.nodes[edge.to].direction.Unit)>0.95,"Exit tangent matches lane")
	local half=Trajectory.At(path,path.length/2)
	check(Trajectory.ValidVector(half.position) and Trajectory.Finite(half.curvature),"Finite curve interpolation")
	if edge.enabled==false then
		excluded+=1; check(not table.find(network.outgoing[edge.from],edge.id),"Unsafe edge excluded from route")
	elseif edge.intersection then turns+=1 end
end
check(excluded>0,"Actual blocked movements are explicitly excluded")
check(turns>0,"City snapshot includes turns and intersections")
for _,id in network.spawns do
	local route=Network.Route(network,id,random)
	check(#route>0 and #route<=Config.MaxRouteHops,"Every spawn has bounded connected route")
	local node=id
	for _,edgeId in route do
		local edge=network.paths[edgeId].edge
		check(edge.from==node and edge.enabled~=false,"Route follows enabled directed adjacency")
		node=edge.to
	end
end
check(#Network.Route(network,"missing",random)==0,"Missing node fails without loop")
local components=Network.Components(network)
local total=0;for _,component in components do total+=#component end
check(total==#Data.nodes,"Connectivity analysis visits each node once")
check(#components>1,"Actual disconnected roads are reported rather than bridged")
local bad=table.clone(Data);bad.nodes=table.clone(Data.nodes)
bad.nodes[1]=table.clone(Data.nodes[1]);bad.nodes[1].position=Vector.new(0/0,0,0)
check(not pcall(Network.Load,bad),"NaN position rejected")
bad=table.clone(Data);bad.edges=table.clone(Data.edges);bad.edges[1]=table.clone(Data.edges[1]);bad.edges[1].to="invalid"
check(not pcall(Network.Load,bad),"Invalid route reference rejected")
bad=table.clone(Data);bad.spawns={"invalid"}
check(not pcall(Network.Load,bad),"Invalid spawn rejected")
local longRoutes=0
for _,id in network.spawns do
	local distance=0
	for _,edgeId in Network.Route(network,id,random) do distance+=network.paths[edgeId].length end
	if distance>=Config.MinSpawnRouteDistance then longRoutes+=1 end
end
check(longRoutes>0,"City snapshot has spawn routes long enough for sustained trips")
local held=Intersections.new()
check(held:Request("junction",1,0,true),"Initial reservation granted")
for id=2,10 do check(not held:Request("junction",id,0,true),"Conflicting cars cannot enter") end
held:Release(1)
check(not held:Request("junction",3,1,true),"FIFO queue prevents starvation")
check(not held:Request("junction",2,1,false),"Exit clearance required")
check(held:Request("junction",2,1,true),"Queue resumes after clearance")
check(#held:Expired(Config.IntersectionWaitTimeout+2)==1,"Deadlock timeout identifies owner")
check(held.held.junction.owner==2,"Timeout never grants through live vehicle")
held:Progress(2)
check(#held:Expired(Config.IntersectionWaitTimeout+3)==0,"Moving reservation owner survives the old acquisition timeout")
check(#held:Expired(Config.IntersectionWaitTimeout*2+4)==1,"Stopped owner still has bounded timeout")
for id=2,10 do held:Release(id) end
check(next(held.held)==nil and next(held.queues)==nil,"All reservation state disposed")
near(Trajectory.Approach(0,32,5,1/30),5/30,"Acceleration integration")
near(Trajectory.Approach(32,0,12,0.5),26,"Comfortable braking")
near(Trajectory.SafeSpeed(8,8,12),0,"Following gap stop")
check(not Trajectory.Finite(math.huge),"Infinite input rejected")
print(string.format("PASS: %d traffic assertions; %d nodes, %d enabled edges, %d spawns, %d components",testCount,#Data.nodes,#Data.edges-excluded,#Data.spawns,#components))
