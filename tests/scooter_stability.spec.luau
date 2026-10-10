local start = testCount
local Geometry = loadModule("ServerScriptService/Scooter/ScooterRigGeometry")
local Collision = loadModule("ServerScriptService/Scooter/ScooterCollision")
local tilted = source:Clone()
local turn = Frame.fromAxisAngle(Vector.xAxis, math.rad(15))
for _, name in { "FrontSuspensionLeft", "FrontSuspensionRight", "VirtualFrontAxle", "FrontWheel" } do
	tilted[name].CFrame = turn * tilted[name].CFrame
end
local wheelBefore = tilted.FrontWheel.CFrame
local corrected = Rig.Prepare(tilted)
check(corrected.FrontWheel.CFrame ~= wheelBefore, "Front repair changes actual mesh pose, not just attachment frames")
near(corrected.FrontWheel.WheelCenter.WorldPosition.Y, corrected.BackWheel.WheelCenter.WorldPosition.Y,
	"Front tire rest level matches rear tire")
near(corrected:GetAttribute("FrontRestCorrectionDegrees"), -15, "Front arm/axle/wheel rest rotation is corrected")
check(corrected.BackWheel.CFrame == tilted.BackWheel.CFrame, "Rear wheel is untouched by front rest correction")
check(#Geometry.Check(corrected).errors == 0, "Reposed front remains mechanically valid after calibration")
local repeated = Rig.Prepare(corrected)
check(repeated.FrontWheel.CFrame == corrected.FrontWheel.CFrame, "Spawn cloning does not accumulate rest pose rotations")
near(repeated.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness,
	corrected.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness, "Cloning retains corrected spring rest tuning")

local moved = Rig.Prepare(source)
moved:SetAttribute("FrontRestPoseRevision", nil)
for _, side in { "Left", "Right" } do
	moved.ScooterBody["PivotAttBase_BackSuspension" .. side].Position += Vector.new(0, -0.1, 0.5)
	moved["BackSuspension" .. side]["PivotAtt_BackSuspension" .. side].Position += Vector.new(0, -0.1, 0.5)
end
local beforeArm = moved.FrontSuspensionLeft.CFrame
Geometry.AlignFrontRest(moved)
local frontPivot = moved.HandleBarStick.PivotAttBase_FrontSuspensionLeft.WorldPosition
local backPivot = moved.ScooterBody.PivotAttBase_BackSuspensionLeft.WorldPosition
near(frontPivot.Y, backPivot.Y, "Front mount uses working rear deck mounting height")
near(frontPivot.Z, -backPivot.Z, "Front mount mirrors rear deck-side joint")
check(moved.FrontSuspensionLeft.CFrame ~= beforeArm, "Moving the mount moves the visible arm with it")

local deck = corrected.DeckCollider
check(deck.CanCollide and deck.Massless and not deck.Anchored, "Deck retains a massless physical road contact after tipping")
near(deck.CustomPhysicalProperties[2], Config.DeckColliderFriction,
	"The underside uses skid friction so the base scooter's acceleration can move it off a support")
near(corrected.FrontWheelCollider.CustomPhysicalProperties[2], Config.GroundColliderFriction,
	"Underside skid tuning preserves tire contact friction")
check(deck.DeckColliderWeld.Part0 == corrected.FootRest, "Deck road contact follows existing FootRest assembly")
check(deck.FrontWheelNoCollision.Part0 == deck and deck.FrontWheelNoCollision.Part1 == corrected.FrontWheelCollider,
	"Deck cannot collide with its own front suspension tire")
check(deck.BackWheelNoCollision.Part1 == corrected.BackWheelCollider, "Deck cannot collide with its own rear tire")
local count = #corrected:GetDescendants()
Collision.Configure(corrected)
check(#corrected:GetDescendants() == count, "Repeated collision setup does not duplicate deck contacts or exclusion pairs")

-- Run the real server setup and update loop; contacts/assemblies remain test doubles.
local originalNew = InstanceMock.new
function InstanceMock.new(className)
	local instance = originalNew(className)
	instance.AssemblyAngularVelocity = Vector.zero
	instance.Triggered = signal()
	instance.OnServerEvent = signal()
	local meta = getmetatable(instance)
	local oldIndex = meta.__index
	meta.__index = function(self, key)
		if key == "AssemblyMass" then return self:GetMass() end
		if key == "AssemblyRootPart" then return self end
		return oldIndex(self, key)
	end
	return instance
end
function instanceMethods:CanSetNetworkOwnership() return true end
function instanceMethods:GetPropertyChangedSignal() return signal() end
function vectorMethods:Lerp(other, alpha) return self + (other - self) * alpha end
function instanceMethods:SetNetworkOwner(owner) self.networkOwner = owner end
function instanceMethods:GetFullName() return self.Name end
function instanceMethods:PivotTo(frame)
	local transform = frame * self.PrimaryPart.CFrame:Inverse()
	for _, part in self:GetDescendants() do if part:IsA("BasePart") then part.CFrame = transform * part.CFrame end end
end
enumMock.AlignType = { AllAxes = "AllAxes", PrimaryAxisParallel = "PrimaryAxisParallel" }
enumMock.OrientationAlignmentMode = { OneAttachment = "OneAttachment" }
enumMock.ActuatorRelativeTo = { World = "World" }
enumMock.KeyCode = { E = "E" }
enumMock.PartType.Block = "Block"
baseEnvironment.ColorSequence = { new = function(value) return value end }
baseEnvironment.NumberSequence = { new = function(first, last) return { first, last } end }
enumMock.NormalId = { Back = "Back" }
moduleCache["ServerScriptService/Combat/CombatService"] = { StunPlayer = function() end }
local physicsModule = make(sharedScooterFolder, "ModuleScript", "ScooterPhysics")
physicsModule._values._path = "ReplicatedStorage/Shared/Scooter/ScooterPhysics"
local shop = make(sharedFolder, "Folder", "Shop")
local shopModule = make(shop, "ModuleScript", "ShopConfig")
shopModule._values._path = "ReplicatedStorage/Shared/Shop/ShopConfig"
local Server = loadModule("ServerScriptService/Scooter/ScooterServer")
local spawn = make(services.Workspace, "SpawnLocation", "StabilitySpawn")
spawn.Enabled = true
spawn.CFrame = Frame.Angles(0, 0.8, 0)
services.Workspace.Raycast = function(_, origin)
	return { Normal = Vector.yAxis, Position = Vector.new(origin.X, 0, origin.Z), Distance = 1, Instance = spawn }
end
function services.Workspace:GetServerTimeNow() return testClock end
function services.Workspace:Blockcast() return nil end
local template = services.ServerStorage.ScooterModels.scooter
local frontLamp = make(corrected, "MeshPart", "FrontLight")
frontLamp.Massless = true
local rearLamp = make(corrected, "Part", "StopLight")
rearLamp.Massless = true
make(rearLamp, "PointLight", "PointLight").Enabled = true
local preservedParent = template.Parent
template.Parent = services.ServerStorage
corrected.Parent = preservedParent
local player = makePlayer(8080)
player.CharacterRemoving = signal()
player.Parent = playersService
local scooter
do
	local spawnCharacter = make(nil, "Model", "SpawnRider")
	local spawnRoot = make(spawnCharacter, "Part", "HumanoidRootPart")
	local distantSpawn = make(services.Workspace, "SpawnLocation", "FartherSpawn")
	distantSpawn.Enabled, distantSpawn.CFrame = true, Frame.new(1000, 0, 0)
	spawnRoot.CFrame = distantSpawn.CFrame
	player.Character = spawnCharacter
	scooter = Server.SpawnForPlayer(player)
	check((scooter.Root.Position - distantSpawn.Position).Magnitude < 15,
		"With multiple enabled spawns, the scooter appears beside the player's actual spawn")
	distantSpawn:Destroy()
end
local root, upright = scooter.Root, scooter.Root.ScooterUpright
-- The service double has no solver; put its flat road at actual tire contact height.
local fixtureGroundY = scooter.FrontWheel.WheelCenter.WorldPosition.Y - scooter:GetAttribute("ResolvedFrontWheelRadius")
services.Workspace.Raycast = function(_, origin)
 return { Normal = Vector.yAxis, Position = Vector.new(origin.X, fixtureGroundY, origin.Z), Distance = 1, Instance = spawn }
end
check(upright.CFrame.LookVector:Dot(root.CFrame.LookVector) > 0.999, "Spawn balance target initializes to actual yaw")
check(upright.MaxTorque > Config.Models[Config.DefaultModel].turnTorque * root.AssemblyMass,
	"Spawn balance includes separate massive hinge assemblies")
check(scooter.DeckCollider.CanCollide, "Server sanitization retains deck collision")
near(scooter:GetAttribute("UprightSupportMass"), root.AssemblyMass + 9,
	"Server support mass includes steering, arms, axles and wheels")
Server.Start()
local beforeTorque = upright.MaxTorque
services.RunService.PreSimulation:Fire(1 / 60)
near(upright.MaxTorque, beforeTorque, "Unoccupied update retains full balance torque rather than reverting to Root mass")
check(upright.Enabled ~= false and scooter.DeckCollider.CanCollide, "Unoccupied scooter retains balance and deck support")

local character = make(nil, "Model", "HandlingRider")
local humanoid = make(character, "Humanoid", "Humanoid")
player.Character = character
scooter.DriverSeat.Occupant = humanoid
local driveRemote = services.ReplicatedStorage.Remotes[Config.RemoteFolderName].DriveInput
local function controls(throttle, brake, steering, wheelie)
	testClock += 0.1
	driveRemote.OnServerEvent:Fire(player, throttle, brake, steering, wheelie)
end
local function tick(speed)
	root.AssemblyLinearVelocity = root.CFrame.LookVector * speed
	services.RunService.PreSimulation:Fire(0.1)
end

do
	local originalPose, originalRaycast = root.CFrame, services.Workspace.Raycast
	controls(true, false, 0, false)
	tick(20)
	root.CFrame = Frame.new(root.Position) * Frame.Angles(0, math.rad(0.5), 0) * originalPose.Rotation
	controls(true, false, 0, false)
	tick(20)
	check(root.ScooterRoadBalance.Enabled and root.ScooterRoadBalance.RigidityEnabled
		and root.ScooterRoadBalance.AlignType == enumMock.AlignType.PrimaryAxisParallel,
		"Normal road contact restricts collision-driven tilt through the up axis only")
	check(root.ScooterRoadBalance.Attachment0.CFrame.RightVector:Dot(Vector.yAxis)>0.999,
		"Road balance targets chassis up instead of steering heading")
	check(root:FindFirstChild("ScooterArcadeYaw") == nil, "Previous steering does not add a separate yaw actuator")
	check(upright.CFrame.LookVector:Dot(originalPose.LookVector) > 0.999,
		"Neutral traction retains the rider heading needed for shallow curb entry")
	check(upright.AlignType == enumMock.AlignType.AllAxes,
		"Previous balance controller retains full orientation control")
	services.Workspace.Raycast = function() return nil end
	tick(20)
	check(upright.AlignType == enumMock.AlignType.AllAxes, "Unsupported flight retains full orientation balance")
	check(not root.ScooterRoadBalance.Enabled, "Road tilt restriction disengages during unsupported flight")
	root.CFrame, services.Workspace.Raycast = originalPose, originalRaycast
	controls(true, false, 0, false)
	tick(20)
end

do
 local saved = services.Workspace.Raycast
 local front = scooter.VirtualFrontAxle.AxlePivot.WorldPosition
 local back = scooter.VirtualBackAxle.AxlePivot.WorldPosition
 local axis = (front-back).Unit
 local midpoint = (front+back)*.5
 services.Workspace.Raycast = function(_, origin)
  local height = fixtureGroundY - (if (origin-midpoint):Dot(axis)>0 then 1 else 0)
  return { Normal=Vector.yAxis, Position=Vector.new(origin.X,height,origin.Z), Instance=spawn }
 end
 controls(false,false,0,false)
 for _=1,20 do tick(0) end
 check(not scooter:GetAttribute("FrontGrounded") and scooter:GetAttribute("RearGrounded"),
  "A lower road informs pitch without pretending an airborne front wheel has contact")
 check(upright.CFrame.UpVector:Dot(axis)>0.05,
  "Chassis tilts toward lower front ground rather than staying flat on the rear contact")
 services.Workspace.Raycast = function(_,origin)
  return {Normal=Vector.yAxis,Position=Vector.new(origin.X,fixtureGroundY-10,origin.Z),Instance=spawn}
 end
 tick(0)
 check(not scooter:GetAttribute("FrontGrounded") and not scooter:GetAttribute("RearGrounded"),
  "Distant ground cannot authorize driving while the scooter is airborne")
 services.Workspace.Raycast=saved
 for _=1,20 do tick(0) end
end

do
 local policeStart=testCount
 controls(true,false,0,false);tick(80)
 local riding=Server.GetRidingState(player)
 check(riding and riding.model==scooter,"Police reads the actual owned, occupied server record")
 near(riding.speedKmh,50,"Police uses existing precise 1.6 stud/s per km/h conversion")
 check(not riding.wheelie,"Grounded normal riding is not wheelie")
 local owner,other={},{}
 check(Server.LockMount(player,owner),"Server detention can acquire a mount lock")
 check(not Server.LockMount(player,other),"Mount lock has one owner")
 check(Server.GetRidingState(player)==nil,"Locked rider cannot supply fresh violation state")
 check(not Server.RequestSpawnForPlayer(player,Config.DefaultModel),"Detained player cannot replace the scooter")
 Server.ReleaseMount(player,other)
 check(not Server.LockMount(player,other),"Wrong owner cannot release a mount lock")
 Server.ReleaseMount(player,owner)
 check(Server.LockMount(player,other),"Authorized release permits reuse")
 Server.ReleaseMount(player,other)
 local ownedWeld=make(scooter.DriverSeat,"Weld","SeatWeld")
 check(Server.DismountForPlayer(player),"Authorized server dismount uses existing scooter lifecycle")
 check(ownedWeld.destroyed and humanoid.Sit==false,"Only owned seat weld is removed")
 check(not scooter.destroyed and scooter.VirtualFrontAxle.HingeConstraint.Parent~=nil,"Dismount preserves the articulated scooter")
 check(not Server.DismountForPlayer(makePlayer(8081)),"A player without a scooter cannot force a dismount")
 tick(0)
 print(string.format("PASS: %d police/scooter integration assertions",testCount-policeStart))
end

do
	local lampStart = testCount
	local remote = services.ReplicatedStorage.Remotes[Config.RemoteFolderName].ToggleHeadlight
	local beam = scooter.FrontLight.HeadlightBeamAttachment.HeadlightBeam
	check(not beam.Enabled and not scooter.StopLight.PointLight.Enabled, "Front/rear lights start off despite authored rear glow")
	for _, value in { true, "on", 1, {}, 0 / 0 } do
		remote.OnServerEvent:Fire(player, value)
		check(not beam.Enabled, "Headlight remote rejects client state/invalid payload")
	end
	remote.OnServerEvent:Fire(player, nil)
	check(not beam.Enabled, "Headlight rejects even an extra nil argument")
	local outsider = makePlayer(8082)
	outsider.Parent = playersService
	remote.OnServerEvent:Fire(outsider)
	check(not beam.Enabled, "Headlight denies another player's scooter")
	remote.OnServerEvent:Fire(player)
	check(beam.Enabled and scooter:GetAttribute("HeadlightEnabled") == true, "Mounted owner toggles white front beam")
	check(beam.Color == Config.Headlight.Color and scooter.FrontLight.Material == enumMock.Material.Neon, "Beam and lamp use white emission")
	remote.OnServerEvent:Fire(player)
	check(beam.Enabled, "Headlight server cooldown blocks spam")
	testClock += Config.Headlight.ToggleCooldown
	remote.OnServerEvent:Fire(player)
	check(not beam.Enabled and scooter:GetAttribute("HeadlightEnabled") == false, "Valid second toggle turns beam off")
	scooter.DriverSeat.Occupant = nil
	testClock += 1
	remote.OnServerEvent:Fire(player)
	check(not beam.Enabled, "Unmounted owner cannot switch headlight")
	scooter.DriverSeat.Occupant = humanoid
	controls(false, true, 0, false)
	tick(10)
	check(scooter:GetAttribute("BrakeActive") and scooter.StopLight.PointLight.Enabled, "S during forward roll lights BRAKE and stop")
	controls(false, true, 0, false)
	tick(-10)
	check(not scooter:GetAttribute("BrakeActive") and scooter:GetAttribute("StopLightActive"), "Reverse drive lights stop without BRAKE")
	controls(false, false, 0, false)
	tick(-5)
	check(not scooter:GetAttribute("BrakeActive") and scooter.StopLight.PointLight.Enabled, "Reverse coasting retains stop")
	controls(true, false, 0, false)
	tick(-10)
	check(scooter:GetAttribute("BrakeActive") and scooter.StopLight.PointLight.Enabled, "W brakes a reverse roll")
	controls(false, false, 0, false)
	tick(0)
	check(not scooter:GetAttribute("BrakeActive") and not scooter.StopLight.PointLight.Enabled, "Idle clears both brake indicators")
	controls(true, true, 0, false)
	tick(0)
	check(scooter:GetAttribute("BrakeActive") and scooter.StopLight.PointLight.Enabled, "W+S retains brake while stationary")
	controls(false, false, 0, false)
	tick(0)
	print(string.format("PASS: %d light, brake semantics and remote validation assertions", testCount - lampStart))
end

do
local modesStart = testCount
local modeRemote = services.ReplicatedStorage.Remotes[Config.RemoteFolderName].ToggleDriveMode
check(scooter:GetAttribute("DriveMode") == "SPORT", "New scooters start in SPORT")
for _, malformed in { "ECO", 25, {}, true, 0 / 0 } do
	modeRemote.OnServerEvent:Fire(player, malformed)
	check(scooter:GetAttribute("DriveMode") == "SPORT", "Mode remote rejects client-supplied mode or tuning")
end
modeRemote.OnServerEvent:Fire(player, nil)
check(scooter:GetAttribute("DriveMode") == "SPORT", "Even an extra nil argument is rejected")
local outsider = makePlayer(8081)
outsider.Parent = playersService
modeRemote.OnServerEvent:Fire(outsider)
check(scooter:GetAttribute("DriveMode") == "SPORT", "A different player cannot change the rider's mode")
root.AssemblyLinearVelocity = root.CFrame.LookVector * 55 * Config.StudsPerKmH
local movingVelocity = root.AssemblyLinearVelocity
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "ECO" and scooter:GetAttribute("MaxSpeedKmh") == 25,
	"A mounted rider can select the authoritative 25 km/h ECO limit while moving")
check(root.AssemblyLinearVelocity == movingVelocity, "Mode switching never assigns velocity")
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "ECO", "Server cooldown rejects repeated toggles")
controls(true, false, 0, false)
services.RunService.PreSimulation:Fire(1 / 60)
local mass = scooter:GetAttribute("UprightSupportMass")
local acceleration = root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) / mass
check(acceleration < 0 and math.abs(acceleration) <= scooter:GetAttribute("Acceleration") + 1e-6,
	"ECO overspeed deceleration uses the existing bounded drive force")
