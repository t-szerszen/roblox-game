--!strict
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local Pathfinding=game:GetService("PathfindingService")
local Config=require(script.Parent.PoliceConfig)
local Officer={};Officer.__index=Officer
type Joint={joint: Motor6D, base: CFrame, phase: number}
export type Controller=typeof(setmetatable({} :: {
 model: Model, root: BasePart, humanoid: Humanoid, car: Model,
 outside: boolean, door: Vector3?, goal: Vector3?, nextPath: number,
 waypoints: {PathWaypoint}, cursor: number, generation: number, busy: boolean,
 destroyed: boolean, path: Path?, pathConnection: RBXScriptConnection?,
 joints: {Joint}, collisions: {[BasePart]: boolean}, phase: number,
 exitStarted: number?, exitFrom: CFrame?, exitTo: CFrame?,
},Officer))
function Officer.CreateTemplate(): Model
 local description=Instance.new("HumanoidDescription")
 local navy=Color3.fromRGB(28,44,72)
 description.TorsoColor=navy;description.LeftArmColor=navy;description.RightArmColor=navy
 description.LeftLegColor=Color3.fromRGB(22,26,35);description.RightLegColor=description.LeftLegColor
 local ok,model=pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15) end)
 description:Destroy();assert(ok,model)
 local rig=model :: Model;rig.Name="PoliceOfficer"
 for _,v in rig:GetDescendants() do if v:IsA("LuaSourceContainer") then v:Destroy() end end
 rig.PrimaryPart=rig:FindFirstChild("HumanoidRootPart") :: BasePart
 assert(rig.PrimaryPart and rig:FindFirstChildOfClass("Humanoid"),"Invalid R15 officer")
 local human=rig:FindFirstChildOfClass("Humanoid") :: Humanoid
 local footBottom=math.huge
 for _,name in {"LeftFoot","RightFoot"} do
  local foot=rig:FindFirstChild(name) :: BasePart
  assert(foot,"R15 officer foot missing")
  footBottom=math.min(footBottom,foot.Position.Y-foot.Size.Y/2)
 end
 -- Generated default descriptions can have HipHeight=0 before character setup.
 human.HipHeight=math.max(0,rig.PrimaryPart.Position.Y-rig.PrimaryPart.Size.Y/2-footBottom)
 local torso=rig:FindFirstChild("UpperTorso") :: BasePart
 local badge=Instance.new("Part");badge.Name="PoliceBadge";badge.Size=Vector3.new(0.3,0.35,0.05)
 badge.Color=Color3.fromRGB(218,197,107);badge.Material=Enum.Material.Metal
 badge.CanCollide=false;badge.CanTouch=false;badge.CanQuery=false;badge.Massless=true
 badge.CFrame=torso.CFrame*CFrame.new(-0.35,0.25,-torso.Size.Z/2);badge.Parent=rig
 local weld=Instance.new("WeldConstraint");weld.Part0=torso;weld.Part1=badge;weld.Parent=badge
 return rig
end
function Officer.new(template: Model, car: Model): Controller
 local model=template:Clone();model.Name="PoliceOfficer";model:SetAttribute("PoliceOwned",true)
 local root=model.PrimaryPart :: BasePart
 local human=model:FindFirstChildOfClass("Humanoid") :: Humanoid
 human.WalkSpeed=Config.OfficerWalkSpeed;human.DisplayName="POLICJA"
 local joints: {Joint}={};local collisions: {[BasePart]: boolean}={}
 for _,v in model:GetDescendants() do
  if v:IsA("BasePart") then collisions[v]=v.CanCollide;v.CanCollide=false;v.CanTouch=false end
  if v:IsA("Motor6D") and (v.Name=="LeftHip" or v.Name=="RightHip" or v.Name=="LeftShoulder" or v.Name=="RightShoulder") then
   table.insert(joints,{joint=v,base=v.C0,phase=if string.find(v.Name,"Left",1,true) then 1 else -1})
  end
 end
 root.Anchored=true;model.Parent=car
 local self=setmetatable({model=model,root=root,humanoid=human,car=car,outside=false,door=nil,goal=nil,
  nextPath=0,waypoints={},cursor=1,generation=0,busy=false,destroyed=false,path=nil,pathConnection=nil,
  joints=joints,collisions=collisions,phase=0,exitStarted=nil,exitFrom=nil,exitTo=nil},Officer)
 self:Board()
 return self
end
function Officer.Board(self: Controller)
 if self.destroyed or not self.model.Parent or not self.root.Parent or not self.car.Parent then return end
 self.generation+=1;self.busy=false;self:ClearPath()
 self.exitStarted=nil;self.exitFrom=nil;self.exitTo=nil
 self.outside=false;self.goal=nil;self.root.Anchored=true
 for p in self.collisions do if p.Parent then p.CanCollide=false end end
 self.model.Parent=self.car
 local chassis=self.car.PrimaryPart :: BasePart
 local size=chassis.Size
 -- Derived from this car's envelope; the original Kia seat is below its chassis.
 self.model:PivotTo(chassis.CFrame*CFrame.new(-size.X*0.18,-size.Y*0.22,-size.Z*0.12))
