# NPC police

## Inspected architecture (2026-10-08)

The repository was clean on `main` at `8bd9697`; implementation uses
`feature/npc-police-system`. The connected Studio is `gra roblox`, place
`127535941224851`, inspected directly in Edit mode. `Workspace.Map.Drogi`
contains the authored road surfaces. No map is rebuilt or serialized by police.
The existing approved Git road snapshot contains 216 nodes and 204 directed
Bezier curves (198 enabled). Its disconnected streets remain disconnected.

`TrafficManager` owns the shared fleet, Heartbeat, cached sensors and intersection
reservations. `VehicleController` is kinematic: acceleration and braking advance
distance on sampled road curves; anchored models move with `PivotTo`, with road
support, footprint overlap, predicted bodies and swept collision checks. Cars do
not use VehicleSeat throttle, constraints or Humanoid movement. Police must reuse
this controller and the same reservations and sensor bodies.

`ScooterServer` retains network ownership of articulated scooters and validates
all rider input. Its private records own seating, controls, contacts and wheelie.
`SpeedKmh` is a rounded presentation of physical motion using the established
arcade conversion `ScooterConfig.StudsPerKmH = 1.6`; police must use that conversion,
not introduce a different real-world scaling. Wheelie is server accepted and
requires rear contact; jumping and arbitrary pitch are not violations. Existing
dismount resets controls and removes only the owned seat's `SeatWeld`.

Both source cars are direct children of Workspace, anchored, without PrimaryPart,
constraints or an officer. Kia has 73 physical parts, A-Chassis/ELS scripts and
four wheel roots `Wheels.FL/FR/RL/RR`; its front points toward world +Z, opposite
its saved pivot. Fiat Ducato Policja has 93 physical parts, five passenger seats,
A-Chassis/ELS scripts and the same four wheel names; its front points toward -X.
Both contain blue/red PointLights and existing Wail/HiLow/Yelp sounds. Their
unscaled envelopes are approximately 14.3 x 11.7 x 31.2 and 14.8 x 14.0 x 28.0
studs. They cannot be passed directly to the existing strict traffic adapter.

## Scope decisions

The current request replaces the older GDD police triggers with a configurable
50 km/h limit and sustained wheelie, and authorizes temporary detention without
economy penalties. PvP, jumps, toll gates, fines, rewards and playable police
factions are outside this implementation. The documented spawn safe zone and
night reduction remain applicable. No gang membership changes police authority.

Integration will add per-car tuning and directed destination routing, preserving
civilian defaults. Police units participate in the same fleet and collision list.
An adapter sanitizes clones of the two actual cars, derives orientation from
axles, adds the traffic chassis contract, and leaves source models untouched.
Server-only scooter state/dismount APIs and a reversible mount lock support
detention. Officer navigation uses a standard R15 rig and bounded asynchronous
PathfindingService tasks. Violation rules, pursuit ownership, AI transitions and
detention validation are separate responsibilities.
