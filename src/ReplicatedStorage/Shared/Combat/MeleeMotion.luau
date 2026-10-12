--!strict
-- One upper-body mixer owns the fists pose; locomotion and character appearance stay untouched.
local RunService = game:GetService("RunService")
local Config = require(script.Parent.MeleeConfig)
local Motion = {}
type Joint = Motor6D | AnimationConstraint
type Pose = {[string]: CFrame}
type Frame = {time: number, pose: Pose}
type State = {
 stance: boolean, joints: {[string]: Joint}, basis: {[Joint]: CFrame},
 pose: Pose, frames: {Frame}?, started: number, duration: number,
 reactionAt: number?, heavyReaction: boolean, missed: boolean,
 tracks: {[string]: AnimationTrack}, externalUntil: number, externalStance: boolean,
}
local states: {[Model]: State} = {}
local connection: RBXScriptConnection? = nil
local names = {RightShoulder="Right",["Right Shoulder"]="Right",LeftShoulder="Left",["Left Shoulder"]="Left",
 RightElbow="RightElbow",LeftElbow="LeftElbow",RightWrist="RightWrist",LeftWrist="LeftWrist",Waist="Waist",Neck="Neck"}
local function angle(x: number, y: number, z: number): CFrame
 return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end
local function guard(r15: boolean): Pose
 if not r15 then
  -- R6 has no elbows: keep arms close and below the face rather than imitating an impossible bend.
  return {Right=angle(76,10,-9),Left=angle(82,-10,9),Neck=angle(-2,0,0)}
 end
 return {
  Right=angle(28,25,-12),Left=angle(33,-23,12),
  RightElbow=angle(104,0,0),LeftElbow=angle(98,0,0),
  RightWrist=angle(-6,-4,3),LeftWrist=angle(-6,4,-3),
  Waist=angle(2,-4,0),Neck=angle(-2,4,0),
 }
end
local function stateOf(character: Model): State
 local state=states[character]
 if state then return state end
 state={stance=false,joints={},basis={},pose={},frames=nil,started=0,duration=0,
  reactionAt=nil,heavyReaction=false,missed=false,tracks={},externalUntil=0,externalStance=false}
 for _,joint in character:GetDescendants() do
  if (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) and names[joint.Name] then
   state.joints[names[joint.Name]]=joint
   state.basis[joint]=joint.C0.Rotation
  end
 end
 states[character]=state
 return state
end
function Motion.Stop(character: Model)
 local state=states[character]
 if not state then return end
 for _,joint in state.joints do if joint.Parent then joint.Transform=CFrame.identity end end
 for _,track in state.tracks do track:Stop(0.08) track:Destroy() end
 states[character]=nil