check(root.AssemblyLinearVelocity == movingVelocity, "The drive controller does not teleport the velocity to the ECO cap")
local speed = 55 * Config.StudsPerKmH
for _ = 1, 300 do
	controls(true, false, 0, false)
	root.AssemblyLinearVelocity = root.CFrame.LookVector * speed
	services.RunService.PreSimulation:Fire(1 / 60)
	speed += root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) / mass / 60
end
near(speed / Config.StudsPerKmH, 25, "Actual ECO server forces converge to 25 km/h")
scooter.DriverSeat.Occupant = nil
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "ECO", "Dismount retains the chosen mode and denies remote toggles")
scooter.DriverSeat.Occupant = humanoid
player:SetAttribute("StunnedUntil", services.Workspace:GetServerTimeNow() + 10)
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "ECO", "Stunned riders cannot switch modes")
player:SetAttribute("StunnedUntil", nil)
humanoid.Health = 0
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "ECO", "Dead riders cannot switch modes")
humanoid.Health = 100
modeRemote.OnServerEvent:Fire(player)
check(scooter:GetAttribute("DriveMode") == "SPORT" and scooter:GetAttribute("MaxSpeedKmh") == 55,
	"Remounting retains the mode and the next accepted toggle restores full SPORT tuning")
for name in Config.Models do
	local tuned = assert(Config.GetTuning(name, 3))
	near(Config.GetDriveModeMaxSpeed(tuned.maxSpeed, "ECO"), 25, "All models share the ECO cap after upgrades")
	near(Config.GetDriveModeMaxSpeed(tuned.maxSpeed, "SPORT"), tuned.maxSpeed, "SPORT preserves each upgraded speed")
