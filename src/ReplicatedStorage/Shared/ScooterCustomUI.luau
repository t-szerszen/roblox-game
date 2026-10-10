--!strict
-- Native hexagons keep the palette sharp at every resolution without uploaded UI assets.
local UI = {}
local gold = Color3.fromRGB(255, 193, 87)
local ink = Color3.fromRGB(16, 18, 23)
local card = Color3.fromRGB(25, 29, 36)
local white = Color3.fromRGB(243, 239, 228)
local muted = Color3.fromRGB(139, 149, 162)

local function frame(parent, name, x, y, w, h, color)
 local f = Instance.new("Frame")
 f.Name, f.Position, f.Size = name, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
 f.BackgroundColor3, f.BorderSizePixel, f.Parent = color or card, 0, parent
 return f
end
local function round(f, radius)
 local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0,radius) c.Parent = f
end
local function label(parent, caption, x,y,w,h,size,color)
 local l = Instance.new("TextLabel")
 l.Text, l.Position, l.Size = caption, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
 l.BackgroundTransparency, l.Font, l.TextSize = 1, Enum.Font.GothamMedium, size
 l.TextColor3, l.TextXAlignment, l.Parent = color or white, Enum.TextXAlignment.Left, parent
 return l
end
local function button(parent, caption, x,y,w,h)
 local b = Instance.new("TextButton")
 b.Text, b.Position, b.Size = caption, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
 b.Font, b.TextSize, b.TextColor3 = Enum.Font.GothamBold, 13, white
 b.BackgroundColor3, b.BorderSizePixel, b.Parent = Color3.fromRGB(37,43,52), 0, parent
 round(b,10) return b
end
local function hexagon(parent, x,y,r,color,filled)
 local container = frame(parent,"Hexagon",x,y,r*math.sqrt(3),r*2,color)
 container.BackgroundTransparency = 1
 if filled then
  for _,angle in {0,60,120} do
   local strip = frame(container,"Fill",r*math.sqrt(3)/2,r,r*math.sqrt(3),r,color)
   strip.AnchorPoint, strip.Rotation = Vector2.new(.5,.5), angle
  end
 else
  for i=0,5 do
   local a,b = math.rad(i*60-90),math.rad((i+1)*60-90)
   local p,q = Vector2.new(math.cos(a)*r,math.sin(a)*r),Vector2.new(math.cos(b)*r,math.sin(b)*r)
   local edge = frame(container,"Edge",r*math.sqrt(3)/2+(p.X+q.X)/2,r+(p.Y+q.Y)/2,r,1,color)
   edge.AnchorPoint, edge.Rotation = Vector2.new(.5,.5),math.deg(math.atan2(q.Y-p.Y,q.X-p.X))
  end
 end
 return container
end

