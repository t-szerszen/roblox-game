-- Run after Rojo sync in Studio's Command Bar. Fixtures stay outside the DataModel.
local Inspector = require(game.ServerScriptService.Scooter.DevScooterInspect)
local HttpService = game:GetService("HttpService")
local root = Instance.new("Folder")
root.Name = "InspectionFixture"
local outside = Instance.new("Part")
local ok, result = xpcall(function()
	local first = Instance.new("Model")
	first.Name = "Grip"
	first.Parent = root
	local second = Instance.new("Model")
	second.Name = "Grip"
	second.Parent = root
	local mesh = Instance.new("MeshPart")
	mesh.Name = "RawMesh"
	mesh.CFrame = CFrame.new(10, 20, 30) * CFrame.Angles(0.2, 0.4, 0.6)
	mesh.Anchored = true
	mesh:SetAttribute("Mount", CFrame.new(1, 2, 3))
	mesh.Parent = first
	local part = Instance.new("Part")
	part.Parent = second
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.new(0.5, 1, 2)
	a.Parent = mesh
	local b = Instance.new("Attachment")
	b.Parent = part
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0, hinge.Attachment1 = a, b
	hinge.Parent = mesh
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0, spring.Attachment1 = a, b
	spring.MaxForce = math.huge
	spring.Parent = mesh
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = part, outside
	weld.Parent = part
	local missing = Instance.new("HingeConstraint")
	missing.Parent = part
	local before, pose = #root:GetDescendants(), mesh.CFrame
	local selected = game:GetService("Selection"):Get()
	local report = Inspector.Read(root)
	local decoded = HttpService:JSONDecode(Inspector.ToJSON(report))
	local ids, entries = {}, {}
	for _, entry in report.entries do
		ids[entry.id] = entry
		entries[entry.className] = entry
		if entry.parentId then assert(ids[entry.parentId], "parent must precede child") end
	end
	assert(report.counts.MeshPart == 1 and report.counts.Model == 2 and #report.entries == before + 1)
	assert(#decoded.entries == #report.entries and #report.warnings >= 4)
	local meshEntry = entries.MeshPart
	assert(meshEntry.properties.CFrame[1] == 10 and #meshEntry.properties.CFrame == 12)
	assert(meshEntry.attributes.Mount[2] == 2)
	assert(ids[entries.SpringConstraint.properties.Attachment0.id].className == "Attachment")
	assert(entries.SpringConstraint.properties.MaxForce == "inf")
	assert(entries.WeldConstraint.properties.Part1.external and entries.WeldConstraint.properties.Part1.id == nil)
	local grips = {}
	for _, entry in report.entries do if entry.name == "Grip" then table.insert(grips, entry) end end
	assert(grips[1].id ~= grips[2].id and grips[1].path == grips[2].path)
	assert(#root:GetDescendants() == before and mesh.CFrame == pose and mesh.Anchored)
	assert(weld.Part1 == outside and spring.MaxForce == math.huge and root.Parent == nil)
	local afterSelection = game:GetService("Selection"):Get()
	assert(#selected == #afterSelection)
	for index, item in selected do assert(item == afterSelection[index]) end
	assert(not pcall(Inspector.Read, mesh), "must reject a single part as root")
	local empty = Instance.new("Folder")
	local emptyReport = Inspector.Read(empty)
	empty:Destroy()
	assert(#emptyReport.entries == 1 and #emptyReport.warnings == 0)
	return "PASS: scooter inspection with real Roblox Instances, duplicate IDs, endpoint references, poses, JSON and read-only behavior"
end, debug.traceback)
root:Destroy()
outside:Destroy()
if not ok then error(result) end
print(result)
return result
