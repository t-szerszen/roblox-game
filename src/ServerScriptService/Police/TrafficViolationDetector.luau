--!strict
local Workspace=game:GetService("Workspace")
local Config=require(script.Parent.PoliceConfig)
local Scooter=require(script.Parent.Parent.Scooter.ScooterServer)
local Combat=require(script.Parent.Parent.Combat.CombatService)
local Detector={}
export type ReadState=Scooter.RidingState
export type Evidence={lastSeen: number, lastSample: number, speedTime: number, wheelieTime: number}
function Detector.NewEvidence(now: number): Evidence
 return {lastSeen=now,lastSample=now,speedTime=0,wheelieTime=0}
end
function Detector.Eligible(player: Player, position: Vector3): boolean
 local now=Workspace:GetServerTimeNow()
 local grace=player:GetAttribute("PoliceReleaseUntil")
 local protection=player:GetAttribute("InvulnerableUntil")
 return player:GetAttribute("PoliceState")~="ARRESTED"
  and not (typeof(grace)=="number" and grace>now)
  and not (typeof(protection)=="number" and protection>now)
  and not Combat.IsInSafeZone(position)
end
function Detector.Visible(vehicle: Model, frame: CFrame, character: Model, scooter: Model?): boolean
 local root=character:FindFirstChild("HumanoidRootPart")
 if not root or not root:IsA("BasePart") then return false end
 local origin=frame.Position+Vector3.yAxis
 local delta=root.Position-origin
 if delta.Magnitude>Config.DetectionRange then return false end
 if delta.Magnitude>0.01 and frame.LookVector:Dot(delta.Unit)<math.cos(math.rad(Config.FieldOfView/2)) then return false end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local ignored: {Instance}={vehicle}
 local traffic=Workspace:FindFirstChild("TrafficSystem")
 if traffic then for _,name in {"Debug","Network","CandidateNetwork","RoadRegions"} do
  local child=traffic:FindFirstChild(name);if child then table.insert(ignored,child) end
 end end
 params.FilterDescendantsInstances=ignored
 -- Two samples bound query cost and tolerate a low fence without seeing through buildings.
 for _,point in {root.Position,root.Position+Vector3.yAxis*1.5} do
  local hit=Workspace:Raycast(origin,point-origin,params)
  if not hit or hit.Instance:IsDescendantOf(character) or (scooter and hit.Instance:IsDescendantOf(scooter)) then return true end
 end
 return false
end
function Detector.Accumulate(evidence: Evidence, now: number, visible: boolean,
 riding: boolean, speedKmh: number, wheelie: boolean): string?
 local dt=math.clamp(now-evidence.lastSample,0,1/Config.ObservationRate*2)
 evidence.lastSample=now
 if not riding then evidence.speedTime=0;evidence.wheelieTime=0;return nil end
 if not visible then
  if now-evidence.lastSeen>Config.OcclusionTolerance then evidence.speedTime=0;evidence.wheelieTime=0 end
  return nil
 end
 evidence.lastSeen=now
 evidence.speedTime=if speedKmh>Config.SpeedLimitKmh and speedKmh<math.huge then evidence.speedTime+dt else 0
 evidence.wheelieTime=if wheelie then evidence.wheelieTime+dt else 0
 if evidence.speedTime>=Config.SpeedConfirmation then return "Speeding" end
 if evidence.wheelieTime>=Config.WheelieConfirmation then return "Wheelie" end
 return nil
end
function Detector.Read(player: Player): Scooter.RidingState?
 local state=Scooter.GetRidingState(player)
 return if state and Detector.Eligible(player,state.root.Position) then state else nil
end
return Detector
