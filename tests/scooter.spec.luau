--!strict
-- Bundled by run_scooter_tests.py; module source is executed without rewriting it.

local Config = loadModule("ReplicatedStorage/Shared/Scooter/ScooterConfig")
local Input = loadModule("ServerScriptService/Scooter/ScooterInput")
local Physics = loadModule("ReplicatedStorage/Shared/Scooter/ScooterPhysics")

local models = {
	{ "KuKirin G2 Pro", 55, { 300, 600, 1200 } },
	{ "KuKirin G2 Max", 65, { 600, 1200, 2400 } },
	{ "KuKirin G2 Master", 72, { 1500, 3000, 6000 } },
	{ "KuKirin G3 Pro", 80, { 4000, 8000, 14000 } },
	{ "KuKirin G4", 90, { 8000, 16000, 24000 } },
}
for _, item in models do
	for tier = 0, 3 do
		local tuning = assert(Config.GetTuning(item[1], tier))
		near(tuning.maxSpeed, item[2] + tier * 1.5, "GDD speed: " .. item[1])
		near(tuning.acceleration / Config.Models[item[1]].acceleration,
			tuning.maxSpeed / item[2], "Acceleration scales proportionally")
		check(Config.GetUpgradeCost(item[1], tier) == item[3][tier + 1], "GDD price and cap")
	end
end
for _, value in { -1, 0.5, 4, math.huge, -math.huge, 0 / 0, "1", true, {} } do
	check(not Config.IsValidSpeedTier(value), "Invalid tier rejected")
	check(Config.GetUpgradeCost(Config.DefaultModel, value) == nil, "Invalid tier has no price")
	check(Config.GetTuning(Config.DefaultModel, value) == nil, "Invalid tier has no tuning")
end
check(Config.GetTuning("Not a model", 0) == nil, "Unknown model rejected")
check(Config.GetUpgradeCost("Not a model", 0) == nil, "Unknown model has no price")
local altered = assert(Config.GetTuning(Config.DefaultModel, 3))
altered.maxSpeed = 999
near(assert(Config.GetTuning(Config.DefaultModel, 3)).maxSpeed, 59.5, "Tuning copies cannot mutate base")

local input = Input.New()
check(not Input.IsFresh(input, 1), "New controller has no accepted intent")
check(Input.Apply(input, 1, true, true, 0.6, true), "Simultaneous brake/throttle accepted")
check(input.throttleHeld and input.brakeHeld and input.wheelieHeld and input.wheelieQueued,
	"All buttons preserve independent intent")
check(not Input.Apply(input, 1.01, false, false, 0, false), "Input spam is rejected")
near(input.lastReceivedAt, 1, "Rejected spam does not extend freshness")
check(Input.Apply(input, 1.1, false, false, -1, false), "Released input accepted")
check(input.wheelieQueued, "Wheelie trigger edge survives button release")
for _, value in { -1.01, 1.01, math.huge, -math.huge, 0 / 0, "0", {}, false } do
	check(not Input.Apply(input, 2, true, false, value, false), "Malformed steering rejected")
end
for field = 1, 4 do
	if field == 3 then continue end
	local values = { false, false, 0, false }
	values[field] = 1
	check(not Input.Apply(input, 2, table.unpack(values)), "Nonboolean intent rejected")
end
near(input.lastReceivedAt, 1.1, "Malformed requests do not refresh intent")
check(Input.IsFresh(input, 1.1 + Config.DriveInputTimeout - 0.001), "Keepalive is fresh within timeout")
check(not Input.IsFresh(input, 1.1 + Config.DriveInputTimeout + 0.001), "Stale intent expires")
Input.Reset(input)
check(not input.throttleHeld and not input.brakeHeld and not input.wheelieHeld
	and not input.wheelieQueued and input.steering == 0,
	"Reset clears every pending drive/trick intent")
near(input.lastReceivedAt, 1.1, "Reset preserves request cooldown")
check(not Input.Apply(input, 1.11, true, false, 0, false), "Reset does not bypass rate limit")

near(Physics.SmoothSteering(0, 1, 0), 0, "Zero timestep does not steer")
local smooth = Physics.SmoothSteering(0, 1, 1 / 60)
check(smooth > 0 and smooth < 1, "Steering lerps instead of snapping")
near(Physics.SmoothSteering(0, 1, 1 / 30),
	Physics.SmoothSteering(smooth, 1, 1 / 60), "Steering smoothing is framerate independent")
