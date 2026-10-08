--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local Config=require(script.Parent.TrafficConfiguration)
local Data=require(script.Parent.RoadNetworkData)
local Network=require(script.Parent.RoadNetwork)
local Adapter=require(script.Parent.VehicleAdapter)
local Sensors=require(script.Parent.TrafficSensors)
local Controller=require(script.Parent.VehicleController)
local Spawner=require(script.Parent.TrafficSpawner)
local Intersections=require(script.Parent.IntersectionManager)
local Debug=require(script.Parent.TrafficDebug)
local Tool=require(script.Parent.DevTrafficTool)
local Manager={}
local heartbeat: RBXScriptConnection?=nil
local cleanup: (() -> ())?=nil
local infrastructureConnections: {RBXScriptConnection}={}
local epoch=0
function Manager.Stop()
	epoch+=1
	for _,connection in infrastructureConnections do connection:Disconnect() end
	table.clear(infrastructureConnections)
	if heartbeat then heartbeat:Disconnect(); heartbeat=nil end
	if cleanup then cleanup(); cleanup=nil end
end
function Manager.Start(): boolean
	assert(RunService:IsServer(),"Traffic is server authoritative")
	Manager.Stop()
	local startEpoch=epoch
	if not Config.Enabled then return false end
	local root=Tool.Root()
	local authored=root:FindFirstChild("Network")
	local data=if authored and authored:GetAttribute("Approved")==true then Tool.Read(authored) else Data
	if not data.approved then warn("[Traffic] No approved network. Use TrafficWorkflow in Edit mode; map generation is never automatic."); return false end
	for _,name in {"Network","CandidateNetwork"} do
		local authoring=root:FindFirstChild(name)
		local nodes=if authoring then authoring:FindFirstChild("RoadNodes") else nil
		if nodes then for _,part in nodes:GetChildren() do if part:IsA("BasePart") then part.Transparency=1 end end end
	end
	local network=Network.Load(data)
	assert(#network.spawns>0,"Approved traffic network has no spawn points")
	local _,_,roads=Tool.Inspect()
	if epoch~=startEpoch then return false end
	assert(#roads>0,"Traffic requires road support in Workspace.Map")
	local active=root:FindFirstChild("ActiveVehicles")
	assert(not active or active:IsA("Folder"),"ActiveVehicles must be Folder")
	local activeFolder=(active or Instance.new("Folder")) :: Folder; activeFolder.Name="ActiveVehicles"; activeFolder.Parent=root
	-- Only dispose owned runtime cars left by a previous manager, preserving authoring content.
	for _,v in activeFolder:GetChildren() do if v:GetAttribute("NPCVehicle")==true then v:Destroy() end end
	local assets=ReplicatedStorage:FindFirstChild("TrafficAssets")
	if not assets then assets=Instance.new("Folder"); assets.Name="TrafficAssets"; assets.Parent=ReplicatedStorage end
	local template=assets:FindFirstChild(Config.Vehicle.TemplateName)
	if not template then template=Adapter.Placeholder(); template.Parent=assets end
	assert(template:IsA("Model"),"Traffic car template must be Model")
	local prepared=Adapter.Prepare(template); prepared.model:Destroy()
	local intersections=Intersections.new(); local debug=Debug.new(root)
	local sensor=Sensors.new(roads,{debug.folder})
	local cars: {Controller.Vehicle}={}; local nextId=0; local random=Random.new()
	local moveClock,senseClock,spawnClock,debugClock=0,0,0,0
	local debugEnabled=false; local now=0
	local players: {Vector3}={}
	local function refreshBodies()
		local bodies: {Sensors.Body}={}
		for _,car in cars do table.insert(bodies,{model=car.vehicle.model,frame=car.vehicle.root.CFrame,
			size=car.vehicle.bounds,velocity=car.vehicle.root.CFrame.LookVector*car.speed}) end
		sensor:RefreshBodies(bodies)
	end
	local function remove(index: number)
		local car=table.remove(cars,index); assert(car)
		if car.exitReason and car.exitReason~="RemovedModel" and car.exitReason~="Irrelevant" and car.exitReason~="DeadEnd" then
			warn(string.format("[Traffic] car %d removed: %s",car.id,car.exitReason))
		end
		debug:Remove(car.id); car:Destroy(intersections)
	end
	cleanup=function()
		for i=#cars,1,-1 do remove(i) end
		debug:Destroy(); table.clear(sensor.bodies); table.clear(players)
		root:SetAttribute("ActiveVehicleCount",0)
	end
	table.insert(infrastructureConnections,root.Destroying:Connect(Manager.Stop))
	table.insert(infrastructureConnections,activeFolder.Destroying:Connect(Manager.Stop))
	heartbeat=RunService.Heartbeat:Connect(function(elapsed: number)
		now+=elapsed; moveClock+=elapsed; senseClock+=elapsed; spawnClock+=elapsed; debugClock+=elapsed
		if senseClock>=1/Config.SenseRate then
			senseClock=0; table.clear(players)
			for _,player in Players:GetPlayers() do
				local character=player.Character; local part=if character then character.PrimaryPart else nil
				if part then table.insert(players,part.Position) end
			end
			refreshBodies()
			for _,car in cars do
				if not car.vehicle.model.Parent then car:Fail("RemovedModel"); continue end
				local ok,err=pcall(function() car:Sense(sensor,intersections,now) end)
				if not ok then warn("[Traffic] sensing: "..tostring(err)); car:Fail("ControllerError") end
				if Spawner.NearPlayers(car.vehicle.root.Position,players)>Config.DespawnDistance then
					if not car.irrelevantSince then car.irrelevantSince=now end
					if now-(car.irrelevantSince :: number)>Config.DespawnGrace then car:Fail("Irrelevant") end
				else car.irrelevantSince=nil end
			end
			-- Remove a jammed owner before releasing its reservation; never grant through a live blocker.
			for _,id in intersections:Expired(now) do for _,car in cars do if car.id==id then car:Fail("IntersectionTimeout") end end end
		end
		if moveClock>=1/Config.UpdateRate then
			-- Bound the step after a server stall; skip elapsed simulation rather than jump through obstacles.
			local dt=math.min(moveClock,2/Config.UpdateRate); moveClock=0
			for i=#cars,1,-1 do
				local car=cars[i]
				local ok,err=pcall(function() car:Step(dt,sensor,intersections) end)
				if not ok then warn("[Traffic] movement: "..tostring(err)); car:Fail("ControllerError") end
				if car.remove then remove(i) end
			end
		end
		if spawnClock>=Config.SpawnInterval then
			spawnClock=0; refreshBodies(); nextId+=1
			local ok,car=pcall(Spawner.Spawn,nextId,network,template :: Model,activeFolder,sensor,cars,players,random)
			if ok and car then table.insert(cars,car) elseif not ok then warn("[Traffic] spawn rejected: "..tostring(car)) end
		end
		if debugClock>=1/Config.DebugRate then
			debugClock=0
			local enabled=Config.Debug or root:GetAttribute("Debug")==true
			if enabled and not debugEnabled then debug:Network(network) elseif not enabled and debugEnabled then debug:Clear() end
			debugEnabled=enabled
			for _,car in cars do debug:Vehicle(car,enabled) end
			root:SetAttribute("ActiveVehicleCount",#cars)
		end
	end)
	return true
end
return Manager