end
near(Config.GetDriveModeMaxSpeed(20, "ECO"), 20, "ECO does not raise a model's native limit")
print(string.format("PASS: %d drive mode server assertions", testCount - modesStart))
end
controls(false, false, 1, false)
scooter.ScooterBody.HingeConstraint.CurrentAngle = -48
tick(0)
check(math.abs(scooter.ScooterBody.HingeConstraint.TargetAngle) > 0
	and math.abs(scooter.ScooterBody.HingeConstraint.TargetAngle) <= math.deg(Config.MaxHandlebarAngle),
	"A stationary mounted rider can steer without throttle or burnout")
check(upright.CFrame.LookVector:Dot(root.CFrame.LookVector) > 0.999,
	"Stationary measured steering does not rotate the chassis heading")
scooter.ScooterBody.HingeConstraint.CurrentAngle = 0
controls(false, false, 0, false)
tick(0)
controls(true, true, 0, false)
tick(4.9 * Config.StudsPerKmH)
local rearMotor = scooter.VirtualBackAxle.HingeConstraint
check(scooter:GetAttribute("BurnoutActive") == true and scooter.VirtualBackAxle.RearWheelAttachment.BurnoutSmoke.Enabled,
	"Validated W+S alone starts motor/smoke below 5 km/h without a trick event")