near(Physics.SmoothSteering(0, 1, 1), Physics.SmoothSteering(0, 1, 0.1), "Long frame steering is bounded")
near(Physics.GetEffectiveSteering(1, 0), 0, "Scooter cannot turn in place")
near(Physics.GetEffectiveSteering(1, 10), 1, "Low speed retains maneuverability")
near(Physics.GetEffectiveSteering(1, 100), Config.HighSpeedSteeringScale, "High speed yaw is limited")
near(Physics.GetEffectiveSteering(1, -100), Config.HighSpeedSteeringScale, "Reverse steering uses absolute speed")
near(Physics.GetTurnSteering(0.7, 10), 0.7, "Forward steering keeps input direction")
near(Physics.GetTurnSteering(0.7, -10), -0.7, "Reverse steering inverts chassis yaw")
near(Physics.GetTurnSteering(0.7, 0), 0.7, "Stationary steering does not flip")
local forward = Vector.new(0, 0, -1)
local turned = Physics.AdvanceForward(forward, 1, 20, 1 / 60)
near(turned.Magnitude, 1, "Turning preserves unit direction")
check(turned.X > 0, "Right input turns toward positive X")
near(Physics.AdvanceForward(forward, 0, 20, 1 / 60).X, 0, "No steer preserves heading")
local reverseTurned = Physics.AdvanceForward(forward, Physics.GetTurnSteering(1, -20), -20, 1 / 60)
check(reverseTurned.X < 0, "Reverse left/right input turns travel in the requested direction")
local balanceSpeed = Config.WheelieLowSpeedDropStart
local raisedWheelie = Physics.AdvanceWheeliePitch(Config.WheelieKickAngle, 1, balanceSpeed, 0.1)
check(raisedWheelie > Config.WheelieKickAngle, "W raises an active wheelie")
check(Physics.AdvanceWheeliePitch(raisedWheelie, -1, balanceSpeed, 0.1) < raisedWheelie,
	"S lowers an active wheelie")
near(Physics.AdvanceWheeliePitch(raisedWheelie, 0, balanceSpeed, 0.1), raisedWheelie,
	"Wheelie angle holds without W or S")
check(Physics.AdvanceWheeliePitch(raisedWheelie, 0, 0, 0.1) < raisedWheelie,
	"Wheelie drops without forward momentum")
check(Physics.AdvanceWheeliePitch(raisedWheelie, 1, 0, 0.1) < raisedWheelie,
	"Throttle cannot balance a stationary wheelie")
local overbalancedWheelie = Config.WheelieKickAngle
for _ = 1, 30 do
	overbalancedWheelie = Physics.AdvanceWheeliePitch(overbalancedWheelie, 1, balanceSpeed, 0.1)
end
near(overbalancedWheelie, Config.WheelieFallAngle, "Holding W reaches the fall angle")
local drive = {
	velocity = forward * 20, forward = forward, groundUp = Vector.yAxis, gravity = 196.2,
	mass = 10, maxSpeed = 55 * Config.StudsPerKmH, acceleration = 135,
	throttleHeld = false, brakeHeld = false, burnout = false,
	grounded = true, fallen = false, deltaTime = 1 / 60,
}
local coast = Physics.ComputeDriveForce(drive):Dot(forward)
check(coast < 0 and 20 + coast / drive.mass * drive.deltaTime > 0,
	"Releasing throttle bleeds speed without instant stop")
drive.brakeHeld = true
local brake = Physics.ComputeDriveForce(drive):Dot(forward)
check(brake < coast, "Braking is stronger than coasting")
drive.throttleHeld = true
near(Physics.ComputeDriveForce(drive):Dot(forward), brake, "Brake and throttle cannot launch during burnout")
drive.brakeHeld = false
check(Physics.ComputeDriveForce(drive):Dot(forward) > 0, "Throttle accelerates below top speed")
drive.throttleHeld = false
drive.brakeHeld = true
drive.velocity = Vector.zero
check(Physics.ComputeDriveForce(drive):Dot(forward) < 0, "Brake input engages reverse from rest")
drive.brakeHeld = false
drive.throttleHeld = true
drive.velocity = forward * drive.maxSpeed
near(Physics.ComputeDriveForce(drive):Dot(forward), 0, "Throttle adds no force at configured speed cap")
drive.velocity = forward * (drive.maxSpeed + 2)
check(Physics.ComputeDriveForce(drive):Dot(forward) < 0, "Overspeed is corrected")
drive.throttleHeld = false
drive.velocity = forward * 0.3
drive.deltaTime = 0.1
near(0.3 + Physics.ComputeDriveForce(drive):Dot(forward) / drive.mass * drive.deltaTime,
	0, "Coasting does not overshoot through zero")
