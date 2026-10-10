--!strict
local Ragdoll = {}
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PepperSprayConfig"))
type State = {
 character: Model, humanoid: Humanoid, root: BasePart,
 motors: {[Motor6D]: boolean}, collisions: {[BasePart]: boolean},
 objects: {Instance}, connections: {RBXScriptConnection},
 walk: number, jump: number, jumpHeight: number, autoRotate: boolean, platform: boolean,
}
local states: {[Model]: State} = {}

function Ragdoll.Stop(character: Model)
 local state = states[character]
 if not state then return end
 states[character] = nil
 for _,connection in state.connections do connection:Disconnect() end
 for _,object in state.objects do object:Destroy() end
 for motor, enabled in state.motors do if motor.Parent then motor.Enabled = enabled end end
 for part, collision in state.collisions do if part.Parent then part.CanCollide = collision end end
 local humanoid = state.humanoid
 if humanoid.Parent then
  -- Preserve intervening changes made by other gameplay systems.
  if humanoid.WalkSpeed == 0 then humanoid.WalkSpeed = state.walk end
  if humanoid.JumpPower == 0 then humanoid.JumpPower = state.jump end
  if humanoid.JumpHeight == 0 then humanoid.JumpHeight = state.jumpHeight end
  if not humanoid.AutoRotate then humanoid.AutoRotate = state.autoRotate end
  humanoid.PlatformStand = state.platform
  if humanoid.Health > 0 and not state.platform then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
 end
 if state.root.Parent then
  state.root.AssemblyAngularVelocity = Vector3.zero
  pcall(function() state.root:SetNetworkOwnershipAuto() end)
 end
 character:SetAttribute("PepperSprayStunned", nil)
end

function Ragdoll.Start(character: Model, duration: number): boolean
 if states[character] then return false end
 local humanoid = character:FindFirstChildOfClass("Humanoid")
 local root = character:FindFirstChild("HumanoidRootPart")
 if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand or root.Anchored then return false end
 local state: State = {
  character = character, humanoid = humanoid, root = root,
  motors = {}, collisions = {}, objects = {}, connections = {},
  walk = humanoid.WalkSpeed, jump = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight,
  autoRotate = humanoid.AutoRotate, platform = humanoid.PlatformStand,
 }
 states[character] = state
 character:SetAttribute("PepperSprayStunned", true)
 local body: {BasePart} = {}
 for _,part in character:GetChildren() do
  if part:IsA("BasePart") and part ~= root then
   state.collisions[part] = part.CanCollide
   part.CanCollide = true
   table.insert(body, part)
  end
 end
 -- Keep neck and root motors intact: safe health and a stable camera subject on both rigs.
 for _,joint in character:GetDescendants() do
  if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 and joint.Name ~= "Neck"
   and joint.Part0 ~= root and joint.Part1 ~= root
   and joint.Part0.Parent == character and joint.Part1.Parent == character then
   local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
   a0.Name, a1.Name = "PepperSprayJoint", "PepperSprayJoint"
   a0.CFrame, a1.CFrame = joint.C0, joint.C1
   a0.Parent, a1.Parent = joint.Part0, joint.Part1
   local socket = Instance.new("BallSocketConstraint")
   socket.Name = "PepperSpraySocket"
   socket.Attachment0, socket.Attachment1 = a0, a1
   socket.LimitsEnabled, socket.UpperAngle = true, 40
   socket.TwistLimitsEnabled, socket.TwistLowerAngle, socket.TwistUpperAngle = true, -30, 30
   socket.Parent = joint.Part0
   table.insert(state.objects, a0) table.insert(state.objects, a1) table.insert(state.objects, socket)
   state.motors[joint] = joint.Enabled
   joint.Enabled = false
  end
 end
 -- Collide with the floor, never with the character's own body.
 for i, a in body do
  for j = i + 1, #body do
   local constraint = Instance.new("NoCollisionConstraint")
   constraint.Name = "PepperSprayNoCollision"
   constraint.Part0, constraint.Part1 = a, body[j]
   constraint.Parent = a
   table.insert(state.objects, constraint)
  end
 end
 humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
 humanoid.AutoRotate, humanoid.PlatformStand = false, true
 pcall(function() root:SetNetworkOwner(nil) end)
 humanoid:ChangeState(Enum.HumanoidStateType.Physics)
 -- A short controlled rotation tips the torso off balance even on a flat floor.
 -- A single impulse was too weak on some avatar mass distributions.
 local fallAttachment = Instance.new("Attachment")
 fallAttachment.Name = "PepperSprayFallOrigin"
 fallAttachment.Parent = root
 local fallDrive = Instance.new("AngularVelocity")
 fallDrive.Name = "PepperSprayFallDrive"
 fallDrive.Attachment0 = fallAttachment
 fallDrive.RelativeTo = Enum.ActuatorRelativeTo.World
 fallDrive.AngularVelocity = root.CFrame.RightVector * Config.FallAngularSpeed
 fallDrive.MaxTorque = root.AssemblyMass * Config.FallTorquePerMass
 fallDrive.Parent = root
 table.insert(state.objects, fallDrive)
 table.insert(state.objects, fallAttachment)
 task.delay(math.min(Config.FallDriveTime, duration), function()
  if states[character] == state then
   fallDrive:Destroy()
   fallAttachment:Destroy()
  end
 end)
 table.insert(state.connections, humanoid.Died:Connect(function() Ragdoll.Stop(character) end))
 table.insert(state.connections, character.Destroying:Connect(function() Ragdoll.Stop(character) end))
 task.delay(duration, function() if states[character] == state then Ragdoll.Stop(character) end end)
 return true
end

function Ragdoll.StopAll()
 local list = {} for character in states do table.insert(list, character) end
 for _,character in list do Ragdoll.Stop(character) end
end
return Ragdoll
