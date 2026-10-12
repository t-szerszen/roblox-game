--!strict
export type Upgrade = {
 Id: string,
 Label: string,
 Description: string,
 Price: number,
 SpeedKmh: number?,
 AccelerationBonus: number?,
 BrakeBonus: number?,
 PowerWatts: number?,
 WheelieBonus: number?,
}

local items: {Upgrade} = {
 {Id="Vesc", Label="VESC kontroler", Description="+20% startu · +4 km/h", Price=5000, SpeedKmh=4, AccelerationBonus=.20},
 {Id="WeightReduction", Label="Zmniejszenie wagi", Description="+10% startu · +2 km/h", Price=750, SpeedKmh=2, AccelerationBonus=.10},
 {Id="WheelieMode", Label="Pakiet wheelie", Description="Bez błotników i iskier · +5% nachylenia · −0,5 kg", Price=5000, WheelieBonus=.05},
 {Id="DualMotor", Label="Podwójny silnik", Description="+10 km/h · +15% startu · napęd na oba koła", Price=20000, SpeedKmh=10, AccelerationBonus=.15},
 {Id="Brakes", Label="Ulepszenie hamulców", Description="+25% hamowania · większe tarcze i zaciski", Price=15000, BrakeBonus=.25},
 {Id="Battery1Kw", Label="+1 kW bateria", Description="+1000 W · +10 km/h · +10% startu", Price=25000, PowerWatts=1000, SpeedKmh=10, AccelerationBonus=.10},
}

local byId: {[string]: Upgrade} = {}
for _,item in items do
 assert(not byId[item.Id], "Duplicate upgrade ID")
 byId[item.Id] = table.freeze(item)
end

local function normalize(state: any): {owned: {[string]: boolean}, equipped: {[string]: boolean}}
 local owned: {[string]: boolean}={}
 local equipped: {[string]: boolean}={}
 if typeof(state) ~= "table" then return {owned=owned,equipped=equipped} end
 for id in byId do
  if typeof(state.owned)=="table" and state.owned[id]==true then
   owned[id]=true
   if typeof(state.equipped)=="table" and state.equipped[id]==true then equipped[id]=true end
  end
 end
 -- Retain the earlier fender purchase as the combined wheelie package.
 if typeof(state.owned)=="table" and state.owned.RemoveFenders==true then
  owned.WheelieMode=true
  if typeof(state.equipped)=="table" and state.equipped.RemoveFenders==true then equipped.WheelieMode=true end
 end
 -- Keep historical ownership for a possible return of the display option, but unequip it.
 if typeof(state.owned)=="table" and state.owned.RemoveDisplay==true then owned.RemoveDisplay=true end
 return {owned=owned,equipped=equipped}
end

return table.freeze({
 Normalize=normalize,
 FreeInstallation=true,
 WeightReductionKg=2,
 FenderWeightKg=.5,
 BrakeVisualScale=1.25,
 CaliperVisualScale=1.15,
 RequestCooldown=.3,
 Items=table.freeze(items),
 ById=table.freeze(byId),
})