check(rearMotor.ActuatorType == enumMock.ActuatorType.Motor and math.abs(rearMotor.AngularVelocity) > 0,
	"Burnout commands actual rear-wheel hinge rotation")
check(rearMotor.MotorMaxTorque > Config.BurnoutMotorTorque and rearMotor.MotorMaxAcceleration > 0,
	"Burnout motor has load-scaled torque and positive spin acceleration")
tick(5.1 * Config.StudsPerKmH)
check(scooter:GetAttribute("BurnoutActive") == false and rearMotor.ActuatorType == enumMock.ActuatorType.None,
	"Server stops wheel motor/smoke when speed exceeds 5 km/h")
controls(true, true, 0, false)
tick(0)
testClock += Config.DriveInputTimeout + 0.01
tick(0)
check(scooter:GetAttribute("BurnoutActive") == false, "Expired W+S input cannot keep burnout active")

local originalHeading = root.CFrame
local servo = scooter.ScooterBody.HingeConstraint
servo.CurrentAngle = 0
controls(true, true, 1, false)
tick(0)
check(math.abs(servo.TargetAngle) > 0 and math.abs(servo.TargetAngle) <= math.deg(Config.MaxHandlebarAngle),
	"Stationary burnout accepts bounded steering input")
check(math.abs(upright.CFrame.LookVector:Dot(root.CFrame.RightVector)) < 1e-6,
	"Burnout also waits for actual Servo deflection")
