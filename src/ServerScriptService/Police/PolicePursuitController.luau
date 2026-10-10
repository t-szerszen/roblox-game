--!strict
local Config=require(script.Parent.PoliceConfig)
local Pursuits={};Pursuits.__index=Pursuits
export type Memory={position: Vector3, lastSeen: number, started: number}
export type Registry=typeof(setmetatable({} :: {owners: {[Player]: {}}, memories: {[Player]: Memory}},Pursuits))
function Pursuits.new(): Registry
 return setmetatable({owners={},memories={}},Pursuits)
end
function Pursuits.Claim(self: Registry, player: Player, owner: {}, position: Vector3, now: number): boolean
 if self.owners[player] then return false end
 local count=0;for _ in self.owners do count+=1 end
 if count>=Config.MaxPursuits then return false end
 self.owners[player]=owner;self.memories[player]={position=position,lastSeen=now,started=now}
 return true
end
function Pursuits.Owns(self: Registry, player: Player, owner: {}): boolean
 return self.owners[player]==owner
end
function Pursuits.Release(self: Registry, player: Player, owner: {})
 if not self:Owns(player,owner) then return end
 self.owners[player]=nil;self.memories[player]=nil
end
function Pursuits.Observe(self: Registry, player: Player, owner: {}, position: Vector3?, now: number)
 if not self:Owns(player,owner) or not position then return end
 local memory=self.memories[player];memory.position=position;memory.lastSeen=now
end
function Pursuits.Expired(memory: Memory, vehiclePosition: Vector3, now: number): string?
 if now-memory.started>=Config.PursuitTimeout then return "PursuitTimeout" end
 local unseen=now-memory.lastSeen
 -- Escape distance is measured to the last observed location, never a hidden live target.
 if unseen>=Config.LostSightTolerance and (vehiclePosition-memory.position).Magnitude>=Config.EscapeDistance then return "Escaped" end
 if unseen>=Config.SearchTimeout then return "SearchTimeout" end
 return nil
end
return Pursuits
