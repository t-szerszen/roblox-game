local stateAssertionsBefore = testCount
local StateMath = loadModule("ReplicatedStorage/Shared/Scooter/ScooterAnimationMath")
local AnimatorModule = loadModule("StarterPlayer/StarterPlayerScripts/ScooterAnimator")
check(StateMath.GetLegState(nil, 0, false, true) == "IDLE", "Rest enters idle")
check(StateMath.GetLegState("RIDING", 1, false, true) == "RIDING", "Moving near threshold retains riding")
check(StateMath.GetLegState("IDLE", 1, false, true) == "IDLE", "Idle hysteresis prevents threshold flicker")
check(StateMath.GetLegState("IDLE", 2, false, true) == "RIDING", "Speed exits idle")
check(StateMath.GetLegState("RIDING", 0, true, true) == "WHEELIE", "Wheelie takes priority even at zero reported speed")
check(StateMath.GetLegState("WHEELIE", 5, false, true) == "RIDING", "Wheelie exit returns to riding")
check(StateMath.GetLegState("WHEELIE", 0, false, true) == "IDLE", "Wheelie exit at rest returns to idle")
check(StateMath.GetLegState("IDLE", 0, false, false) == "RIDING", "Airborne/fallen state cannot plant a foot on ground")
check(StateMath.GetLegState(nil, math.huge, false, true) == "RIDING", "Missing speed keeps both feet supported")
check(StateMath.GetLegState(nil, 0 / 0, false, true) == "RIDING", "Malformed speed has a safe pose")
check(StateMath.GetLegState(nil, -5, false, true) == "RIDING", "Reverse travel counts as riding")

local function riderFixture(name)
	local rider = make(baseEnvironment.workspace, "Model", name)
	local hum = make(rider, "Humanoid", "Humanoid")
	hum.RigType = enumMock.HumanoidRigType.R15
	make(rider, "LocalScript", "Animate").Disabled = false
	for _, partName in { "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
		"LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" } do make(rider, "Part", partName) end
	make(rider, "Motor6D", "Waist")
	make(rider, "Motor6D", "Root")
	return rider, hum
end
local settings = Config.RiderAnimations
local priorIdle, priorWheelie = settings.IdleFootAnim, settings.WheelieBalanceAnim
local rider, hum = riderFixture("StateRider")
model:SetAttribute("SpeedKmh", 0)
model:SetAttribute("DriveState", "Idle")
model:SetAttribute("WheelieActive", false)
model:SetAttribute("Fallen", false)
local controller = AnimatorModule.new(model)
check(controller.mount(rider) and controller.getState() == "IDLE", "Initial state reads server speed on mount")
services.RunService.PreAnimation:Fire(1 / 60)
check(hum.ScooterLeftFootIK.Enabled and hum.ScooterRightFootIK.Enabled, "Empty IDs keep procedural foot fallback")
controller.dismount()
check(controller.getState() == nil, "Dismount resets state")

settings.IdleFootAnim, settings.WheelieBalanceAnim = "12345", "rbxassetid://67890"
check(controller.mount(rider), "Configured clips mount")
local characterAnimator = hum:FindFirstChildOfClass("Animator")
local idleTrack, wheelieTrack
for _, track in characterAnimator._tracks do
	if track.Animation.Name == "IdleFootAnim" then idleTrack = track else wheelieTrack = track end