servo.CurrentAngle = -20
tick(0)
check(upright.CFrame.LookVector:Dot(root.CFrame.RightVector) > 0,
	"Measured right steering permits a stationary burnout donut")
local totalYaw = 0
servo.CurrentAngle = -math.deg(Config.MaxHandlebarAngle)
for _ = 1, 70 do
	controls(true, true, 1, false)
	root.CFrame = Frame.new(root.Position) * upright.CFrame
	local previousHeading = root.CFrame.LookVector
	tick(0)
	totalYaw += math.abs(math.atan2(previousHeading:Cross(upright.CFrame.LookVector).Y,
		previousHeading:Dot(upright.CFrame.LookVector)))
end
check(totalYaw > math.pi * 2 and scooter:GetAttribute("BurnoutActive") == true,
	"Burnout heading can complete an entire donut without translation or losing the motor")
servo.CurrentAngle = 20
for _ = 1, 3 do tick(0) end
check(upright.CFrame.LookVector:Dot(root.CFrame.RightVector) < 0, "Left burnout steering reverses the donut")
controls(true, false, 1, false)
tick(0)
check(scooter:GetAttribute("BurnoutActive") == false
	and math.abs(upright.CFrame.LookVector:Dot(root.CFrame.RightVector)) < 1e-6,
	"Releasing brake ends stationary donut yaw along with burnout")
