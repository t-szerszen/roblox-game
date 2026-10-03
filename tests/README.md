# Scooter verification

## Runtime regression suite

Run with Python 3 and the [official Luau CLI](https://github.com/luau-lang/luau/releases):

```sh
python3 tests/run_scooter_tests.py --luau /path/to/luau
```

The runner loads the actual source files without rewriting their implementation.
`support/roblox_mock.luau` supplies a controlled clock, vector arithmetic, player
instances, signals, DataStore and Marketplace responses. No live account, currency,
Marketplace purchase or DataStore is accessed. The expected warning for a simulated
failed profile load is part of the test.

Assertions cover the five GDD base speeds and all 15 upgrade prices, acceleration
scaling, tier limits, malformed/NaN/infinite input, packet cooldowns, input expiry,
held-button reset, gradual coasting, braking, speed-sensitive steering, lateral grip,
airborne drive rejection, exact coin debits, duplicate expected tiers, ownership,
profile migration, failed-load protection, saved upgrades, disconnected profile
listeners, validated RGB, garage rate limits, unconfigured premium IDs, verified
game passes, entitlement caching/failure and garage shutdown.

These tests do not simulate Roblox physics integration or real network replication.
In particular, torque stability, humanoid seating, raycast contacts, remote delivery
ordering and the physical mesh/template must also be checked in Studio.

## Build and strict type analysis

```sh
rojo build default.project.json --output /tmp/scooter-check.rbxlx
rojo sourcemap default.project.json --output /tmp/scooter-sourcemap.json
```

Use `luau-compile --null` for syntax/bytecode verification. For actual Roblox-aware
type analysis, use [Luau Language Server](https://github.com/JohnnyMorganz/luau-lsp)
with its generated `scripts/globalTypes.d.luau` definitions and the Rojo sourcemap:

```sh
luau-lsp analyze --platform=roblox \
  --sourcemap=/tmp/scooter-sourcemap.json \
  --definitions=@roblox=/path/to/globalTypes.d.luau \
  src/ReplicatedStorage/Shared/ScooterConfig.luau \
  src/ReplicatedStorage/Shared/Scooter/ScooterPhysics.luau \
  src/ServerScriptService/Scooter \
  src/ServerScriptService/Activity/PlayerDataService.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau \
  src/StarterPlayer/StarterPlayerScripts/ScooterPrediction.luau
```

## Studio multiplayer acceptance checks

Use an isolated test place with the current Rojo source, a flat test road and the
production scooter template. Start a server with two clients. Repeat physical
checks with the generated fallback and the imported template, and with R6/R15.
Avoid changing the production `Workspace.Map` for testing.

1. **Ownership and collision.** Player B cannot mount or control player A's scooter.
   Inspect the canonical root on the server: `GetNetworkOwner()` remains `nil`
   while mounted and unmounted. All visual meshes remain noncolliding/massless;
   only the invisible wheel proxies contact the road. Local prediction models
   exist only on the rider's client and cannot move other players or physical
   objects. The standing rider remains aligned with the deck and handlebars.
2. **Driving.** Accelerate each model on level ground and compare the settled
   speed to the replicated `MaxSpeedKmh` (before and after each purchased tier).
   Release W to coast, press S to brake, then continue S to reverse responsively
   from a complete stop on both flat road and a mild slope. Steering
   cannot rotate the scooter at rest; at high speed the same input produces a
   smaller turn. Cross raised road markings, seams, ramps and curbs up to the
   configured step height from rest and at low speed, both forward and backward,
   without catching meshes or repeatedly injecting step impulses in midair. Dismount while
   moving and crash from a wheelie; the abandoned scooter should settle nearby
   instead of bouncing or accelerating away. Test 30/60/120 FPS and Studio
   network emulation around 150–250 ms latency.
3. **Wheelie and pitch.** Space performs no action and does not unseat the rider.
   Press Shift or C once while moving forward to trigger wheelie, then use W/S to
   adjust pitch; releasing both holds the angle only while enough forward momentum
   remains. Brake hard and stop: the front must drop rapidly instead of balancing
   at zero speed. Outside wheelie, W/S must not tilt the chassis. Wheelie cannot
   start while reversing.
   Falling releases the rider and recovers after the configured stun. Pepper-spray
   stun overlapping a crash must retain the longer authoritative stun.
4. **Burnout replication.** Hold W+S at rest. Both clients see the server emitter
   on `RearWheelAttachment`; only an entitled owner sees their selected premium
   color. Releasing either key, being pushed above the low-speed threshold,
   leaving the ground, death, dismount and stale drive input all disable the emitter.
   Calling `TrickState:FireServer("Burnout", true)` without fresh simultaneous
   throttle/brake intent cannot activate it. Supplying an extra client color has
   no authority over the server emitter.
5. **Hostile remotes.** From the test client call `DriveInput` with strings, tables,
   NaN (`0/0`), infinity, steering outside `[-1,1]` and nonboolean trick buttons.
   Spam both valid and invalid requests and confirm the server stays responsive,
   input does not become NaN, and speed/coins/tier/ownership do not change. Stop
   sending accepted drive packets while holding W; intent resets within
   `DriveInputTimeout`. Send requests from player B while player A is mounted.
6. **Garage transactions.** Seed Coins only from the test server. Buy each speed
   tier, verify the exact GDD debit, immediate scooter attribute update and tier-3
   cap. Send two requests with the same expected tier; only one debit occurs.
   Attempt an unowned model, insufficient balance and purchases before profile
   load. Rejoin the isolated place to confirm persisted tiers/preferences. A
   failed DataStore read must keep purchases disabled and cannot overwrite data.
7. **Premium verification.** IDs of zero leave premium effects unavailable. In the
   isolated place configure actual experience-owned test game passes, test a real
   entitled account and a non-owner, and verify RGB/enable changes replicate to
   both clients. A saved preference, local attribute, purchase prompt or forged
   request alone must not grant entitlement. Invalid RGB values are rejected.
8. **Cleanup.** Repeat mount/dismount, reset, death, scooter replacement and server
   Stop/Start. No extra input/render callbacks, prediction models or smoke remain.
   Camera offset, rider collisions, transparency and character network ownership
   return to normal on dismount. Typing in chat or losing focus releases controls.
   Lose focus, die/dismount, refocus while unmounted, then remount: controls work.
   Compare client memory and event/network activity before and after repeated cycles.

Record Studio results separately from CLI checks; a successful Rojo build alone
does not establish gameplay or multiplayer correctness.