function UI.Create(gui, groups)
 local backdrop = frame(gui,"Backdrop",0,0,0,0,Color3.fromRGB(5,7,11))
 backdrop.Size,backdrop.BackgroundTransparency,backdrop.Active,backdrop.Visible=UDim2.fromScale(1,1),.28,true,false
 local panel = frame(gui,"HoneycombCustom",0,0,1020,660,ink)
 panel.Position, panel.AnchorPoint, panel.Visible = UDim2.fromScale(.5,.5),Vector2.new(.5,.5),false
 round(panel,22)
 local outline = Instance.new("UIStroke") outline.Color, outline.Transparency, outline.Parent = gold,.65,panel
 local scale = Instance.new("UIScale") scale.Parent = panel
 local top = frame(panel,"HoneyLine",26,0,968,2,gold)
 round(top,2)
 hexagon(panel,27,24,19,gold,false)
 label(panel,"H",34,27,24,30,20,gold).Font = Enum.Font.GothamBlack
 label(panel,"HONEYCOMB",78,21,300,32,25).Font = Enum.Font.GothamBlack
 label(panel,"CUSTOM GARAGE  /  STWÓRZ SWÓJ STYL",79,55,460,18,10,muted)
 local badge = frame(panel,"GarageBadge",780,29,151,30,Color3.fromRGB(48,39,24)) round(badge,15)
 label(badge,"●  WARSZTAT",20,0,130,30,10,gold)
 local closeButton = button(panel,"×",950,25,42,42)
 local stage = frame(panel,"Showroom",24,98,556,466,card) round(stage,16)
 stage.ClipsDescendants = true
 local gradient = Instance.new("UIGradient")
 gradient.Color = ColorSequence.new(Color3.fromRGB(39,44,54),Color3.fromRGB(19,22,28))
 gradient.Rotation, gradient.Parent = 65,stage
 for row=0,3 do for col=0,6 do
  local motif = hexagon(stage,20+col*75+(row%2)*37.5,42+row*65,42,Color3.fromRGB(67,72,79),false)
  for _,edge in motif:GetChildren() do if edge:IsA("Frame") then edge.BackgroundTransparency = .75 end end
 end end
 label(stage,"TWÓJ PROJEKT",22,16,260,24,10,gold)
 local viewport = Instance.new("ViewportFrame")
 viewport.Name, viewport.Position, viewport.Size = "ScooterPreview",UDim2.fromOffset(8,38),UDim2.fromOffset(540,380)
 viewport.BackgroundTransparency, viewport.Ambient = 1,Color3.fromRGB(180,183,198)
 viewport.LightColor, viewport.LightDirection = Color3.fromRGB(255,243,212),Vector3.new(-1,-1,-.5)
 viewport.Parent = stage
 local world = Instance.new("WorldModel") world.Parent = viewport
 local camera = Instance.new("Camera") camera.FieldOfView,camera.Parent = 35,viewport viewport.CurrentCamera = camera
 local left = button(stage,"‹",21,417,36,32)
 local right = button(stage,"›",499,417,36,32)
 label(stage,"OBRÓĆ PODGLĄD",188,422,220,22,10,muted)
 local picker = frame(panel,"Palette",596,98,400,466,card) round(picker,16)
 label(picker,"01  /  WYBIERZ ELEMENT  •  PRZEWIŃ ↔",18,12,365,20,10,gold)
 local tabs = {}
 local categoryScroll = Instance.new("ScrollingFrame")
 categoryScroll.Name,categoryScroll.Position,categoryScroll.Size = "Categories",UDim2.fromOffset(16,40),UDim2.fromOffset(368,40)
 categoryScroll.BackgroundTransparency,categoryScroll.BorderSizePixel = 1,0
 categoryScroll.ScrollingDirection,categoryScroll.ScrollBarThickness = Enum.ScrollingDirection.X,3
 categoryScroll.ScrollBarImageColor3 = gold
 categoryScroll.CanvasSize = UDim2.fromOffset(#groups*124-6,0)
 categoryScroll.Parent = picker
 for index,group in groups do
  tabs[group.Id] = button(categoryScroll,group.Label,(index-1)*124,0,118,32)
 end
 label(picker,"02  /  ZNAJDŹ SWÓJ KOLOR",18,91,340,20,10,gold)
 local swatches = {}
 local palette = {
  "FFF5D6","FFE29B","FFC157","FF9A42","F47747","E65363","DD5596",
  "A855F7","7857E7","576DE8","448CFA","47BBDD","51D2BB","62CD81",
  "A2D562","D6D36A","C49464","9A655A","684B60","514873","3B5969",
  "FFFFFF","C8CDD4","939EAB","637080","3C4756","252D38","121820",
 }
 for index,code in palette do
  local row,col = math.floor((index-1)/7),(index-1)%7
  local color = Color3.fromHex(code)
  local x,y = 22+col*48+(row%2)*24,123+row*39
  local shape = hexagon(picker,x,y,25,color,true)
  local selected = hexagon(picker,x-2,y-2,27,gold,false) selected.Visible = false
  local hit = button(picker,"",x,y,43,50)
  hit.BackgroundTransparency,hit.ZIndex = 1,3
  table.insert(swatches,{Button=hit,Color=color,Selection=selected})
 end
 local sliders = {}
 for index,name in {"Hue","Saturation","Value"} do
  local y=318+(index-1)*32
  local captions = {Hue="BARWA",Saturation="NASYCENIE",Value="JASNOŚĆ"}
  label(picker,captions[name],18,y-3,88,21,9,muted)
  local bar = frame(picker,name,112,y,266,12,white) round(bar,6) bar.Active=true
  local g = Instance.new("UIGradient") g.Parent = bar
  local thumb = frame(bar,"Thumb",0,6,5,22,white) thumb.AnchorPoint=Vector2.new(.5,.5) round(thumb,2)
  local st=Instance.new("UIStroke") st.Color,st.Thickness,st.Parent=ink,1,thumb
  sliders[name]={Bar=bar,Gradient=g,Thumb=thumb}
 end
 local swatch = frame(picker,"CurrentColor",18,419,34,30,white) round(swatch,8)
 local hex = Instance.new("TextBox")
 hex.Name,hex.Position,hex.Size="HexColor",UDim2.fromOffset(62,419),UDim2.fromOffset(180,30)
 hex.Text,hex.PlaceholderText,hex.ClearTextOnFocus="#FFFFFF","#RRGGBB",false
 hex.Font,hex.TextSize,hex.TextColor3=Enum.Font.GothamBold,14,white
 hex.BackgroundColor3,hex.BorderSizePixel,hex.Parent=ink,0,picker round(hex,8)
 label(picker,"WŁASNY HEX",259,425,125,19,9,muted)
 label(panel,"TWÓJ KOLOR. TWÓJ CHARAKTER.",26,581,500,24,12)
 label(panel,"Wybierz kolor • obejrzyj podgląd • zatwierdź",26,610,540,22,11,muted)
 local apply = button(panel,"ZATWIERDŹ PROJEKT  →",596,582,265,48)
 apply.BackgroundColor3,apply.TextColor3=gold,ink
 local reset = button(panel,"Resetuj",871,582,125,48)
 local status = label(panel,"",596,636,400,16,10,muted)
 return {Panel=panel,Backdrop=backdrop,Scale=scale,Viewport=viewport,World=world,Camera=camera,
  Close=closeButton,Apply=apply,Reset=reset,Status=status,Hex=hex,Swatch=swatch,
  Tabs=tabs,Swatches=swatches,Sliders=sliders,Left=left,Right=right,Gold=gold}
end
return UI