end
local function sample(frames: {Frame}, elapsed: number, key: string): CFrame
 for i=2,#frames do
  local a,b=frames[i-1],frames[i]
  if elapsed<=b.time then
   local alpha=math.clamp((elapsed-a.time)/math.max(0.001,b.time-a.time),0,1)
   alpha=alpha*alpha*(3-2*alpha)
   return (a.pose[key] or CFrame.identity):Lerp(b.pose[key] or CFrame.identity,alpha)
  end
 end
 return frames[#frames].pose[key] or CFrame.identity
end
local function published(state: State, character: Model, name: string, elapsed: number?): boolean
 local h=character:FindFirstChildOfClass("Humanoid")
 local animator=h and h:FindFirstChildOfClass("Animator")
 local rig=if h and h.RigType==Enum.HumanoidRigType.R6 then "R6" else "R15"
 local id=(Config.Animations :: any)[rig][name]
 if not animator or type(id)~="string" or not id:match("^rbxassetid://%d+$") then return false end
 local track=state.tracks[name]
 if not track then
  local animation=Instance.new("Animation") animation.AnimationId=id
  local ok,result=pcall(function() return animator:LoadAnimation(animation) end)
  animation:Destroy()
  if not ok then return false end
  track=result state.tracks[name]=track
 end
 -- Stance and strikes never compete on the same limbs.
 for key,other in state.tracks do if key~=name and other.IsPlaying then other:Stop(0.08) end end
 track.Priority=if name=="Stance" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Action2
 track.Looped=name=="Stance"
 track:Play(0.08)
 if elapsed and elapsed>0 and track.Length>0 then track.TimePosition=math.min(elapsed,track.Length) end
 return true
end
local function ensureLoop()
 if connection then return end
 connection=RunService.PreSimulation:Connect(function()
  local now=os.clock()
  for character,state in states do
   local h=character:FindFirstChildOfClass("Humanoid")
   if not character.Parent or not h or h.Health<=0 or character:GetAttribute("PepperSprayStunned")==true then Motion.Stop(character) continue end
   if now<state.externalUntil then continue end
   if state.externalUntil>0 then
    state.externalUntil=0
    for key,track in state.tracks do if key~="Stance" then track:Stop(0.08) end end
    state.externalStance=state.stance and published(state,character,"Stance")
   end
   local elapsed=now-state.started
   if state.frames and elapsed>=state.duration then state.frames=nil state.missed=false end
   local reacting=state.reactionAt~=nil and now-(state.reactionAt :: number)<0.28
   if not state.stance and not state.frames and not reacting then Motion.Stop(character) continue end
   if state.externalStance and not state.frames and not reacting then continue end
   local resting=if state.stance then guard(h.RigType==Enum.HumanoidRigType.R15) else {}
   for key,joint in state.joints do
    if not joint.Parent or not joint.Enabled then continue end
    local pose=if state.frames then sample(state.frames,elapsed,key) else (resting[key] or CFrame.identity)
    if reacting and (key=="Waist" or key=="Neck") then
     local t=math.clamp((now-(state.reactionAt :: number))/0.28,0,1)
     local weight=math.sin(t*math.pi)
     local strength=if state.heavyReaction then 10 else 6
     pose=pose*angle(-strength*weight,2*weight,0)
    end
    state.pose[key]=pose
    local basis=state.basis[joint]
    -- Apply authored rotations in the parent body's axes. Never write read-only C0 or retargeting attachments.
    joint.Transform=basis:Inverse()*pose*basis
   end
  end
  if next(states)==nil and connection then connection:Disconnect() connection=nil end
 end)
end
function Motion.Stance(character: Model, enabled: boolean)
 if not enabled then Motion.Stop(character) return end
 local state=stateOf(character)
 if state.stance then return end
 state.stance=true
 state.externalStance=published(state,character,"Stance")
 if not state.externalStance then
  local h=character:FindFirstChildOfClass("Humanoid")
  state.frames={{time=0,pose=table.clone(state.pose)},{time=0.22,pose=guard(h~=nil and h.RigType==Enum.HumanoidRigType.R15)}}
  state.started,state.duration=os.clock(),0.22
 end
 ensureLoop()
end
function Motion.Play(character: Model, name: string, index: number?, elapsed: number?)
 local state=stateOf(character)
 if name=="Miss" then
  -- The server's miss arrives while the punch is recovering. Do not replace that recovery with another arm swing.
  state.missed=true
  if state.frames and #state.frames>2 then
   local recovery=state.frames[#state.frames-1]
   recovery.pose=table.clone(recovery.pose)
   recovery.pose.Waist=(recovery.pose.Waist or CFrame.identity)*angle(2,0,0)
  end
  return
 end
 if name=="Hit" or name=="HeavyHit" then
  if not state.frames and state.externalUntil<=os.clock() and published(state,character,name) then
   state.externalStance=false state.externalUntil=os.clock()+0.28 ensureLoop() return
  end
  state.reactionAt,state.heavyReaction=os.clock(),name=="HeavyHit"
  ensureLoop()
  return
 end
 if not index then return end
 local timing=Config.Swings[index]
 if not timing then return end
 local late=math.clamp(elapsed or 0,0,timing.Cooldown)
 if published(state,character,name,late) then
  state.frames=nil state.externalStance=false
  state.externalUntil=os.clock()+math.max(0,timing.Cooldown-late)
  ensureLoop()
  return
 end
 for _,track in state.tracks do if track.IsPlaying then track:Stop(0.08) end end
 state.externalStance=false
 local h=character:FindFirstChildOfClass("Humanoid")
 local r15=h~=nil and h.RigType==Enum.HumanoidRigType.R15
 local resting=if state.stance then guard(r15) else {}
 local wind,contact,recover=table.clone(guard(r15)),table.clone(guard(r15)),table.clone(guard(r15))
 local arm=if index==2 then "Left" else "Right"
 local elbow=if index==2 then "LeftElbow" else "RightElbow"
 local side=if index==2 then -1 else 1
 wind[arm]=angle(if r15 then 20 else 58,-side*8,-side*7)
 wind[elbow]=angle(110,0,0)
 wind.Waist=angle(1,-side*(if index==4 then 10 else 6),0)
 if index==3 then
  wind.Right=angle(if r15 then 42 else 65,-25,-12)
  contact.Right=angle(72,34,-18) contact.RightElbow=angle(72,0,0)
  contact.Waist=angle(3,12,0)
 elseif index==4 then
  wind.Right=angle(if r15 then 12 else 50,-18,-8)
  contact.Right=angle(94,24,-12) contact.RightElbow=angle(12,0,0)
  contact.Waist=angle(7,12,0)
 else
  contact[arm]=angle(86,side*24,-side*12)
  contact[elbow]=angle(12,0,0)
  contact.Waist=angle(3,side*7,0)
 end
 contact.Neck=angle(-2,-side*4,0)
 recover[arm]=contact[arm]:Lerp(resting[arm] or CFrame.identity,0.65)
 recover[elbow]=angle(if index==3 then 88 else 76,0,0)
 local start=if late<0.08 then table.clone(state.pose) else table.clone(guard(r15))
 state.frames={
  {time=0,pose=start},
  {time=timing.Windup*0.68,pose=wind},
  {time=timing.Windup,pose=contact},
  {time=timing.Windup+timing.Window*0.38,pose=contact},
  {time=timing.Windup+timing.Window+0.03,pose=recover},
  {time=timing.Cooldown,pose=resting},
 }
 state.started,state.duration=os.clock()-late,timing.Cooldown
 state.missed=false
 ensureLoop()
end
function Motion.StopAll()
 local list={} for character in states do table.insert(list,character) end
 for _,character in list do Motion.Stop(character) end
 if connection then connection:Disconnect() connection=nil end
end
return Motion
