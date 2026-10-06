--!strict

local ScooterServer = require(script.Parent.ScooterServer)

ScooterServer.Start()
local ScaleTests = require(script.Parent.DevScooterScaleTests)
ScaleTests.Start()

script.Destroying:Connect(function()
	ScaleTests.Stop()
	ScooterServer.Stop()
end)
