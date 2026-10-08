--!strict
local Config = require(script.Parent.TrafficConfiguration)
local Types = require(script.Parent.TrafficTypes)
local Trajectory = require(script.Parent.Trajectory)
local RoadNetwork = {}
function RoadNetwork.Load(data: Types.Data): Types.Network
	assert(data.version == 1, "Unsupported traffic schema")
	assert(#data.nodes <= Config.MaxNodes and #data.edges <= Config.MaxEdges, "Network exceeds budget")
	local network: Types.Network = {data=data,nodes={},paths={},spawns={},outgoing={}}
	for _,node in data.nodes do
		assert(type(node.id)=="string" and node.id~="" and not network.nodes[node.id], "Duplicate/invalid node")
		assert(Trajectory.ValidVector(node.position) and Trajectory.ValidVector(node.direction)
			and node.direction.Magnitude>0.9, "Invalid node vectors")
		assert(Trajectory.Finite(node.speed) and node.speed>0 and node.speed<=Config.MaxSpeed, "Invalid node speed")
		assert(type(node.road)=="string" and node.road~="" and type(node.lane)=="string" and node.lane~="","Invalid node road/lane")
		assert(node.intersection==nil or (type(node.intersection)=="string" and node.intersection~=""),"Invalid node intersection")
		assert(node.behavior==nil or node.behavior=="stop" or node.behavior=="yield", "Invalid right of way")
		network.nodes[node.id]=node
		network.outgoing[node.id]={}
	end
	for _,edge in data.edges do
		assert(type(edge.id)=="string" and edge.id~="" and not network.paths[edge.id], "Duplicate/invalid edge")
		assert(type(edge.road)=="string" and edge.road~="" and type(edge.lane)=="string" and edge.lane~="","Invalid edge road/lane")
		assert(edge.intersection==nil or (type(edge.intersection)=="string" and edge.intersection~=""),"Invalid edge intersection")
		assert(edge.enabled==nil or type(edge.enabled)=="boolean","Invalid edge availability")
		local a,b = network.nodes[edge.from],network.nodes[edge.to]
		assert(a and b and a~=b, "Invalid edge endpoints: "..edge.id)
		assert(Trajectory.ValidVector(edge.control1) and Trajectory.ValidVector(edge.control2), "Invalid curve")
		assert(Trajectory.Finite(edge.speed) and edge.speed>0 and edge.speed<=Config.MaxSpeed, "Invalid edge speed")
		local samples,length,curvature = Trajectory.Sample(a.position,edge.control1,edge.control2,b.position,
			Config.SampleSpacing,Config.MaxSamplesPerEdge)
		assert(length>0.05, "Degenerate edge")
		assert(samples[1].direction:Dot(a.direction.Unit)>0.95 and samples[#samples].direction:Dot(b.direction.Unit)>0.95,
			"Curve orientation does not match nodes: "..edge.id)
		network.paths[edge.id]={edge=edge,samples=samples,length=length,maxCurvature=curvature}
		if edge.enabled~=false then table.insert(network.outgoing[edge.from],edge.id) end
	end
	for _,node in data.nodes do
		local declared: {[string]: boolean} = {}
		for _,id in node.outgoing do
			assert(not declared[id] and network.paths[id] and network.paths[id].edge.from==node.id,
				"Invalid outgoing reference: "..node.id)
			declared[id]=true
		end
		for _,id in network.outgoing[node.id] do assert(declared[id],"Missing outgoing declaration") end
	end
	local seen: {[string]: boolean} = {}
	for _,id in data.spawns do
		assert(not seen[id] and network.nodes[id] and #network.outgoing[id]>0, "Invalid spawn: "..id)
		seen[id]=true; table.insert(network.spawns,id)
	end
	return network
end
function RoadNetwork.Route(network: Types.Network, start: string, random: Random, avoid: string?): {string}
	local route: {string} = {}
	local current = start
	for _=1,Config.MaxRouteHops do
		local candidates: {string} = {}
		local outgoing: {string}=network.outgoing[current] or {}
		for _,id in outgoing do
			if id~=avoid and network.paths[id].edge.enabled~=false then table.insert(candidates,id) end
		end
		if #candidates==0 then break end
		local id=candidates[random:NextInteger(1,#candidates)]
		table.insert(route,id); current=network.paths[id].edge.to
	end
	return route
end
function RoadNetwork.Components(network: Types.Network): { {string} }
	local adjacency: {[string]: {string}} = {}
	for id in network.nodes do adjacency[id]={} end
	for _,path in network.paths do
		if path.edge.enabled~=false then
			table.insert(adjacency[path.edge.from],path.edge.to)
			table.insert(adjacency[path.edge.to],path.edge.from)
		end
	end
	local visited: {[string]: boolean} = {}; local components: {{string}} = {}
	for id in network.nodes do
		if visited[id] then continue end
		local queue={id}; visited[id]=true; local cursor=1
		while cursor<=#queue do
			for _,nextId in adjacency[queue[cursor]] do
				if not visited[nextId] then visited[nextId]=true; table.insert(queue,nextId) end
			end
			cursor+=1
		end
		table.insert(components,queue)
	end
	return components
end
return RoadNetwork
