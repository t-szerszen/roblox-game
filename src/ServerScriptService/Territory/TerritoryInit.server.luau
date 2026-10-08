--!strict
local TerritoryService = require(script.Parent.TerritoryService)
TerritoryService.Start()
script.Destroying:Connect(TerritoryService.Stop)
