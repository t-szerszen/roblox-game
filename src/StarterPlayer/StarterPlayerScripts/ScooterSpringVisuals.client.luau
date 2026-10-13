--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Compound = require(ReplicatedStorage.Shared.Scooter.ScooterCompoundVisuals)

type Coil = { original: MeshPart, copy: MeshPart, spring: SpringConstraint, size: Vector3, length: number,
	transparency: number, first: Vector3, second: Vector3 }
type Wheel = { original: MeshPart, copy: MeshPart, anchor: Attachment, rest: CFrame,
	frame: CFrame, tracking: boolean, spin: number, rate: number, radius: number, transparency: number }
local scope = Scope.new()
local visuals = Instance.new("Folder")
visuals.Name, visuals.Parent = "_ScooterRideVisuals", workspace
scope:Give(visuals)
local models: { [Model]: { scope: Scope.Scope, coils: { Coil }, wheels: { Wheel }, compound: Compound.Controller? } } = {}
local folderScope: Scope.Scope? = nil
local watched: Instance? = nil

local function copyVisual(original: MeshPart, name: string): MeshPart
	local copy = original:Clone()
	for _, child in copy:GetChildren() do if not child:IsA("SurfaceAppearance") then child:Destroy() end end
	copy.Name = name
	copy.Anchored, copy.CanCollide, copy.CanTouch, copy.CanQuery = true, false, false, false
	copy.Massless, copy.Transparency = true, 1
	-- Render-only parts stay outside the replicated articulated mechanism.
	copy.Parent = visuals
	return copy
end

local function watch(instance: Instance)
	if not instance:IsA("Model") or models[instance] then return end
	local model = instance
	local cleanup = Scope.new()
	local coils: { Coil } = {}
	local wheels: { Wheel } = {}
	models[model] = { scope = cleanup, coils = coils, wheels = wheels }
	local function bind()
		if not models[model] or not cleanup._alive then return end
		local root = model.PrimaryPart
		if not root then return end
		local entry = models[model]
		if entry.compound and not entry.compound.IsAlive() then entry.compound = nil end
		if not entry.compound then
			local compound = Compound.Create(model, visuals)
			if compound then entry.compound = compound; cleanup:Give(compound.Destroy) end
		end
		for _, endName in { "Front", "Back" } do
			local original = model:FindFirstChild(endName .. "Wheel")
			local axle = model:FindFirstChild("Virtual" .. endName .. "Axle")
			if not original or not original:IsA("MeshPart") or not axle then continue end
			local exists = false
			for _, wheel in wheels do if wheel.original == original then exists = true end end
			if exists then continue end
			local anchor: Attachment? = nil
			local wheelPoint: Attachment? = nil
			for _, joint in axle:GetChildren() do
				if joint:IsA("HingeConstraint") and joint.Attachment0 and joint.Attachment1 then
					if joint.Attachment1.Parent == original then anchor, wheelPoint = joint.Attachment0, joint.Attachment1
					elseif joint.Attachment0.Parent == original then anchor, wheelPoint = joint.Attachment1, joint.Attachment0 end
				end
			end
			if not anchor or not wheelPoint then continue end
			local copy = copyVisual(original, endName .. "AnimatedWheel")
			local radius = model:GetAttribute("Resolved" .. endName .. "WheelRadius")
			if typeof(radius) ~= "number" or radius <= 0 then
				local dimensions = { original.Size.X, original.Size.Y, original.Size.Z }
				table.sort(dimensions)
				radius = dimensions[2] * 0.5
			end
			table.insert(wheels, { original = original, copy = copy, anchor = anchor,
				-- Joint-local calibration is stable before replication settles the spawned wheel.
				rest = wheelPoint.CFrame:Inverse(),
				frame = root.CFrame:ToObjectSpace(anchor.WorldCFrame), tracking = false, spin = 0, rate = 0, radius = radius :: number,
				transparency = original.LocalTransparencyModifier })
			cleanup:Give(copy)
		end
		for _, endName in { "Front", "Back" } do
			local original = model:FindFirstChild(endName .. "SpringVisual", true)
			local spring = model:FindFirstChild("ShockAbsorber_" .. endName, true)
			if not original or not original:IsA("MeshPart") or not spring or not spring:IsA("SpringConstraint")
				or not spring.Attachment0 or not spring.Attachment1 then continue end
			local existing = false
			for _, coil in coils do if coil.original == original then existing = true end end
			if existing then continue end
			local copy = copyVisual(original, endName .. "AnimatedCoil")
			table.insert(coils, { original = original, copy = copy, spring = spring, size = original.Size,
				length = (spring.Attachment0.WorldPosition - spring.Attachment1.WorldPosition).Magnitude,
				transparency = original.LocalTransparencyModifier,
				first = root.CFrame:PointToObjectSpace(spring.Attachment0.WorldPosition),
				second = root.CFrame:PointToObjectSpace(spring.Attachment1.WorldPosition) })
			cleanup:Give(copy)
		end
	end
	local bindingScheduled = false
	local function scheduleBind()
		if bindingScheduled then return end
		bindingScheduled = true
		task.defer(function()
			bindingScheduled = false
			bind()
		end)
	end
	cleanup:Give(function()
		models[model] = nil
		for _, coil in coils do
			if coil.original.Parent then coil.original.LocalTransparencyModifier = coil.transparency end
		end
		for _, wheel in wheels do
			if wheel.original.Parent then wheel.original.LocalTransparencyModifier = wheel.transparency end
		end
	end)
	cleanup:Give(model.Destroying:Connect(function() cleanup:Clean() end))
	cleanup:Give(model.AncestryChanged:Connect(function()
		if model.Parent ~= watched then cleanup:Clean() end
	end))
	cleanup:Give(model.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") or instance:IsA("SpringConstraint") or instance:IsA("Model") then scheduleBind() end
	end))
	cleanup:Give(model:GetPropertyChangedSignal("PrimaryPart"):Connect(scheduleBind))
	bind()