drive.velocity = Vector.new(5, 17, -20)
near(Physics.ComputeDriveForce(drive).Y, 0, "Ground friction does not cancel vertical velocity")
check(Physics.ComputeDriveForce(drive).X < 0, "Lateral grip opposes sliding")
drive.grounded = false
near(Physics.ComputeDriveForce(drive).Magnitude, 0, "Airborne scooter cannot apply ground drive")
drive.grounded = true
drive.fallen = true
near(Physics.ComputeDriveForce(drive).Magnitude, 0, "Fallen scooter cannot apply drive")
drive.fallen = false
drive.mass = 0
near(Physics.ComputeDriveForce(drive).Magnitude, 0, "Massless prediction is safe")
drive.mass = 10
drive.velocity = Vector.zero
drive.throttleHeld = true
drive.brakeHeld = false
drive.forward = Vector.new(0, 0.5, -0.8660254)
check(Physics.ComputeDriveForce(drive):Dot(drive.forward) > drive.acceleration * drive.mass,
	"Hill assist offsets gravity while climbing")

local yawTarget = Frame.fromAxisAngle(Vector.yAxis, math.pi / 4)
local torque = Physics.ComputeUprightTorque(Frame.identity, yawTarget, Vector.zero, 10, 4200)
near(torque.X, 0, "Pure yaw does not apply pitch torque")
near(torque.Z, 0, "Pure yaw does not apply roll torque")
near(torque.Y, math.pi / 4 * Config.UprightTorqueStiffness * 10, "Orientation error produces restoring torque")
near(Physics.ComputeUprightTorque(yawTarget, Frame.identity, Vector.zero, 10, 4200).Y,
	-torque.Y, "Opposite orientation error reverses torque")
near(Physics.ComputeUprightTorque(yawTarget, yawTarget, Vector.zero, 10, 4200).Magnitude,
	0, "Aligned stationary scooter has no torque")
local damping = Physics.ComputeUprightTorque(Frame.identity, Frame.identity, Vector.yAxis * 3, 10, 4200)
near(damping.Y, -3 * Config.UprightTorqueDamping * 10, "Angular damping opposes rotation")
near(Physics.ComputeUprightTorque(Frame.identity, yawTarget, Vector.zero, 10, 1).Magnitude,
	10, "Torque saturates at model torque times assembly mass")
near(Physics.ComputeUprightTorque(Frame.identity, yawTarget, Vector.zero, 0, 4200).Magnitude,
	0, "Zero mass cannot create torque")
near(Physics.ComputeUprightTorque(Frame.identity, yawTarget, Vector.zero, 10, 0).Magnitude,
	0, "Zero torque limit disables rotation safely")

local rich = makePlayer(1, { coins = 100000 })
local poor = makePlayer(2, { coins = 299 })
local corrupted = makePlayer(3, {
	coins = 0 / 0,
	scooterUpgrades = { ["KuKirin G2 Pro"] = 4, ["KuKirin G2 Max"] = 0 / 0,
		["KuKirin G4"] = 2, Unknown = 3 },
	scooterVisuals = { Smoke = { enabled = true, color = { 0 / 0, 1, 1 } } },
})
local unavailable = makePlayer(4, { coins = 100000 })
dataStoreService.failLoads["4"] = true
local Profiles = loadModule("ServerScriptService/Activity/PlayerDataService")
Profiles.Start()
local richProfile = assert(Profiles.GetProfile(rich))
local coins = rich.leaderstats.Coins
check(Profiles.OwnsScooter(rich, Config.DefaultModel), "Default scooter is owned")
check(not Profiles.OwnsScooter(rich, "KuKirin G4"), "Paid scooter is not owned by default")
local ok, reason = Profiles.PurchaseSpeedUpgrade(rich, "KuKirin G4", 0)
check(not ok and reason == "NotOwned", "Unowned scooter cannot be upgraded")
near(coins.Value, 100000, "Rejected ownership request does not debit coins")
for tier = 0, 2 do
	local before = coins.Value
	ok = Profiles.PurchaseSpeedUpgrade(rich, Config.DefaultModel, tier)
	check(ok, "Sequential speed tier purchase succeeds")
	near(coins.Value, before - models[1][3][tier + 1], "Exact GDD price debited")
	near(richProfile.scooterUpgrades[Config.DefaultModel], tier + 1, "Tier increment committed")
	near(richProfile.coins, coins.Value, "Profile and leaderboard currency stay synchronized")
	ok, reason = Profiles.PurchaseSpeedUpgrade(rich, Config.DefaultModel, tier)
	check(not ok and reason == "StaleTier", "Duplicate expected tier cannot charge twice")
	near(coins.Value, before - models[1][3][tier + 1], "Duplicate purchase preserves balance")
