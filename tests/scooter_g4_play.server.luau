-- Temporary normal server Script in Play; stop Play to remove the isolated fixtures.
local Players = game:GetService("Players")
local Server = require(game.ServerScriptService.Scooter.ScooterServer)
local player = assert(Players:GetPlayers()[1])
local qa = assert(workspace:FindFirstChild("_ScooterG4PlayQA"))
local client = assert(player.PlayerGui:FindFirstChild("_ScooterG4PlayClient"))
local selected = player:GetAttribute("SelectedScooter")
local samples = {}
local function sample(name, model)
	local root = model.PrimaryPart
	samples[name] = { speed=model:GetAttribute("SpeedKmh"), forward=model:GetAttribute("ForwardSpeed"),
		front=model:GetAttribute("FrontGrounded"), rear=model:GetAttribute("RearGrounded"),
		wheelie=model:GetAttribute("WheeliePhysical"), pitch=math.deg(math.asin(math.clamp(root.CFrame.LookVector.Y,-1,1))),
		burnout=model:GetAttribute("BurnoutActive"), steering=model:GetAttribute("SteeringAngle"),
		mode=model:GetAttribute("DriveMode"), maxSpeed=model:GetAttribute("MaxSpeedKmh"),
		light=model:GetAttribute("HeadlightEnabled"), mounted=model:GetAttribute("RiderMounted"), fallen=model:GetAttribute("Fallen") }
end
local function phase(name, seconds)
	qa:SetAttribute("Phase",name)
	task.wait(seconds)
end
local ok, problem = xpcall(function()
	task.wait(4)
	local bad = Server.RequestStudioModelForPlayer(player,"unknown")
	assert(not bad,"Unlisted developer template accepted")
	local spawned,message = Server.RequestStudioModelForPlayer(player,"g4")
	assert(spawned,message)
	local model
	for _, item in workspace.Scooters:GetChildren() do
		if item:GetAttribute("OwnerUserId")==player.UserId and item:GetAttribute("ScooterTemplate")=="scooter_g4" then model=item end
	end
	assert(model and model:GetAttribute("ScooterG4Rig"),"Dedicated G4 did not spawn")
	model:PivotTo(CFrame.new(6000,1003,6000))
	local assemblies={}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local root=item.AssemblyRootPart
			if root and not assemblies[root] then
				assemblies[root]=true
				root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
			end
		end
	end
	task.wait(2)
	sample("parked",model)
	local humanoid=player.Character:FindFirstChildOfClass("Humanoid")
	player.Character:PivotTo(model.DriverSeat.CFrame+Vector3.yAxis*3)
	local deadline=os.clock()+5
	repeat model.DriverSeat:Sit(humanoid); task.wait(.2) until model.DriverSeat.Occupant==humanoid or os.clock()>deadline
	assert(model.DriverSeat.Occupant==humanoid,"G4 mounting failed")
	client.Enabled=true
	phase("neutral",1)
	sample("mounted",model)
	phase("accel",4)
	sample("accel",model)
	local heading=model.PrimaryPart.CFrame.LookVector
	phase("drive_left",1)
	sample("drive_left",model)
	qa:SetAttribute("DriveLeftTurn",heading:Dot(model.PrimaryPart.CFrame.LookVector)<.99)
	heading=model.PrimaryPart.CFrame.LookVector
	phase("drive_right",1)
	sample("drive_right",model)
	qa:SetAttribute("DriveRightTurn",heading:Dot(model.PrimaryPart.CFrame.LookVector)<.99)
	phase("wheelie_trigger",.2)
	phase("wheelie_balance",2)
	sample("wheelie",model)
	phase("coast",.8)
	phase("brake",3)
	phase("reverse",2)
	sample("reverse",model)
	phase("burnout",3)
	sample("burnout",model)
	local before=model.PrimaryPart.CFrame.LookVector
	phase("turn_left",1.5)
	sample("left",model)
	phase("turn_right",1.5)
	sample("right",model)
	qa:SetAttribute("TurnChanged",before:Dot(model.PrimaryPart.CFrame.LookVector)<.99)
	phase("eco",.6)
	sample("eco",model)
	phase("light",.6)
	sample("light",model)
	phase("neutral",.3)
	model:PivotTo(CFrame.new(6020,1001.5,6020))
	for root in assemblies do root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
	local curb=Instance.new("Part")
	curb.Name="Curb"; curb.Size=Vector3.new(40,1,4); curb.Anchored=true
	curb.CFrame=CFrame.new(6020,1000.5,6009); curb.Parent=qa
	qa:SetAttribute("Phase","curb")
	local arcade=false
	for _=1,60 do task.wait(.05); arcade=arcade or model:GetAttribute("ArcadeStepActive")==true end
	sample("curb",model)
	qa:SetAttribute("CurbArcade",arcade)
	qa:SetAttribute("CurbCrossed",model.VirtualBackAxle.AxlePivot.WorldPosition.Z<6007)
	phase("neutral",.5)
	assert(Server.DismountForPlayer(player),"Owned seat could not dismount")
	phase("done",.6)
	sample("dismounted",model)
	qa:SetAttribute("SelectedPreserved",player:GetAttribute("SelectedScooter")==selected)
	qa:SetAttribute("ServerOwned",model.PrimaryPart:GetNetworkOwner()==nil)
	local passed=samples.parked.front and samples.parked.rear and samples.mounted.mounted
		and samples.accel.speed>10 and samples.wheelie.wheelie and samples.reverse.forward<-.5
		and samples.burnout.burnout and math.abs(samples.left.steering)>.1 and math.abs(samples.right.steering)>.1
		and samples.eco.mode=="ECO" and samples.eco.maxSpeed==25 and samples.light.light
		and not samples.dismounted.mounted and not samples.dismounted.burnout
		and qa:GetAttribute("SelectedPreserved") and qa:GetAttribute("ServerOwned")
		and qa:GetAttribute("DriveLeftTurn") and qa:GetAttribute("DriveRightTurn")
		and qa:GetAttribute("CurbArcade") and qa:GetAttribute("CurbCrossed")
	qa:SetAttribute("Passed",passed)
	local restored, restoreMessage = Server.RequestStudioModelForPlayer(player,"g2_pro")
	assert(restored,restoreMessage)
	local g2
	for _, item in workspace.Scooters:GetChildren() do
		if item:GetAttribute("OwnerUserId")==player.UserId then g2=item end
	end
	local legacyRestored=g2 and g2:GetAttribute("ScooterTemplate")=="scooter"
		and g2:GetAttribute("ScooterG4Rig")~=true and model.Parent==nil
	qa:SetAttribute("G2Restored",legacyRestored==true)
	qa:SetAttribute("Passed",passed and legacyRestored==true)
end,debug.traceback)
qa:SetAttribute("Results",game.HttpService:JSONEncode(samples))
if not ok then qa:SetAttribute("Error",tostring(problem)); qa:SetAttribute("Passed",false) end
qa:SetAttribute("Phase","done")
qa:SetAttribute("Finished",true)