end

local function detach()
	if folderScope then folderScope:Clean(); folderScope = nil end
	watched = nil
	for _, entry in models do entry.scope:Clean() end
end

local function attach(folder: Instance)
	if folder.Name ~= Config.ScooterFolderName or not folder:IsA("Folder") or watched == folder then return end
	detach()
	watched = folder
	local nextScope = Scope.new()
	folderScope = nextScope
	nextScope:Give(folder.ChildAdded:Connect(watch))
	nextScope:Give(folder.Destroying:Connect(detach))
	for _, model in folder:GetChildren() do watch(model) end
end

scope:Give(detach)
scope:Give(workspace.ChildAdded:Connect(attach))
scope:Give(workspace.ChildRemoved:Connect(function(instance) if watched == instance then detach() end end))
-- Run after camera/character presentation so wheel copies share the final chassis pose.
local renderName = "ScooterRideVisuals"
RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value, function(deltaTime: number)
	local dt = math.clamp(deltaTime, 0, 0.1)
	local alpha = 1 - math.exp(-Config.RideVisuals.SuspensionResponse * dt)
	for model, entry in models do
		local root = model.PrimaryPart
		if not root then continue end
		local camera = workspace.CurrentCamera
		local mounted = model:GetAttribute("RiderMounted") == true and camera ~= nil
			and (root.Position - camera.CFrame.Position).Magnitude <= Config.RideVisuals.MaxDistance
		if entry.compound then entry.compound.Update(dt, mounted) end
		for _, wheel in entry.wheels do
			if not wheel.original.Parent or not wheel.copy.Parent or not wheel.anchor.Parent then continue end
			wheel.original.LocalTransparencyModifier = if mounted then 1 else wheel.transparency
			wheel.copy.Transparency = if mounted then wheel.original.Transparency else 1
			if not mounted then wheel.tracking = false; wheel.rate = 0; continue end
			-- Smooth only suspension relative to the chassis; its world motion keeps native interpolation.
			local target = root.CFrame:ToObjectSpace(wheel.anchor.WorldCFrame)
			if not wheel.tracking then wheel.frame = target; wheel.tracking = true end
			local filtered = wheel.frame:Lerp(target, alpha)
			local shift = filtered.Position - wheel.frame.Position
			local limit = Config.RideVisuals.MaxSuspensionSpeed * dt
			if shift.Magnitude > limit then shift = shift.Unit * limit end
			wheel.frame = CFrame.new(wheel.frame.Position + shift) * filtered.Rotation
			local sign = if wheel.anchor.WorldAxis:Dot(root.CFrame.RightVector) >= 0 then -1 else 1
			local rate = sign * root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector) / wheel.radius
			if model:GetAttribute("BurnoutActive") == true then
				rate = wheel.original.AssemblyAngularVelocity:Dot(wheel.anchor.WorldAxis)
			end
			wheel.rate += (rate - wheel.rate) * (1 - math.exp(-Config.RideVisuals.SpinResponse * dt))
			wheel.spin = (wheel.spin + wheel.rate * dt) % (math.pi * 2)
			wheel.copy.CFrame = root.CFrame * wheel.frame * CFrame.Angles(wheel.spin, 0, 0) * wheel.rest
		end
		for _, coil in entry.coils do
			if not coil.original.Parent or not coil.spring.Parent or not coil.copy.Parent then continue end
			local a0, a1 = coil.spring.Attachment0, coil.spring.Attachment1
			local enabled = mounted and a0 ~= nil and a1 ~= nil
			coil.original.LocalTransparencyModifier = if enabled then 1 else coil.transparency
			coil.copy.Transparency = if enabled then coil.original.Transparency else 1
			if not enabled or not a0 or not a1 then continue end
			coil.first = coil.first:Lerp(root.CFrame:PointToObjectSpace(a0.WorldPosition), alpha)
			coil.second = coil.second:Lerp(root.CFrame:PointToObjectSpace(a1.WorldPosition), alpha)
			local first, second = root.CFrame:PointToWorldSpace(coil.first), root.CFrame:PointToWorldSpace(coil.second)
			local delta = second - first
			if delta.Magnitude < 0.001 then continue end
			local up = delta.Unit
			local right = coil.original.CFrame.RightVector
			right -= up * right:Dot(up)
			if right.Magnitude < 0.001 then right = up:Cross(if math.abs(up.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis) end
			coil.copy.CFrame = CFrame.fromMatrix((first + second) * 0.5, right.Unit, up)
			coil.copy.Size = Vector3.new(coil.size.X, coil.size.Y * delta.Magnitude / math.max(coil.length, 0.001), coil.size.Z)
		end
	end
end)
scope:Give(function() RunService:UnbindFromRenderStep(renderName) end)
scope:Give(script.Destroying:Connect(function() scope:Clean() end))
local folder = workspace:FindFirstChild(Config.ScooterFolderName)
if folder then attach(folder) end
