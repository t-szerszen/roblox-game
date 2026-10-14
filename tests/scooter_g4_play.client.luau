-- Temporary LocalScript paired with scooter_g4_play.server.luau.
local player=game.Players.LocalPlayer
local qa=workspace:WaitForChild("_ScooterG4PlayQA")
local controls=player.PlayerScripts:FindFirstChild("ScooterClient")
if controls then controls:Destroy() end
local remotes=game.ReplicatedStorage.Remotes.ScooterRemotes
local last,elapsed=nil,0
local connection
connection=game.RunService.Heartbeat:Connect(function(dt)
	local phase=qa:GetAttribute("Phase")
	if phase~=last then
		last=phase
		if phase=="eco" then remotes.ToggleDriveMode:FireServer()
		elseif phase=="light" then remotes.ToggleHeadlight:FireServer() end
	end
	elapsed+=dt
	if elapsed<.04 then return end
	elapsed=0
	local throttle=phase=="accel" or phase=="wheelie_trigger" or phase=="wheelie_balance"
		or phase=="burnout" or phase=="turn_left" or phase=="turn_right"
		or phase=="drive_left" or phase=="drive_right" or phase=="curb"
	local brake=phase=="brake" or phase=="reverse" or phase=="burnout" or phase=="turn_left" or phase=="turn_right"
	local steering=if phase=="turn_left" or phase=="drive_left" then .7
		else if phase=="turn_right" or phase=="drive_right" then -.7 else 0
	remotes.DriveInput:FireServer(throttle,brake,steering,phase=="wheelie_trigger")
	if phase=="done" then connection:Disconnect(); qa:SetAttribute("ClientFinished",true) end
end)
script.Destroying:Connect(function() connection:Disconnect() end)

-- Observe the actual client presentation, including its mounted-only visibility.
local renderConnection
local firstWheelFrame
local minPalmError=math.huge
renderConnection=game.RunService.RenderStepped:Connect(function()
	local model
	for _, item in workspace.Scooters:GetChildren() do
		if item:GetAttribute("OwnerUserId")==player.UserId and item:GetAttribute("ScooterG4Rig") then model=item end
	end
	local folder=workspace:FindFirstChild("_ScooterRideVisuals")
	local visuals=if folder then folder:FindFirstChild("G4RideVisuals") else nil
	if model and model:GetAttribute("RiderMounted") and visuals then
		local shown=0
		for _, part in visuals:GetChildren() do
			if part:IsA("BasePart") and part.Transparency<1 then shown+=1 end
		end
		if shown>0 then qa:SetAttribute("ClientVisualsVisible",true) end
		local wheel=visuals:FindFirstChild("FrontWheel")
		if wheel and wheel:IsA("BasePart") then
			local frame=model.PrimaryPart.CFrame:ToObjectSpace(wheel.CFrame)
			firstWheelFrame=firstWheelFrame or frame
			if firstWheelFrame.UpVector:Dot(frame.UpVector)<.95 then qa:SetAttribute("ClientWheelMoved",true) end
		end
		if model.FrontWheel.LocalTransparencyModifier==1 then qa:SetAttribute("ClientOriginalHidden",true) end
		local character=player.Character
		local error=0
		for _, side in {"Left","Right"} do
			local hand=character:FindFirstChild(side.."Hand")
			local palm=if hand then hand:FindFirstChild(side.."GripAttachment") else nil
			local grip=model.HandleBar:FindFirstChild(side.."HandGrip")
			if palm and grip then error=math.max(error,(palm.WorldPosition-grip.WorldPosition).Magnitude)
			else error=math.huge end
		end
		minPalmError=math.min(minPalmError,error)
		if minPalmError<math.huge then qa:SetAttribute("ClientMinPalmError",minPalmError) end
	end
	if qa:GetAttribute("Finished") then
		qa:SetAttribute("ClientVisualCleanup",visuals==nil)
		qa:SetAttribute("ClientPresentationFinished",true)
		renderConnection:Disconnect()
	end
end)
script.Destroying:Connect(function() renderConnection:Disconnect() end)
