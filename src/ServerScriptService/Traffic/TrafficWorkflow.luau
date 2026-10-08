--!strict
local ServerScriptService=game:GetService("ServerScriptService")
local RunService=game:GetService("RunService")
local Workflow={}
local function fresh<T>(action: (any)->T): T
	assert(not RunService:IsRunning(),"Traffic authoring runs in Edit mode")
	local original=ServerScriptService:WaitForChild("Traffic")
	local clone=Instance.new("Folder")
	-- Unparented clones avoid executing TrafficInit during an authoring reload.
	for _,module in original:GetChildren() do if module:IsA("ModuleScript") then module:Clone().Parent=clone end end
	local requireFresh: any=require
	local ok,result=pcall(function() return action(requireFresh(clone:FindFirstChild("DevTrafficTool") :: ModuleScript)) end)
	clone:Destroy(); if not ok then error(result,2) end; return result :: T
end
function Workflow.Inspect() return fresh(function(tool) return tool.Inspect() end) end
function Workflow.Generate(replaceDraft: boolean?) return fresh(function(tool) return tool.Generate(replaceDraft) end) end
function Workflow.Connect(fromId: string, toId: string, intersection: string?, handle: number?)
	return fresh(function(tool) return tool.Connect(fromId,toId,intersection,handle) end)
end
function Workflow.Approve() return fresh(function(tool) return tool.Approve() end) end
function Workflow.Serialize(): string
	return fresh(function(tool) local result=tool.Serialize(); print(result); return result end)
end
function Workflow.Validate()
	return fresh(function(tool)
		local root=tool.Root(); local source=root:FindFirstChild("CandidateNetwork") or root:FindFirstChild("Network")
		assert(source,"Generate first"); return tool.Read(source)
	end)
end
return Workflow
