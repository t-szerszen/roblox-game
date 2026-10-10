--!nonstrict
-- Run on the client during Play with an occupied scooter, after Rojo sync.
-- Fixtures are detached; no template, map or production joints are modified.
local BasePose = require(game.ReplicatedStorage.Shared.Scooter.ScooterBasePose)
local Config = require(game.ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Tests = {}

function Tests.Run()
	local player = game.Players.LocalPlayer
	assert(player and player.Character, "Run in the Client datamodel during Play")
	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid.SeatPart
	assert(seat and seat.Name == "DriverSeat", "Mount your scooter first")
	local scooter = seat.Parent
	local root = scooter.PrimaryPart
	local count = 0
	local function check(value, message)
		assert(value, message)
		count += 1
	end
	local deckFrame = root.CFrame:ToObjectSpace(scooter.FootRest.CFrame)
	local deck = scooter.FootRest
	local halfWidth = (math.abs(deckFrame.RightVector.X) * deck.Size.X
		+ math.abs(deckFrame.UpVector.X) * deck.Size.Y + math.abs(deckFrame.LookVector.X) * deck.Size.Z) * .5
	local halfLength = (math.abs(deckFrame.RightVector.Z) * deck.Size.X
		+ math.abs(deckFrame.UpVector.Z) * deck.Size.Y + math.abs(deckFrame.LookVector.Z) * deck.Size.Z) * .5
	local top = deckFrame.Position.Y + (math.abs(deckFrame.RightVector.Y) * deck.Size.X
		+ math.abs(deckFrame.UpVector.Y) * deck.Size.Y + math.abs(deckFrame.LookVector.Y) * deck.Size.Z) * .5
	local function verifyEnd(side, footFrame, handFrame, footSize, palmFrame)
		local localFoot = root.CFrame:ToObjectSpace(footFrame)
		local pitch = if side == "Left" then Config.BaseRidingPose.FrontFootPitch else Config.BaseRidingPose.RearFootPitch
		local halfHeight = (math.abs(math.cos(pitch)) * footSize.Y + math.abs(math.sin(pitch)) * footSize.Z) * .5
		local halfFootLength = (math.abs(math.cos(pitch)) * footSize.Z + math.abs(math.sin(pitch)) * footSize.Y) * .5
		check(math.abs(localFoot.Position.Y - halfHeight - top - Config.RiderDeckClearance) < .005,
			side .. " sole touches deck")
		check((localFoot.UpVector - CFrame.Angles(pitch, 0, 0).UpVector).Magnitude < .005, side .. " foot pitch matches reference")
		check(localFoot.LookVector:Dot(-Vector3.zAxis) > .98, side .. " foot faces forward")
		check(math.abs(localFoot.Position.X - deckFrame.Position.X) + footSize.X * .5 <= halfWidth + .005,
			side .. " foot stays within deck width")
		check(math.abs(localFoot.Position.Z - deckFrame.Position.Z) + halfFootLength <= halfLength + .005,
			side .. " foot stays within deck length")
		check(((handFrame * palmFrame).Position - scooter.HandleBar[side .. "HandGrip"].WorldPosition).Magnitude < .005,
			side .. " palm touches grip")
		local expectedPalm = scooter.HandleBar.CFrame.Rotation * CFrame.Angles(0, math.pi, 0)
			* CFrame.Angles(Config.BaseRidingPose.HandPalmPitch, 0, 0)
		local actualPalm = handFrame * palmFrame
		check((actualPalm.RightVector - expectedPalm.RightVector).Magnitude < .005
			and (actualPalm.UpVector - expectedPalm.UpVector).Magnitude < .005, side .. " palm orientation follows bar")
	end
	for _, side in { "Left", "Right" } do
		verifyEnd(side, character[side .. "Foot"].CFrame, character[side .. "Hand"].CFrame,
			character[side .. "Foot"].Size, character[side .. "Hand"][side .. "GripAttachment"].CFrame)
		for _, kind in { "Leg", "Arm" } do
			local upper, lower = character[side .. "Upper" .. kind], character[side .. "Lower" .. kind]
			local first = upper[side .. (if kind == "Leg" then "Hip" else "Shoulder") .. "RigAttachment"].WorldPosition
			local middle = upper[side .. (if kind == "Leg" then "Knee" else "Elbow") .. "RigAttachment"].WorldPosition
			local last = lower[side .. (if kind == "Leg" then "Ankle" else "Wrist") .. "RigAttachment"].WorldPosition
			local bend = math.deg(math.acos(math.clamp((middle - first).Unit:Dot((last - middle).Unit), -1, 1)))
			check(bend > 5 and bend < 45, side .. kind .. " has a slight, nonzero bend")
		end
	end
	check(character.LeftFoot.Position ~= character.RightFoot.Position, "Feet have distinct positions")
	check(seat:FindFirstChild("SeatWeld") ~= nil, "Native seat weld is retained")
	check(character.Animate.Enabled, "Default Animate stays enabled")

	local wasArchivable = character.Archivable
	character.Archivable = true
	local fixture = character:Clone()
	character.Archivable = wasArchivable
	assert(fixture, "Character fixture clone failed")
	local interpolationScooter
	local success, problem = pcall(function()
		local function sameFrame(first, second)
			return (first.Position - second.Position).Magnitude < .0001
				and (first.RightVector - second.RightVector).Magnitude < .0001
				and (first.UpVector - second.UpVector).Magnitude < .0001
				and (first.LookVector - second.LookVector).Magnitude < .0001
		end
		local function composed(joint, parentFrame)
			return parentFrame * joint.c0 * joint.instance.Transform * joint.c1:Inverse()
		end
		local function verifyFixture(label)
			local rig = assert(BasePose.Bind(fixture), label .. " binds")
			check(BasePose.Update(rig, scooter) < .005, label .. " targets reachable")
			for _, side in { "Left", "Right" } do
				local elbow = rig.limbs[side .. "Hand"].middle.instance.Transform
				check(elbow.Position.Magnitude < .00001, label .. side .. " elbow has no translation")
				check((elbow.RightVector - Vector3.xAxis).Magnitude < .00001, label .. side .. " elbow uses only its hinge axis")
			end
			local lower = composed(rig.root, rig.rootPart.CFrame)
			local upper = composed(rig.waist, lower)
			for _, side in { "Left", "Right" } do
				local function endFrame(limb, parentFrame)
					local first = composed(limb.first, parentFrame)
					local middle = composed(limb.middle, first)
					return composed(limb.last, middle)
				end
				verifyEnd(side, endFrame(rig.limbs[side .. "Foot"], lower),
					endFrame(rig.limbs[side .. "Hand"], upper), fixture[side .. "Foot"].Size,
					fixture[side .. "Hand"][side .. "GripAttachment"].CFrame)
			end
			BasePose.Restore(rig)
			for _, j in { rig.root, rig.waist, rig.neck } do
				check(sameFrame(j.instance.Transform, j.original), label .. " restores torso transforms")
			end
			for _, limb in rig.limbs do
				for _, j in { limb.first, limb.middle, limb.last } do
					check(sameFrame(j.instance.Transform, j.original), label .. " restores limb transforms")
				end
			end
		end
		verifyFixture("AnimationConstraint")
		for _, item in fixture:GetDescendants() do
			if item:IsA("AnimationConstraint") then
				local motor = Instance.new("Motor6D")
				motor.Name = item.Name
				motor.Part0 = item.Attachment0.Parent
				motor.Part1 = item.Attachment1.Parent
				motor.C0, motor.C1, motor.Transform = item.Attachment0.CFrame, item.Attachment1.CFrame, item.Transform
				motor.Parent = item.Parent
				item:Destroy()
			end
		end
		verifyFixture("Motor6D")
		interpolationScooter = scooter:Clone()
		local weld = interpolationScooter.DriverSeat:FindFirstChild("SeatWeld")
		if not weld then
			local native = assert(seat:FindFirstChild("SeatWeld"))
			weld = Instance.new("Weld")
			weld.Name = "SeatWeld"
			weld.C0, weld.C1 = native.C0, native.C1
			weld.Part0 = interpolationScooter.DriverSeat
			weld.Parent = interpolationScooter.DriverSeat
		end
		weld.Part1 = fixture.HumanoidRootPart
		local rig = assert(BasePose.Bind(fixture))
		BasePose.Update(rig, interpolationScooter)
		local before = {}
		for _, limb in rig.limbs do
			for _, j in { limb.first, limb.middle, limb.last } do before[j.instance] = j.instance.Transform end
		end
		-- Simulate a delayed character snapshot relative to its server-owned seat.
		fixture.HumanoidRootPart.CFrame += Vector3.new(7, 0, -5)
		BasePose.Update(rig, interpolationScooter)
		local coherent = true
		for instance, transform in before do coherent = coherent and sameFrame(instance.Transform, transform) end
		check(coherent, "Character interpolation drift does not change seat-relative pose")
		fixture.LeftFoot:Destroy()
		check(BasePose.Bind(fixture) == nil, "Incomplete rig fails closed")
	end)
	if interpolationScooter then interpolationScooter:Destroy() end
	fixture:Destroy()
	assert(success, problem)
	print(string.format("PASS: %d native scooter base pose assertions", count))
	return count
end

return Tests