end
function Officer.Exit(self: Controller, parent: Instance, now: number): boolean
 if self.destroyed or not self.model.Parent or not self.root.Parent or not self.car.Parent then return false end
 local chassis=self.car.PrimaryPart :: BasePart;local size=chassis.Size
 local cast=RaycastParams.new();cast.FilterType=Enum.RaycastFilterType.Exclude
 cast.FilterDescendantsInstances={self.car,self.model};cast.RespectCanCollide=true
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
 overlap.FilterDescendantsInstances={self.car,self.model};overlap.RespectCanCollide=true
 for _,side in {-1,1} do
  local point=chassis.CFrame:PointToWorldSpace(Vector3.new(side*(size.X/2+Config.OfficerExitPadding),0,-size.Z*0.12))
  local hit=Workspace:Raycast(point+Vector3.yAxis*size.Y,-Vector3.yAxis*(size.Y*2+5),cast)
  if not hit or hit.Normal.Y<0.7 then continue end
  local clearance=hit.Position+Vector3.yAxis*(Config.OfficerClearance.Y/2+0.1)
  if #Workspace:GetPartBoundsInBox(CFrame.new(clearance),Config.OfficerClearance,overlap)>0 then continue end
  -- The passage between the door and standing point must also be open.
  local door=chassis.CFrame:PointToWorldSpace(Vector3.new(side*(size.X/2+0.2),0,-size.Z*0.12))
  local passage=Workspace:Raycast(door,clearance-door,cast)
  if passage then continue end
  local from=self.model:GetPivot()
  self.model.Parent=parent
  local p=hit.Position+Vector3.yAxis*(self.humanoid.HipHeight+self.root.Size.Y/2)
  self.exitStarted=now;self.exitFrom=from;self.exitTo=CFrame.lookAt(p,p+chassis.CFrame.LookVector)
  self.outside=true;self.door=p;return true
 end
 return false
end
function Officer.ClearPath(self: Controller)
 if self.pathConnection then self.pathConnection:Disconnect();self.pathConnection=nil end
 if self.path then self.path:Destroy();self.path=nil end
 table.clear(self.waypoints)
end
function Officer.Navigate(self: Controller, goal: Vector3, now: number)
 if self.destroyed or not self.outside or self.exitStarted or self.humanoid.Health<=0 then return end
 if self.goal and (goal-self.goal).Magnitude>Config.OfficerWaypointTolerance*2 then
  self.generation+=1;self.busy=false;self:ClearPath();self.nextPath=0
 end
 self.goal=goal
 if not self.busy and now>=self.nextPath then
  self.nextPath=now+Config.OfficerRepathInterval;self.busy=true
  local generation=self.generation;local start=self.root.Position
  task.spawn(function()
   local path=Pathfinding:CreatePath({AgentRadius=1.5,AgentHeight=5,AgentCanJump=false,WaypointSpacing=3})
   local ok=pcall(function() path:ComputeAsync(start,goal) end)
   if self.destroyed or self.generation~=generation then path:Destroy();return end
   self.busy=false;self:ClearPath()
   if not ok or path.Status~=Enum.PathStatus.Success then path:Destroy();return end
   self.path=path;self.waypoints=path:GetWaypoints();self.cursor=2
   self.pathConnection=path.Blocked:Connect(function(index)
    if index>=self.cursor then self.nextPath=0;self:ClearPath();self.humanoid:MoveTo(self.root.Position) end
   end)
  end)
 end
 local waypoint=self.waypoints[self.cursor]
 local delta=if waypoint then self.root.Position-waypoint.Position else Vector3.zero
 if waypoint and Vector3.new(delta.X,0,delta.Z).Magnitude<Config.OfficerWaypointTolerance and math.abs(delta.Y)<Config.OfficerClearance.Y then
  self.cursor+=1;waypoint=self.waypoints[self.cursor]
 end
 if waypoint then self.humanoid:MoveTo(waypoint.Position) else self.humanoid:MoveTo(self.root.Position) end
end
function Officer.Animate(self: Controller, now: number, arresting: boolean)
 if self.exitStarted then
  local alpha=math.clamp((now-self.exitStarted)/Config.OfficerExitDuration,0,1)
  self.model:PivotTo((self.exitFrom :: CFrame):Lerp(self.exitTo :: CFrame,alpha))
  if alpha>=1 then
   self.exitStarted=nil;self.exitFrom=nil;self.exitTo=nil;self.root.Anchored=false
   for part,collision in self.collisions do if part.Parent then part.CanCollide=collision end end
   if self.root:CanSetNetworkOwnership() then self.root:SetNetworkOwner(nil) end
  end
 end
 -- C0 replicates from the server; this fallback needs no uploaded animation asset.
 local speed=self.root.AssemblyLinearVelocity.Magnitude
 for _,entry in self.joints do
  if not entry.joint.Parent then continue end
  local angle=if self.outside and speed>0.5 then math.sin(now*8)*0.4*entry.phase else 0
  if arresting and entry.joint.Name=="RightShoulder" then angle=-0.65 end
  entry.joint.C0=entry.base*CFrame.Angles(angle,0,0)
 end
end
function Officer.Destroy(self: Controller)
 if self.destroyed then return end
 self.destroyed=true;self.generation+=1;self:ClearPath();self.model:Destroy()
 table.clear(self.joints);table.clear(self.collisions)
end
return Officer
