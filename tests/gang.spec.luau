local Gang = loadModule("ServerScriptService/Gang/GangService")
local Requests = loadModule("ServerScriptService/Gang/GangRequests")
local Capture = loadModule("ServerScriptService/Territory/TerritoryCapture")
local Combat = loadModule("ServerScriptService/Combat/CombatService")
local Territory = loadModule("ServerScriptService/Territory/TerritoryService")
local Rewards = loadModule("ServerScriptService/Territory/TerritoryRewards")
local people = {}
for id = 1, 12 do people[id] = gangPlayer(id) end
local a, b, c = people[1], people[4], people[5]
Gang.Start(); Gang.Start()
check(Gang.Create(a, "Alfa", 1), "Everyone can create without CanCreateGang entitlement")
local aId = Gang.GetGangId(a)
check(not Requests.Handle(b, "CreateGang", {name = "Beta", colorId = 0/0}), "NaN color rejected")
check(not Requests.Handle(b, "CreateGang", {name = "Beta", colorId = math.huge}), "Infinite color rejected")
check(not Requests.Handle(b, "CreateGang", {name = "Beta", colorId = 2, owner = a.UserId}), "Unexpected privilege field rejected")
check(not Gang.Create(b, "Beta", 1), "Occupied color rejected")
advance(2)
check(not Gang.Create(b, "  ALFA  ", 2), "Normalized duplicate name rejected")
advance(2)
services.TextService.fail = true
check(not Gang.Create(b, "Beta", 2) and not Gang.GetGangId(b), "Filter failure does not create gang or leak original name")
services.TextService.fail = false; advance(2)
services.TextService.censored = true
check(not Gang.Create(b, "Beta", 2), "Censored name rejected")
services.TextService.censored = false; advance(2)
check(Gang.Create(b, "Beta", 2), "Second gang created with unique chosen RGB color")
local bId = Gang.GetGangId(b)
check(Gang.Create(c, "Gamma", 3), "Third gang created without fixed faction limit")
local cId = Gang.GetGangId(c)
services.TextService.hook = function()
	check(Gang.Invite(c, people[6].UserId), "Invite can arrive while name filtering yields")
	check(Gang.RespondInvite(people[6], Gang.GetState(people[6]).invites[1].id, true), "Membership changes while creation is filtering")
end
check(not Gang.Create(people[6], "Race gang", 4), "Creation rechecks membership after filtering yields")
check(Gang.GetGangId(people[6]) == cId, "Filtering race cannot steal existing membership")
disconnectPlayer(people[6])
check(not Gang.GetGangId(people[6]) and Gang.Exists(cId), "Ordinary disconnected member removed immediately")
disconnectPlayer(c)
check(not Gang.Exists(cId), "Solo offline leader disbands an empty gang immediately")
people[6] = reconnectPlayer(6); people[5] = reconnectPlayer(5)
check(Gang.Create(people[7], "Rename race", 5), "Create gang for yielding rename lifecycle")
services.TextService.hook = function() check(Gang.Leave(people[7]), "Owner leaves while rename filtering yields") end
check(not Gang.Rename(people[7], "Stale rename"), "Rename rejects owner change while filtering")
check(not Gang.GetGangId(people[7]), "Yielding rename cannot restore a dissolved gang")
advance(30)
for capacity, expected in { [30] = 10, [27] = 9, [21] = 7, [2] = 1 } do
	playersService.MaxPlayers = capacity
	check(Gang.GetState(a).maxMembers == expected, "Dynamic member limit for " .. capacity)
