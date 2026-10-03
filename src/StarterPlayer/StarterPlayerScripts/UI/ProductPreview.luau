--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local Layout = require(ReplicatedStorage.Shared.UI.Layout)
local UI = require(ReplicatedStorage.Shared.UI.Components)
local PreviewConfig = require(ReplicatedStorage.Shared.Shop.PreviewConfig)
type Entry = { key: string, view: ViewportFrame, camera: Camera, world: WorldModel, placeholder: TextLabel, size: Vector3? }

local ProductPreview = {}

function ProductPreview.new(owner: Scope.Scope, scroll: ScrollingFrame)
	local entries: { Entry } = {}
	local active = false
	local renderConnection: RBXScriptConnection? = nil
	local folderScope: Scope.Scope? = nil
	local angle = math.rad(35)
	local function load(entry: Entry)
		entry.world:ClearAllChildren()
		entry.size = nil
		entry.placeholder.Visible = true
		local folder = ReplicatedStorage:FindFirstChild(PreviewConfig.FolderName)
		local template = if folder then folder:FindFirstChild(entry.key) else nil
		if not template or not template:IsA("Model") then return end
		local model = template:Clone()
		model.Parent = entry.world
		local _, size = model:GetBoundingBox()
		entry.size = size
		entry.placeholder.Visible = false
	end
	local function draw()
		local top = scroll.AbsolutePosition.Y
		local bottom = top + scroll.AbsoluteSize.Y
		for _, entry in entries do
			local size = entry.size
			if not size or entry.view.AbsolutePosition.Y + entry.view.AbsoluteSize.Y < top
				or entry.view.AbsolutePosition.Y > bottom then continue end
			local aspect = entry.view.AbsoluteSize.X / math.max(1, entry.view.AbsoluteSize.Y)
			local distance = Layout.PreviewDistance(size, aspect)
			local direction = Vector3.new(math.sin(angle) * 0.97, 0.24, math.cos(angle) * 0.97).Unit
			entry.camera.CFrame = CFrame.lookAt(direction * distance, Vector3.zero)
		end
	end
	local function watchFolder(folder: Instance)
		if folder.Name ~= PreviewConfig.FolderName then return end
		if folderScope then folderScope:Clean() end
		local scope = Scope.new()
		folderScope = scope
		local function changed(child: Instance)
			for _, entry in entries do if entry.key == child.Name then load(entry) end end
			if active then draw() end
		end
		scope:Give(folder.ChildAdded:Connect(changed))
		scope:Give(folder.ChildRemoved:Connect(changed))
		for _, entry in entries do load(entry) end
	end
	owner:Give(ReplicatedStorage.ChildAdded:Connect(watchFolder))
	owner:Give(ReplicatedStorage.ChildRemoved:Connect(function(folder)
		if folder.Name ~= PreviewConfig.FolderName then return end
		if folderScope then folderScope:Clean(); folderScope = nil end
		for _, entry in entries do load(entry) end
	end))
	local existing = ReplicatedStorage:FindFirstChild(PreviewConfig.FolderName)
	if existing then watchFolder(existing) end
	owner:Give(function()
		if renderConnection then renderConnection:Disconnect() end
		if folderScope then folderScope:Clean() end
		table.clear(entries)
	end)
	return {
		SetActive = function(enabled: boolean)
			active = enabled
			if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
			if enabled then
				draw()
				renderConnection = RunService.RenderStepped:Connect(function(dt)
					angle = (angle + Theme.Shop.PreviewRotationSpeed * dt) % (math.pi * 2)
					draw()
				end)
			end
		end,
		Mount = function(parent: Frame, key: string, scope: Scope.Scope)
			local view = Instance.new("ViewportFrame")
			view.Name = "ModelPreview"
			view.BackgroundTransparency = 1
			view.Size = UDim2.fromScale(1, 1)
			view.Ambient = Theme.Shop.PreviewAmbient
			view.LightColor = Color3.fromRGB(255, 244, 230)
			view.LightDirection = Vector3.new(-1, -1, -1)
			view.Parent = parent
			local camera = Instance.new("Camera")
			camera.FieldOfView = Theme.Shop.PreviewFieldOfView
			camera.Parent = view
			view.CurrentCamera = camera
			local world = Instance.new("WorldModel")
			world.Parent = view
			local placeholder = UI.Label(parent, "Podgląd niedostępny", 13, true)
			placeholder.Size = UDim2.fromScale(1, 1)
			placeholder.TextXAlignment = Enum.TextXAlignment.Center
			local entry: Entry = { key = key, view = view, camera = camera, world = world, placeholder = placeholder, size = nil }
			table.insert(entries, entry)
			load(entry)
			if active then draw() end
			scope:Give(function()
				local index = table.find(entries, entry)
				if index then table.remove(entries, index) end
				view:Destroy()
				placeholder:Destroy()
			end)
		end,
	}
end

export type Controller = typeof(ProductPreview.new(nil :: any, nil :: any))
return ProductPreview
