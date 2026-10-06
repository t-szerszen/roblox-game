local visualStart = testCount
check(not Config.BrakeLight.Enabled, "Fender brake visualization is disabled by default")
Config.BrakeLight.Enabled = true
local BrakeLight = loadModule("ServerScriptService/Scooter/ScooterBrakeLight")
local visualModel = make(nil, "Model", "BrakeTest")
check(BrakeLight.Create(visualModel) == nil, "Absent fender skips optional brake effect")
local fender = make(visualModel, "MeshPart", "BackFender")
local appearance = make(fender, "SurfaceAppearance", "SurfaceAppearance")
fender.Color = Color.fromRGB(35, 50, 70)
appearance.Color = Color.fromRGB(80, 90, 100)
appearance.EmissiveTint = Color.fromRGB(10, 30, 50)
appearance.EmissiveStrength = 0.3
local originalColor, originalTint, originalEmissionTint = fender.Color, appearance.Color, appearance.EmissiveTint
local light = assert(BrakeLight.Create(visualModel))
local glow = fender:FindFirstChild("ScooterBrakeGlow")
check(not glow.Enabled and fender.Material == enumMock.Material.Metal,
	"Creating brake effect retains authored appearance")
light.SetActive(true)
check(fender.Material == enumMock.Material.Neon and fender.Color == Config.BrakeLight.Color,
	"Braking makes fender red Neon")
check(appearance.Parent == fender and appearance.Color == Config.BrakeLight.Color,
	"PBR appearance is preserved and tinted")
check(glow.Enabled and glow.Color == Config.BrakeLight.Color, "Brake glow supports textured mesh")
near(appearance.EmissiveStrength, Config.BrakeLight.EmissiveStrength, "Authored emissive mask receives strength")
light.SetActive(false)
check(fender.Material == enumMock.Material.Metal and fender.Color == originalColor,
	"Release restores authored material and color")
check(appearance.Color == originalTint and appearance.EmissiveTint == originalEmissionTint,
	"Release restores both PBR tints")
near(appearance.EmissiveStrength, 0.3, "Release restores authored emission")
check(not glow.Enabled, "Release disables brake glow")
light.SetActive(true)
light.Destroy()
check(fender.Color == originalColor and fender:FindFirstChild("ScooterBrakeGlow") == nil,
	"Cleanup restores active light and removes runtime support")
light.Destroy()
light.SetActive(true)
check(fender.Color == originalColor, "Disposed controller is inert")
appearance:Destroy()
local plainLight = assert(BrakeLight.Create(visualModel))
plainLight.SetActive(true)
check(fender.Material == enumMock.Material.Neon, "Untextured fender supports same brake effect")
plainLight.Destroy()
local authoredGlow = make(fender, "PointLight", "AuthoredGlow")
authoredGlow.Enabled, authoredGlow.Shadows = true, true
authoredGlow.Color, authoredGlow.Brightness, authoredGlow.Range = originalColor, 4, 12
local reusedLight = assert(BrakeLight.Create(visualModel))
check(not authoredGlow.Enabled and not authoredGlow.Shadows, "Existing lamp is reused and starts disabled")
reusedLight.SetActive(true)
reusedLight.Destroy()
check(authoredGlow.Parent == fender and authoredGlow.Enabled and authoredGlow.Shadows
	and authoredGlow.Color == originalColor and authoredGlow.Brightness == 4 and authoredGlow.Range == 12,
	"Cleanup preserves the authored light and restores all changed properties")
Config.BrakeLight.Enabled = false
check(BrakeLight.Create(visualModel) == nil, "Brake visuals can be disabled in configuration")
Config.BrakeLight.Enabled = false

local requested = Physics.GetEffectiveSteering(0.75, 15)
local angle, limited = Physics.GetServoSteering(requested, false, false, 0, 0)
near(angle, Config.SteeringServoSign * math.deg(Config.MaxHandlebarAngle) * requested,
	"Servo target follows speed-adjusted player input in degrees")