root.CFrame = originalHeading
servo.CurrentAngle = 0

for _, speedKmh in { 9.9, -20 } do
	controls(false, false, 0, false)
	tick(speedKmh * Config.StudsPerKmH)
	controls(true, false, 0, true)
	tick(speedKmh * Config.StudsPerKmH)
	check(scooter:GetAttribute("WheelieActive") == false, "Wheelie rejects insufficient forward speed")
end
controls(false, false, 0, false)
tick(20)
controls(true, false, 0, true)
tick(20)
local raisedPitch = math.asin(upright.CFrame.LookVector.Y)
check(scooter:GetAttribute("WheelieActive") == true and raisedPitch > Config.WheelieKickAngle,
	"Shift edge above 10 km/h triggers the moving scooter's wheelie")
controls(true, false, 0, false)
tick(20)
local continuedRaise = math.asin(upright.CFrame.LookVector.Y)
check(continuedRaise > raisedPitch, "W continues raising after releasing Shift without a new trigger")
controls(false, false, 0, false)
tick(20)
local firstReturn = math.asin(upright.CFrame.LookVector.Y)
check(firstReturn > 0 and firstReturn < continuedRaise, "Releasing W lowers wheelie smoothly while still moving")
controls(true, false, 0, false)
tick(20)
local balancedRaise = math.asin(upright.CFrame.LookVector.Y)
check(balancedRaise > firstReturn and scooter:GetAttribute("WheelieActive") == true,
	"Adding W again raises the balance angle without Shift")
controls(false, true, 0, false)
tick(20)
check(math.asin(upright.CFrame.LookVector.Y) < firstReturn, "S lowers the balanced wheelie faster than coasting")
for _ = 1, 30 do controls(false, false, 0, false); tick(20) end
check(scooter:GetAttribute("WheelieActive") == false and math.abs(upright.CFrame.LookVector.Y) < 1e-6,
	"Wheelie lands while forward speed remains positive")
controls(true, false, 0, false)
tick(20)
check(scooter:GetAttribute("WheelieActive") == false, "Throttle alone cannot restart a completed wheelie")

controls(false, true, 0, false)
tick(1)
local supportMass = scooter:GetAttribute("UprightSupportMass")
check(1 + root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) / supportMass * 0.1 < 0,
	"Server accepts S at forward crawl and immediately supplies reverse drive force")
