--!strict

local ScooterServer = require(script.Parent.ScooterServer)

ScooterServer.Start()

script.Destroying:Connect(ScooterServer.Stop)
