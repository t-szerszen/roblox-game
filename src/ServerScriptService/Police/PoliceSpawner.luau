--!strict
local Lighting=game:GetService("Lighting")
local Players=game:GetService("Players")
local Traffic=script.Parent.Parent.Traffic
local Config=require(script.Parent.PoliceConfig)
local Network=require(Traffic.RoadNetwork)
local Types=require(Traffic.TrafficTypes)
local Adapter=require(Traffic.VehicleAdapter)
local Controller=require(Traffic.VehicleController)
local Sensors=require(Traffic.TrafficSensors)
local Spawner={}
function Spawner.Target(): number
 local night=Lighting.ClockTime>=Config.NightStart or Lighting.ClockTime<Config.NightEnd
 return if night then math.max(0,math.floor(Config.VehicleCount*(1-Config.NightReduction))) else Config.VehicleCount
end
function Spawner.Spawn(id: number, template: Model, network: Types.Network, sensor: Sensors.Sensor,
 cars: {Controller.Vehicle}, parent: Instance, random: Random): Controller.Vehicle?
 local pool=table.clone(network.spawns)
 local positions: {Vector3}={}
 for _,player in Players:GetPlayers() do
  local root=player.Character and player.Character.PrimaryPart
  if root then table.insert(positions,root.Position) end
 end
 if #positions==0 then return nil end
 for _=1,math.min(#pool,Config.MaxSpawnAttempts) do
  local index=random:NextInteger(1,#pool);local node=network.nodes[table.remove(pool,index) :: string]
  if node.intersection or node.behavior then continue end
  local nearest=math.huge
  for _,position in positions do nearest=math.min(nearest,(node.position-position).Magnitude) end
  if nearest<Config.SpawnMinDistance or nearest>Config.SpawnMaxDistance then continue end
  local occupied=false
  for _,car in cars do if (car.vehicle.root.Position-node.position).Magnitude<Config.SpawnSeparation then occupied=true;break end end
  if occupied then continue end
  local route=Network.Route(network,node.id,random);local length=0
  for _,edge in route do length+=network.paths[edge].length end
  if #route<2 or length<Config.MinRouteDistance then continue end
  local vehicle=Adapter.Prepare(template)
  local frame=sensor:Ground(node.position,node.direction,vehicle.bounds)
  if not frame or not sensor:Clear(nil,frame,vehicle.bounds+Vector3.new(8,0,8)) then vehicle.model:Destroy();continue end
  vehicle.model:PivotTo(frame);vehicle.model.Name="PoliceCar_"..id
  vehicle.model:SetAttribute("PoliceVehicle",true);vehicle.model.Parent=parent
  local driving={maxSpeed=Config.PatrolSpeed,acceleration=Config.Acceleration,
   braking=Config.Braking,emergencyBraking=Config.EmergencyBraking,edgeSpeedMultiplier=1}
  local car=Controller.new(id,vehicle,network,route,random,driving);car.role="Police"
  return car
 end
 return nil
end
return Spawner