local reverseSpeed = 0
for _ = 1, 20 do
	controls(false, true, 0, false)
	tick(reverseSpeed)
	reverseSpeed += root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) / supportMass * 0.1
end
near(reverseSpeed, -Config.MaxReverseSpeedKmh * Config.StudsPerKmH,
	"Authoritative drive integration reaches the revised reverse cap")
check(scooter:GetAttribute("DriveState") == "Reverse" and scooter:GetAttribute("WheelieActive") == false,
	"Faster reversing retains reverse state without triggering wheelie")

controls(true, false, 1, false)
scooter.ScooterBody.HingeConstraint.CurrentAngle = 0
tick(20)
check(math.abs(upright.CFrame.LookVector:Dot(root.CFrame.RightVector)) < 1e-6,
	"Blocked neutral Servo cannot rotate chassis from requested steering alone")
scooter.ScooterBody.HingeConstraint.CurrentAngle = -30
tick(20)
check(upright.CFrame.LookVector:Dot(root.CFrame.RightVector) > 0, "Actual right Servo angle drives right chassis yaw")
tick(0.6)
check(math.acos(math.clamp(upright.CFrame.LookVector:Dot(root.CFrame.LookVector), -1, 1)) < math.rad(2),
	"Slow turn target remains near actual chassis orientation after braking")
local contactRaycast = services.Workspace.Raycast
services.Workspace.Raycast = function() return nil end
tick(20)
check(math.abs(upright.CFrame.LookVector:Dot(root.CFrame.RightVector)) < 1e-6,
	"A turned Servo cannot generate chassis yaw without wheel contact")
near(root.ScooterDriveForce.Force.Magnitude, 0, "Unsupported airborne input still supplies no drive force")
do
local deckBottom = scooter.DeckCollider.CFrame:PointToWorldSpace(Vector.new(0, -scooter.DeckCollider.Size.Y * 0.5, 0))
local originalBlockcast = services.Workspace.Blockcast
services.Workspace.Blockcast = function(_, frame, size)
	check(size.X == scooter.DeckCollider.Size.X and size.Z == scooter.DeckCollider.Size.Z,
		"Underside support covers the full deck footprint, including contact between point samples")
	return { Normal = Vector.yAxis, Position = deckBottom, Instance = spawn }
end
controls(true, false, 0, false)
tick(0)
check(not scooter:GetAttribute("FrontGrounded") and not scooter:GetAttribute("RearGrounded")
	and scooter:GetAttribute("DeckGrounded") and scooter:GetAttribute("DriveState") == "Forward",
	"Physical underside support keeps the grounded drive state with both tires off the road")
check(root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) > 0, "W can drive off an underside obstacle")
controls(false, true, 0, false)
tick(0)
check(root.ScooterDriveForce.Force:Dot(root.CFrame.LookVector) < 0
	and scooter:GetAttribute("DriveState") == "Reverse", "S can reverse off the same underside obstacle")
services.Workspace.Blockcast = originalBlockcast
tick(0)
check(not scooter:GetAttribute("DeckGrounded") and scooter:GetAttribute("DriveState") == "Airborne",
	"Losing underside support clears grounded drive without retained air thrust")
near(root.ScooterDriveForce.Force.Magnitude, 0, "Reverse force clears immediately after losing all physical support")
end
services.Workspace.Raycast = contactRaycast
controls(false, false, 0, false)
tick(0)
do
	local terrain = loadModule("ServerScriptService/Scooter/ScooterTerrain")
	local oldProbe = terrain.Probe
	terrain.Probe = function(_, direction)
		return (direction + root.CFrame.RightVector * 0.6 + Vector.yAxis * 0.5).Unit, 1
	end
	controls(true, false, 0, false)
	tick(0)
	check(root.ScooterDriveForce.Force:Dot(root.CFrame.RightVector) > 0,
		"Drive grip cooperates with supported sideways curb entry")
	check(upright.CFrame.LookVector:Dot(root.CFrame.LookVector) > 0.999,
		"Curb entry preserves rider-controlled chassis heading instead of automatic yaw into the face")
	terrain.Probe = oldProbe
	controls(false, false, 0, false)
	tick(0)
end
scooter.DriverSeat.Occupant = nil

