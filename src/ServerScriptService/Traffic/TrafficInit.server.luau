--!strict
local Manager=require(script.Parent.TrafficManager)
local destroying=script.Destroying:Connect(Manager.Stop)
-- Existing road collision sanitization finishes before traffic captures its support surfaces.
task.defer(function()
	if not script.Parent then return end
	local ok,err=pcall(Manager.Start)
	if not ok then Manager.Stop(); warn("[Traffic] startup rejected: "..tostring(err)) end
end)
game:BindToClose(function() Manager.Stop(); destroying:Disconnect() end)
