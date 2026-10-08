--!strict
local Traffic=script.Parent.Parent.Traffic
local Adapter=require(Traffic.VehicleAdapter)
local Config=require(Traffic.TrafficConfiguration)
local PoliceVehicle={}
function PoliceVehicle.Template(source: Model, scale: number): Model
 assert(scale>0 and scale<=1, "Invalid police scale")
 local model=source:Clone()
 local ok,err=pcall(function()
  -- Sanitize only the clone. Authored vehicles and their playable chassis stay intact.
  for _,v in model:GetDescendants() do
   if v:IsA("LuaSourceContainer") or v:IsA("Constraint") or v:IsA("BodyMover")
    or v:IsA("RemoteEvent") or v:IsA("RemoteFunction") or v:IsA("LayerCollector") then v:Destroy()
   elseif v:IsA("BasePart") then
    v.Anchored=true; v.CanCollide=false; v.CanTouch=false; v.CanQuery=false
    if v:IsA("Seat") then v.Disabled=true end
   end
  end
  local wheels=assert(model:FindFirstChild("Wheels"),"Missing police wheels")
  local function wheel(name: string): BasePart
   local part=wheels:FindFirstChild(name)
   assert(part and part:IsA("BasePart"),"Missing police axle "..name)
   return part
  end
  local front=(wheel("FL").Position+wheel("FR").Position)/2
  local rear=(wheel("RL").Position+wheel("RR").Position)/2
  local delta=front-rear; local forward=Vector3.new(delta.X,0,delta.Z)
  assert(forward.Magnitude>1,"Degenerate police wheelbase")
  local frame=CFrame.lookAt((front+rear)/2,(front+rear)/2+forward)
  local minimum=Vector3.new(math.huge,math.huge,math.huge)
  local maximum=-minimum
  for _,p in model:GetDescendants() do
   if p:IsA("BasePart") then
    for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
     local point=frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(p.Size*Vector3.new(x,y,z)/2))
     minimum=Vector3.new(math.min(minimum.X,point.X),math.min(minimum.Y,point.Y),math.min(minimum.Z,point.Z))
     maximum=Vector3.new(math.max(maximum.X,point.X),math.max(maximum.Y,point.Y),math.max(maximum.Z,point.Z))
    end end end
   end
  end
  local root=Instance.new("Part"); root.Name=Config.Vehicle.RootName
  root.Size=maximum-minimum+Vector3.one*0.04
  assert(root.Size.Magnitude<100,"Invalid police envelope")
  root.CFrame=frame*CFrame.new((maximum+minimum)/2)
  root.Transparency=1; root.Anchored=true; root.CanCollide=false
  root.CanTouch=false; root.CanQuery=false; root.Parent=model; model.PrimaryPart=root
  local mounts: {[string]: Vector3}={FrontAxle=front,RearAxle=rear,DriverPosition=front-forward.Unit*2}
  for name,point in mounts do
   local a=Instance.new("Attachment"); a.Name=name
   a.Position=root.CFrame:PointToObjectSpace(point); a.Parent=root
  end
  model:ScaleTo(model:GetScale()*scale)
  model:SetAttribute("TrafficBounds",root.Size)
  model:SetAttribute("PoliceTemplate",true)
  local prepared=Adapter.Prepare(model); prepared.model:Destroy()
 end)
 if not ok then model:Destroy(); error(tostring(err)) end
 return model
end
function PoliceVehicle.Signals(model: Model, active: boolean, now: number)
 local flashing=active and math.floor(now*4)%2==0
 local changed=model:GetAttribute("PoliceSignalsActive")~=active
 if changed then model:SetAttribute("PoliceSignalsActive",active) end
 for _,v in model:GetDescendants() do
  if v:IsA("Light") then v.Enabled=flashing
  elseif v:IsA("Sound") and changed then
   if active and v.Name=="Wail" then
    v.Looped=true; if not v.IsPlaying then v:Play() end
   else v:Stop() end
  end
 end
end
return PoliceVehicle
