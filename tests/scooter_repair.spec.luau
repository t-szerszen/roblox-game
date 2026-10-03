local repairStart = testCount
local Geometry = loadModule("ServerScriptService/Scooter/ScooterRigGeometry")
local Collision = loadModule("ServerScriptService/Scooter/ScooterCollision")
check(#Geometry.Check(source).errors == 0, "Valid authored fixture passes geometry checks")
local damaged = source:Clone()
damaged.VirtualFrontAxle.AxlePivot.Position = Vector.new(0, 2, 0)
damaged.HandleBarStick.SteerPivot.CFrame = Frame.Angles(0, 0, math.pi / 2)
local rightBase = damaged.HandleBarStick.PivotAttBase_FrontSuspensionRight
rightBase.Position = rightBase.Position + Vector.new(0, 0.3, 0)
local collisionWeld = weldTest(damaged.ScooterBody, damaged.ScooterBody, damaged.VirtualBackAxle, "InvalidRigidSuspension")
damaged.HandleBarStick.PivotHinge_FrontSuspensionLeft.ActuatorType = enumMock.ActuatorType.Servo
local brokenReport = Geometry.Check(damaged)
check(#brokenReport.errors >= 5, "Detects hinge gap, rotated axis, noncoaxial pivots, wrong weld and active suspension motor")
check(not pcall(Rig.Prepare, damaged), "Runtime refuses mechanically incompatible rig")
local wheelBefore, bodyBefore = damaged.FrontWheel.CFrame, damaged.ScooterBody.CFrame
local spring = damaged.HandleBarStick.ShockAbsorber_FrontSuspensionLeft
local stiffness, damping, freeLength = spring.Stiffness, spring.Damping, spring.FreeLength
local changes = Geometry.Repair(damaged)
check(#changes >= 3 and #Geometry.Check(damaged).errors == 0, "Repair removes incompatible geometric constraints")
check(damaged.FrontWheel.CFrame == wheelBefore and damaged.ScooterBody.CFrame == bodyBefore,
	"Repair preserves authored mesh transforms")
near(spring.Stiffness, stiffness, "Repair preserves spring stiffness")
near(spring.Damping, damping, "Repair preserves spring damping")
near(spring.FreeLength, freeLength, "Repair preserves spring free length")
check(not collisionWeld.Enabled, "Conflicting weld disabled only on staged clone")
check(source.VirtualFrontAxle.AxlePivot.Position.Y == 0, "Source attachment remains intact")
local repaired = Rig.Prepare(damaged)
local frontCollider, backCollider = repaired.FrontWheelCollider, repaired.BackWheelCollider
check(frontCollider.CanCollide and backCollider.CanCollide, "Both contact colliders exist in prepared template")
check(frontCollider.Massless and not repaired.ScooterBody.CanCollide, "Contact proxies retain wheel support without chassis collision")
near((frontCollider.Position - repaired.FrontWheel.WheelCenter.WorldPosition).Magnitude, 0,
	"Contact collider is centered on physical wheel")
check(frontCollider.WheelColliderWeld.Part0 == repaired.FrontWheel, "Contact collider follows rotating wheel")
local oldProxyWeld = weldTest(repaired.FrontWheel, repaired.FrontWheel, frontCollider, "LegacyProxyWeld")
local childCount = #repaired:GetDescendants()
Collision.Configure(repaired)
check(not oldProxyWeld.Enabled, "Legacy proxy weld cannot drag wheel during collider repositioning")
check(#repaired:GetDescendants() == childCount, "Reconfiguring contacts does not accumulate colliders/welds")
check(#Geometry.Check(repaired).errors == 0, "Generated runtime welds remain within their mechanical assemblies")
repaired.FrontWheel.Size = Vector.new(0.4, 4, 4)
repaired.BackWheel.Size = Vector.new(3, 0.3, 3)
local radius = Collision.ResolveRadius(repaired, repaired.FrontWheel)
near(radius, 2, "Mesh-derived radius replaces unrelated 0.7 default")
local radii = Collision.Configure(repaired)
near(radii.frontRadius, 2, "Front wheel radius resolves independently")
near(radii.backRadius, 1.5, "Back wheel radius resolves independently")
near(repaired.FrontWheelCollider.Size.Y, 2 * (2 - Config.WheelColliderClearance),
	"Collider diameter tracks actual wheel size")
near(Collision.GetSpawnLift(repaired, Frame.identity), 2 - Config.WheelColliderClearance,
	"Spawn lift accounts for actual collider radius")
repaired.FrontWheelCollider.Position = repaired.FrontWheelCollider.Position - Vector.new(0, 3, 0)
near(Collision.GetSpawnLift(repaired, Frame.identity), 5 - Config.WheelColliderClearance,
	"Spawn lift includes wheel offset below deck")
Collision.Configure(repaired)
repaired:SetAttribute("WheelRadius", 1.7)
near(Collision.ResolveRadius(repaired, repaired.FrontWheel), 1.7, "Authored template radius overrides size inference")
repaired.FrontWheel:SetAttribute("WheelRadius", 1.8)
near(Collision.ResolveRadius(repaired, repaired.FrontWheel), 1.8, "Wheel override has highest priority")
repaired.FrontWheel:SetAttribute("WheelRadius", 0 / 0)
near(Collision.ResolveRadius(repaired, repaired.FrontWheel), 1.7, "Invalid radius does not reach collider")
repaired:SetAttribute("WheelRadius", -1)
near(Collision.ResolveRadius(repaired, repaired.FrontWheel), 2, "Invalid template radius falls back to wheel size")
local badSpring = repaired.ScooterBody.ShockAbsorber_BackSuspensionLeft
badSpring.MaxForce = 0
check(#Geometry.Check(repaired).errors > 0, "Zero maximum spring force is reported")
badSpring.MaxForce = math.huge
badSpring.LimitsEnabled, badSpring.MinLength, badSpring.MaxLength = true, 1, 2
check(#Geometry.Check(repaired).errors > 0, "Impossible initial spring length is reported")
badSpring.LimitsEnabled = false

-- The developer tool reloads actual code, stages changes and preserves originals.
badRigModule.Parent = serverFolder
services.Workspace = baseEnvironment.workspace
local RepairTool = loadModule("ServerScriptService/Scooter/DevScooterRepair")
services.Selection.Get = function() return { damaged } end
damaged.Parent = services.ServerStorage
local oldTemplate = services.ServerStorage.ScooterModels.scooter
local result = RepairTool.RepairSelection()
check(result.Parent == services.ServerStorage.ScooterModels, "Repair installs validated runtime template")
check(oldTemplate.Parent == services.ServerStorage.ScooterRepairBackups, "Previous template survives in backups")
check(damaged.Parent == services.ServerStorage.ScooterRepairBackups, "Original selected source survives in backups")
check(services.Selection.selected[1] == result, "Successful repair selects installed template")
check(#serverFolder:GetChildren() == 5, "Successful repair removes temporary reload modules")
services.Selection.Get = function() return { result } end
local diagnosticReport = RepairTool.DiagnoseSelection()
check(#diagnosticReport.errors == 0, "Read-only diagnostics run against installed template")
check(#serverFolder:GetChildren() == 5, "Diagnostics clean up reloaded modules")
baseEnvironment.RaycastParams = { new = function() return {} end }
enumMock.RaycastFilterType = { Exclude = "Exclude" }
local floorQueries = {}
services.Workspace.Raycast = function(_, origin, direction, params)
	table.insert(floorQueries, { origin = origin, direction = direction, params = params })
	return nil
end
result.Parent = services.Workspace
result.FrontWheelCollider.CollisionGroup = "ScooterTest"
result.FrontWheelCollider.CanCollide = false
local liveReport = RepairTool.DiagnoseSelection()
check(#liveReport.errors == 1 and string.find(liveReport.errors[1], "collider") ~= nil,
	"Live diagnostics detect disabled tire contact")
check(#floorQueries == 2 and floorQueries[1].params.RespectCanCollide
	and floorQueries[1].params.CollisionGroup == "ScooterTest", "Floor diagnostics respect physical collider group")
check(floorQueries[1].params.FilterDescendantsInstances[1] == result and floorQueries[1].direction.Y < 0,
	"Floor probe excludes scooter and tests ground below wheel")
result.FrontWheelCollider.CanCollide = true
result.Parent = services.ServerStorage.ScooterModels
local unrepaired = source:Clone()
unrepaired.ScooterBody.ShockAbsorber_BackSuspensionLeft.Stiffness = 0
unrepaired.Parent = services.ServerStorage
services.Selection.Get = function() return { unrepaired } end
local originalParent = unrepaired.Parent
local backupsCount = #services.ServerStorage.ScooterRepairBackups:GetChildren()
check(not pcall(RepairTool.RepairSelection), "Invalid spring tuning prevents replacement")
check(unrepaired.Parent == originalParent and result.Parent == services.ServerStorage.ScooterModels,
	"Failed repair preserves original source and working template")
check(#services.ServerStorage.ScooterRepairBackups:GetChildren() == backupsCount,
	"Failed staging adds no backup artifacts")
check(#serverFolder:GetChildren() == 5, "Failed repair removes temporary reload modules")
services.RunService.IsRunning = function() return true end
check(not pcall(RepairTool.RepairSelection), "Repair rejects Play-mode edits")
services.RunService.IsRunning = function() return false end
print(string.format("PASS: %d scooter repair assertions (%d total)", testCount - repairStart, testCount))
