local start = testCount
local Scrape = loadModule("ServerScriptService/Scooter/ScooterScrape")
local savedRaycast = services.Workspace.Raycast
local model = make(nil, "Model", "ScrapeFixture")
local chassis = make(model, "Part", "Root")
local rear = make(chassis, "Attachment", "RearAxle")
local controller = Scrape.Create(model, chassis, rear)
local emitter = chassis.WheelieScrapePoint.WheelieSparks
local settings = Config.WheelieSparks
local probes = 0
services.Workspace.Raycast = function()
	probes += 1
	return { Position = Vector.zero, Normal = Vector.yAxis }
end
controller.Update(true, settings.StartPitch - 0.01, 20, {})
check(not emitter.Enabled and probes == 0, "Ordinary wheelie does not emit sparks or probe the road")
controller.Update(false, settings.StartPitch + 0.1, 20, {})
check(not emitter.Enabled, "Unmounted and fallen states cannot enable scrape sparks")
controller.Update(true, settings.StartPitch + 0.1, settings.MinSpeed - 1, {})
check(not emitter.Enabled, "Stationary overbalance never produces moving scrape sparks")
controller.Update(true, settings.StartPitch, 20, {})
check(emitter.Enabled and model:GetAttribute("WheelieSparksActive"), "High actual pitch near the road enables sparks")
controller.Update(true, (settings.StartPitch + settings.StopPitch) / 2, 20, {})
check(emitter.Enabled, "Pitch hysteresis avoids emitter flicker during suspension motion")
controller.Update(true, settings.StopPitch - 0.01, 20, {})
check(not emitter.Enabled, "Recovering pitch stops sparks")
services.Workspace.Raycast = function() return nil end
controller.Update(true, settings.StartPitch, 20, {})
check(not emitter.Enabled, "Over-pitched airborne wheelie does not scrape an absent road")
controller.Destroy()
controller.Destroy()
controller.Update(true, settings.StartPitch, 20, {})
check(chassis:FindFirstChild("WheelieScrapePoint") == nil and not model:GetAttribute("WheelieSparksActive"),
	"Repeated cleanup removes particles and update stays inert")
model:Destroy()
services.Workspace.Raycast = savedRaycast
print(string.format("PASS: %d wheelie scrape assertions (%d total)", testCount - start, testCount))
