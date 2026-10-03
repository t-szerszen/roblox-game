local suspensionStart = testCount
local Suspension = loadModule("ServerScriptService/Scooter/ScooterSuspension")
local BrakeLight = loadModule("ServerScriptService/Scooter/ScooterBrakeLight")
local suspended = Rig.Prepare(source)
check(suspended:GetAttribute("SuspensionRevision") == Config.Suspension.Revision, "Prepared rigs are calibrated")
check(not Config.BrakeLight.Enabled and BrakeLight.Create(suspended) == nil, "No red fender or brake glow is created")
for _, constraint in suspended:GetDescendants() do
	if constraint:IsA("Constraint") then check(not constraint.Visible, "Physical constraint visualization is hidden") end
end

local function wheelUpAt(model, endName, angle)
	local parent = if endName == "Front" then model.HandleBarStick else model.ScooterBody
	local fixed = parent["PivotAttBase_" .. endName .. "SuspensionLeft"]
	local offset = model[endName .. "Wheel"].WheelCenter.WorldPosition - fixed.WorldPosition
	local rotated = Frame.fromAxisAngle(fixed.WorldAxis, angle):VectorToWorldSpace(offset)
	return rotated.Y - offset.Y
end

local function torqueAt(model, endName, angle)
	local parent = if endName == "Front" then model.HandleBarStick else model.ScooterBody
	local pivot = parent["PivotAttBase_" .. endName .. "SuspensionLeft"]
	local axis = pivot.WorldAxis
	local torque = 0
	for _, side in { "Left", "Right" } do
		local suffix = endName .. "Suspension" .. side
		local spring = parent["ShockAbsorber_" .. suffix]
		local moving = model[suffix]["SpringAtt_" .. suffix]
		local fixed = parent["SpringAttBase_" .. suffix]
		local offset = moving.WorldPosition - pivot.WorldPosition
		local rotated = Frame.fromAxisAngle(axis, angle):VectorToWorldSpace(offset)
		local delta = pivot.WorldPosition + rotated - fixed.WorldPosition
		local force = delta.Unit * spring.Stiffness * (spring.FreeLength - delta.Magnitude)
		torque += axis:Dot(rotated:Cross(force))
	end
	return torque
end

for _, endName in { "Front", "Back" } do
	local parent = if endName == "Front" then suspended.HandleBarStick else suspended.ScooterBody
	local left = parent["PivotHinge_" .. endName .. "SuspensionLeft"]
	local right = parent["PivotHinge_" .. endName .. "SuspensionRight"]
	check(left.LimitsEnabled and left.ActuatorType == enumMock.ActuatorType.None,
		"Suspension travel is physically bounded by passive pivots")
	check(left.LowerAngle < 0 and left.UpperAngle > 0 and left.Restitution == 0,
		"Stops allow both compression and droop without bounce")
	near(left.LowerAngle, right.LowerAngle, "Coaxial pivots share lower stop")
	near(left.UpperAngle, right.UpperAngle, "Coaxial pivots share upper stop")
	local lower, upper = math.rad(left.LowerAngle), math.rad(left.UpperAngle)
	check(wheelUpAt(suspended, endName, lower) * wheelUpAt(suspended, endName, upper) < 0,
		"Wheel can move above and below its authored pose")
	local neutralTorque = torqueAt(suspended, endName, 0)
	for _, angle in { lower, upper } do
		check((torqueAt(suspended, endName, angle) - neutralTorque) * angle < 0,
			"Both travel limits retain a restoring spring response")
	end
	local spring = parent["ShockAbsorber_" .. endName .. "SuspensionLeft"]
	local restLength = spring:GetAttribute("SuspensionRestLength")
	check(restLength > spring.MinLength and restLength < spring.MaxLength,
		"Spring length stops do not lock the neutral pose")
	check(spring.Stiffness > 0 and spring.Damping > 0 and spring.MaxForce < math.huge,
		"Shocks have positive calibrated stiffness/damping and bounded force")
