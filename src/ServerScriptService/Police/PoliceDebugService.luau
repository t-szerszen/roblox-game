--!strict
local Config=require(script.Parent.PoliceConfig)
local Debug={}
function Debug.Enabled(root: Instance): boolean
 return Config.Debug or root:GetAttribute("PoliceDebug")==true
end
function Debug.Write(model: Model, values: {[string]: string | number | boolean})
 for name,value in values do if model:GetAttribute(name)~=value then model:SetAttribute(name,value) end end
end
function Debug.Signal(player: Player, unitId: number?)
 player:SetAttribute("PoliceStopRequested",unitId)
end
return Debug