local incompatibleRest = corrected:Clone()
incompatibleRest:SetAttribute("FrontRestPoseRevision", nil)
incompatibleRest.FootRest.CFrame += Vector.new(0, 0, 0.25)
local baselineWheel = incompatibleRest.FrontWheel.CFrame
local baselineSpring = incompatibleRest.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness
corrected.Parent = nil
incompatibleRest.Parent = preservedParent
local shiftLimit = Config.FrontRestPose.MaxMountShiftRadiusRatio
Config.FrontRestPose.MaxMountShiftRadiusRatio = 0
local fallback = Server.SpawnForPlayer(player)
check(fallback:GetAttribute("DriveMode") == "SPORT", "Replacing the scooter resets its mode to SPORT")
Config.FrontRestPose.MaxMountShiftRadiusRatio = shiftLimit
check(fallback.Parent == services.Workspace[Config.ScooterFolderName], "Rejected optional front correction still spawns a scooter")
check(fallback:GetAttribute("FrontRestPoseStatus") == "Skipped", "Skipped correction exposes diagnostic status")
check(string.find(fallback:GetAttribute("FrontRestPoseError"), "mirrored rear deck joint") ~= nil,
	"Skipped correction retains its concrete error for diagnostics")
near(fallback.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness, baselineSpring,
	"Rejected correction preserves baseline calibrated spring")
check(fallback.DeckCollider.CanCollide and fallback.Root.ScooterUpright.Enabled ~= false,
	"Fallback retains ground contact and stabilization")
check(incompatibleRest.FrontWheel.CFrame == baselineWheel and incompatibleRest:GetAttribute("FrontRestPoseRevision") == nil,
	"Rejected correction cannot mutate installed source pose or revision")
check(scooter.destroyed, "Successful fallback spawn replaces the previous scooter normally")

local Suspension = loadModule("ServerScriptService/Scooter/ScooterSuspension")
local configureFront = Suspension.ConfigureFront
Suspension.ConfigureFront = function() error("injected front calibration failure after mesh repositioning") end
local rollback = Rig.Prepare(incompatibleRest)
Suspension.ConfigureFront = configureFront
check(rollback.FrontWheel.CFrame == baselineWheel, "Failure after mesh movement rolls back to untouched baseline pose")
check(pcall(Rig.Inspect, rollback) and #Geometry.Check(rollback).errors == 0,
	"Failure after mesh movement retains mechanically valid baseline welds and attachments")
rollback:Destroy()
incompatibleRest.Parent = nil
local savedStudioCheck = services.RunService.IsStudio
services.RunService.IsStudio = function() return false end
check(not Server.RequestStudioScaleForPlayer(player, "scale020"),
	"Published servers cannot use the Studio scale selection endpoint")
services.RunService.IsStudio = function() return true end
check(not Server.RequestStudioScaleForPlayer(player, "arbitrary_template"),
	"Studio selection rejects template names outside the explicit variant whitelist")
check(not Server.RequestSpawnForPlayer(player, "scale020"),
	"Normal spawn requests cannot treat a development scale as an owned shop product")
check(not fallback.destroyed, "Rejected scale requests preserve the player's working scooter")
services.RunService.IsStudio = savedStudioCheck
Server.Stop()
check(fallback.destroyed, "Server stop cleans up the fallback spawned rig")
corrected.Parent = nil
template.Parent = preservedParent
spawn:Destroy()
InstanceMock.new = originalNew

local legacy = Rig.Prepare(source)
local original = source:Clone()
original.Name = "UniqueAuthoredReference"
original.Parent = services.ServerStorage
for _, side in { "Left", "Right" } do
	local name = "FrontSuspension" .. side
	legacy[name].MeshId = "rbxassetid://108080"
	original[name].MeshId = legacy[name].MeshId
	legacy[name]["PivotAtt_" .. name]:SetAttribute("AuthoredPivotCFrame", nil)
end
legacy.Parent = services.ServerStorage
services.Selection.Get = function() return { legacy } end
local repaired = loadModule("ServerScriptService/Scooter/DevScooterFrontMount").Apply()
check(repaired.FrontSuspensionLeft.PivotAtt_FrontSuspensionLeft:GetAttribute("AuthoredPivotCFrame") ~= nil,
	"Front developer repair recovers an unambiguous original without requiring a second selection")
check(original.Parent == services.ServerStorage, "Automatic original recovery is read-only")
local beforePose = repaired.FrontWheel.CFrame
services.Selection.Get = function() return { repaired } end
local reapplied = loadModule("ServerScriptService/Scooter/DevScooterFrontMount").Apply()
near((reapplied.FrontWheel.Position - beforePose.Position).Magnitude, 0, "Repeated repair does not drift front position")
near(reapplied.FrontWheel.CFrame.LookVector:Dot(beforePose.LookVector), 1, "Repeated repair does not drift front rotation")
print(string.format("PASS: %d stability assertions (%d total)", testCount - start, testCount))
