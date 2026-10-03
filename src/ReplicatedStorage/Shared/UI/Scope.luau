--!strict

export type Cleanup = RBXScriptConnection | Instance | (() -> ())
export type Scope = {
	_tasks: { Cleanup },
	_alive: boolean,
	Give: (self: Scope, cleanup: Cleanup) -> (),
	Clean: (self: Scope) -> (),
}

local Scope = {}

local function dispose(cleanup: Cleanup): any
	if typeof(cleanup) == "RBXScriptConnection" then
		cleanup:Disconnect()
	elseif typeof(cleanup) == "Instance" then
		cleanup:Destroy()
	else
		cleanup()
	end
	return nil
end

function Scope.new(): Scope
	local self: Scope = { _tasks = {}, _alive = true } :: any
	function self:Give(cleanup: Cleanup)
		if self._alive then
			table.insert(self._tasks, cleanup)
		else
			dispose(cleanup)
		end
	end
	function self:Clean()
		if not self._alive then return end
		self._alive = false
		-- Disconnect callbacks before destroying their objects. One faulty cleanup
		-- must not retain the remaining connections or a modal movement lock.
		for index = #self._tasks, 1, -1 do
			local ok, problem = pcall(dispose, self._tasks[index])
			if not ok then warn("UI cleanup: " .. tostring(problem)) end
		end
		table.clear(self._tasks)
	end
	return self
end

return Scope
