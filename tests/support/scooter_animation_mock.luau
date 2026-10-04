-- Additional object/pose doubles; these do not run Roblox's IK or physics solvers.
Vector.one = Vector.new(1, 1, 1)
local function position(frame) return frame.position or Vector.zero end
local originalMultiply = frameMetatable.__mul
frameMetatable.__mul = function(a, b)
	local result = originalMultiply(a, b)
	result.position = position(a) + a:VectorToWorldSpace(position(b))
	return result
end
frameMetatable.__add = function(frame, vector)
	local result = quaternion(frame.x, frame.y, frame.z, frame.w)
	result.position = position(frame) + vector
	return result
end
frameMetatable.__sub = function(frame, vector) return frame + -vector end
frameMetatable.__index = function(self, key)
	if key == "Position" then return position(self) end
	if key == "Rotation" then return quaternion(self.x, self.y, self.z, self.w) end
	if key == "LookVector" then return self:VectorToWorldSpace(-Vector.zAxis) end
	if key == "RightVector" then return self:VectorToWorldSpace(Vector.xAxis) end
	if key == "UpVector" then return self:VectorToWorldSpace(Vector.yAxis) end
	return frameMethods[key]
end
function Frame.new(x, y, z)
	local result = quaternion(0, 0, 0, 1)
	result.position = if type(x) == "table" then x else Vector.new(x or 0, y or 0, z or 0)
	return result
end
function Frame.Angles(x, y, z)
	return Frame.fromAxisAngle(Vector.xAxis, x) * Frame.fromAxisAngle(Vector.yAxis, y)
		* Frame.fromAxisAngle(Vector.zAxis, z)
end
function Frame.lookAt(origin, target)
	local direction = target - origin
	return Frame.Angles(0, math.atan2(-direction.X, -direction.Z), 0) + origin
end
function Frame.fromMatrix(origin, right, up)
	local back = right:Cross(up)
	local trace = right.X + up.Y + back.Z
	local x, y, z, w
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w, x, y, z = s / 4, (up.Z - back.Y) / s, (back.X - right.Z) / s, (right.Y - up.X) / s
	elseif right.X > up.Y and right.X > back.Z then
		local s = math.sqrt(1 + right.X - up.Y - back.Z) * 2
		w, x, y, z = (up.Z - back.Y) / s, s / 4, (up.X + right.Y) / s, (back.X + right.Z) / s
	elseif up.Y > back.Z then
		local s = math.sqrt(1 + up.Y - right.X - back.Z) * 2
		w, x, y, z = (back.X - right.Z) / s, (up.X + right.Y) / s, s / 4, (back.Y + up.Z) / s
	else
		local s = math.sqrt(1 + back.Z - right.X - up.Y) * 2
		w, x, y, z = (right.Y - up.X) / s, (back.X + right.Z) / s, (back.Y + up.Z) / s, s / 4
	end
	return quaternion(x, y, z, w) + origin
end
function frameMethods:Inverse()
	local result = quaternion(-self.x, -self.y, -self.z, self.w)
	result.position = result:VectorToWorldSpace(-position(self))
	return result
end
function frameMethods:PointToObjectSpace(point)
	return self:Inverse():VectorToWorldSpace(point - position(self))
end
function frameMethods:ToObjectSpace(frame) return self:Inverse() * frame end
function frameMethods:Lerp(other, alpha)
	local result = quaternion(self.x + (other.x - self.x) * alpha, self.y + (other.y - self.y) * alpha,
		self.z + (other.z - self.z) * alpha, self.w + (other.w - self.w) * alpha)
	result.position = position(self) + (position(other) - position(self)) * alpha
	return result
end

local enumMock = {
	HumanoidRigType = { R15 = "R15", R6 = "R6" },
	IKControlType = { Position = "Position", Transform = "Transform" },
	ActuatorType = { None = "None", Motor = "Motor", Servo = "Servo" },
	AnimationPriority = { Action = "Action" },
	Material = { Metal = "Metal", Neon = "Neon" },
	PartType = { Ball = "Ball" },
}
function playersService:GetPlayerFromCharacter(character)
	for _, player in players do if player.Character == character then return player end end
	return nil
