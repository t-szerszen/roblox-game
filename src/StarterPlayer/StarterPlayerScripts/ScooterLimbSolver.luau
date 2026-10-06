--!strict

type Joint = Motor6D | AnimationConstraint
type Link = { joint: Joint, first: BasePart, second: BasePart, c0: CFrame, c1: CFrame }
type Limb = { top: Link, middle: Link, tip: Link, length0: number, length1: number, isLeg: boolean }
export type Controller = {
	HasLimb: (name: string) -> boolean,
	Apply: (upper: CFrame?, lower: CFrame?, targets: { [string]: Attachment }, poles: { [string]: Attachment }, legs: boolean) -> (),
	Destroy: () -> (),
}
local Solver = {}

-- Rotate the actual rest-bone axis; assuming local -Y displaces joints and twists blocky meshes.
local function segmentFrame(origin: Vector3, endPoint: Vector3, right: Vector3, bone: Vector3): CFrame
	local restUp = -bone.Unit
	local restRight = Vector3.xAxis - restUp * restUp:Dot(Vector3.xAxis)
	if restRight.Magnitude < 0.001 then restRight = Vector3.zAxis - restUp * restUp:Dot(Vector3.zAxis) end
	local rest = CFrame.fromMatrix(Vector3.zero, restRight.Unit, restUp)
	return CFrame.fromMatrix(origin, right, (origin - endPoint).Unit) * rest:Inverse()
end

local function setTransform(joint: Joint, transform: CFrame)
	if joint:IsA("Motor6D") then joint.Transform = transform
	else (joint :: AnimationConstraint).Transform = transform end
end

local function link(character: Model, name: string): Link?
	local joint = character:FindFirstChild(name, true)
	if joint and joint:IsA("AnimationConstraint") then
		local first, second = joint.Attachment0, joint.Attachment1
		if first and second and first.Parent and second.Parent
			and first.Parent:IsA("BasePart") and second.Parent:IsA("BasePart") then
			return { joint = joint, first = first.Parent, second = second.Parent, c0 = first.CFrame, c1 = second.CFrame }
		end
	elseif joint and joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
		return { joint = joint, first = joint.Part0, second = joint.Part1, c0 = joint.C0, c1 = joint.C1 }
	end
	return nil
end

function Solver.JointPose(joint: Joint?, parentFrame: CFrame): CFrame?
	if not joint then return nil end
	if joint:IsA("AnimationConstraint") then
		if joint.Attachment0 and joint.Attachment1 then
			return parentFrame * joint.Attachment0.CFrame * joint.Transform * joint.Attachment1.CFrame:Inverse()
		end
	elseif joint.Part0 and joint.Part1 then
		return parentFrame * joint.C0 * joint.Transform * joint.C1:Inverse()
	end
	return nil
end

function Solver.Knee(origin: Vector3, goal: Vector3, pole: Vector3, firstLength: number, secondLength: number): (Vector3, Vector3)
	local line = goal - origin
	local direction = if line.Magnitude > 0.001 then line.Unit else -Vector3.yAxis
	local distance = math.clamp(line.Magnitude, math.abs(firstLength - secondLength) + 0.001, firstLength + secondLength - 0.001)
	local bend = pole - origin
	bend -= direction * bend:Dot(direction)
	if bend.Magnitude < 0.001 then
		local fallback = if math.abs(direction:Dot(Vector3.zAxis)) < 0.9 then Vector3.zAxis else Vector3.xAxis
		bend = fallback - direction * fallback:Dot(direction)
	end
	bend = bend.Unit
	local along = (firstLength^2 + distance^2 - secondLength^2) / (2 * distance)
	local across = math.sqrt(math.max(0, firstLength^2 - along^2))
	return origin + direction * along + bend * across, origin + direction * distance
end

function Solver.Start(character: Model): Controller
	local limbs: { [string]: Limb } = {}
	local saved: { [Joint]: CFrame } = {}
	for _, side in { "Left", "Right" } do
		for _, definition in { { "Hand", "Shoulder", "Elbow", "Wrist" }, { "Foot", "Hip", "Knee", "Ankle" } } do
			local top, middle, tip = link(character, side .. definition[2]), link(character, side .. definition[3]), link(character, side .. definition[4])
			if top and middle and tip then
				local firstLength = (middle.c0.Position - top.c1.Position).Magnitude
				local secondLength = (tip.c0.Position - middle.c1.Position).Magnitude
				if firstLength > 0.01 and secondLength > 0.01 then
					limbs[side .. definition[1]] = { top = top, middle = middle, tip = tip,
						length0 = firstLength, length1 = secondLength, isLeg = definition[1] == "Foot" }
					for _, item in { top, middle, tip } do saved[item.joint] = item.joint.Transform end
				end
			end
		end
	end
	local destroyed = false
	return {
		HasLimb = function(name) return limbs[name] ~= nil end,
		Apply = function(upper, lower, targets, poles, legs)
			if destroyed then return end
			for name, limb in limbs do
				if limb.isLeg and not legs then continue end
				local target = targets[name]
				if not target then continue end
				local parent = (if limb.isLeg then lower else upper) or limb.top.first.CFrame
				local origin = (parent * limb.top.c0).Position
				local desired = target.WorldCFrame
				local goal = (desired * limb.tip.c1).Position
				local length0, length1 = limb.length0, limb.length1
				local pole = poles[name]
				local polePosition = if pole then
					(if pole.Parent == limb.top.first then parent:PointToWorldSpace(pole.Position) else pole.WorldPosition)
					else origin + parent.LookVector * 2
				local knee, endPoint = Solver.Knee(origin, goal, polePosition, length0, length1)
				desired += endPoint - goal
				local axis = (endPoint - origin).Unit
				local bend = knee - origin - axis * (knee - origin):Dot(axis)
				local right = axis:Cross(bend)
				if right.Magnitude < 0.001 then
					right = axis:Cross(if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis)
				end
				right = right.Unit
				local topFrame = segmentFrame(origin, knee, right, limb.middle.c0.Position - limb.top.c1.Position) * CFrame.new(-limb.top.c1.Position)
				local middleFrame = segmentFrame(knee, endPoint, right, limb.tip.c0.Position - limb.middle.c1.Position) * CFrame.new(-limb.middle.c1.Position)
				setTransform(limb.top.joint, (parent * limb.top.c0):Inverse() * topFrame * limb.top.c1)
				setTransform(limb.middle.joint, (topFrame * limb.middle.c0):Inverse() * middleFrame * limb.middle.c1)
				setTransform(limb.tip.joint, (middleFrame * limb.tip.c0):Inverse() * desired * limb.tip.c1)
			end
		end,
		Destroy = function()
			if destroyed then return end
			destroyed = true
			for joint, transform in saved do if joint.Parent then setTransform(joint, transform) end end
			table.clear(saved)
			table.clear(limbs)
		end,
	}
end

return Solver
