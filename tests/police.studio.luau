--!strict
-- Native Edit/Play fixtures: no authored map or active player is modified.
local root=Instance.new("Folder");root.Name="__PoliceValidationModules"
for _,name in {"Traffic","Police","Scooter","Combat","Gang"} do
 local source=game.ServerScriptService:FindFirstChild(name) :: Folder
 local clone=Instance.new("Folder");clone.Name=name;clone.Parent=root
 for _,module in source:GetChildren() do if module:IsA("ModuleScript") then module:Clone().Parent=clone end end
end
local fixtures=Instance.new("Folder");fixtures.Name="__PoliceValidationFixtures";fixtures.Parent=workspace
local count=0
local function check(value: boolean,message: string) assert(value,message);count+=1 end
local ok,result=pcall(function()
 local Adapter=require(root.Police.PoliceVehicleAdapter)
 local TrafficAdapter=require(root.Traffic.VehicleAdapter)
 local Controller=require(root.Traffic.VehicleController)
 local Network=require(root.Traffic.RoadNetwork)
 local Rules=require(root.Police.TrafficViolationDetector)
 local Arrest=require(root.Police.ArrestService)
 local Officers=require(root.Police.PoliceOfficerController)
 local Intersections=require(root.Traffic.IntersectionManager)
 local OfficerTemplate=Officers.CreateTemplate();OfficerTemplate.Parent=root
 check(OfficerTemplate.Humanoid.HipHeight>1,"R15 standing height derives from real feet")
 local sources=game.ServerStorage.PoliceVehicleModels
 for _,name in {"Kia","Fiat Ducato Policja"} do
  local source=sources:FindFirstChild(name) :: Model
  local originalPivot=source:GetPivot();local originalCount=#source:GetDescendants()
  local template=Adapter.Template(source,0.45);template.Parent=root
  local prepared=TrafficAdapter.Prepare(template);prepared.model.Parent=root
  check(source:GetPivot()==originalPivot and #source:GetDescendants()==originalCount,"Source vehicle preserved")
  check(prepared.root.Anchored and prepared.root.CanCollide,"Shared kinematic collision root")
  check(prepared.bounds.Z>prepared.bounds.X,"Forward envelope is longitudinal")
  check(template.PrimaryPart.FrontAxle.Position.Z<template.PrimaryPart.RearAxle.Position.Z,"Axle-derived front is -Z")
  for _,v in prepared.model:GetDescendants() do
   check(not v:IsA("LuaSourceContainer") and not v:IsA("Constraint"),"No chassis executable/actuator in vehicle clone")
   if v:IsA("Seat") then check(v.Disabled,"Police seats cannot capture players") end
  end
  local officer=Officers.new(OfficerTemplate,prepared.model)
  check(officer.humanoid.RigType==Enum.HumanoidRigType.R15,"Native R15 fallback")
  check(not officer.outside and officer.root.Anchored,"Officer is aboard during patrol")
  officer:Destroy();officer:Destroy();check(officer.destroyed,"Officer cleanup idempotent")
 end
 local origin=Vector3.new(10000,500,10000)
 local function part(name: string,size: Vector3,pos: Vector3,parent: Instance): Part
  local p=Instance.new("Part");p.Name=name;p.Size=size;p.Anchored=true;p.CanCollide=true;p.Position=pos;p.Parent=parent;return p
 end
 local character=Instance.new("Model");character.Name="TestSuspect";character.Parent=fixtures
 local target=part("HumanoidRootPart",Vector3.new(2,2,1),origin+Vector3.new(0,0,-30),character);character.PrimaryPart=target
 local vehicle=Instance.new("Model");vehicle.Name="TestCar";vehicle.Parent=fixtures
 local chassis=part("Chassis",Vector3.new(6,4,12),origin,vehicle);vehicle.PrimaryPart=chassis
 local frame=CFrame.new(origin)
 check(Rules.Visible(vehicle,frame,character,nil),"Clear forward visibility")
 target.Position=origin+Vector3.new(0,0,30);check(not Rules.Visible(vehicle,frame,character,nil),"Rear target outside FOV")
 target.Position=origin+Vector3.new(0,0,-250);check(not Rules.Visible(vehicle,frame,character,nil),"Target outside detection range")
 target.Position=origin+Vector3.new(0,0,-30)
 local wall=part("Occluder",Vector3.new(30,15,2),origin+Vector3.new(0,0,-15),fixtures)
 check(not Rules.Visible(vehicle,frame,character,nil),"Wall blocks both observation points")
 wall:Destroy();check(Rules.Visible(vehicle,frame,character,nil),"Visibility restored after removal")
 local ground=part("Ground",Vector3.new(100,1,100),origin-Vector3.yAxis*4,fixtures)
 local nativeOfficer=Officers.new(OfficerTemplate,vehicle)
 check(nativeOfficer:Exit(fixtures,0),"Exit selects supported, clear side of this vehicle")
 nativeOfficer:Animate(1,false)
 check(nativeOfficer.outside and not nativeOfficer.root.Anchored,"Exited officer is physical")
 check(nativeOfficer.model.Parent==fixtures,"Officer separated from vehicle movement")
 nativeOfficer:Board();check(not nativeOfficer.outside and nativeOfficer.model.Parent==vehicle,"Return restores aboard ownership")
 nativeOfficer:Destroy();ground:Destroy()
 local data={version=1,approved=true,nodes={},edges={},spawns={"N0"},review={}}
 for i=0,4 do
  table.insert(data.nodes,{id="N"..i,position=Vector3.new(0,0,-100*i),direction=-Vector3.zAxis,road="r",lane="r",speed=32,outgoing=if i<4 then {"E"..i} else {}})
  if i<4 then table.insert(data.edges,{id="E"..i,from="N"..i,to="N"..(i+1),control1=Vector3.new(0,0,-100*i-30),control2=Vector3.new(0,0,-100*i-70),road="r",lane="r",speed=32}) end
 end
 local network=Network.Load(data);local basic=TrafficAdapter.Placeholder();basic.Parent=root
 local prepared=TrafficAdapter.Prepare(basic);prepared.model.Parent=root
 local car=Controller.new(1,prepared,network,{"E0","E1","E2","E3"},Random.new(1),{maxSpeed=80,acceleration=18,braking=32,emergencyBraking=70,edgeSpeedMultiplier=3})
 local sensor: any={Ground=function(_,p,dir,size) return CFrame.lookAt(p+Vector3.yAxis*(size.Y/2+0.3),p+Vector3.yAxis*(size.Y/2+0.3)+dir) end,Clear=function() return true,nil end,Sweep=function() return true,nil end}
 prepared.model:PivotTo(sensor:Ground(Vector3.zero,-Vector3.zAxis,prepared.bounds));car.lastFrame=prepared.root.CFrame
 local junctions=Intersections.new()
 car:Sense(sensor,junctions,0);check(car.target>32,"Per-car pursuit tuning exceeds civilian cap")
 car.distance=20;local prior=prepared.root.CFrame;car:SetDestination(Vector3.new(0,0,-180))
 check(car.route[1]=="E0" and car.distance==20 and prepared.root.CFrame==prior,"Retarget preserves physical position and current edge")
 check(car.managed and car.destinationDistance~=nil,"Managed road destination installed")
 car:Patrol();check(not car.managed and car.destinationDistance==nil,"Return restores existing patrol routing")
 car.hold=true;car:Sense(sensor,junctions,0);check(car.target==0,"Commanded stop honored")
 for i=1,2000 do car:Step(1/30,sensor,junctions) end
 check(not car.remove and car.blockedTime==0,"Intentional intervention stop is not stuck recovery")
 car:Destroy(junctions)
 local broken=TrafficAdapter.Prepare(basic);broken.model.Parent=root
 local brokenCar=Controller.new(2,broken,network,{"E0"},Random.new(1))
 broken.root:Destroy();brokenCar:Sense(sensor,junctions,0)
 check(brokenCar.remove and brokenCar.exitReason=="RemovedRoot","Missing chassis retires controller safely")
 brokenCar:Destroy(junctions)
 -- Player double with real native characters and physics parts isolates authority
 -- and hold cleanup without altering the connected user's character.
 local human=Instance.new("Humanoid");human.Parent=character
 target.Anchored=false
 local fake: any={Parent=game.Players,Character=character,attrs={},CharacterRemoving=Instance.new("BindableEvent")}
 function fake:GetAttribute(name) return self.attrs[name] end
 function fake:SetAttribute(name,value) self.attrs[name]=value end
 local removing=fake.CharacterRemoving;fake.CharacterRemoving=removing.Event
 local officerModel=OfficerTemplate:Clone();officerModel.Parent=fixtures
 officerModel:PivotTo(CFrame.new(target.Position+Vector3.new(0,0,3)))
 local owner={};local arrests=Arrest.new(function(player,authority) return player==fake and authority==owner end)
 check(not arrests:Validate(fake,{},character,officerModel,vehicle),"Unowned arrest rejected")
 local walk=human.WalkSpeed
 check(arrests:Try(fake,owner,character,officerModel,vehicle,0),"Server authority accepts close stopped target")
 check(not arrests:Try(fake,owner,character,officerModel,vehicle,0),"Duplicate arrest rejected")
 arrests:Update(0.2);check(target.Anchored and human.WalkSpeed==0,"Arrest is applied after assembly separation")
 arrests:Update(11);check(not target.Anchored and human.WalkSpeed==walk and fake.attrs.PoliceState==nil,"Timed release restores controls")
 fake.attrs.PoliceReleaseUntil=nil
 check(arrests:Try(fake,owner,character,officerModel,vehicle,20),"Re-arrest fixture after grace")
 arrests:Update(20.2);vehicle:Destroy();task.wait()
 check(not target.Anchored and human.WalkSpeed==walk,"Vehicle removal immediately releases hold")
 arrests:Destroy();removing:Destroy()
 return count
end)
fixtures:Destroy();root:Destroy();assert(ok,result)
print("PASS: "..count.." native police assertions")
return count