end
services.RunService = { PreAnimation = signal(), PreSimulation = signal() }
local originalNew = InstanceMock.new
function InstanceMock.new(className)
	local instance = originalNew(className)
	local values = instance._values
	values.CFrame = Frame.identity
	values.Transform = Frame.identity
	values.Size = Vector.new(1, 1, 1)
	values.AssemblyLinearVelocity = Vector.zero
	values.Enabled = true
	values.Health = 100
	values.ServoMaxTorque = 1234
	values.AngularSpeed = 5
	values.ActuatorType = enumMock.ActuatorType.None
	values.MaxForce = math.huge
	values.LimitsEnabled = false
	values.CurrentAngle = 0
	values.LowerAngle = -45
	values.UpperAngle = 45
	values.CollisionGroup = "Default"
	values.Anchored = false
	values.CanCollide = true
	values.Massless = false
	values.Gravity = 196.2
	values.Material = enumMock.Material.Metal
	values.Color = Color.new(1, 1, 1)
	values.EmissiveStrength = 0
	values.EmissiveTint = Color.new(1, 1, 1)
	values.Destroying = signal()
	values.AncestryChanged = signal()
	values.Died = signal()
	values.AnimationPlayed = signal()
	local meta = getmetatable(instance)
	local oldIndex, oldNewIndex = meta.__index, meta.__newindex
	meta.__index = function(self, key)
		if key == "Position" then return self.CFrame.Position end
		if key == "WorldCFrame" then return self.Parent.CFrame * self.CFrame end
		if key == "WorldPosition" then return self.WorldCFrame.Position end
		if key == "WorldAxis" then return self.WorldCFrame.RightVector end
		if values[key] ~= nil then return values[key] end
		return oldIndex(self, key)
	end
	meta.__newindex = function(self, key, value)
		if key == "Position" then values.CFrame = Frame.new(value); return end
		if key == "Name" and values.Parent then
			if values.Parent._children[values.Name] == self then values.Parent._children[values.Name] = nil end
			values.Parent._children[value] = self
		end
		oldNewIndex(self, key, value)
		if key == "Parent" and value and self.ClassName == "ModuleScript" and values._path then
			local path = "TestReload/" .. value.Name .. "/" .. self.Name
			SOURCES[path] = assert(SOURCES[values._path])
			values._path = path
		end
	end
	return instance
end
function instanceMethods:IsA(className)
	if className == "GuiObject" then return self.ClassName == "Frame" or self.ClassName == "TextLabel" end
	if className == "UIComponent" then return self.ClassName == "UICorner" end
	if className == "BasePart" then return self.ClassName == "Part" or self.ClassName == "MeshPart" or self.ClassName == "VehicleSeat" end
	if className == "Constraint" then return self.ClassName == "HingeConstraint" or self.ClassName == "SpringConstraint" end
	return self.ClassName == className or className == "Instance"
end
function instanceMethods:GetMass() return self.Size.X * self.Size.Y * self.Size.Z end
function instanceMethods:FindFirstChild(name, recursive)
	if self._children[name] then return self._children[name] end
	if recursive then
		for _, child in self._children do
			local result = child:FindFirstChild(name, true)
			if result then return result end
		end
	end
	return nil
end
function instanceMethods:FindFirstChildOfClass(className)
	for _, child in self._children do if child:IsA(className) then return child end end
	return nil
end
function instanceMethods:GetDescendants()
	local result = {}
	for _, child in self._children do
		table.insert(result, child)
		for _, descendant in child:GetDescendants() do table.insert(result, descendant) end
	end
	return result
end
function instanceMethods:GetPlayingAnimationTracks()
	local result = {}
	for _, track in self._tracks or {} do
		if track.IsPlaying then table.insert(result, track) end
	end
	return result
end
function instanceMethods:LoadAnimation(animation)
	if self.failLoad then error("mock asset unavailable") end
	local track = InstanceMock.new("AnimationTrack")
	track.Animation = animation
	track.Length = 1
	track.WeightCurrent = 0
	track.IsPlaying = false
	track.playCount, track.stopCount = 0, 0
	track._animator = self
	self._tracks = self._tracks or {}
	table.insert(self._tracks, track)
	return track
end
function instanceMethods:Play(fadeTime, weight, speed)
	if self.failPlay then error("mock playback unavailable") end
	self.playCount += 1
	self.IsPlaying = true
	self.lastFade, self.WeightTarget, self.Speed = fadeTime, weight, speed
	self._animator.AnimationPlayed:Fire(self)
end
function instanceMethods:Stop(fadeTime)
	self.stopCount += 1
	self.lastStopFade = fadeTime
	self.WeightTarget = 0
	self.IsPlaying = false
	if fadeTime == 0 then self.WeightCurrent = 0 end
end
function instanceMethods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do
		if parent == ancestor then return true end
		parent = parent.Parent
	end
	return false
end
function instanceMethods:Destroy()
	self.destroyed = true
	if self.ClassName == "AnimationTrack" then self.IsPlaying = false end
	self.Destroying:Fire()
	for _, child in self:GetChildren() do child:Destroy() end
	self.Parent = nil
end
function instanceMethods:Clone()
	local copies = {}
	local function allocate(source)
		local copy = InstanceMock.new(source.ClassName)
		copies[source] = copy
		copy.Name = source.Name
		for _, child in source:GetChildren() do allocate(child).Parent = copy end
		return copy
	end
	local result = allocate(self)
	for source, copy in copies do
		for name, value in source._values do
			if name ~= "Parent" and type(value) ~= "function" and not (type(value) == "table" and value.Connect) then
				copy[name] = copies[value] or value
			end
		end
		for name, value in source._attributes do copy:SetAttribute(name, value) end
	end
	return result
end

baseEnvironment.Enum = enumMock
baseEnvironment.Vector2 = { new = function(x, y) return { X = x, Y = y } end }
baseEnvironment.UDim2 = { new = function(xs, xo, ys, yo)
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end }
baseEnvironment.PhysicalProperties = { new = function(...) return { ... } end }
services.Workspace = InstanceMock.new("Workspace")
