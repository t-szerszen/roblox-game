--!strict
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DaylightConfig"))
local period = Config.DayHoldSeconds + Config.SunsetHoldSeconds + Config.TransitionSeconds * 2
local started = os.clock()
local elapsed = 0
Lighting.ClockTime = Config.DayTime
local function clockAt(seconds: number): number
	local phase = seconds % period
	if phase < Config.DayHoldSeconds then return Config.DayTime end
	phase -= Config.DayHoldSeconds
	if phase < Config.TransitionSeconds then
		local t = phase / Config.TransitionSeconds
		return Config.DayTime + (Config.SunsetTime - Config.DayTime) * (t * t * (3 - 2 * t))
	end
	phase -= Config.TransitionSeconds
	if phase < Config.SunsetHoldSeconds then return Config.SunsetTime end
	local t = (phase - Config.SunsetHoldSeconds) / Config.TransitionSeconds
	return Config.SunsetTime + (Config.DayTime - Config.SunsetTime) * (t * t * (3 - 2 * t))
end
-- Low-frequency updates avoid waking every streetlight script on every frame.
local connection = RunService.Heartbeat:Connect(function(delta: number)
	elapsed += delta
	if elapsed < Config.UpdateInterval then return end
	elapsed = 0
	Lighting.ClockTime = clockAt(os.clock() - started)
end)
local guard = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	if Lighting.ClockTime < Config.DayTime or Lighting.ClockTime > Config.SunsetTime then
		Lighting.ClockTime = math.clamp(Lighting.ClockTime, Config.DayTime, Config.SunsetTime)
	end
end)
script.Destroying:Once(function() connection:Disconnect() guard:Disconnect() end)
