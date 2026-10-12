--!strict
local Gang=require(script.Parent.Parent.Gang.GangService)
local Data=require(script.Parent.Parent.Activity.PlayerDataService)
local Rewards={}
local lastTime: number?=nil
local previous: {[Player]: number}={}
function Rewards.Update(flagCounts: {[string]: number}, now: number)
 if lastTime and now<lastTime then return end
 local elapsed=if lastTime then now-lastTime else 0
 lastTime=now
 if elapsed>0 then for player,flags in previous do Data.RecordTimedReward(player,"Gang",elapsed,flags) end end
 table.clear(previous)
 for id,flags in flagCounts do
  if flags<=0 or not Gang.Exists(id) then continue end
  for _,player in Gang.GetOnlineMembers(id) do if Data.Ready(player) then previous[player]=flags end end
 end
end
function Rewards.Clear() lastTime=nil;table.clear(previous) end
return Rewards
