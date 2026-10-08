--!strict
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local Config=require(script.Parent.PoliceConfig)
local Scooter=require(script.Parent.Parent.Scooter.ScooterServer)
local Rules=require(script.Parent.TrafficViolationDetector)
local Arrest={};Arrest.__index=Arrest
type Hold={owner: {}, character: Model, humanoid: Humanoid, root: BasePart,
 expires: number, separatingUntil: number, scooterRoot: BasePart?,
 anchored: boolean, walkSpeed: number, jumpPower: number, jumpHeight: number, autoRotate: boolean,
 connections: {RBXScriptConnection}, applied: boolean}
export type Service=typeof(setmetatable({} :: {holds: {[Player]: Hold}, owns: (Player,{}) -> boolean},Arrest))
function Arrest.new(owns: (Player,{}) -> boolean): Service
 return setmetatable({holds={},owns=owns},Arrest)
end
function Arrest.Validate(self: Service, player: Player, owner: {}, character: Model,
 officer: Model, vehicle: Model): (boolean,string)
 if self.holds[player] or player:GetAttribute("PoliceState")=="ARRESTED" then return false,"AlreadyArrested" end
 if player.Parent~=Players or player.Character~=character or not self.owns(player,owner) then return false,"InvalidAuthority" end
 local human=character:FindFirstChildOfClass("Humanoid")
 local root=character:FindFirstChild("HumanoidRootPart")
 local officerHuman=officer:FindFirstChildOfClass("Humanoid")
 local officerRoot=officer.PrimaryPart
 if not vehicle.Parent or not officer.Parent or not officerHuman or officerHuman.Health<=0 or not officerRoot
  or not human or human.Health<=0 or not root or not root:IsA("BasePart") then return false,"InvalidCharacter" end
 local stun=player:GetAttribute("StunnedUntil")
 if not Rules.Eligible(player,root.Position) or (typeof(stun)=="number" and stun>Workspace:GetServerTimeNow())
  or human.PlatformStand or root.Anchored then return false,"IneligibleState" end
 if (officerRoot.Position-root.Position).Magnitude>Config.ArrestDistance then return false,"OutOfRange" end
 local riding=Scooter.GetRidingState(player)
 if human.SeatPart and not riding then return false,"UnsupportedSeat" end
 local velocity=if riding then riding.root.AssemblyLinearVelocity else root.AssemblyLinearVelocity
 if Vector3.new(velocity.X,0,velocity.Z).Magnitude>Config.MaxStoppedSpeed then return false,"TargetMoving" end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local ignored: {Instance}={officer,vehicle}
 if riding then table.insert(ignored,riding.model) end
 params.FilterDescendantsInstances=ignored
 local hit=Workspace:Raycast(officerRoot.Position,root.Position-officerRoot.Position,params)
 if hit and not hit.Instance:IsDescendantOf(character) then return false,"Obstructed" end
 return true,"Ready"
end
function Arrest.Try(self: Service, player: Player, owner: {}, character: Model,
 officer: Model, vehicle: Model, now: number): (boolean,string)
 local valid,reason=self:Validate(player,owner,character,officer,vehicle)
 if not valid then return false,reason end
 local human=character:FindFirstChildOfClass("Humanoid") :: Humanoid
 local root=character:FindFirstChild("HumanoidRootPart") :: BasePart
 local riding=Scooter.GetRidingState(player)
 if not Scooter.LockMount(player,owner) then return false,"MountLocked" end
 if riding and not Scooter.DismountForPlayer(player) then Scooter.ReleaseMount(player,owner);return false,"DismountFailed" end
 local hold: Hold={owner=owner,character=character,humanoid=human,root=root,expires=now+Config.ArrestDuration,
  separatingUntil=now+1,scooterRoot=if riding then riding.root else nil,anchored=root.Anchored,
  walkSpeed=human.WalkSpeed,jumpPower=human.JumpPower,jumpHeight=human.JumpHeight,
  autoRotate=human.AutoRotate,connections={},applied=false}
 self.holds[player]=hold
 player:SetAttribute("PoliceState","ARRESTED")
 player:SetAttribute("PoliceArrestUntil",Workspace:GetServerTimeNow()+Config.ArrestDuration)
 table.insert(hold.connections,human.Died:Connect(function() self:Release(player) end))
 table.insert(hold.connections,player.CharacterRemoving:Connect(function() self:Release(player) end))
 table.insert(hold.connections,officer.Destroying:Connect(function() self:Release(player) end))
 table.insert(hold.connections,vehicle.Destroying:Connect(function() self:Release(player) end))
 return true,"Arrested"
end
function Arrest.Release(self: Service, player: Player)
 local hold=self.holds[player];if not hold then return end
 self.holds[player]=nil
 for _,connection in hold.connections do connection:Disconnect() end
 Scooter.ReleaseMount(player,hold.owner)
 if hold.applied and hold.humanoid.Parent then
  local human=hold.humanoid
  if human.WalkSpeed==0 then human.WalkSpeed=hold.walkSpeed end
  if human.JumpPower==0 then human.JumpPower=hold.jumpPower end
  if human.JumpHeight==0 then human.JumpHeight=hold.jumpHeight end
  local stun=player:GetAttribute("StunnedUntil")
  if not (typeof(stun)=="number" and stun>Workspace:GetServerTimeNow()) then human.AutoRotate=hold.autoRotate end
  if hold.root.Parent then
   hold.root.Anchored=hold.anchored
   if hold.root:CanSetNetworkOwnership() then hold.root:SetNetworkOwnershipAuto() end
  end
 end
 if player.Parent==Players then
  player:SetAttribute("PoliceState",nil);player:SetAttribute("PoliceArrestUntil",nil)
  player:SetAttribute("PoliceReleaseUntil",Workspace:GetServerTimeNow()+Config.ReleaseGrace)
 end
end
function Arrest.Update(self: Service, now: number)
 for player,hold in self.holds do
  if player.Parent~=Players or player.Character~=hold.character or not hold.root.Parent
   or not hold.humanoid.Parent or hold.humanoid.Health<=0 or now>=hold.expires then self:Release(player);continue end
  if not hold.applied then
   if hold.humanoid.SeatPart==nil and hold.root.AssemblyRootPart~=hold.scooterRoot then
    hold.applied=true;hold.root.Anchored=true
    hold.humanoid.WalkSpeed=0;hold.humanoid.JumpPower=0;hold.humanoid.JumpHeight=0;hold.humanoid.AutoRotate=false
   elseif now>=hold.separatingUntil then self:Release(player) end
  end
 end
end
function Arrest.ReleaseOwner(self: Service, owner: {})
 for player,hold in self.holds do if hold.owner==owner then self:Release(player) end end
end
function Arrest.Destroy(self: Service)
 for player in self.holds do self:Release(player) end
end
return Arrest
