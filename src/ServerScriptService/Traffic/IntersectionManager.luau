--!strict
local Config=require(script.Parent.TrafficConfiguration)
local Manager={}; Manager.__index=Manager
export type Reservation = { owner: number, since: number, progressed: boolean }
export type Queue = { id: number, at: number }
export type State = typeof(setmetatable({} :: {held: {[string]: Reservation}, queues: {[string]: {Queue}}},Manager))
function Manager.new(): State return setmetatable({held={},queues={}},Manager) end
function Manager.Request(self: State, zone: string, id: number, now: number, clear: boolean): boolean
	local held=self.held[zone]
	if held and held.owner==id then return true end
	local queue=self.queues[zone]
	if not queue then queue={}; self.queues[zone]=queue end
	local found=false
	for _,entry in queue do if entry.id==id then found=true; break end end
	if not found then table.insert(queue,{id=id,at=now}) end
	if held or not clear or queue[1].id~=id then return false end
	self.held[zone]={owner=id,since=now,progressed=false}; table.remove(queue,1)
	return true
end
function Manager.Progress(self: State, id: number)
	for _,held in self.held do
		if held.owner==id then held.progressed=true end
	end
end
function Manager.Release(self: State, id: number)
	for zone,held in self.held do if held.owner==id then self.held[zone]=nil end end
	for zone,queue in self.queues do
		for i=#queue,1,-1 do if queue[i].id==id then table.remove(queue,i) end end
		if #queue==0 then self.queues[zone]=nil end
	end
end
function Manager.ReleaseZone(self: State, zone: string, id: number)
	local held=self.held[zone]
	if held and held.owner==id then self.held[zone]=nil end
end
function Manager.Expired(self: State, now: number): {number}
	local expired: {number} = {}
	for _,held in self.held do
		-- Expire a blocked owner, not a vehicle still making its way through traffic.
		if held.progressed then held.since=now; held.progressed=false end
		if now-held.since>Config.IntersectionWaitTimeout then table.insert(expired,held.owner) end
	end
	return expired
end
return Manager
