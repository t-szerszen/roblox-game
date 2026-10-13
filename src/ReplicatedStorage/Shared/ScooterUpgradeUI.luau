--!strict
local Catalog = require(script.Parent.ScooterUpgradeCatalog)
local Config = require(script.Parent.ScooterConfig)
local Thumbnails=require(script.Parent.ScooterUpgradeThumbnails)
local UI = {}
local gold = Color3.fromRGB(255,193,87)
local muted = Color3.fromRGB(139,149,162)
local function round(parent: Instance, radius: number)
	local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,radius) c.Parent=parent
end
local function label(parent: Instance, text: string, position: UDim2, size: UDim2, fontSize: number)
	local l=Instance.new("TextLabel")
	l.Text=text l.Position=position l.Size=size
	l.BackgroundTransparency=1 l.Font=Enum.Font.GothamMedium l.TextSize=fontSize
	l.TextColor3=Color3.fromRGB(243,239,228) l.TextXAlignment=Enum.TextXAlignment.Left
	l.Parent=parent return l
end
function UI.Create(panel: Frame)
	local body=Instance.new("Frame")
	body.Name="Performance" body.Position=UDim2.fromOffset(24,98) body.Size=UDim2.fromOffset(972,466)
	body.BackgroundColor3=Color3.fromRGB(25,29,36) body.BorderSizePixel=0 body.Visible=false
	body.Parent=panel round(body,16)
	local title=label(body,"",UDim2.fromOffset(18,10),UDim2.fromOffset(935,22),16)
	title.TextColor3=gold title.Font=Enum.Font.GothamBold
	local stats=label(body,"",UDim2.fromOffset(18,36),UDim2.fromOffset(935,28),13)
	local scroll=Instance.new("ScrollingFrame")
	scroll.Name="UpgradeCards" scroll.Position=UDim2.fromOffset(14,78) scroll.Size=UDim2.fromOffset(944,374)
	scroll.BackgroundTransparency=1 scroll.BorderSizePixel=0 scroll.ScrollBarThickness=4
	scroll.ScrollBarImageColor3=gold scroll.CanvasSize=UDim2.fromOffset(0,math.ceil(#Catalog.Items/3)*272)
	scroll.Parent=body
	local cards={}
	for index,item in Catalog.Items do
		local col,row=(index-1)%3,math.floor((index-1)/3)
		local card=Instance.new("Frame")
		card.Name=item.Id card.Position=UDim2.fromOffset(col*313,row*272) card.Size=UDim2.fromOffset(301,260)
		card.BackgroundColor3=Color3.fromRGB(16,18,23) card.BorderSizePixel=0 card.Parent=scroll round(card,12)
		local stroke=Instance.new("UIStroke") stroke.Color=Color3.fromRGB(63,69,82) stroke.Parent=card
		local graphic=Instance.new("Frame")
		graphic.Name="UpgradeArtwork" graphic.Position=UDim2.fromOffset(12,12) graphic.Size=UDim2.fromOffset(277,110)
		graphic.BackgroundColor3=Color3.fromRGB(43,59,98) graphic.BorderSizePixel=0 graphic.ClipsDescendants=true
		graphic.Parent=card round(graphic,10)
		local gradient=Instance.new("UIGradient")
		gradient.Color=ColorSequence.new(Color3.fromRGB(74,92,160),Color3.fromRGB(23,30,50))
		gradient.Rotation=55 gradient.Parent=graphic
		local viewport=Instance.new("ViewportFrame")
		viewport.Name="PartPreview" viewport.Size=UDim2.fromScale(1,1) viewport.BackgroundTransparency=1
		viewport.Ambient=Color3.fromRGB(160,168,194) viewport.LightColor=Color3.fromRGB(255,237,206)
		viewport.LightDirection=Vector3.new(-1,-1,-.5) viewport.Parent=graphic
		local world=Instance.new("WorldModel") world.Parent=viewport
		local camera=Instance.new("Camera") camera.FieldOfView=32 camera.Parent=viewport viewport.CurrentCamera=camera
		local symbols={Vesc="VESC",WeightReduction="−2 kg",WheelieMode="WHEELIE",DualMotor="2× MOTOR",Brakes="+25%",Battery1Kw="+1 kW"}
		local symbol=label(graphic,symbols[item.Id] or "",UDim2.fromOffset(9,8),UDim2.fromOffset(130,17),10)
		symbol.TextColor3=gold symbol.Font=Enum.Font.GothamBold symbol.ZIndex=2
		local badge=label(card,"",UDim2.fromOffset(14,128),UDim2.fromOffset(273,14),9)
		badge.TextXAlignment=Enum.TextXAlignment.Right badge.TextColor3=muted
		label(card,item.Label,UDim2.fromOffset(14,147),UDim2.fromOffset(275,24),14).Font=Enum.Font.GothamBold
		local desc=label(card,item.Description,UDim2.fromOffset(14,176),UDim2.fromOffset(273,32),11)
		desc.TextWrapped=true desc.TextYAlignment=Enum.TextYAlignment.Top desc.TextColor3=muted
		local b=Instance.new("TextButton")
		b.Name="Install" b.Position=UDim2.fromOffset(12,216) b.Size=UDim2.fromOffset(277,32)
		b.Font=Enum.Font.GothamBold b.TextSize=12 b.TextColor3=Color3.new(1,1,1)
		b.BackgroundColor3=Color3.fromRGB(0,172,111) b.BorderSizePixel=0 b.Parent=card round(b,8)
		cards[item.Id]={Button=b,Badge=badge,Stroke=stroke,World=world,Camera=camera}
	end
	return {Body=body,Title=title,Stats=stats,Cards=cards}
end
function UI.Update(view: any, state: any)
	view.Title.Text=state.modelName
	local s=state.stats
	view.Stats.Text=string.format("%.1f km/h   |   Start +%.0f%%   |   Zdjęta waga %.1f kg   |   Moc +%.0f W   |   Hamowanie %.0f%%",
		s.SpeedKmh,s.StartBonusPercent,s.WeightRemovedKg,s.AddedPowerWatts,(s.BrakeForce/Config.BrakingDeceleration-1)*100)
	for id,card in view.Cards do
		local installed=state.equipped[id] == true
		card.Button.Text=if installed then "Zdejmij wyposażenie" else "Instalacja · bezpłatnie"
		card.Button.BackgroundColor3=if installed then Color3.fromRGB(57,65,92) else Color3.fromRGB(0,172,111)
		card.Button.Active=state.ready == true
		card.Badge.Text=if installed then "● ZAINSTALOWANE" else if state.owned[id] then "POSIADANE" else "DOSTĘPNE"
		card.Stroke.Color=if installed then gold else Color3.fromRGB(63,69,82)
	end
end
UI.BuildThumbnails=Thumbnails.Build
UI.ClearThumbnails=Thumbnails.Clear
return UI
