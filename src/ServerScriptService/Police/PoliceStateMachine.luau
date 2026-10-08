--!strict
local Machine={};Machine.__index=Machine
local allowed: {[string]: {[string]: boolean}}={
 PATROL={OBSERVING=true,RECOVERING=true},
 OBSERVING={PATROL=true,PURSUIT=true,RECOVERING=true},
 PURSUIT={APPROACHING=true,RETURNING=true,RECOVERING=true},
 APPROACHING={PURSUIT=true,STOPPING=true,RETURNING=true,RECOVERING=true},
 STOPPING={PURSUIT=true,OFFICER_EXITING=true,RETURNING=true,RECOVERING=true},
 OFFICER_EXITING={ARRESTING=true,PURSUIT=true,RETURNING=true,RECOVERING=true},
 ARRESTING={PURSUIT=true,RETURNING=true,RECOVERING=true},
 RETURNING={PATROL=true,PURSUIT=true,RECOVERING=true},
 RECOVERING={PATROL=true,PURSUIT=true,RETURNING=true},
}
export type State=typeof(setmetatable({} :: {state: string, since: number, reason: string, generation: number},Machine))
function Machine.new(now: number): State
 return setmetatable({state="PATROL",since=now,reason="Spawned",generation=0},Machine)
end
function Machine.Transition(self: State, state: string, now: number, reason: string): boolean
 if state==self.state then return false end
 assert(allowed[self.state] and allowed[self.state][state],"Illegal police transition: "..self.state.." -> "..state)
 self.state=state;self.since=now;self.reason=reason;self.generation+=1
 return true
end
return Machine