end
check(idleTrack.playCount == 1 and wheelieTrack.playCount == 0, "Only initial state's clip plays")
check(idleTrack.Animation.AnimationId == "rbxassetid://12345", "Numeric string ID is normalized")
check(idleTrack.Looped and idleTrack.Priority == enumMock.AnimationPriority.Action, "State clips are looping with matching priority")
near(idleTrack.lastFade, settings.FadeTime, "Play uses configured fade")
near(idleTrack.WeightTarget, settings.Weight, "Play uses configured weight")
near(idleTrack.Speed, settings.PlaybackSpeed, "Play uses configured playback speed")
idleTrack.WeightCurrent = 1
idleTrack.Length = 0
services.RunService.PreAnimation:Fire(1 / 60)
check(hum.ScooterLeftFootIK.Enabled, "Unloaded animation retains foot IK")
idleTrack.Length, idleTrack.WeightCurrent = 1, 0.4
services.RunService.PreAnimation:Fire(1 / 60)
near(hum.ScooterLeftFootIK.Weight, 0.6, "Foot IK blends inversely to loaded clip weight")
idleTrack.WeightCurrent = 1
services.RunService.PreAnimation:Fire(1 / 60)
check(not hum.ScooterLeftFootIK.Enabled and not hum.ScooterRightFootIK.Enabled, "Full authored clip releases foot IK and poles")
check(hum.ScooterLeftHandIK.Enabled and hum.ScooterLeftHandIK.Weight == 1, "Leg animation preserves hand IK")
model:SetAttribute("SpeedKmh", 1)
services.RunService.PreAnimation:Fire(1 / 60)
check(controller.getState() == "IDLE" and idleTrack.playCount == 1, "Stable state never restarts clip each frame")
model:SetAttribute("WheelieActive", true)
check(controller.getState() == "WHEELIE" and wheelieTrack.playCount == 1, "Authoritative wheelie event starts balance clip")
near(idleTrack.lastStopFade, settings.FadeTime, "Wheelie crossfades outgoing idle clip")
idleTrack.WeightCurrent, wheelieTrack.WeightCurrent = 0.5, 0.5
services.RunService.PreAnimation:Fire(1 / 60)
check(not hum.ScooterRightFootIK.Enabled, "Crossfade between authored states does not reenable deck IK")
model:SetAttribute("SpeedKmh", 10)
model:SetAttribute("WheelieActive", false)
check(controller.getState() == "RIDING", "Server speed and wheelie release select riding")
check(not wheelieTrack.IsPlaying, "Stopped track can retain a fading pose after playback stops")
idleTrack.WeightCurrent, wheelieTrack.WeightCurrent = 0, 0.5
services.RunService.PreAnimation:Fire(1 / 60)
near(hum.ScooterRightFootIK.Weight, 0.5, "Riding blends foot IK back as outgoing track fades")
wheelieTrack.WeightCurrent = 0
services.RunService.PreAnimation:Fire(1 / 60)
check(hum.ScooterLeftFootIK.Enabled and hum.ScooterLeftFootIK.Weight == 1, "Riding restores both feet to deck")
model:SetAttribute("SpeedKmh", 0)
check(idleTrack.playCount == 2, "Reentering idle plays its clip once")
model:SetAttribute("DriveState", "Airborne")
check(controller.getState() == "RIDING", "Airborne at zero speed does not ground a foot")
model:SetAttribute("WheelieActive", true)
model:SetAttribute("Fallen", true)
check(controller.getState() == "RIDING", "Fallen state overrides delayed wheelie attribute")
controller.dismount()
check(idleTrack.destroyed and wheelieTrack.destroyed, "Dismount destroys owned tracks")
near(idleTrack.lastStopFade, 0, "Dismount stops tracks immediately before destruction")
local playCountAfterDismount = idleTrack.playCount
model:SetAttribute("Fallen", false)
model:SetAttribute("WheelieActive", false)
model:SetAttribute("DriveState", "Idle")
check(controller.getState() == nil and idleTrack.playCount == playCountAfterDismount, "Dismount disconnects state listeners")

characterAnimator.failLoad = true
check(controller.mount(rider), "Asset load failure does not prevent mounting")
services.RunService.PreAnimation:Fire(1 / 60)
check(hum.ScooterRightFootIK.Enabled, "Failed asset load keeps procedural legs")
controller.dismount()
characterAnimator.failLoad = false

-- Observer consumes owner-replicated tracks and leaves their lifecycle to the owner.
local remoteRider, remoteHumanoid = riderFixture("RemoteStateRider")
local remotePlayer = makePlayer(90, nil)
remotePlayer.Character = remoteRider
local remoteAnimator = make(remoteHumanoid, "Animator", "Animator")
local replicatedClip = make(nil, "Animation", "IdleFootAnim")
replicatedClip.AnimationId = "rbxassetid://12345"
local replicatedTrack = remoteAnimator:LoadAnimation(replicatedClip)
replicatedTrack:Play(settings.FadeTime, 1, 1)
replicatedTrack.WeightCurrent = 1
local observer = AnimatorModule.new(model)
check(observer.mount(remoteRider), "Observer mounts remote rider")
check(#remoteAnimator._tracks == 1 and replicatedTrack.stopCount == 0, "Observer preserves existing replicated clip without duplicate loading")
services.RunService.PreAnimation:Fire(1 / 60)
check(not remoteHumanoid.ScooterLeftFootIK.Enabled, "Observer releases feet for replicated authored pose")
local incomingClip = make(nil, "Animation", "WheelieBalanceAnim")
incomingClip.AnimationId = "rbxassetid://67890"
local incomingTrack = remoteAnimator:LoadAnimation(incomingClip)
incomingTrack:Play(settings.FadeTime, 1, 1)
incomingTrack.WeightCurrent, replicatedTrack.WeightCurrent = 1, 0
model:SetAttribute("WheelieActive", true)
services.RunService.PreAnimation:Fire(1 / 60)
check(observer.getState() == "WHEELIE" and incomingTrack.playCount == 1, "Observer follows incoming wheelie track without replaying it")
observer.dismount()
check(not incomingTrack.destroyed and incomingTrack.stopCount == 0, "Observer cleanup does not stop or destroy owner's track")

remoteAnimator:Destroy()
check(not observer.mount(remoteRider), "Player character waits for replicated Animator instead of creating a local one")
check(not remoteHumanoid:FindFirstChildOfClass("Animator"), "Rejected player mount leaves no nonreplicating Animator")
model:SetAttribute("WheelieActive", false)
check(controller.mount(rider), "Remount reloads state tracks")
local latestIdle
for _, track in characterAnimator._tracks do
	if track.Animation.Name == "IdleFootAnim" and not track.destroyed then latestIdle = track end
end
latestIdle.failPlay = true
model:SetAttribute("SpeedKmh", 10)
model:SetAttribute("SpeedKmh", 0)
check(latestIdle.destroyed and controller.getState() == "IDLE", "Playback failure releases failed track and retains visual state")
services.RunService.PreAnimation:Fire(1 / 60)
check(hum.ScooterRightFootIK.Enabled, "Playback failure restores procedural foot support")
controller.dismount()
settings.IdleFootAnim, settings.WheelieBalanceAnim = priorIdle, priorWheelie

print(string.format("PASS: %d leg-state assertions", testCount - stateAssertionsBefore))
