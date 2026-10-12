--!strict
local UI = {}
function UI.Create(parent: Instance, config)
 local gui = Instance.new("ScreenGui")
 gui.Name,gui.IgnoreGuiInset,gui.ResetOnSpawn = "ScooterLoadingScreen",true,false
 gui.DisplayOrder,gui.ZIndexBehavior = 10000,Enum.ZIndexBehavior.Sibling
 local root=Instance.new("Frame")
 root.Name,root.Size,root.BackgroundColor3,root.BorderSizePixel="Root",UDim2.fromScale(1,1),Color3.fromRGB(12,17,24),0
 root.Active,root.Parent=true,gui
 local background=Instance.new("ImageLabel")
 background.Name,background.Size,background.BackgroundTransparency="CityBackground",UDim2.fromScale(1,1),1
 background.Image,background.ScaleType,background.Parent=config.Background,Enum.ScaleType.Crop,root
 local shade=Instance.new("Frame")
 shade.Size,shade.BackgroundColor3,shade.BackgroundTransparency=UDim2.fromScale(1,1),Color3.fromRGB(6,10,17),.35
 shade.BorderSizePixel,shade.Parent=0,root
 local gradient=Instance.new("UIGradient")
 gradient.Rotation=90
 gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(.55,.05),NumberSequenceKeypoint.new(1,0)})
 gradient.Parent=shade
 local card=Instance.new("Frame")
 card.Size,card.Position,card.AnchorPoint=UDim2.fromOffset(520,410),UDim2.fromScale(.5,.5),Vector2.new(.5,.5)
 card.BackgroundTransparency,card.Parent=1,root
 local scale=Instance.new("UIScale") scale.Parent=card
 local function label(caption: string,y: number,height: number,size: number,color: Color3)
  local l=Instance.new("TextLabel")
  l.Text,l.Position,l.Size=caption,UDim2.fromOffset(0,y),UDim2.fromOffset(520,height)
  l.BackgroundTransparency,l.TextColor3,l.Font,l.TextSize=1,color,Enum.Font.GothamBold,size
  l.Parent=card return l
 end
 local wheel=Instance.new("Frame")
 wheel.Name,wheel.Size,wheel.Position,wheel.AnchorPoint="ScooterWheel",UDim2.fromOffset(146,146),UDim2.fromOffset(260,100),Vector2.new(.5,.5)
 wheel.BackgroundColor3,wheel.BorderSizePixel,wheel.Parent=Color3.fromRGB(15,18,24),0,card
 local corner=Instance.new("UICorner") corner.CornerRadius=UDim.new(1,0) corner.Parent=wheel
 local rim=Instance.new("UIStroke") rim.Color,rim.Thickness,rim.Parent=config.Accent,5,wheel
 for n=0,7 do
  local spoke=Instance.new("Frame")
  spoke.Size,spoke.Position,spoke.AnchorPoint=UDim2.fromOffset(98,5),UDim2.fromScale(.5,.5),Vector2.new(.5,.5)
  spoke.Rotation,spoke.BackgroundColor3,spoke.BorderSizePixel,spoke.Parent=n*45,Color3.fromRGB(182,193,202),0,wheel
 end
 local hub=Instance.new("Frame")
 hub.Size,hub.Position,hub.AnchorPoint=UDim2.fromOffset(29,29),UDim2.fromScale(.5,.5),Vector2.new(.5,.5)
 hub.BackgroundColor3,hub.BorderSizePixel,hub.Parent=config.Accent,0,wheel
 local hubCorner=Instance.new("UICorner") hubCorner.CornerRadius=UDim.new(1,0) hubCorner.Parent=hub
 label("ZA CHWILĘ RUSZAMY",195,36,27,Color3.new(1,1,1))
 local status=label("Łączenie z miastem…",237,25,13,Color3.fromRGB(209,215,224))
 status.Font=Enum.Font.GothamMedium
 local percentage=label("0%",276,40,29,config.Accent)
 local track=Instance.new("Frame")
 track.Position,track.Size,track.BackgroundColor3=UDim2.fromOffset(60,335),UDim2.fromOffset(400,5),Color3.fromRGB(61,69,82)
 track.BorderSizePixel,track.Parent=0,card
 local fill=Instance.new("Frame")
 fill.Name,fill.Size,fill.BackgroundColor3,fill.BorderSizePixel,fill.Parent="Progress",UDim2.fromScale(0,1),config.Accent,0,track
 local note=label("Miasto • hulajnogi • własny styl",361,23,11,Color3.fromRGB(183,192,206))
 note.Font=Enum.Font.GothamMedium
 gui.Parent=parent
 return {Gui=gui,Root=root,Background=background,Wheel=wheel,Scale=scale,Status=status,Percentage=percentage,Fill=fill}
end
return UI
