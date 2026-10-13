-- Run with fresh modules in an unparented sandbox; no template installation or Play required.
local Test = {}

function Test.Run(builder, rig, compound, config, source, reference, basePose)
	local count = 0
	local models = {}
	local destination = Instance.new("Folder")
	local presentation
	local function check(value, message)
		assert(value, message)
		count += 1
	end
	local function near(value, expected, message, tolerance)
		check(math.abs(value - expected) <= (tolerance or 0.001), message)
	end
	local function sameFrame(a, b)
		return (a.Position - b.Position).Magnitude < 0.001
			and (a.RightVector - b.RightVector).Magnitude < 0.0001
			and (a.UpVector - b.UpVector).Magnitude < 0.0001
	end
	local sourceState, sourceParts = {}, {}
	for _, item in source:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(sourceParts, item)
			sourceState[item] = {frame=item.CFrame,size=item.Size,parent=item.Parent,name=item.Name,
				anchored=item.Anchored,collide=item.CanCollide,massless=item.Massless,attributes=item:GetAttributes()}
		end
	end
	local initialDescendants = #source:GetDescendants()
	local originalTemplate = reference
	local result
	local ok, problem = xpcall(function()
		local scale = builder.ResolveScale(source, reference)
		check(scale > 0.4 and scale < 1, "Reference avatar requires a smaller copy")
		local model = builder.Build(source, scale, config)
		table.insert(models, model)
		check(model.Parent == nil and model.PrimaryPart == model.Root, "Detached rig has canonical root")
		check(model:GetAttribute("CentralShockRig") == false and model:GetAttribute("AuthoredSuspensionRig"), "Four-shock authored topology")
		check(model:GetAttribute("FrontRestPoseStatus") == "Authored" and not model:GetAttribute("FrontMountShift"), "No legacy mount relocation")
		local sourceDeck = source.Body.Deck.CFrame
		local originals = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				check(not part.Anchored, "Runtime candidate is fully unanchored")
				check(part.CanCollide == (part:GetAttribute("RuntimeCollisionProxy") == true), "Only simplified proxies collide")
				local id = part:GetAttribute("G4SourcePart")
				if id then
					originals += 1
					local original = sourceParts[id]
					check(original and original.ClassName == part.ClassName, "Original Part/Union/Wedge geometry retained")
					local relative = sourceDeck:ToObjectSpace(original.CFrame)
					local expected = sourceDeck * CFrame.new(relative.Position * scale) * relative.Rotation
					check(sameFrame(part.CFrame, expected), "Uniform scaling preserves authored orientation and layout")
					check((part.Size - original.Size * scale).Magnitude < 0.001, "Original dimensions scaled uniformly")
				end
			end
		end
		check(originals == #sourceParts, "Every source part survives")
		near(model.Root:GetMass(), 12, "Chassis mass")
		near(model.HandleBarStick:GetMass(), 2, "Steering mass")
		near(model.FrontWheel:GetMass(), 2, "Front tire mass")
		near(model.BackWheel:GetMass(), 2, "Rear tire mass")
		near(model:GetAttribute("SuspensionReferenceMass"), 60, "Reference rider plus articulated mass", 0.02)
		local left = model.HandleBar.LeftHandGrip
		local right = model.HandleBar.RightHandGrip
		near((left.WorldPosition-model.LeftGrip.Position).Magnitude, 0, "Left palm target on actual grip")
		near((right.WorldPosition-model.RightGrip.Position).Magnitude, 0, "Right palm target on actual grip")
		local height = ((left.WorldPosition+right.WorldPosition)*0.5-model.FootRest.Position).Y-model.FootRest.Size.Y*0.5
		local referenceHeight = ((reference.HandleBar.LeftHandGrip.WorldPosition+reference.HandleBar.RightHandGrip.WorldPosition)*0.5
			-reference.FootRest.Position).Y-reference.FootRest.Size.Y*0.5
		near(height, referenceHeight, "Grip height matches the existing avatar fit")
		check(model.FootRest.LeftFootTarget and model.FootRest.RightFootTarget, "Both foot support targets exist")
		check(model.DeckCollider.Position.Y-model.DeckCollider.Size.Y*.5
			<=model.ScooterBody.Position.Y-model.ScooterBody.Size.Y*.5+config.DeckColliderInset+.001,
			"Skid protects the battery underside")
		check(model.ScooterDashboard.DisplaySurface.DashboardGui.Face == Enum.NormalId.Front, "Existing dashboard presentation reused")
		check(model.ScooterDashboard.DisplaySurface.CFrame.LookVector:Dot(model.Display.CFrame.UpVector)>.99,
			"Dashboard front face points above the authored glass")
		local avatarError
		if basePose then
			local description = Instance.new("HumanoidDescription")
			local created, avatar = pcall(function()
				return game:GetService("Players"):CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15)
			end)
			description:Destroy()
			check(created,"Detached R15 fixture generated")
			table.insert(models,avatar)
			local _, size = avatar:GetBoundingBox()
			avatar:ScaleTo(avatar:GetScale()*8/size.Y)
			local humanoid, root = avatar.Humanoid, avatar.HumanoidRootPart
			avatar.PrimaryPart=root
			local offset=Vector3.new(0,humanoid.HipHeight+root.Size.Y*.5
				-humanoid.HipHeight*config.BaseRidingPose.CrouchHipHeightFraction,-config.BaseRidingPose.RootForwardOffset)
			local at=CFrame.new(model.Root.RiderRootAttachment.WorldPosition+model.Root.CFrame:VectorToWorldSpace(offset))*model.Root.CFrame.Rotation
			avatar:PivotTo(at)
			local seatWeld=Instance.new("Weld")
			seatWeld.Name,seatWeld.Part0,seatWeld.Part1="SeatWeld",model.DriverSeat,root
			seatWeld.C0=model.DriverSeat.CFrame:ToObjectSpace(at)
			seatWeld.Parent=model.DriverSeat
			local pose=basePose.Bind(avatar)
			check(pose~=nil,"Eight-stud R15 fixture binds without changing a real avatar")
			for _=1,30 do avatarError=basePose.Update(pose,model,1/60) end
			check(avatarError<0.005,"Neutral hands and feet are reachable on the G4")
			basePose.Restore(pose)
			seatWeld:Destroy()
		end
		for _, endName in {"Front","Back"} do
			local base = if endName == "Front" then model.HandleBarStick else model.ScooterBody
			local axle, wheel = model["Virtual"..endName.."Axle"], model[endName.."Wheel"]
			check(axle.HingeConstraint.Attachment1.Parent == wheel, "Wheel rotates independently of axle")
			local caliper = model[endName.."BrakeCaliper"]
			local attached = false
			for _, weld in axle:GetChildren() do
				if weld:IsA("WeldConstraint") and weld.Part1 == caliper then attached = true end
			end
			check(attached, "Brake caliper stays on suspension instead of rotating")
			local pivot = base["PivotAttBase_"..endName.."SuspensionLeft"]
			local axis = pivot.WorldAxis
			local wheelOffset = wheel.WheelCenter.WorldPosition-pivot.WorldPosition
			local torqueRest = 0
			local torques = {0,0}
			local leftHinge = base["PivotHinge_"..endName.."SuspensionLeft"]
			for _, side in {"Left","Right"} do
				local suffix = endName.."Suspension"..side
				local spring = base["ShockAbsorber_"..suffix]
				local a,b = spring.Attachment0.WorldPosition,spring.Attachment1.WorldPosition
				local length = (a-b).Magnitude
				check(spring.LimitsEnabled and spring.MinLength < length and spring.MaxLength > length, "Neutral spring is inside travel stops")
				check(spring.Stiffness > 0 and spring.Damping > 0 and spring.MaxForce > 0 and spring.MaxForce < math.huge, "Finite calibrated physical shock")
				local offset = b-pivot.WorldPosition
				local function torque(angle)
					local moved = CFrame.fromAxisAngle(axis,angle):VectorToWorldSpace(offset)
					local delta = pivot.WorldPosition+moved-a
					return axis:Dot(moved:Cross(delta.Unit*spring.Stiffness*(spring.FreeLength-delta.Magnitude)))
				end
				torqueRest += torque(0)
				for i, degrees in {leftHinge.LowerAngle,leftHinge.UpperAngle} do torques[i] += torque(math.rad(degrees)) end
			end
			local lower,upper = math.rad(leftHinge.LowerAngle),math.rad(leftHinge.UpperAngle)
			check((CFrame.fromAxisAngle(axis,lower):VectorToWorldSpace(wheelOffset).Y-wheelOffset.Y)
				*(CFrame.fromAxisAngle(axis,upper):VectorToWorldSpace(wheelOffset).Y-wheelOffset.Y)<0, "Compression and droop move tire both ways")
			check((torques[1]-torqueRest)*lower<0 and (torques[2]-torqueRest)*upper<0, "Springs restore at both travel stops")
		end
		local repeated = rig.Prepare(model,config)
		table.insert(models,repeated)
		check(#repeated:GetDescendants()==#model:GetDescendants(), "Runtime cloning adds no duplicate helpers or welds")
		local legacy = rig.Prepare(reference,config)
		table.insert(models,legacy)
		check(#legacy:GetDescendants()==#reference:GetDescendants(),"Existing two-shock template remains compatible")
		check(legacy:GetAttribute("CentralShockRig")==true,"Existing central-shock topology retained")
		for _, item in repeated:GetDescendants() do
			if item:IsA("SpringConstraint") then
				near(item.Stiffness,model:FindFirstChild(item.Name,true).Stiffness,"Cloning retains calibration")
			end
		end
		local invalid = model:Clone()
		table.insert(models,invalid)
		invalid.ScooterBody.ShockAbsorber_BackSuspensionLeft.MaxForce=0
		check(not pcall(builder.Validate,invalid,config), "Zero support force rejected")
		invalid.ScooterBody.ShockAbsorber_BackSuspensionLeft.MaxForce=10000
		local weld=Instance.new("WeldConstraint")
		weld.Part0,weld.Part1,weld.Parent=invalid.Root,invalid.FrontWheel,invalid.Root
		check(not pcall(builder.Validate,invalid,config), "Rigid chassis-to-wheel lock rejected")
		check(not pcall(builder.Build,source,0/0,config), "NaN scale rejected before authoring")
		presentation=compound.Create(model,destination)
		check(presentation and presentation.IsAlive(), "Compound wheel and four-shock presentation binds")
		local copies={}
		for _, i in destination:GetDescendants() do
			if i:IsA("BasePart") then table.insert(copies,i)
			elseif i:IsA("SurfaceGui") then check(not i.Enabled,"Unmounted render labels stay hidden") end
		end
		check(#copies>700, "Segmented geometry is included in presentation")
		presentation.Update(1/60,true)
		local copyGui
		for _,i in destination:GetDescendants() do if i:IsA("SurfaceGui") and i.Enabled then copyGui=i; break end end
		check(copyGui and copyGui.Adornee==copyGui.Parent,"Rendered wheel label follows its own copy")
		local coil, copy
		for _, part in copies do
			if part:GetAttribute("G4ShockSection")=="Coil" then
				copy=part
				for _, original in model:GetDescendants() do
					if original:IsA("BasePart") and original:GetAttribute("G4SourcePart")==part:GetAttribute("G4SourcePart") then coil=original; break end
				end
				break
			end
		end
		check(coil and copy and copy.Transparency<1 and coil.LocalTransparencyModifier==1, "Original coils hide only while copies are shown")
		coil.Color=Color3.fromRGB(210,120,30)
		coil.Transparency=.2
		task.wait()
		check(copy.Color==coil.Color,"Paint changes reach render copies")
		near(copy.Transparency,coil.Transparency,"Transparency changes reach render copies")
		local before=copy.CFrame
		for _, item in model:GetDescendants() do
			if item:IsA("SpringConstraint") then item.Attachment1.Position+=item.Attachment1.Parent.CFrame:VectorToObjectSpace(Vector3.yAxis*0.08) end
		end
		for _=1,20 do presentation.Update(1/60,true) end
		check((copy.Position-before.Position).Magnitude>0.005,"Decorative coil follows physical shock compression")
		presentation.Update(1/60,false)
		near(coil.LocalTransparencyModifier,0,"Distance/unmounted path restores originals")
		presentation.Destroy()
		presentation.Destroy()
		check(not presentation.IsAlive() and #destination:GetChildren()==0,"Presentation cleanup is repeatable and removes copies")
		presentation=compound.Create(model,destination)
		check(presentation and presentation.IsAlive(),"Presentation can bind again")
		presentation.Update(1/60,true)
		local originalParent=coil.Parent
		coil.Parent=nil
		task.wait()
		check(not presentation.IsAlive() and #destination:GetChildren()==0,"Streaming removal cleans copies and connections")
		near(coil.LocalTransparencyModifier,0,"Unparented source visibility restored on streaming cleanup")
		coil.Parent=originalParent
		local summary={assertions=count,scale=scale,sourceParts=#sourceParts,visualCopies=#copies,
			gripHeight=height,wheelbase=(model.FrontWheel.Position-model.BackWheel.Position).Magnitude,
			wheelRadius=model.FrontWheel:GetAttribute("WheelRadius"),avatarTargetError=avatarError}
		check(#source:GetDescendants()==initialDescendants and reference==originalTemplate,"Source hierarchy and active template unchanged")
		for part,state in sourceState do
			check(part.Parent==state.parent and part.Name==state.name and part.CFrame==state.frame and part.Size==state.size
				and part.Anchored==state.anchored and part.CanCollide==state.collide and part.Massless==state.massless,
				"Source part left untouched")
			check(part:GetAttribute("G4SourcePart")==nil,"Source has no generated IDs")
		end
		summary.assertions=count
		result=summary
	end,debug.traceback)
	if presentation then presentation.Destroy() end
	for _, model in models do model:Destroy() end
	destination:Destroy()
	if not ok then error(problem,2) end
	return result
end

return Test
