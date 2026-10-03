local start = testCount
local Geometry = loadModule("ServerScriptService/Scooter/ScooterRigGeometry")
local Suspension = loadModule("ServerScriptService/Scooter/ScooterSuspension")
local original = source:Clone()
for _, side in { "Left", "Right" } do
	local point = original["FrontSuspension" .. side]["PivotAtt_FrontSuspension" .. side]
	point.Position += Vector.new(0, -0.25, 0)
end
local correctedSource = original:Clone()
Geometry.Repair(correctedSource)
check(#Geometry.Check(correctedSource).errors == 0, "Full repair supports misplaced front base mounts")
near(correctedSource.FrontSuspensionLeft.PivotAtt_FrontSuspensionLeft.Position.Y, -0.25,
	"Full repair preserves the arm's deck-side pivot position")
near(correctedSource.HandleBarStick.PivotAttBase_FrontSuspensionLeft.Position.Y, -0.25,
	"Fixed mount follows authored arm pivot, rather than moving the arm pivot to the column")

local legacy = Rig.Prepare(source)
for _, side in { "Left", "Right" } do
	legacy["FrontSuspension" .. side]["PivotAtt_FrontSuspension" .. side]:SetAttribute("AuthoredPivotCFrame", nil)
end
local rear = legacy.ScooterBody.ShockAbsorber_BackSuspensionLeft
rear.Stiffness *= 1.1 -- Preserve even custom tuning, not just default rear calculations.
local before = {
	stiffness = rear.Stiffness, damping = rear.Damping, free = rear.FreeLength,
	min = rear.MinLength, max = rear.MaxLength, force = rear.MaxForce,
	restLength = rear:GetAttribute("SuspensionRestLength"),
	pivot = legacy.BackSuspensionLeft.PivotAtt_BackSuspensionLeft.CFrame,
	base = legacy.ScooterBody.PivotAttBase_BackSuspensionLeft.CFrame,
	lower = legacy.ScooterBody.PivotHinge_BackSuspensionLeft.LowerAngle,
	upper = legacy.ScooterBody.PivotHinge_BackSuspensionLeft.UpperAngle,
	steerBase = legacy.ScooterBody.SteerBase.CFrame, steerPivot = legacy.HandleBarStick.SteerPivot.CFrame,
	steerAngle = legacy.ScooterBody.HingeConstraint.TargetAngle,
	mass = legacy:GetAttribute("SuspensionReferenceMass"),
	body = legacy.ScooterBody.CFrame, wheel = legacy.FrontWheel.CFrame,
}

local function checkRear(model)
	local shock = model.ScooterBody.ShockAbsorber_BackSuspensionLeft
	for property, value in { Stiffness = before.stiffness, Damping = before.damping, FreeLength = before.free,
		MinLength = before.min, MaxLength = before.max, MaxForce = before.force } do
		near(shock[property], value, "Front repair preserves rear " .. property)
	end
	near(shock:GetAttribute("SuspensionRestLength"), before.restLength, "Rear rest reference is preserved")
	check(model.BackSuspensionLeft.PivotAtt_BackSuspensionLeft.CFrame == before.pivot
		and model.ScooterBody.PivotAttBase_BackSuspensionLeft.CFrame == before.base, "Rear pivot frames are preserved")
	near(model.ScooterBody.PivotHinge_BackSuspensionLeft.LowerAngle, before.lower, "Rear lower stop preserved")
	near(model.ScooterBody.PivotHinge_BackSuspensionLeft.UpperAngle, before.upper, "Rear upper stop preserved")
end

check(not pcall(Geometry.RepairFront, legacy:Clone()), "Legacy template cannot guess lost authored pivot locations")
for _, part in original:GetChildren() do
	if part:IsA("BasePart") then
		part.CFrame = Frame.Angles(0, 0.7, 0) * part.CFrame + Vector.new(50, 20, 8)
	end
end
Geometry.RepairFront(legacy, original)
Suspension.ConfigureFront(legacy)
checkRear(legacy)
check(#Geometry.Check(legacy).errors == 0, "Corrected front passes geometric validation")
check(legacy.ScooterBody.CFrame == before.body and legacy.FrontWheel.CFrame == before.wheel,
	"Mount repair leaves mesh poses intact")
check(legacy.ScooterBody.SteerBase.CFrame == before.steerBase
	and legacy.HandleBarStick.SteerPivot.CFrame == before.steerPivot, "Steering axis remains intact")
near(legacy.ScooterBody.HingeConstraint.TargetAngle, before.steerAngle, "Steering target remains intact")
near(legacy:GetAttribute("SuspensionReferenceMass"), before.mass, "Front repair uses existing calibrated mass")
for _, side in { "Left", "Right" } do
	local armPoint = legacy["FrontSuspension" .. side]["PivotAtt_FrontSuspension" .. side]
	local fixed = legacy.HandleBarStick["PivotAttBase_FrontSuspension" .. side]
	near((armPoint.WorldPosition - fixed.WorldPosition).Magnitude, 0, "Arm stays attached at its visible mounting center")
	near(armPoint.Position.Y, -0.25, "Deck-side original pivot is restored")
	check(fixed.Parent == legacy.HandleBarStick, "Suspension base remains on the steering assembly")
	near(original["FrontSuspension" .. side]["PivotAtt_FrontSuspension" .. side].Position.Y, -0.25,
		"Reference geometry is read-only")
end

local pivot = legacy.HandleBarStick.PivotAttBase_FrontSuspensionLeft
local hinge = legacy.HandleBarStick.PivotHinge_FrontSuspensionLeft
local offset = legacy.FrontWheel.WheelCenter.WorldPosition - pivot.WorldPosition
local lower = math.rad(hinge.LowerAngle)
local upper = math.rad(hinge.UpperAngle)
local down = Frame.fromAxisAngle(pivot.WorldAxis, lower):VectorToWorldSpace(offset).Y - offset.Y
local up = Frame.fromAxisAngle(pivot.WorldAxis, upper):VectorToWorldSpace(offset).Y - offset.Y
check(down * up < 0, "Restored front mount allows wheel compression and droop around the fixed deck-side pivot")
local noRevision = legacy:Clone()
noRevision:SetAttribute("SuspensionRevision", nil)
check(not pcall(Suspension.ConfigureFront, noRevision), "Front-only tuning refuses an uncalibrated rear")
local diagonal = original:Clone()
diagonal.FrontSuspensionRight.PivotAtt_FrontSuspensionRight.Position += Vector.new(0, 0.5, 0)
check(not pcall(Geometry.RepairFront, legacy:Clone(), diagonal), "Misaligned arm mounting centers are rejected")

-- Exercise install, module cache bypass and failure rollback with actual module sources.
for _, side in { "Left", "Right" } do
	legacy["FrontSuspension" .. side]["PivotAtt_FrontSuspension" .. side]:SetAttribute("AuthoredPivotCFrame", nil)
end
legacy.Parent = services.ServerStorage
original.Parent = services.ServerStorage
services.Selection.Get = function() return { original, legacy } end
local count = #serverFolder:GetChildren()
local apply = loadModule("ServerScriptService/Scooter/DevScooterFrontMount")
local installed = apply.Apply()
check(installed.Parent == services.ServerStorage.ScooterModels, "Front repair installs validated replacement")
check(legacy.Parent == services.ServerStorage.ScooterRepairBackups, "Front repair retains previous template")
check(original.Parent == services.ServerStorage, "Front repair leaves reference source untouched")
checkRear(installed)
check(#serverFolder:GetChildren() == count, "Fresh front repair modules are cleaned up after success")
services.Selection.Get = function() return { installed } end
local repeated = apply.Apply()
checkRear(repeated)
near(repeated.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness,
	installed.HandleBarStick.ShockAbsorber_FrontSuspensionLeft.Stiffness, "Repeated repair retains the same front response")
services.Selection.Get = function() return { repeated, diagonal } end
check(not pcall(apply.Apply), "Invalid reference fails before replacing the template")
check(repeated.Parent == services.ServerStorage.ScooterModels, "Failed repair preserves installed template")
check(#serverFolder:GetChildren() == count, "Fresh modules are cleaned up after failure")
services.RunService.IsRunning = function() return true end
check(not pcall(apply.Apply), "Front mount edits cannot run during Play")
services.RunService.IsRunning = function() return false end
print(string.format("PASS: %d front mount assertions (%d total)", testCount - start, testCount))