end
playersService.MaxPlayers = 30
check(not Gang.Invite(people[2], people[3].UserId), "Only owner can invite")
check(Gang.Invite(a, people[2].UserId), "Owner invites valid target")
local invitation = Gang.GetState(people[2]).invites[1]
check(not Requests.Handle(people[2], "RespondGangInvite", true), "Legacy boolean cannot accept a different invitation")
check(not Gang.RespondInvite(people[3], invitation.id, true), "Invitation bound to target")
check(Gang.RespondInvite(people[2], invitation.id, true), "Exact invitation accepted")
check(not Gang.RespondInvite(people[2], invitation.id, true), "Replayed acceptance is harmless")
check(Gang.RequestJoin(people[3], aId), "Join request created")
local request = Gang.GetState(a).requests[1]
check(not Gang.RespondRequest(people[2], request.id, true), "Nonowner cannot accept requests")
check(Gang.RespondRequest(a, request.id, true), "Owner accepts request")
check(Gang.CanDamage(a, b) and not Gang.CanDamage(a, people[3]), "Friendly fire disabled without blocking rival gangs")
check(Gang.Invite(a, people[6].UserId), "Expiring invitation created")
local expired = Gang.GetState(people[6]).invite.id
advance(31)
check(not Gang.RespondInvite(people[6], expired, true), "Expired invitation cannot join")
check(Gang.Invite(a, people[8].UserId) and Gang.Invite(b, people[8].UserId), "Multiple gangs can invite without overwriting IDs")
local incoming = Gang.GetState(people[8]).invites
check(#incoming == 2, "Both incoming invitations visible")
local inviteA, inviteB
for _, entry in incoming do if entry.gangId == aId then inviteA = entry else inviteB = entry end end
check(Gang.RespondInvite(people[8], inviteA.id, true), "Selected gang accepted")
check(not Gang.RespondInvite(people[8], inviteB.id, true) and Gang.GetGangId(people[8]) == aId, "Other invitation invalidated after joining")
for _, id in {9, 10, 11} do
	check(Gang.RequestJoin(people[id], aId), "Request from " .. id)
	local matching
	for _, entry in Gang.GetState(a).requests do if entry.userId == id then matching = entry end end
	check(Gang.RespondRequest(a, matching.id, true), "Accept " .. id)
end
check(#Gang.GetOnlineMembers(aId) == 7, "Seven online members")
playersService.MaxPlayers = 21
check(not Gang.Invite(a, people[12].UserId), "Limit checked before invitation")
playersService.MaxPlayers = 30
check(not Gang.SetColor(people[2], 4), "Nonowner cannot change color")
check(not Gang.SetColor(a, 2), "Rival color unavailable")
check(Gang.SetColor(a, 4), "Owner selects free color")
check(not Gang.SetColor(a, 6), "Color cooldown enforced")
check(Gang.Rename(a, "Nowa Alfa"), "Owner renames with filtered text")
check(Gang.GetState(people[3]).gangName == "Nowa Alfa", "All members see renamed gang")
check(not Gang.Rename(people[2], "Forged"), "Nonowner cannot rename")
check(not Requests.Handle(a, "KickGangMember", -1), "Negative target rejected")
check(not Requests.Handle(a, "InviteGangMember", {}), "Wrong target type rejected")
check(not Requests.Handle(a, "LeaveGang", {id = aId}), "Leave rejects extra payload")
check(not Requests.Handle(a, "RespondGangRequest", {id = "x", accept = 1}), "Nonboolean acceptance rejected")

local state = Capture.New()
Capture.Step(state, { A = 2, B = 1 }, 10)
near(state.progress, 10, "2v1 gives one-person capture speed")
Capture.Step(state, { A = 2, B = 2 }, 10)
near(state.progress, 5, "Tie decays progress gradually")
check(state.phase == "contested" and state.ownerGangId == nil, "Tie does not grant ownership")
Capture.Step(state, {}, 4)
near(state.progress, 3, "Empty zone decays gradually")
Capture.Step(state, { B = 1 }, 3)
check(state.progress == 0 and state.capturingGangId == "B", "New gang erases opponent progress before capturing")
Capture.Step(state, { B = 1 }, 45)
check(state.ownerGangId == "B" and state.phase == "captured", "Capture succeeds after required control")
Capture.Step(state, {}, 100)
check(state.ownerGangId == "B", "No living capturer does not erase existing owner")
Capture.Step(state, { A = 3, B = 2, C = 1 }, 10)
check(state.phase == "contested", "Three gangs balance against total opposition")
Capture.Step(state, { A = 4, B = 2, C = 1 }, 10)
near(state.progress, 10, "4v2v1 gives one-person advantage")
Capture.RemoveGang(state, "B")
check(state.ownerGangId == nil and state.capturingGangId == "A", "Disband neutralizes owner without stealing rival progress")
Capture.RemoveGang(state, "A")
check(state.capturingGangId == nil and state.progress == 0, "Disband clears capturer")
for _, player in people do player.Character.HumanoidRootPart.Position = Vector.new(100, 1, 100) end
Combat.Start(); advance(4)
a.Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
b.Character.HumanoidRootPart.Position = Vector.new(0, 1, -3)
check(Combat.SetPassive(people[2], true), "Gang member can enable protection")
check(Combat.GetTerritoryPosition(people[2]) == nil and not Combat.CanDamage(b, people[2]), "Protection excludes capture and incoming combat")
check(not Combat.CanDamage(people[2], b), "Protection excludes outgoing combat")
Combat.StunPlayer(people[3], 3)
check(Combat.GetTerritoryPosition(people[3]) ~= nil, "Living stunned member still participates")
advance(3)
a:SetAttribute("OwnsPepperSpray", true)
local combatRemote = services.ReplicatedStorage.CombatRemotes.CombatAction
combatRemote.OnServerEvent:Fire(a, "Pepper")
near(b:GetAttribute("StunnedUntil") - testClock, 3, "Pepper stun lasts three seconds")
check(b.Character.Humanoid.Health == 100 and b.Character.Humanoid.PlatformStand, "Pepper falls player without damage")
check(not Combat.SetPassive(b, true), "Cannot enable protection immediately after combat")
local oldCharacter = b.Character
character(b); b.CharacterAdded:Fire(b.Character)
Combat.StunPlayer(b, 8)
advance(3)
check(b:GetAttribute("StunnedUntil") > testClock, "Old-character stun callback cannot clear new-character stun")
advance(5)
check(b:GetAttribute("StunnedUntil") == nil, "Current stun cleans up")

Territory.Start(); flush()
check(people[1]:GetAttribute("DataLoaded") == true, "Existing profile service started")
Rewards.Pay({ [aId] = 1 })
for _, player in Gang.GetOnlineMembers(aId) do check(player.leaderstats.Coins.Value == 8, "Equal first 60/7 payout") end
Rewards.Pay({ [aId] = 1 })
for _, player in Gang.GetOnlineMembers(aId) do check(player.leaderstats.Coins.Value == 17, "Remainder carried, all second shares equal") end
Rewards.Clear()
local eligible = Gang.GetOnlineMembers(aId)
for index, player in eligible do player:SetAttribute("DataPersistenceAvailable", index <= 3) end
Rewards.Pay({ [aId] = 2 })
for index, player in eligible do
	check(player.leaderstats.Coins.Value == (if index <= 3 then 57 else 17), "Two flags split 120 Coins among three eligible profiles only")
	player:SetAttribute("DataPersistenceAvailable", true)
end
local map = InstanceMock.new("Folder"); map.Name = "Map"; map.Parent = services.Workspace
local flag = InstanceMock.new("Model"); flag.Name = "Flag"; flag.Parent = map
local cloth = InstanceMock.new("Part"); cloth.Color = Color.new(0.1, 0.2, 0.3); cloth.Parent = flag
local originalCloth = cloth.Color
cloth:SetAttribute("TerritoryTint", true)
local zone = InstanceMock.new("Part"); zone.Name = "CaptureZone"; zone.Anchored = true; zone.Size = Vector.new(20, 20, 20)
zone.Position = Vector.zero
zone.CFrame = { PointToObjectSpace = function(_, p) return p end }
zone.Parent = flag; zone:SetAttribute("TerritoryId", "square"); zone:SetAttribute("TerritoryName", "Plac")
services.CollectionService:AddTag(zone, "GangTerritory")
local published = services.ReplicatedStorage.Territories.square
check(published:GetAttribute("Phase") == "idle", "Authored zone starts neutral")
check(cloth.Color == loadModule("ReplicatedStorage/Shared/Gang/TerritoryConfig").NeutralColor, "Unowned flag shows neutral color")
for _, player in people do player.Character.HumanoidRootPart.Position = Vector.new(100, 1, 100) end
check(Combat.SetPassive(people[2], false), "Protection can be disabled")
a.Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
people[2].Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
b.Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
people[12].Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
advance(1)
check(published:GetAttribute("Advantage") == 1, "Server counts 2v1 and ignores unganged observer")
check(Combat.SetPassive(a, true), "Owner may enable protection while capturing")
advance(1)
check(published:GetAttribute("Phase") == "contested" and published:GetAttribute("Advantage") == 0, "Protected member no longer contests or captures")
advance(3); check(Combat.SetPassive(a, false), "Owner exits protection")
b.Character.HumanoidRootPart.Position = Vector.new(100, 1, 100)
for _ = 1, 24 do advance(1) end
check(published:GetAttribute("OwnerGangId") == aId, "Server zone captures for actual gang")
check(cloth.Color == Gang.GetState(a).gangColor, "Captured flag changes to owner color")
check(a:GetAttribute("GangFlagsOwned") == 1, "Phone flag count published")
check(a:GetAttribute("GangIncomePerMinute") == 8, "Phone displays equal share estimate")
for _, player in Gang.GetOnlineMembers(aId) do player.Character.Humanoid.Health = 0 end
advance(1)
check(published:GetAttribute("OwnerGangId") == aId, "Wipe preserves owned flag; dead players cannot capture")
advance(60)
check(Gang.SetColor(a, 1), "Owner can recolor an existing captured flag")
check(cloth.Color == Gang.GetState(a).gangColor, "Flag follows owner palette change immediately")
for _, player in people do player.Character.Humanoid.Health = 100; player.Character.HumanoidRootPart.Position = Vector.new(100, 1, 100) end
local bad = InstanceMock.new("Part"); bad.Name = "Duplicate"; bad.Anchored = true; bad.Parent = map; bad:SetAttribute("TerritoryId", "square")
services.CollectionService:AddTag(bad, "GangTerritory")
check(#services.ReplicatedStorage.Territories:GetChildren() == 1, "Duplicate territory ID rejected")

-- Exercise the real phone transport, including rate limiting before expensive reads.
loadModule("ServerScriptService/Phone/PhoneServer.server")
local phone = services.ReplicatedStorage.PhoneRemotes.PhoneRequest
advance(1)
check(phone.OnServerInvoke(a, "GetState", nil), "Phone returns state")
check(not phone.OnServerInvoke(a, "GetState", nil), "GetState is server rate limited")
advance(1)
check(not phone.OnServerInvoke(a, "LeaveGang", nil, "extra"), "Extra remote argument rejected")
advance(1)
check(not phone.OnServerInvoke(a, "SetGangColor", 0/0), "Hostile color request rejected at transport")
advance(1)
check(not phone.OnServerInvoke(people[12], "RespondGangInvite", {id = "forged", accept = true}), "Forged invitation ID rejected")

-- The owner's slot survives only while other online members keep the gang alive.
disconnectPlayer(a)
check(Gang.Exists(aId) and Gang.GetState(people[2]).leaderOfflineUntil ~= nil, "Offline leader preserved for thirty minutes")
advance(1799)
check(not Gang.GetState(people[2]).isLeader, "Grace does not transfer early")
a = reconnectPlayer(1)
check(Gang.GetState(a).isLeader and not Gang.GetState(a).leaderOfflineUntil, "Rejoin cancels leader timeout")
disconnectPlayer(a); advance(1800)
check(Gang.GetState(people[2]).isLeader and not Gang.GetGangId(a), "Oldest remaining member inherits after timeout")
check(Gang.Leave(people[2]), "Leader voluntarily leaves")
check(Gang.GetState(people[3]).isLeader, "Voluntary exit immediately promotes oldest member")
check(not Gang.Create(people[2], "Immediate", 6), "Leaving applies membership cooldown")
advance(30)
check(Gang.Create(people[2], "New gang", 6), "Free creation available after cooldown")
-- A rival can take the flag; disbanding it neutralizes the flag synchronously.
b.Character.HumanoidRootPart.Position = Vector.new(0, 1, 0)
for _ = 1, 45 do advance(1) end
check(published:GetAttribute("OwnerGangId") == bId, "Rival captures existing owner flag")
check(cloth.Color == Gang.GetState(b).gangColor, "Flag follows new owner after rival capture")
check(Gang.Leave(b), "Last member leaves")
check(not Gang.Exists(bId) and published:GetAttribute("OwnerGangId") == nil, "Empty gang disbands and neutralizes its flags")
check(cloth.Color == loadModule("ReplicatedStorage/Shared/Gang/TerritoryConfig").NeutralColor, "Disband restores neutral flag color")
services.CollectionService:RemoveTag(zone, "GangTerritory")
check(#services.ReplicatedStorage.Territories:GetChildren() == 0, "Zone removal disposes published state")
check(cloth.Color == originalCloth, "Unregister restores the authored flag appearance")
Territory.Stop(); Gang.Stop(); flush()
check(services.ReplicatedStorage:FindFirstChild("Territories") == nil, "Territory stop cleans replicated folder")
check(not Gang.Exists(aId), "Session stop removes gangs")
print("PASS: " .. testCount .. " gang, territory, combat and phone assertions")