near(limited, requested, "Unrestricted Servo retains driving steering")
local reverseAngle, reverseLimited = Physics.GetServoSteering(requested, true, false, 0, 0)
near(reverseAngle, -angle, "Reversing attachment order reverses Servo convention")
near(reverseLimited, requested, "Attachment order does not reverse chassis yaw")
local limitedAngle, limitInput = Physics.GetServoSteering(1, false, true, -10, 20)
near(limitedAngle, -10, "Authored asymmetric limits clamp right Servo target")
near(limitInput, 10 / math.deg(Config.MaxHandlebarAngle), "Chassis steering uses actual limited right angle")
local leftAngle, leftInput = Physics.GetServoSteering(-1, false, true, -10, 20)
near(leftAngle, 20, "Authored asymmetric limits clamp left Servo target")
near(leftInput, -20 / math.deg(Config.MaxHandlebarAngle), "Chassis steering uses actual limited left angle")
local swappedAngle, swappedInput = Physics.GetServoSteering(1, true, true, -10, 20)
near(swappedAngle, 20, "Reversed attachments apply the positive-side authored limit")
near(swappedInput, 20 / math.deg(Config.MaxHandlebarAngle), "Reversed limited Servo preserves correct chassis turn direction")
near(Physics.GetYawRate(limitInput, 15), -15 * math.tan(math.rad(10)) / Config.WheelBase,
	"Limited Servo supplies the actual wheel curvature")
local neutral = Physics.GetServoSteering(0, false, true, -10, 20)
near(neutral, 0, "Neutral input remains neutral with authored limits")
local modelSteer = source.ScooterBody.HingeConstraint
modelSteer.LimitsEnabled, modelSteer.LowerAngle, modelSteer.UpperAngle = true, 5, 20
check(not pcall(Rig.Inspect, source), "Rig rejects steering limits excluding neutral")
modelSteer.LimitsEnabled = false

local speed, turn = 15, 0.3
local expectedYaw = -speed * math.tan(turn * Config.MaxHandlebarAngle) / Config.WheelBase
near(Physics.GetYawRate(turn, speed), expectedYaw, "Chassis yaw follows bicycle curvature")
local lean = Physics.GetSteeringLean(turn, speed, 196.2)
near(lean, math.atan2(speed * expectedYaw, 196.2), "Lean follows centripetal acceleration v*yawRate")
check(lean < 0, "Right turn rolls chassis inward to right")
near(Physics.GetSteeringLean(-turn, speed, 196.2), -lean, "Left turn mirrors right lean")
near(Physics.GetSteeringLean(Physics.GetTurnSteering(turn, -speed), -speed, 196.2), lean,
	"Reverse speed and reverse yaw retain inward lean")
check(math.abs(Physics.GetSteeringLean(turn, 25, 196.2)) > math.abs(lean),
	"Greater cornering speed increases roll")
near(Physics.GetSteeringLean(1, 100, 196.2), -Config.MaxSteeringLean, "High speed roll remains bounded")
near(Physics.GetSteeringLean(1, 0, 196.2), 0, "No lean at rest")
near(Physics.GetSteeringLean(0, speed, 196.2), 0, "No lean without turning")
near(Physics.GetSteeringLean(turn, speed, 0), 0, "Zero gravity safely disables lean")
local blended = Physics.SmoothSteeringLean(0, lean, 1 / 60)
check(blended < 0 and blended > lean, "Lean approaches target without a snap or overshoot")
local thirty = 0
local sixty = 0
for _ = 1, 30 do thirty = Physics.SmoothSteeringLean(thirty, lean, 1 / 30) end
for _ = 1, 60 do sixty = Physics.SmoothSteeringLean(sixty, lean, 1 / 60) end
near(thirty, sixty, "Lean smoothing is frame-rate independent")
near(Physics.SmoothSteeringLean(lean, 0, 0), lean, "Zero timestep retains roll")
check(math.abs(Physics.SmoothSteeringLean(lean, 0, 1 / 30)) < math.abs(lean),
	"Roll eases back on unsupported chassis or released steering")

print(string.format("PASS: %d scooter visual assertions (%d total)", testCount - visualStart, testCount))
