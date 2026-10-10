--!strict

local Config = require(script.Parent.ScooterConfig)

type Joint = {
	instance: Motor6D | AnimationConstraint,
	c0: CFrame,
	c1: CFrame,
	original: CFrame,
}
type Limb = {
	first: Joint,
	middle: Joint,
	last: Joint,
	endPart: BasePart,
}
export type Rig = {
	rootPart: BasePart,
	root: Joint,
	waist: Joint,
	neck: Joint,
	limbs: { [string]: Limb },
}

local BasePose = {}
local EPSILON = 1e-5

local function joint(character: Model, name: string, parentName: string, childName: string): Joint?
	local parent = character:FindFirstChild(parentName)
	local child = character:FindFirstChild(childName)
	if not parent or not child then return nil end
	-- Upgraded R15 avatars use attachment frames instead of Motor6D.C0/C1.
	for _, className in { "AnimationConstraint", "Motor6D" } do
		for _, item in child:GetChildren() do
			if item.Name ~= name or not item:IsA(className) then continue end
			if item:IsA("AnimationConstraint") then
				local a0, a1 = item.Attachment0, item.Attachment1
				if a0 and a1 and a0.Parent == parent and a1.Parent == child then
					return { instance = item, c0 = a0.CFrame, c1 = a1.CFrame, original = item.Transform }
				end
			elseif item:IsA("Motor6D") and item.Part0 == parent and item.Part1 == child then
				return { instance = item, c0 = item.C0, c1 = item.C1, original = item.Transform }
			end
		end
		-- Motor6D can live in the parent rather than its driven part.
		if className == "Motor6D" then
			for _, item in parent:GetChildren() do
				if item:IsA("Motor6D") and item.Name == name and item.Part0 == parent and item.Part1 == child then
					return { instance = item, c0 = item.C0, c1 = item.C1, original = item.Transform }
				end
			end
		end
	end
	return nil
end

