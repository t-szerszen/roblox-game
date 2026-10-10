--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScooterCustomConfig"))
local Paint = require(ReplicatedStorage.Shared:WaitForChild("ScooterCustomPaint"))
local action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ScooterCustom"):WaitForChild("Action") :: RemoteFunction
local opened = action.Parent:WaitForChild("Opened") :: RemoteEvent
local player = Players.LocalPlayer
local connections: {RBXScriptConnection} = {}
local characterConnections: {RBXScriptConnection} = {}
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ScooterCustomUI", false, 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local active = true
local generation = 0
local busy = false
local sourceModel: Model? = nil
local preview: Model? = nil
local colors: {[string]: Color3} = {}
local selected = "Deck"
local hue, saturation, value = 0, 0, 1
local drag: string? = nil
local touch: InputObject? = nil
local watchedCharacter: Model? = nil
local UI = require(ReplicatedStorage.Shared:WaitForChild("ScooterCustomUI"))
local ui = UI.Create(gui, Config.Groups)
local panel, scale = ui.Panel, ui.Scale
local viewport, world, camera = ui.Viewport, ui.World, ui.Camera
local closeButton, applyButton, resetButton = ui.Close, ui.Apply, ui.Reset
local status, hex, swatch, tabs = ui.Status, ui.Hex, ui.Swatch, ui.Tabs
local rotation = 0
local previewCenter, previewOffset, previewDistance = Vector3.zero, Vector3.new(1,.5,1), 10
local function fit()
 local size = gui.AbsoluteSize
 scale.Scale = math.min(1, math.max(.25, math.min((size.X-24)/1020,(size.Y-24)/660)))
end
table.insert(connections,gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)) fit()

local function refreshPicker()
 local color = colors[selected] or Color3.new(1, 1, 1)
 hue, saturation, value = color:ToHSV()
 local hueKeys = {}
 for n=0,6 do table.insert(hueKeys,ColorSequenceKeypoint.new(n/6,Color3.fromHSV(n/6,1,1))) end
 ui.Sliders.Hue.Gradient.Color = ColorSequence.new(hueKeys)
 ui.Sliders.Saturation.Gradient.Color = ColorSequence.new(Color3.fromHSV(hue,0,value),Color3.fromHSV(hue,1,value))
 ui.Sliders.Value.Gradient.Color = ColorSequence.new(Color3.new(0,0,0),Color3.fromHSV(hue,saturation,1))
 for name,amount in {Hue=hue,Saturation=saturation,Value=value} do ui.Sliders[name].Thumb.Position=UDim2.fromScale(amount,.5) end
 swatch.BackgroundColor3,hex.Text = color,"#" .. string.upper(color:ToHex())
 for id,tab in tabs do
  tab.BackgroundColor3 = if id==selected then ui.Gold else Color3.fromRGB(37,43,52)
  tab.TextColor3 = if id==selected then Color3.fromRGB(16,18,23) else Color3.fromRGB(243,239,228)
 end
 for _,item in ui.Swatches do item.Selection.Visible = math.abs(item.Color.R-color.R)+math.abs(item.Color.G-color.G)+math.abs(item.Color.B-color.B) < .008 end
end
local function setColor(color: Color3)
 colors[selected] = color
 if preview then Paint.Apply(preview, colors) end
 refreshPicker()
 status.Text = "Podgląd — zatwierdź projekt, aby zapisać kolory."
end
local function close()
 generation += 1 busy = false panel.Visible = false sourceModel = nil drag = nil touch = nil
 if preview then preview:Destroy() preview = nil end
end
local function ownsModel(model: any): boolean
 return typeof(model)=="Instance" and model:IsA("Model") and model:IsDescendantOf(workspace)
  and model:GetAttribute("OwnerUserId")==player.UserId
end
local function makePreview(model: Model)
 if preview then preview:Destroy() preview = nil end
 local clone = model:Clone()
 if not clone then status.Text = "Podgląd modelu niedostępny." return end
 for _,item in clone:GetDescendants() do
  if item:IsA("LuaSourceContainer") or item:IsA("Constraint") or item:IsA("JointInstance") or item:IsA("WeldConstraint")
   or item:IsA("ProximityPrompt") or item:IsA("ParticleEmitter") or item:IsA("Sound") then item:Destroy()
  elseif item:IsA("BasePart") then
   if item.Transparency >= 1 then item:Destroy() else item.Anchored = true item.CanCollide = false item.CanTouch = false end
  end
 end
 clone.Parent = world preview = clone
 local bounds, size = clone:GetBoundingBox()
 local center = bounds.Position
 local root = model.PrimaryPart
 local offset = if root then root.CFrame.RightVector * 1.2 - root.CFrame.LookVector * .8 + Vector3.yAxis * .55 else Vector3.new(1, .5, 1)
 local distance = size.Magnitude / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.05
 previewCenter,previewOffset,previewDistance,rotation = center,offset.Unit,distance,0
 camera.CFrame = CFrame.lookAt(center + offset.Unit * distance, center)
 Paint.Apply(clone, colors)
end
local function call(operation: string)
 if busy then return end
 local token = generation
 busy = true
 status.Text = "Chwilę…"
 local target = sourceModel
 local palette = if operation == "Apply" then table.clone(colors) else nil
 task.spawn(function()
  local ok, response = pcall(function()
   return action:InvokeServer(operation, target, palette)
  end)
  if not active or token ~= generation then return end
  busy = false
  if not ok or typeof(response) ~= "table" or response.ok ~= true then
   status.Text = if ok and typeof(response) == "table" then response.message or "Nie udało się zmienić koloru." else "Brak połączenia. Spróbuj ponownie."
   return
  end
  if not ownsModel(response.model) or response.model~=target then close() return end
  sourceModel, colors = response.model, response.colors
  if preview then Paint.Apply(preview, colors) end
  refreshPicker()
  status.Text = if operation == "Reset" then "Przywrócono kolory początkowe." else "Kolory zastosowane."
 end)
