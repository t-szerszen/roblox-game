--!strict
local Config = require(game:GetService("ReplicatedStorage").Shared.CharacterConfig)
local Proportions = {}

function Proportions.Apply(character: Model): boolean
	if character:GetAttribute(Config.ReadyAttribute) == true then return true end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then return false end
	local changes: { { joint: Instance, frame: CFrame, offset: Vector3, source: Attachment? } } = {}
	local maximumAdded = 0
	for _, side in { "Left", "Right" } do
		local added = 0
		for _, pair in { { "UpperLeg", "Hip", "Knee" }, { "LowerLeg", "Knee", "Ankle" } } do
			local part = character:FindFirstChild(side .. pair[1])
			local start = if part then part:FindFirstChild(side .. pair[2] .. "RigAttachment") else nil
			local joint = character:FindFirstChild(side .. pair[3], true)
			if not part or not part:IsA("BasePart") or not start or not start:IsA("Attachment") or not joint then return false end
			local source: Attachment? = nil
			local frame: CFrame
			if joint:IsA("AnimationConstraint") then
				source = joint.Attachment0
				if not source or source.Parent ~= part then return false end
				frame = source.CFrame
			elseif joint:IsA("Motor6D") then
				if joint.Part0 ~= part then return false end
				frame = joint.C0
			else return false end
			local bone = frame.Position - start.Position
			if bone.Magnitude < 0.01 then return false end
			local extra = math.max(0, part.Size.Y * Config.LegBoneLengthFraction - bone.Magnitude)
			table.insert(changes, { joint = joint, frame = frame, offset = bone.Unit * extra, source = source })
			added += extra
		end
		maximumAdded = math.max(maximumAdded, added)
	end
	for _, change in changes do
		local joint = change.joint
		if joint:IsA("Motor6D") then
			joint.C0 = change.frame + change.offset
		elseif joint:IsA("AnimationConstraint") then
			local source = change.source :: Attachment
			-- Keep Roblox's RigAttachment metadata intact for animation retargeting.
			local rest = Instance.new("Attachment")
			rest.Name = Config.JointPrefix .. joint.Name
			rest.CFrame = change.frame + change.offset
			rest.Parent = source.Parent
			joint.Attachment0 = rest
			for _, socket in (source.Parent :: Instance):GetChildren() do
				if socket:IsA("BallSocketConstraint") and socket.Attachment0 == source then socket.Attachment0 = rest end
			end
			-- Socket instances usually live on the child segment.
			local child = joint.Attachment1 and joint.Attachment1.Parent
			if child then
				for _, socket in child:GetChildren() do
					if socket:IsA("BallSocketConstraint") and socket.Attachment0 == source then socket.Attachment0 = rest end
				end
			end
		end
	end
	humanoid.HipHeight += maximumAdded
	character:SetAttribute(Config.LengthAttribute, maximumAdded)
	character:SetAttribute(Config.ReadyAttribute, true)
	return true
end
return Proportions