end
ok, reason = Profiles.PurchaseSpeedUpgrade(rich, Config.DefaultModel, 3)
check(not ok and reason == "MaximumTier", "Fourth upgrade is impossible")
ok, reason = Profiles.PurchaseSpeedUpgrade(poor, Config.DefaultModel, 0)
check(not ok and reason == "InsufficientCoins", "Insufficient funds rejected")
near(poor.leaderstats.Coins.Value, 299, "Rejected purchase preserves funds")
check(Profiles.GetProfile(poor).scooterUpgrades[Config.DefaultModel] == nil,
	"Rejected purchase cannot grant a tier")
check(not Profiles.PurchaseSpeedUpgrade(makePlayer(5, nil), Config.DefaultModel, 0), "Unloaded player rejected")
check(not Profiles.PurchaseSpeedUpgrade(unavailable, Config.DefaultModel, 0), "Failed data load disables purchases")
for _, tier in { -1, 0.5, 4, 0 / 0, math.huge, "1" } do
	check(not Profiles.PurchaseSpeedUpgrade(rich, Config.DefaultModel, tier), "Malformed purchase tier rejected")
end
ok = Profiles.PurchaseScooter(rich, "KuKirin G2 Max")
check(ok and Profiles.OwnsScooter(rich, "KuKirin G2 Max"), "Scooter purchase grants profile ownership immediately")
check(Profiles.PurchaseSpeedUpgrade(rich, "KuKirin G2 Max", 0), "New scooter can immediately be upgraded")
local cleanProfile = assert(Profiles.GetProfile(corrupted))
near(cleanProfile.coins, 0, "NaN currency deserializes safely")
check(cleanProfile.scooterUpgrades["KuKirin G2 Pro"] == nil
	and cleanProfile.scooterUpgrades["KuKirin G2 Max"] == nil
	and cleanProfile.scooterUpgrades.Unknown == nil, "Invalid and unknown saved tiers discarded")
near(cleanProfile.scooterUpgrades["KuKirin G4"], 2, "Valid saved tier survives migration")
check(not cleanProfile.scooterVisuals.Smoke.enabled, "Invalid saved RGB preference resets")

local Garage = loadModule("ServerScriptService/Scooter/GarageService")
local Shop = loadModule("ReplicatedStorage/Shared/Shop/ShopConfig")
local refreshCount = 0
Garage.Start(function(_) refreshCount += 1 end)
local function request(player, action, model, payload)
	testClock += Config.GarageRequestCooldown + 0.01
	return Garage.HandleRequest(player, action, model, payload)
end
local state
ok, reason, state = request(rich, "GetState", nil, nil)
check(ok and state.dataReady, "Garage reports loaded profile")
near(state.models[Config.DefaultModel].maxSpeed, 59.5, "Garage publishes purchased top speed")
check(not state.smokeOwned and not state.neonOwned, "Unconfigured premium passes fail closed")
check(marketplaceService.ownershipCalls == 0, "Zero product IDs never call Marketplace")
ok, reason = Garage.HandleRequest(rich, "GetState", nil, nil)
check(not ok and reason == "RateLimited", "Garage reads are rate limited")
ok, reason = request(rich, "SetVisual", nil, { kind = "Smoke", enabled = true, color = Color.new(1, 0, 0) })
check(not ok and reason == "GamePassRequired", "Non-owner cannot enable premium smoke")
check(not Garage.GetVisuals(rich).smokeEnabled, "Denied smoke is not replicated")
for _, color in { Color.new(0 / 0, 0, 0), Color.new(math.huge, 0, 0), Color.new(-0.1, 0, 0),
	Color.new(1.1, 0, 0), { R = 1, G = 0, B = 0 } } do
	ok, reason = request(rich, "SetVisual", nil, { kind = "Neon", enabled = true, color = color })
	check(not ok and reason == "InvalidVisual", "Malformed or non-finite RGB rejected")
