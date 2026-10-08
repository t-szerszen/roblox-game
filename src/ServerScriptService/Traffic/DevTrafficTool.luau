--!strict
local Workspace=game:GetService("Workspace")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local CollectionService=game:GetService("CollectionService")
local Config=require(script.Parent.TrafficConfiguration)
local Types=require(script.Parent.TrafficTypes)
local Network=require(script.Parent.RoadNetwork)
local Sensors=require(script.Parent.TrafficSensors)
local Tool={}
export type Region = {part: BasePart, id: string, center: Vector3, size: Vector3, cf: CFrame, neighbors: {number}}
local function folder(parent: Instance, name: string): Folder
	local existing=parent:FindFirstChild(name)
	assert(not existing or existing:IsA("Folder"),name.." must be Folder")
	local f=(existing or Instance.new("Folder")) :: Folder; f.Name=name; f.Parent=parent; return f
end
function Tool.Root(): Folder
	return folder(Workspace,"TrafficSystem")
end
function Tool.Inspect(): ({Region},{string},{Instance})
	local map=Workspace:FindFirstChild("Map"); assert(map,"Workspace.Map is missing")
	local candidates: {BasePart} = {}; local seen: {[Instance]: boolean} = {}; local review: {string} = {}
	local function collect(v: Instance)
		if not v:IsA("BasePart") or seen[v] or v:GetAttribute("TrafficIgnore")==true then return end
		seen[v]=true
		local marked=v:GetAttribute("TrafficRoad")==true or CollectionService:HasTag(v,"TrafficRoad")
		local named=string.lower(v.Name)=="road" or string.lower(v.Name)=="asphalt"
		if not marked and not named then return end
		if v.Size.Y>Config.Generation.MaxThickness or v.Size.X<Config.Generation.MinWidth
			or v.Size.Z<Config.Generation.MinWidth or v.CFrame.UpVector.Y<math.cos(Config.MaxSlope) then
			table.insert(review,"Rejected dimensions/slope: "..v:GetFullName()); return
		end
		if not v:IsA("Part") or v.Shape~=Enum.PartType.Block then
			if not marked then table.insert(review,"Mesh/union requires explicit TrafficRoad region: "..v:GetFullName()); return end
		end
		if math.min(v.Size.X,v.Size.Z)<Config.Generation.MinTileSize or math.max(v.Size.X,v.Size.Z)>Config.Generation.MaxTileSize then
			table.insert(review,"Non-tile road: overlay 40–100 stud TrafficRoad block regions: "..v:GetFullName()); return
		end
		table.insert(candidates,v)
	end
	for i,v in map:GetDescendants() do collect(v); if i%1000==0 then task.wait() end end
	for _,v in CollectionService:GetTagged("TrafficRoad") do collect(v) end
	local authoring=Workspace:FindFirstChild("TrafficSystem")
	local markedRegions=if authoring then authoring:FindFirstChild("RoadRegions") else nil
	if markedRegions then for _,v in markedRegions:GetDescendants() do collect(v) end end
	assert(#candidates<=Config.Generation.MaxRoadParts,"Road region budget exceeded")
	table.sort(candidates,function(a,b)
		if a.Position.X~=b.Position.X then return a.Position.X<b.Position.X end
		if a.Position.Z~=b.Position.Z then return a.Position.Z<b.Position.Z end
		return a.Position.Y>b.Position.Y
	end)
	local regions: {Region} = {}; local roads: {Instance} = {}
	-- Regions are evidence of navigable space, not replacement collision surfaces.
	if markedRegions then table.insert(roads,map); table.insert(roads,Workspace.Terrain) end
	for _,p in candidates do
		table.insert(roads,p)
		local duplicate=false
		for _,region in regions do
			if (p.Position-region.part.Position).Magnitude<Config.Generation.DuplicateDistance then duplicate=true; break end
		end
		if duplicate then continue end
		local center=p.CFrame:PointToWorldSpace(Vector3.new(0,p.Size.Y/2,0))
		local id=string.format("R_%.1f_%.1f_%.1f",center.X,center.Y,center.Z)
		table.insert(regions,{part=p,id=id,center=center,size=p.Size,cf=p.CFrame,neighbors={}})
	end
	-- Collision sanitizer proxies are used by ground queries during Play.
	for _,v in map:GetDescendants() do
		if v:IsA("BasePart") and v:GetAttribute("RoadCollisionProxy")==true then table.insert(roads,v) end
	end
	for i,a in regions do
		local slots: {[string]: {index: number, distance: number}} = {}
		for j,b in regions do
			if i==j or math.abs(a.center.Y-b.center.Y)>Config.MaxGroundChange then continue end
			local delta=a.cf:VectorToObjectSpace(b.center-a.center)
			local axis=if math.abs(delta.X)>math.abs(delta.Z) then "X" else "Z"
			local along=if axis=="X" then delta.X else delta.Z
			local lateral=if axis=="X" then math.abs(delta.Z) else math.abs(delta.X)
			local aLength=if axis=="X" then a.size.X else a.size.Z
			local bLocal=a.cf:VectorToObjectSpace(b.cf.RightVector)
			local bLength=if math.abs(bLocal.X)>0.98 then (if axis=="X" then b.size.X else b.size.Z)
				elseif math.abs(bLocal.Z)>0.98 then (if axis=="X" then b.size.Z else b.size.X) else 0
			if bLength==0 or lateral>Config.Generation.LateralTolerance or math.abs(along)<20
				or math.abs(along)>(aLength+bLength)/2+Config.Generation.JoinGap then continue end
			local slot=axis..(if along>0 then "+" else "-")
			if not slots[slot] or math.abs(along)<slots[slot].distance then slots[slot]={index=j,distance=math.abs(along)} end
		end
		for _,slot in slots do table.insert(a.neighbors,slot.index) end
		table.sort(a.neighbors)
		if #a.neighbors==0 then table.insert(review,"Isolated road region: "..a.id) end
	end
	-- Only reciprocal, unambiguous joins survive.
	for i,a in regions do
		for n=#a.neighbors,1,-1 do
			if not table.find(regions[a.neighbors[n]].neighbors,i) then table.remove(a.neighbors,n) end
		end
	end
	return regions,review,roads
end
function Tool.BuildData(): Types.Data
	assert(not RunService:IsRunning(),"Analyze in Edit mode")
	local regions,review,roads=Tool.Inspect()
	local data: Types.Data={version=1,approved=false,nodes={},edges={},spawns={},review=review}
	local nodes: {[string]: Types.Node} = {}
	local function portal(i: number,j: number): Types.Node
		local a,b=regions[i],regions[j]; local id=a.id..">"..b.id
		if nodes[id] then return nodes[id] end
		local direction=(b.center-a.center).Unit
		local right=direction:Cross(Vector3.yAxis).Unit
		local p=(a.center+b.center)/2+right*Config.Generation.LaneOffset
		local node: Types.Node={id=id,position=p,direction=direction,road=b.id,speed=Config.MaxSpeed,
			lane="right",outgoing={},behavior=nil,intersection=nil}
		nodes[id]=node; table.insert(data.nodes,node); return node
	end
	for i,a in regions do for _,j in a.neighbors do portal(i,j) end end
	for i,a in regions do
		for _,incoming in a.neighbors do for _,outgoing in a.neighbors do
			if incoming==outgoing then continue end -- No inferred U-turn through an unknown dead end.
			local from,to=portal(incoming,i),portal(i,outgoing)
			local turn=from.direction:Dot(to.direction)<0.9
			local handle=math.min(Config.Generation.CurveHandle,(to.position-from.position).Magnitude*0.45)
			local edge: Types.Edge={id=from.id.."/"..to.id,from=from.id,to=to.id,
				control1=from.position+from.direction*handle,control2=to.position-to.direction*handle,
				speed=Config.MaxSpeed,lane="right",road=a.id,intersection=if turn or #a.neighbors>2 then a.id else nil}
			if edge.intersection then from.intersection=edge.intersection; from.behavior="yield" end
			table.insert(data.edges,edge); table.insert(from.outgoing,edge.id)
		end end
	end
	local network=Network.Load(data)
	local sensor=Sensors.new(roads,{})
	-- Reject a movement unless its full footprint has road support and obstacle clearance.
	for i,path in network.paths do
		local valid=true
		for _,sample in path.samples do
			local frame=sensor:Ground(sample.position,sample.direction,Config.Vehicle.Bounds)
			if not frame or not sensor:Clear(nil,frame,Config.Vehicle.Bounds) then valid=false; break end
		end
		if not valid then
			path.edge.enabled=false
			table.insert(review,"Blocked/unsupported movement: "..i)
		end
		task.wait()
	end
	network=Network.Load(data)
	for _,node in data.nodes do
		if #network.outgoing[node.id]>0 then
			local path=network.paths[network.outgoing[node.id][1]]
			if not path.edge.intersection then table.insert(data.spawns,node.id) end
		end
	end
	table.insert(review,string.format("%d weak components; verify directed routes, dead ends and gaps",#Network.Components(network)))
	return data
end
function Tool.Generate(replaceDraft: boolean?): Types.Data
	assert(not RunService:IsRunning(),"Generate in Edit mode")
	local root=Tool.Root()
	assert(replaceDraft or not root:FindFirstChild("CandidateNetwork"),"Draft exists; correct it or explicitly Generate(true)")
	local data=Tool.BuildData()
	Tool.Write(data,"CandidateNetwork")
	return data
end
function Tool.Write(data: Types.Data, name: string): Folder
	local root=Tool.Root(); local staged=Instance.new("Folder"); staged.Name=name
	staged:SetAttribute("TrafficGenerated",true); staged:SetAttribute("Approved",data.approved)
	staged:SetAttribute("Review",HttpService:JSONEncode(data.review))
	local nodeFolder=folder(staged,"RoadNodes"); local edges=folder(staged,"Connections")
	for i,node in data.nodes do
		local p=Instance.new("Part"); p.Name=node.id; p.Size=Vector3.one; p.CFrame=CFrame.lookAt(node.position,node.position+node.direction)
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Transparency=0.4
		p:SetAttribute("Road",node.road); p:SetAttribute("Lane",node.lane); p:SetAttribute("Speed",node.speed)
		p:SetAttribute("Intersection",node.intersection); p:SetAttribute("Behavior",node.behavior)
		p:SetAttribute("Spawn",table.find(data.spawns,node.id)~=nil); p.Parent=nodeFolder
		if i%200==0 then task.wait() end
	end
	for i,edge in data.edges do
		local f=Instance.new("Folder"); f.Name=edge.id
		local attributes: {[string]: any} = {From=edge.from,To=edge.to,Control1=edge.control1,Control2=edge.control2,
			Speed=edge.speed,Lane=edge.lane,Road=edge.road,Enabled=edge.enabled~=false}
		for key,value in attributes do f:SetAttribute(key,value) end
		f:SetAttribute("Intersection",edge.intersection); f.Parent=edges
		if i%200==0 then task.wait() end
	end
	local previous=root:FindFirstChild(name)
	assert(not previous or previous:GetAttribute("TrafficGenerated")==true,"Refusing to replace unrelated instance")
	if previous then previous:Destroy() end
	staged.Parent=root; return staged
end
function Tool.Read(source: Instance): Types.Data
	local data: Types.Data={version=1,approved=source:GetAttribute("Approved")==true,nodes={},edges={},spawns={},review={}}
	local nodeFolder=source:FindFirstChild("RoadNodes"); local edges=source:FindFirstChild("Connections")
	assert(nodeFolder and edges,"Missing network folders")
	local byId: {[string]: Types.Node}={}
	for _,p in nodeFolder:GetChildren() do
		assert(p:IsA("BasePart"),"RoadNodes must contain parts")
		local node: Types.Node={id=p.Name,position=p.Position,direction=p.CFrame.LookVector,
			road=p:GetAttribute("Road") :: string,lane=p:GetAttribute("Lane") :: string,
			speed=p:GetAttribute("Speed") :: number,intersection=p:GetAttribute("Intersection") :: string?,
			behavior=p:GetAttribute("Behavior") :: string?,outgoing={}}
		assert(not byId[node.id],"Duplicate node"); byId[node.id]=node; table.insert(data.nodes,node)
		if p:GetAttribute("Spawn")==true then table.insert(data.spawns,node.id) end
	end
	for _,f in edges:GetChildren() do
		local edge: Types.Edge={id=f.Name,from=f:GetAttribute("From") :: string,to=f:GetAttribute("To") :: string,
			control1=f:GetAttribute("Control1") :: Vector3,control2=f:GetAttribute("Control2") :: Vector3,
			speed=f:GetAttribute("Speed") :: number,lane=f:GetAttribute("Lane") :: string,road=f:GetAttribute("Road") :: string,
			intersection=f:GetAttribute("Intersection") :: string?,enabled=f:GetAttribute("Enabled")~=false}
		assert(byId[edge.from],"Missing From node"); table.insert(byId[edge.from].outgoing,edge.id); table.insert(data.edges,edge)
	end
	local review=source:GetAttribute("Review")
	if type(review)=="string" then data.review=HttpService:JSONDecode(review) end
	Network.Load(data)
	return data
end
function Tool.Approve(): Types.Data
	assert(not RunService:IsRunning(),"Approve in Edit mode")
	local candidate=Tool.Root():FindFirstChild("CandidateNetwork"); assert(candidate,"Generate a draft first")
	local data=Tool.Read(candidate)
	assert(#data.edges>0 and #data.spawns>0,"No usable traffic routes/spawns")
	local _,_,roads=Tool.Inspect()
	local sensor=Sensors.new(roads,{})
	local network=Network.Load(data)
	for _,path in network.paths do
		if path.edge.enabled==false then continue end
		for _,sample in path.samples do
			local frame=sensor:Ground(sample.position,sample.direction,Config.Vehicle.Bounds)
			assert(frame and sensor:Clear(nil,frame,Config.Vehicle.Bounds),"Corrected movement blocked/unsupported: "..path.edge.id)
		end
		task.wait()
	end
	data.approved=true; Tool.Write(data,"Network"); return data
end
function Tool.Connect(fromId: string, toId: string, intersection: string?, handle: number?)
	assert(not RunService:IsRunning(),"Connect in Edit mode")
	local candidate=Tool.Root():FindFirstChild("CandidateNetwork"); assert(candidate,"Generate first")
	local data=Tool.Read(candidate)
	local byId: {[string]: Types.Node}={}; for _,n in data.nodes do byId[n.id]=n end
	local a,b=byId[fromId],byId[toId]; assert(a and b and a~=b,"Invalid nodes")
	local distance=(b.position-a.position).Magnitude
	local h=handle or math.min(Config.Generation.CurveHandle,distance*0.45)
	assert(h>0 and h<=distance,"Invalid control handle")
	local id=fromId.."/"..toId
	local connections=candidate:FindFirstChild("Connections"); assert(connections)
	assert(not connections:FindFirstChild(id),"Connection already exists; edit its attributes")
	local edge: Types.Edge={id=id,from=fromId,to=toId,control1=a.position+a.direction*h,
		control2=b.position-b.direction*h,speed=math.min(a.speed,b.speed),lane=a.lane,road=a.road,intersection=intersection}
	table.insert(data.edges,edge); table.insert(a.outgoing,id)
	Network.Load(data); Tool.Write(data,"CandidateNetwork")
end
local function vec(v: Vector3): string return string.format("Vector3.new(%.6f,%.6f,%.6f)",v.X,v.Y,v.Z) end
local function quote(s: string?): string return if s then string.format("%q",s) else "nil" end
function Tool.SerializeData(data: Types.Data): string
	Network.Load(data)
	assert(data.approved,"Export requires reviewed network")
	table.sort(data.review)
	table.sort(data.nodes,function(a,b) return a.id<b.id end); table.sort(data.edges,function(a,b) return a.id<b.id end)
	table.sort(data.spawns)
	local lines={"--!strict","local Types=require(script.Parent.TrafficTypes)","return {version=1,approved=true,nodes={"}
	for _,n in data.nodes do
		local outgoing={}; for _,id in n.outgoing do table.insert(outgoing,quote(id)) end
		table.insert(lines,string.format("{id=%s,position=%s,direction=%s,road=%s,lane=%s,speed=%.6f,intersection=%s,behavior=%s,outgoing={%s}},",
			quote(n.id),vec(n.position),vec(n.direction),quote(n.road),quote(n.lane),n.speed,quote(n.intersection),quote(n.behavior),table.concat(outgoing,",")))
	end
	table.insert(lines,"},edges={")
	for _,e in data.edges do
		local line=string.format("{id=%s,from=%s,to=%s,control1=%s,control2=%s,speed=%.6f,lane=%s,road=%s,intersection=%s,enabled=%s},",
			quote(e.id),quote(e.from),quote(e.to),vec(e.control1),vec(e.control2),e.speed,quote(e.lane),quote(e.road),quote(e.intersection),tostring(e.enabled~=false))
		table.insert(lines,line)
	end
	table.insert(lines,"},spawns={")
	for _,id in data.spawns do table.insert(lines,quote(id)..",") end
	table.insert(lines,"},review={")
	for _,message in data.review do table.insert(lines,quote(message)..",") end
	table.insert(lines,"}} :: Types.Data")
	return table.concat(lines,"\n")
end
function Tool.Serialize(): string
	local source=Tool.Root():FindFirstChild("Network"); assert(source,"Approve a corrected network first")
	return Tool.SerializeData(Tool.Read(source))
end
return Tool
