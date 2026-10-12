--!strict
local Players=game:GetService("Players")
local ReplicatedFirst=game:GetService("ReplicatedFirst")
local ContentProvider=game:GetService("ContentProvider")
local TweenService=game:GetService("TweenService")
local ContextActionService=game:GetService("ContextActionService")
local Config=require(script.Parent:WaitForChild("LoadingConfig"))
local UI=require(script.Parent:WaitForChild("LoadingUI"))
local player=Players.LocalPlayer
local view=UI.Create(player:WaitForChild("PlayerGui"),Config)
ReplicatedFirst:RemoveDefaultLoadingScreen()
local started=os.clock()
local alive=true
local progress=0
local movementAction="ScooterLoadingMovement"
local connections: {RBXScriptConnection}={}
local spin=TweenService:Create(view.Wheel,TweenInfo.new(1.7,Enum.EasingStyle.Linear,Enum.EasingDirection.In,-1),{Rotation=360})
spin:Play()
ContextActionService:BindActionAtPriority(movementAction,function() return Enum.ContextActionResult.Sink end,false,10000,
 Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Space,
 Enum.KeyCode.Up,Enum.KeyCode.Down,Enum.KeyCode.Left,Enum.KeyCode.Right,Enum.KeyCode.Thumbstick1,Enum.KeyCode.ButtonA)
local function fit()
 local size=view.Gui.AbsoluteSize
 view.Scale.Scale=math.min(1,math.max(.3,math.min((size.X-24)/520,(size.Y-24)/410)))
end
table.insert(connections,view.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)) fit()
local function cleanup()
 if not alive then return end
 alive=false spin:Cancel()
 ContextActionService:UnbindAction(movementAction)
 for _,c in connections do c:Disconnect() end
 table.clear(connections)
end
table.insert(connections,view.Gui.Destroying:Connect(cleanup))
table.insert(connections,script.Destroying:Connect(function() cleanup() view.Gui:Destroy() end))
local function update(amount: number,caption: string?)
 if not alive then return end
 progress=math.max(progress,math.clamp(amount,0,100))
 view.Percentage.Text=tostring(math.floor(progress)).."%"
 view.Fill.Size=UDim2.fromScale(progress/100,1)
 if caption then view.Status.Text=caption end
end
local function finish(complete: boolean)
 if not alive then return end
 if complete then
  update(100,"Gotowe. Witaj w mieście!")
 end
 task.wait(math.max(.4,Config.MinimumVisibleTime-(os.clock()-started)))
 if not alive then return end
 -- Fade existing objects once; animation and input bindings are always released.
 for _,item in view.Gui:GetDescendants() do
  if item:IsA("GuiObject") then
   local props: {[string]: number}={BackgroundTransparency=1}
   if item:IsA("TextLabel") then props.TextTransparency=1 end
   if item:IsA("ImageLabel") then props.ImageTransparency=1 end
   TweenService:Create(item,TweenInfo.new(Config.FadeTime),props):Play()
  elseif item:IsA("UIStroke") then TweenService:Create(item,TweenInfo.new(Config.FadeTime),{Transparency=1}):Play() end
 end
 task.wait(Config.FadeTime)
 cleanup() view.Gui:Destroy()
end
task.spawn(function()
 local ok,problem=pcall(function()
  local deadline=os.clock()+Config.GameTimeout
  while alive and not game:IsLoaded() and os.clock()<deadline do task.wait(.1) end
  if not alive then return end
  if not game:IsLoaded() then finish(false) return end
  update(20,"Przygotowywanie postaci…")
  deadline=os.clock()+Config.CharacterTimeout
  local root: BasePart?=nil
  while alive and os.clock()<deadline do
   local character=player.Character
   local candidate=character and character:FindFirstChild("HumanoidRootPart")
   if candidate and candidate:IsA("BasePart") then root=candidate break end
   task.wait(.1)
  end
  if not alive then return end
  if not root then finish(false) return end
  update(35,"Wczytywanie otoczenia startowego…")
  if workspace.StreamingEnabled then
   local streamDone=false
   task.spawn(function()
    pcall(function() player:RequestStreamAroundAsync(root.Position,Config.StreamTimeout) end)
    streamDone=true
   end)
   deadline=os.clock()+Config.StreamTimeout+1
   while alive and not streamDone and os.clock()<deadline do task.wait(.1) end
  end
  if not alive then return end
  update(60,"Wczytywanie tekstur i modeli…")
  -- Only nearby assets are preloaded; a streamed world has no meaningful global percent.
  local assets: {string | Instance}={}
  local seen: {[string | Instance]: boolean}={}
  local function add(id: string | Instance)
   if id~="" and not seen[id] and #assets<Config.AssetLimit then seen[id]=true table.insert(assets,id) end
  end
  add(Config.Background)
  local params=OverlapParams.new() params.MaxParts=Config.PartLimit
  for _,part in workspace:GetPartBoundsInRadius(root.Position,Config.SpawnRadius,params) do
   if part:IsA("MeshPart") then add(part.MeshId) add(part.TextureID) end
   for _,child in part:GetChildren() do
    -- Map properties are restricted to plugins; preload the instance at runtime.
    if child:IsA("SurfaceAppearance") then add(child)
    elseif child:IsA("Decal") or child:IsA("Texture") then add(child.Texture) end
   end
  end
  local completed,nextIndex=0,0
  local assetsOpen=true
  for _=1,math.min(Config.AssetWorkers,#assets) do
   task.spawn(function()
    while alive and assetsOpen do
     nextIndex+=1
     local id=assets[nextIndex]
     if not id then break end
     pcall(function() ContentProvider:PreloadAsync({id}) end)
     if not alive or not assetsOpen then return end
     completed+=1
     update(60+completed/#assets*35)
    end
   end)
  end
  deadline=os.clock()+Config.AssetTimeout
  while alive and completed<#assets and os.clock()<deadline do task.wait(.1) end
  assetsOpen=false
  if not alive then return end
  update(95,if completed<#assets then "Pozostałe detale doczytają się podczas jazdy…" else "Kończymy przygotowanie miasta…")
  finish(true)
 end)
 if not ok then
  warn("Scooter loading screen: "..tostring(problem))
  view.Status.Text="Pozostałe detale doczytają się podczas jazdy…"
  finish(false)
 end
end)