function BasePose.Bind(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15
		or not rootPart or not rootPart:IsA("BasePart") then return nil end
	local root = joint(character, "Root", "HumanoidRootPart", "LowerTorso")
	local waist = joint(character, "Waist", "LowerTorso", "UpperTorso")
	local neck = joint(character, "Neck", "UpperTorso", "Head")
	if not root or not waist or not neck then return nil end
	local limbs: { [string]: Limb } = {}
	for _, side in { "Left", "Right" } do
		for _, kind in { "Arm", "Leg" } do
			local isArm = kind == "Arm"
			local endName = side .. (if isArm then "Hand" else "Foot")
			local first = joint(character, side .. (if isArm then "Shoulder" else "Hip"),
				if isArm then "UpperTorso" else "LowerTorso", side .. "Upper" .. kind)
			local middle = joint(character, side .. (if isArm then "Elbow" else "Knee"),
				side .. "Upper" .. kind, side .. "Lower" .. kind)
			local last = joint(character, side .. (if isArm then "Wrist" else "Ankle"),
				side .. "Lower" .. kind, endName)
			local endPart = character:FindFirstChild(endName)
			if not first or not middle or not last or not endPart or not endPart:IsA("BasePart") then return nil end
			if (middle.c0.Position - first.c1.Position).Magnitude < EPSILON
				or (last.c0.Position - middle.c1.Position).Magnitude < EPSILON then return nil end
			limbs[endName] = { first = first, middle = middle, last = last, endPart = endPart }
		end
	end
	return { rootPart = rootPart, root = root, waist = waist, neck = neck, limbs = limbs }
end

local function setTransform(j: Joint, value: CFrame)
	local instance = j.instance
	if instance:IsA("Motor6D") then
		instance.Transform = value
	else
		instance.Transform = value
	end
end

local function setJoint(j: Joint, parentFrame: CFrame, childFrame: CFrame)
	setTransform(j, (parentFrame * j.c0):ToObjectSpace(childFrame * j.c1))
end

local function boneFrame(start: Vector3, finish: Vector3, localStart: Vector3, localFinish: Vector3, reference: CFrame): CFrame
	local from = reference:VectorToWorldSpace(localFinish - localStart).Unit
	local to = (finish - start).Unit
	local axis = from:Cross(to)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local rotation = CFrame.identity
	if axis.Magnitude > EPSILON then
		rotation = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
	elseif dot < 0 then
		rotation = CFrame.fromAxisAngle(reference.RightVector, math.pi)
	end
	return CFrame.new(start) * rotation * reference.Rotation * CFrame.new(-localStart)
end

local function solve(limb: Limb, parentFrame: CFrame, desiredEnd: CFrame, pole: Vector3): number
	local start = (parentFrame * limb.first.c0).Position
	local finish = (desiredEnd * limb.last.c1).Position
	local firstLength = (limb.middle.c0.Position - limb.first.c1.Position).Magnitude
	local secondLength = (limb.last.c0.Position - limb.middle.c1.Position).Magnitude
	local delta = finish - start
	local distance = delta.Magnitude
	if distance < EPSILON then return math.huge end
	local direction = delta.Unit
	local reachableDistance = math.clamp(distance, math.abs(firstLength - secondLength) + EPSILON,
		firstLength + secondLength - EPSILON)
	local along = (firstLength * firstLength - secondLength * secondLength + reachableDistance * reachableDistance)
		/ (2 * reachableDistance)
	local height = math.sqrt(math.max(0, firstLength * firstLength - along * along))
	local poleDirection = pole - start
	local bend = poleDirection - direction * poleDirection:Dot(direction)
	if bend.Magnitude < EPSILON then
		bend = parentFrame.RightVector - direction * parentFrame.RightVector:Dot(direction)
		if bend.Magnitude < EPSILON then bend = parentFrame.UpVector:Cross(direction) end
	end
	local middle = start + direction * along + bend.Unit * height
	local endPosition = start + direction * reachableDistance
	local firstFrame = boneFrame(start, middle, limb.first.c1.Position, limb.middle.c0.Position, parentFrame)
	local secondFrame = boneFrame(middle, endPosition, limb.middle.c1.Position, limb.last.c0.Position, parentFrame)
	-- Unreachable avatars retain joint lengths; no limb stretching or avatar scaling.
	local endFrame = desiredEnd + (endPosition - finish)
	setJoint(limb.first, parentFrame, firstFrame)
	setJoint(limb.middle, firstFrame, secondFrame)
	setJoint(limb.last, secondFrame, endFrame)
	return math.abs(distance - reachableDistance)
end

local function solveArm(limb: Limb, parentFrame: CFrame, desiredEnd: CFrame, pole: Vector3): number
	local start = (parentFrame * limb.first.c0).Position
	local finish = (desiredEnd * limb.last.c1).Position
	local delta = finish - start
	if delta.Magnitude < EPSILON then return math.huge end
	local direction = delta.Unit
	local firstVector = limb.middle.c0.Position - limb.first.c1.Position
	local secondVector = (limb.middle.c0.Rotation * limb.middle.c1.Rotation:Inverse())
		:VectorToWorldSpace(limb.last.c0.Position - limb.middle.c1.Position)
	local axis = limb.middle.c0.RightVector
	local firstAxial, secondAxial = firstVector:Dot(axis), secondVector:Dot(axis)
	local firstPlanar = firstVector - axis * firstAxial
	local secondPlanar = secondVector - axis * secondAxial
	local cosine = firstPlanar:Dot(secondPlanar)
	local sine = firstPlanar:Dot(axis:Cross(secondPlanar))
	local amplitude = math.sqrt(cosine * cosine + sine * sine)
	if amplitude < EPSILON then return math.huge end
	local constant = firstVector:Dot(firstVector) + secondVector:Dot(secondVector) + 2 * firstAxial * secondAxial
	local desiredCosine = (delta:Dot(delta) - constant) / (2 * amplitude)
	local angle = math.atan2(sine, cosine) + math.acos(math.clamp(desiredCosine, -1, 1))
	local elbowRotation = CFrame.Angles(angle, 0, 0)
	local combined = firstVector + (limb.middle.c0.Rotation * elbowRotation * limb.middle.c1.Rotation:Inverse())
		:VectorToWorldSpace(limb.last.c0.Position - limb.middle.c1.Position)
	local reachableFinish = start + direction * combined.Magnitude
	local firstFrame = boneFrame(start, reachableFinish, limb.first.c1.Position,
		limb.first.c1.Position + combined, parentFrame)
	local elbow = firstFrame:PointToWorldSpace(limb.middle.c0.Position) - start
	local elbowPlanar = elbow - direction * elbow:Dot(direction)
	local target = pole - start
	local targetPlanar = target - direction * target:Dot(direction)
	if elbowPlanar.Magnitude > EPSILON and targetPlanar.Magnitude > EPSILON then
		local twist = math.atan2(direction:Dot(elbowPlanar:Cross(targetPlanar)), elbowPlanar:Dot(targetPlanar))
		firstFrame = CFrame.new(start) * CFrame.fromAxisAngle(direction, twist)
			* (firstFrame - start)
	end
	local secondFrame = firstFrame * limb.middle.c0 * elbowRotation * limb.middle.c1:Inverse()
	local endFrame = desiredEnd + (reachableFinish - finish)
	setJoint(limb.first, parentFrame, firstFrame)
	-- An elbow bends on its authored hinge axis. Independent segment rotations
	-- introduce elbow twist and expose the mesh seam even when pivots coincide.
	setTransform(limb.middle, elbowRotation)
	setJoint(limb.last, secondFrame, endFrame)
	return math.abs(delta.Magnitude - combined.Magnitude)
end

function BasePose.Update(rig: Rig, scooter: Model): number
	local root = scooter.PrimaryPart
	local deck = scooter:FindFirstChild("FootRest", true)
	local bar = scooter:FindFirstChild("HandleBar", true)
	if not root or not deck or not deck:IsA("BasePart") or not bar or not bar:IsA("BasePart") then return math.huge end
	local leftGrip, rightGrip = bar:FindFirstChild("LeftHandGrip"), bar:FindFirstChild("RightHandGrip")
	if not leftGrip or not leftGrip:IsA("Attachment") or not rightGrip or not rightGrip:IsA("Attachment") then
		return math.huge
	end
	local settings = Config.BaseRidingPose
	local seat = scooter:FindFirstChild("DriverSeat")
	local weld = if seat then seat:FindFirstChild("SeatWeld") else nil
	-- The server-owned character and chassis can be interpolated at different
	-- instants. Derive both sides of the pose from the same native seat frame.
	local rootFrame = if seat and seat:IsA("BasePart") and weld and weld:IsA("Weld")
		and weld.Part0 == seat and weld.Part1 == rig.rootPart
		then seat.CFrame * weld.C0 * weld.C1:Inverse() else rig.rootPart.CFrame
	local lower = rootFrame * rig.root.c0 * rig.root.c1:Inverse()
	local upper = lower * rig.waist.c0 * CFrame.Angles(-settings.TorsoLean, 0, 0) * rig.waist.c1:Inverse()
	setTransform(rig.root, CFrame.identity)
	setTransform(rig.waist, CFrame.Angles(-settings.TorsoLean, 0, 0))
	setTransform(rig.neck, CFrame.Angles(settings.TorsoLean, 0, 0))
	local deckFrame = root.CFrame:ToObjectSpace(deck.CFrame)
	local width = math.abs(deckFrame.RightVector.X) * deck.Size.X
		+ math.abs(deckFrame.UpVector.X) * deck.Size.Y + math.abs(deckFrame.LookVector.X) * deck.Size.Z
	local length = math.abs(deckFrame.RightVector.Z) * deck.Size.X
		+ math.abs(deckFrame.UpVector.Z) * deck.Size.Y + math.abs(deckFrame.LookVector.Z) * deck.Size.Z
	local deckTop = deckFrame.Position.Y + (math.abs(deckFrame.RightVector.Y) * deck.Size.X
		+ math.abs(deckFrame.UpVector.Y) * deck.Size.Y + math.abs(deckFrame.LookVector.Y) * deck.Size.Z) * 0.5
	local error = 0
	for _, side in { "Left", "Right" } do
		local sign = if side == "Left" then -1 else 1
		local leg = rig.limbs[side .. "Foot"]
		local foot = leg.endPart
		local lateral = math.max(0, math.min(settings.FootLateralOffset, (width - foot.Size.X) * 0.5 - settings.DeckMargin))
		local pitch = if side == "Left" then settings.FrontFootPitch else settings.RearFootPitch
		local projectedLength = math.abs(math.cos(pitch)) * foot.Size.Z + math.abs(math.sin(pitch)) * foot.Size.Y
		local projectedHeight = math.abs(math.cos(pitch)) * foot.Size.Y + math.abs(math.sin(pitch)) * foot.Size.Z
		local longitudinal = math.max(0, (length - projectedLength) * 0.5 - settings.DeckMargin)
		local footFrame = root.CFrame * CFrame.new(deckFrame.Position.X + sign * lateral,
			deckTop + Config.RiderDeckClearance + projectedHeight * 0.5, deckFrame.Position.Z + sign * longitudinal)
			* CFrame.Angles(pitch, 0, 0)
		local kneePole = root.CFrame:PointToWorldSpace(Vector3.new(sign * width * 0.5, deckTop + 2, -length))
		error = math.max(error, solve(leg, lower, footFrame, kneePole))
		local arm = rig.limbs[side .. "Hand"]
		local grip = if side == "Left" then leftGrip else rightGrip
		-- Use the palm's authored grip frame, rather than assuming the mesh axes
		-- or grip attachment rotation matches the character's forward direction.
		local palm = arm.endPart:FindFirstChild(side .. "GripAttachment")
		local palmOffset = if palm and palm:IsA("Attachment") then palm.CFrame else CFrame.identity
		-- The imported bar points along -X. Its corrected frame follows the
		-- actual steering hinge, so palms cannot twist against moving grips.
		local handOrientation = bar.CFrame.Rotation * CFrame.Angles(0, math.pi, 0)
		local handFrame = CFrame.new(grip.WorldPosition) * handOrientation
			* CFrame.Angles(settings.HandPalmPitch, 0, 0) * palmOffset:Inverse()
		local elbowPole = root.CFrame:PointToWorldSpace(Vector3.new(sign * settings.ElbowPoleWidth, deckTop + settings.ElbowPoleHeight, -settings.ElbowPoleForwardOffset))
		error = math.max(error, solveArm(arm, upper, handFrame, elbowPole))
	end
	return error
end

function BasePose.Restore(rig: Rig)
	for _, j in { rig.root, rig.waist, rig.neck } do
		if j.instance.Parent then setTransform(j, j.original) end
	end
	for _, limb in rig.limbs do
		for _, j in { limb.first, limb.middle, limb.last } do
			if j.instance.Parent then setTransform(j, j.original) end
		end
	end
end

return BasePose
