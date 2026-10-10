--!strict
function vectorMethods:Lerp(other,alpha) return self+(other-self)*alpha end
local Config=loadModule("ServerScriptService/Police/PoliceConfig")
local Machine=loadModule("ServerScriptService/Police/PoliceStateMachine")
local Registry=loadModule("ServerScriptService/Police/PolicePursuitController")
local Rules=loadModule("ServerScriptService/Police/TrafficViolationDetector")
local Network=loadModule("ServerScriptService/Traffic/RoadNetwork")
local Data=loadModule("ServerScriptService/Traffic/RoadNetworkData")
local machine=Machine.new(0)
check(machine.state=="PATROL","Starts in patrol")
check(not pcall(function() machine:Transition("ARRESTING",1,"bad") end),"Illegal transition denied")
check(machine.state=="PATROL" and machine.generation==0,"Rejected transition has no effects")
for _,state in {"OBSERVING","PURSUIT","APPROACHING","STOPPING","OFFICER_EXITING","ARRESTING","RETURNING","PURSUIT","RECOVERING","RETURNING","PATROL"} do
 check(machine:Transition(state,1,state),"Legal transition "..state)
end
check(not machine:Transition("PATROL",2,"same"),"Same state does not reset timeout")
local p1,p2,p3={},{},{}
local a,b={},{},{}
local registry=Registry.new()
check(registry:Claim(p1,a,Vector.zero,0),"Claim target")
check(not registry:Claim(p1,b,Vector.zero,0),"Two units cannot pursue one target")
check(registry:Claim(p2,b,Vector.zero,0),"Second independent target")
check(not registry:Claim(p3,{},Vector.zero,0),"Global pursuit cap")
registry:Release(p1,b)
check(registry:Owns(p1,a),"Wrong owner cannot release target")
registry:Observe(p1,b,Vector.xAxis*100,2)
check(registry.memories[p1].position.Magnitude==0,"Wrong owner cannot supply a target location")
registry:Observe(p1,a,nil,3)
check(registry.memories[p1].lastSeen==0,"Hidden target does not refresh last sight")
registry:Observe(p1,a,Vector.zAxis*10,3)
check(registry.memories[p1].lastSeen==3,"Visible target updates memory")
local memory=registry.memories[p1]
check(Registry.Expired(memory,Vector.zero,4)==nil,"Short occlusion tolerated")
check(Registry.Expired(memory,Vector.xAxis*1000,6)=="Escaped","Escape uses remembered location")
check(Registry.Expired(memory,Vector.zero,3+Config.SearchTimeout)=="SearchTimeout","Search lifetime bounded")
check(Registry.Expired(memory,Vector.zero,Config.PursuitTimeout)=="PursuitTimeout","Total pursuit lifetime bounded")
registry:Release(p1,a)
check(registry.owners[p1]==nil and registry.memories[p1]==nil,"Claim and memory cleaned together")
check(registry:Claim(p3,a,Vector.zero,0),"Freed capacity reused")
local evidence=Rules.NewEvidence(0)
for i=1,15 do check(Rules.Accumulate(evidence,i*0.2,true,true,50,false)==nil,"At limit is legal") end
check(Rules.Accumulate(evidence,3.2,true,true,55,false)==nil,"Single fast sample insufficient")
check(Rules.Accumulate(evidence,3.4,true,true,40,false)==nil and evidence.speedTime==0,"Speed reduction resets evidence")
evidence=Rules.NewEvidence(0)
local reason
for i=1,8 do reason=Rules.Accumulate(evidence,i*0.2,true,true,55,false) end
check(reason=="Speeding","Sustained physical speed confirms")
evidence=Rules.NewEvidence(0)
for i=1,3 do Rules.Accumulate(evidence,i*0.2,true,true,55,false) end
local held=evidence.speedTime
check(Rules.Accumulate(evidence,0.8,false,true,90,true)==nil,"No confirmation while invisible")
check(evidence.speedTime==held,"Occlusion does not accumulate unseen time")
Rules.Accumulate(evidence,1.4,false,true,90,true)
check(evidence.speedTime==0 and evidence.wheelieTime==0,"Long occlusion discards stale evidence")
evidence=Rules.NewEvidence(0)
for i=1,7 do reason=Rules.Accumulate(evidence,i*0.2,true,true,20,true) end
check(reason=="Wheelie","Sustained authoritative wheelie confirms")
check(Rules.Accumulate(evidence,1.6,true,false,90,true)==nil and evidence.wheelieTime==0,"Dismount invalidates observation")
evidence=Rules.NewEvidence(0)
check(Rules.Accumulate(evidence,100,true,true,100,false)==nil,"Server stall cannot instantly confirm")
check(Rules.Accumulate(evidence,100.2,true,true,0/0,false)==nil and evidence.speedTime==0,"Nonfinite speed rejected")
local network=Network.Load(Data)
local examined=0
for _,edge in Data.edges do
 if edge.enabled==false or edge.intersection then continue end
 local current=network.paths[edge.id]
 local route,distance,gap=Network.Destination(network,edge.id,0,current.samples[#current.samples].position)
 check(route[1]==edge.id,"Destination retains current edge")
 local node=edge.from
 for _,id in route do
  local e=network.paths[id].edge
  check(e.from==node and e.enabled~=false,"Destination follows directed connections")
  node=e.to
 end
 check(distance>=0 and distance<=network.paths[route[#route]].length,"Destination distance bounded")
 check(gap<math.huge,"Reachable safe stopping projection")
 examined+=1
end
check(examined>100,"Routing checked on actual city graph")
local edge=network.paths[Data.edges[1].id]
local route,dist=Network.Destination(network,edge.edge.id,edge.length*0.8,edge.samples[1].position)
check(route[1]==edge.edge.id and (#route>1 or dist>=edge.length*0.8),"No reversal or teleport to a point behind the car")
check(not pcall(Network.Destination,network,edge.edge.id,0,Vector.new(0/0,0,0)),"Invalid goal rejected")
print(string.format("PASS: %d police evidence, ownership, transition and city routing assertions",testCount))