end
for id, tab in tabs do table.insert(connections, tab.Activated:Connect(function() selected = id refreshPicker() end)) end
for _,item in ui.Swatches do
 table.insert(connections,item.Button.Activated:Connect(function() setColor(item.Color) end))
 table.insert(connections,item.Button.MouseEnter:Connect(function() item.Selection.Visible=true end))
 table.insert(connections,item.Button.MouseLeave:Connect(refreshPicker))
end
local function rotate(amount: number)
 rotation += amount
 local offset = CFrame.Angles(0,rotation,0):VectorToWorldSpace(previewOffset)
 TweenService:Create(camera,TweenInfo.new(.22),{CFrame=CFrame.lookAt(previewCenter+offset*previewDistance,previewCenter)}):Play()
end
table.insert(connections,ui.Left.Activated:Connect(function() rotate(-math.pi/6) end))
table.insert(connections,ui.Right.Activated:Connect(function() rotate(math.pi/6) end))
table.insert(connections, hex.FocusLost:Connect(function()
 local input = string.upper(hex.Text):gsub("#", "")
 if #input == 6 and input:match("^%x+$") then setColor(Color3.fromHex(input)) else refreshPicker() status.Text = "Wpisz kolor, np. #FF00CC." end
end))
local function updateDrag(position: Vector3)
 if not panel.Visible then return end
 local point = Vector2.new(position.X, position.Y)
 if drag and ui.Sliders[drag] then
  local bar = ui.Sliders[drag].Bar
  local amount=math.clamp((point.X-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1)
  if drag=="Hue" then hue=amount elseif drag=="Saturation" then saturation=amount else value=amount end
  setColor(Color3.fromHSV(hue,saturation,value))
 end
end
local function startDrag(kind: string, input: InputObject)
 if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
 drag, touch = kind, if input.UserInputType == Enum.UserInputType.Touch then input else nil
 updateDrag(input.Position)
end
for name,slider in ui.Sliders do
 table.insert(connections,slider.Bar.InputBegan:Connect(function(input) startDrag(name,input) end))
end
table.insert(connections, UserInputService.InputChanged:Connect(function(input)
 if drag and (input == touch or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)) then updateDrag(input.Position) end
end))
table.insert(connections, UserInputService.InputEnded:Connect(function(input)
 if input == touch or input.UserInputType == Enum.UserInputType.MouseButton1 then drag = nil touch = nil end
end))
table.insert(connections, closeButton.Activated:Connect(function() close() end))
table.insert(connections, applyButton.Activated:Connect(function() call("Apply") end))
table.insert(connections, resetButton.Activated:Connect(function() call("Reset") end))
local function refreshAccess()
 ui.Backdrop.Visible=panel.Visible
 if sourceModel and not ownsModel(sourceModel) then close() end
end
-- The server sends entry/exit transitions; closing manually stays closed until re-entry.
table.insert(connections,opened.OnClientEvent:Connect(function(response)
 if not active or typeof(response)~="table" then return end
 if response.close==true then close() return end
 if not ownsModel(response.model) then return end
 close()
 sourceModel,colors=response.model,response.colors
 panel.Visible=true
 local ok=pcall(function() makePreview(response.model) end)
 refreshPicker() refreshAccess()
 panel.Position=UDim2.fromScale(.5,.53)
 TweenService:Create(panel,TweenInfo.new(.25,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
 status.Text=if ok then "Wybierz detal i stwórz swój projekt." else "Podgląd niedostępny — kolory możesz nadal zmieniać."
end))

table.insert(connections,panel:GetPropertyChangedSignal("Visible"):Connect(refreshAccess))
local function bind(character: Model)
 for _,connection in characterConnections do connection:Disconnect() end table.clear(characterConnections)
 watchedCharacter = character close()
 task.spawn(function()
  local humanoid = character:WaitForChild("Humanoid", 10)
  if not active or watchedCharacter ~= character or not humanoid or not humanoid:IsA("Humanoid") then return end
  table.insert(characterConnections, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
   refreshAccess()
  end))
  table.insert(characterConnections, humanoid.Died:Connect(function() close() end))
  refreshAccess()
 end)
end
table.insert(connections, player.CharacterAdded:Connect(bind))
table.insert(connections, player.CharacterRemoving:Connect(function()
 watchedCharacter = nil
 for _,connection in characterConnections do connection:Disconnect() end table.clear(characterConnections)
 close()
end))
if player.Character then bind(player.Character) end
table.insert(connections, gui.Destroying:Connect(function()
 active = false close()
 for _,connection in connections do connection:Disconnect() end
 for _,connection in characterConnections do connection:Disconnect() end
end))
table.insert(connections, script.Destroying:Connect(function() gui:Destroy() end))

-- Handshake prevents the initial entry event being sent before the UI listener exists.
task.spawn(function()
 local ok,response=pcall(function() return action:InvokeServer("Ready") end)
 if active and (not ok or typeof(response)~="table" or response.ok~=true) then
  task.wait(1)
  if active then pcall(function() action:InvokeServer("Ready") end) end
 end
end)
