local Config = loadModule("ReplicatedStorage/Shared/ScooterConfig")
services.Workspace = {}
local Arcade = loadModule("ServerScriptService/Scooter/ScooterArcadeSteps")
local Physics = loadModule("ReplicatedStorage/Shared/Scooter/ScooterPhysics")
check(Config.ArcadeSteps.Enabled, "Production uses smooth traversal")
for _, fps in { 30, 60, 120 } do
 for _, target in { 1, 2.5, -1, -2.5 } do
  local current, velocity = 0, 0
  for _ = 1, fps * 3 do
   local nextHeight, nextVelocity = Arcade.AdvanceHeight(current, target, 1 / fps, velocity)
   check(if target > 0 then nextHeight >= current and nextHeight <= target else nextHeight <= current and nextHeight >= target,
    "Height follows the surface without overshoot")
   local limit = if target > 0 then Config.ArcadeSteps.MaxRiseSpeed else Config.ArcadeSteps.MaxDropSpeed
   check(math.abs(nextHeight - current) <= limit / fps + 1e-8, "Vertical path speed is bounded")
   check(math.abs(nextVelocity - velocity) <= Config.ArcadeSteps.MaxHeightAcceleration / fps + 1e-8,
    "Vertical acceleration is bounded")
   current, velocity = nextHeight, nextVelocity
  end
  near(current, target, "Height settles at all supported frame rates", 1e-4)
 end
end
for _,fps in {30,60,120} do
 local yaw=0
 for tick=1,fps*3 do
  local target=if tick<=fps then Config.TurnRate else if tick<=fps*2 then -Config.TurnRate else 0
  local nextYaw=Physics.SmoothYawRate(yaw,target,1/fps)
  check(math.abs(nextYaw-yaw)<=Config.MaxYawAcceleration/fps+1e-8,"Yaw starts, reverses and stops without snapping")
  yaw=nextYaw
 end
 check(math.abs(yaw)<.001,"Yaw returns to neutral")
end
local height, velocity = 0, 0
for _ = 1, 120 do
 local nextHeight, nextVelocity = Arcade.AdvanceHeight(height, if height < .5 then 1 else -1, 1 / 60, velocity)
 check(math.abs(nextVelocity - velocity) <= Config.ArcadeSteps.MaxHeightAcceleration / 60 + 1e-8,
  "Changing support cannot introduce a velocity kick")
 height, velocity = nextHeight, nextVelocity
end
near(Arcade.CompressionPulse(0), 0, "Suspension starts without snapping")
near(Arcade.CompressionPulse(Config.ArcadeSteps.SuspensionAttack), 1, "Suspension reaches visible compression")
near(Arcade.CompressionPulse(Config.ArcadeSteps.SuspensionAttack + Config.ArcadeSteps.SuspensionHold), 1,
 "Compression persists even after a fast tire has passed the edge")
near(Arcade.CompressionPulse(Config.ArcadeSteps.SuspensionAttack + Config.ArcadeSteps.SuspensionHold + Config.ArcadeSteps.SuspensionRelease),
 0, "Suspension releases smoothly")
near(Arcade.AdvanceHeight(1, 2.5, 0), 1, "Zero time cannot move the chassis")
near(Arcade.AdvanceHeight(2.5, 2.5, .1), 2.5, "Settled height does not inject rebound")
print("PASS: smooth arcade height assertions", testCount)