end
local rear = suspended.ScooterBody.PivotHinge_BackSuspensionLeft
check(rear.UpperAngle < 45 and rear.LowerAngle > -45, "Rear arm cannot fold above the chassis")
check(Config.Suspension.Front.SagFraction > Config.Suspension.Back.SagFraction,
	"Front wheel target is softer relative to its available stroke")
local beforeSpring = suspended.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness
local beforeLimit = rear.UpperAngle
local again = Rig.Prepare(suspended)
near(again.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness, beforeSpring, "Runtime cloning preserves tuning")
near(again.ScooterBody.PivotHinge_BackSuspensionLeft.UpperAngle, beforeLimit, "Runtime cloning preserves rest stops")

local reversed = source:Clone()
local hinge = reversed.HandleBarStick.PivotHinge_FrontSuspensionLeft
hinge.Attachment0, hinge.Attachment1 = hinge.Attachment1, hinge.Attachment0
local reversedRig = Rig.Prepare(reversed)
near(reversedRig.HandleBarStick.PivotHinge_FrontSuspensionLeft.LowerAngle,
	-suspended.HandleBarStick.PivotHinge_FrontSuspensionLeft.UpperAngle, "Swapped hinge endpoints invert lower limit")
near(reversedRig.HandleBarStick.PivotHinge_FrontSuspensionLeft.UpperAngle,
	-suspended.HandleBarStick.PivotHinge_FrontSuspensionLeft.LowerAngle, "Swapped hinge endpoints invert upper limit")

local noLeverage = source:Clone()
local moving = noLeverage.FrontSuspensionLeft.SpringAtt_FrontSuspensionLeft
moving.Position = noLeverage.FrontSuspensionLeft.PivotAtt_FrontSuspensionLeft.Position
check(not pcall(Rig.Prepare, noLeverage), "Spring at pivot is rejected rather than assigned extreme stiffness")
check(not noLeverage:FindFirstChild("Root"), "Failed calibration preserves authored source")

local riderMass = Config.Suspension.ReferenceRiderMass
Config.Suspension.ReferenceRiderMass = riderMass * 2
local heavier = Rig.Prepare(source)
Config.Suspension.ReferenceRiderMass = riderMass
local massRatio = heavier:GetAttribute("SuspensionReferenceMass") / suspended:GetAttribute("SuspensionReferenceMass")
near(heavier.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness / beforeSpring, massRatio,
	"Spring stiffness scales with supported design mass")
near(heavier.ScooterBody.ShockAbsorber_BackSuspensionLeft.Damping
	/ suspended.ScooterBody.ShockAbsorber_BackSuspensionLeft.Damping, massRatio,
	"Both ends retain their damping response when design mass changes")

local repairModule = make(serverFolder, "ModuleScript", "DevScooterRepair")
repairModule._values._path = "ServerScriptService/Scooter/DevScooterRepair"
moduleCache["ServerScriptService/Scooter/DevScooterRepair"] = {
	RepairSelection = function() error("outdated cached wrapper missing ScooterSuspension") end,
}
services.Selection.Get = function() return { suspended } end
suspended.Parent = services.ServerStorage
local count = #serverFolder:GetChildren()
local apply = loadModule("ServerScriptService/Scooter/DevScooterSuspension")
local applied = apply.Apply()
check(applied:GetAttribute("SuspensionRevision") == Config.Suspension.Revision,
	"Suspension entry point bypasses outdated cached repair wrapper")
check(#serverFolder:GetChildren() == count, "Suspension entry point cleans up fresh repair module")
services.Selection.Get = function() return { noLeverage } end
check(not pcall(apply.Apply), "Suspension entry point propagates invalid mounting geometry")
check(#serverFolder:GetChildren() == count, "Suspension entry point cleans up failed repair module")
print(string.format("PASS: %d suspension assertions (%d total)", testCount - suspensionStart, testCount))
