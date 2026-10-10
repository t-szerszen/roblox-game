--!strict
local Players=game:GetService("Players")
local Config=require(script.Parent.TrafficConfiguration)
local Types=require(script.Parent.TrafficTypes)
local Network=require(script.Parent.RoadNetwork)
local Adapter=require(script.Parent.VehicleAdapter)
local Sensors=require(script.Parent.TrafficSensors)
local Controller=require(script.Parent.VehicleController)
local Spawner={}
function Spawner.NearPlayers(position: Vector3, players: {Vector3}): number
	local distance=math.huge
	for _,p in players do distance=math.min(distance,(position-p).Magnitude) end
	return distance
end
function Spawner.Spawn(id: number, network: Types.Network, template: Model, parent: Instance,
	sensor: Sensors.Sensor, cars: {Controller.Vehicle}, players: {Vector3}, random: Random): Controller.Vehicle?
	local target=math.min(Config.MaxVehicles,math.floor(Config.TargetVehicles*Config.DensityMultiplier))
	local civilianCount=0;for _,car in cars do if car.role~="Police" then civilianCount+=1 end end
	if civilianCount>=target or #players==0 or #network.spawns==0 then return nil end
	-- Shuffle a bounded subset; no separate fleet is created for each player.
	local pool=table.clone(network.spawns)
	for _=1,math.min(Config.MaxSpawnAttempts,#pool) do
		local pick=random:NextInteger(1,#pool); local spawnId=table.remove(pool,pick); assert(spawnId)
		local node=network.nodes[spawnId]
		if not node then continue end
		local distance=Spawner.NearPlayers(node.position,players)
		if distance<Config.SpawnMinDistance or distance>Config.SpawnMaxDistance then continue end
		local nearby,roadCount,occupied=0,0,false
		for _,car in cars do
			local gap=(car.vehicle.root.Position-node.position).Magnitude
			if gap<Config.SpawnSeparation then occupied=true end
			if gap<Config.AreaRadius then nearby+=1 end
			local path=car:Path(); if path and path.edge.road==node.road then roadCount+=1 end
		end
		if occupied or nearby>=Config.MaxVehiclesPerArea or roadCount>=Config.MaxVehiclesPerRoad then continue end
		local visible=false
		for _,player in Players:GetPlayers() do
			local character=player.Character; local root=if character then character.PrimaryPart else nil
			if root then
				local delta=node.position-root.Position
				if delta.Magnitude<Config.SpawnVisibilityDistance and delta.Magnitude>0
					and root.CFrame.LookVector:Dot(delta.Unit)>Config.SpawnForwardDot then visible=true; break end
			end
		end
		if visible then continue end
		local route=Network.Route(network,node.id,random)
		if #route<2 then continue end
		local routeDistance=0
		for _,edgeId in route do routeDistance+=network.paths[edgeId].length end
		if routeDistance<Config.MinSpawnRouteDistance then continue end
		local prepared=Adapter.Prepare(template)
		local frame=sensor:Ground(node.position,node.direction,prepared.bounds)
		if not frame or not sensor:Clear(nil,frame,prepared.bounds+Vector3.new(Config.SafeGap,0,Config.SafeGap)) then prepared.model:Destroy(); continue end
		prepared.model:PivotTo(frame); prepared.model.Name="TrafficCar_"..id
		prepared.model.Parent=parent
		return Controller.new(id,prepared,network,route,random)
	end
	return nil
end
return Spawner