end
ok, reason = request(rich, "SetVisual", nil, {
	kind = "Smoke", enabled = true, color = Color.new(1, 0, 0), owned = true,
})
check(not ok and reason == "InvalidRequest", "Client entitlement fields are rejected")
ok, reason = request(rich, "PurchaseSpeed", "KuKirin G2 Max", 0 / 0)
check(not ok and reason == "InvalidUpgrade", "Garage rejects non-finite upgrade requests")
ok, reason = request(rich, "GetState", Config.DefaultModel, nil)
check(not ok and reason == "InvalidRequest", "Garage rejects extra state request arguments")

Shop.GetProduct("burnout_smoke").productId = 777
Shop.GetProduct("scooter_neons").productId = 778
marketplaceService.PromptGamePassPurchaseFinished:Fire(rich, 777, true)
check(not Garage.GetVisuals(rich).smokeEnabled, "Purchase signal alone never grants premium access")
marketplaceService.ownership["1:777"] = true
marketplaceService.ownership["1:778"] = true
marketplaceService.PromptGamePassPurchaseFinished:Fire(rich, 777, true)
ok, reason, state = request(rich, "SetVisual", nil, { kind = "Smoke", enabled = true, color = Color.new(0.2, 0.4, 0.6) })
check(ok and state.smokeOwned and state.visuals.smokeEnabled, "Verified pass can enable smoke")
near(state.visuals.smokeColor.R, 0.2, "Server returns selected RGB")
near(richProfile.scooterVisuals.Smoke.color[2], 0.4, "Selected RGB persists in profile")
ok, reason, state = request(rich, "SetVisual", nil, { kind = "Smoke", enabled = false, color = Color.new(0.2, 0.4, 0.6) })
check(ok and not state.visuals.smokeEnabled and not richProfile.scooterVisuals.Smoke.enabled,
	"Premium smoke can be disabled without discarding preference")
near(state.visuals.smokeColor.B, 0.6, "Disabled premium smoke preserves selected RGB")
ok, reason, state = request(rich, "SetVisual", nil, { kind = "Neon", enabled = true, color = Color.new(1, 0, 1) })
check(ok and state.neonOwned and state.visuals.neonEnabled, "Verified neon pass can enable underglow")
local calls = marketplaceService.ownershipCalls
request(rich, "GetState", nil, nil)
check(marketplaceService.ownershipCalls == calls, "Cached entitlement avoids repeated network queries")
marketplaceService.failRequests = true
marketplaceService.PromptGamePassPurchaseFinished:Fire(rich, 777, true)
check(not Garage.GetVisuals(rich).smokeEnabled and not Garage.GetVisuals(rich).neonEnabled,
	"Marketplace errors fail closed even with saved premium preferences")
marketplaceService.failRequests = false
check(refreshCount > 0, "Garage changes notify scooter refresh")
Garage.Stop()
calls = marketplaceService.ownershipCalls
marketplaceService.PromptGamePassPurchaseFinished:Fire(rich, 777, true)
check(marketplaceService.ownershipCalls == calls, "Garage stop disconnects Marketplace listener")
ok, reason = request(rich, "GetState", nil, nil)
check(not ok and reason == "Unavailable", "Stopped garage rejects requests")

playersService.PlayerRemoving:Fire(unavailable)
check(writes["4"] == nil, "Failed data load cannot overwrite a saved profile")
playersService.PlayerRemoving:Fire(rich)
check(writes["1"].scooterUpgrades[Config.DefaultModel] == 3, "Upgrade tiers included in saved profile")
check(Profiles.GetProfile(rich) == nil, "Player removal releases profile")
local savedCoins = writes["1"].coins
coins.Value = 1
near(writes["1"].coins, savedCoins, "Player removal disconnects currency listeners")

print(string.format("PASS: %d scooter runtime assertions", testCount))
