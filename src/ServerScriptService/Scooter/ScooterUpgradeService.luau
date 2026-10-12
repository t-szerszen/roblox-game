--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage.Shared.ScooterUpgradeCatalog)
local Stats = require(ReplicatedStorage.Shared.ScooterUpgradeStats)
local Config = require(ReplicatedStorage.Shared.ScooterConfig)
local Data = require(script.Parent.Parent.Activity.PlayerDataService)
local Service = {}
local function modelState(profile: any, modelName: string)
 if not profile then return nil end
 local normalized=Catalog.Normalize(profile.scooterEquipment[modelName])
 profile.scooterEquipment[modelName]=normalized
 return normalized
end

function Service.Equipped(player: Player, modelName: string): {[string]: boolean}
 local profile = Data.GetProfile(player)
 local state = modelState(profile,modelName)
 return if state then table.clone(state.equipped) else {}
end

function Service.Calculate(player: Player, modelName: string)
 local base = Config.Models[modelName]
 if not base then return nil end
 local profile = Data.GetProfile(player)
 local tier = if profile then profile.scooterUpgrades[modelName] or 0 else 0
 local tuning = Config.GetTuning(modelName,tier)
 if not tuning then return nil end
 local result = Stats.Calculate({
  SpeedKmh=tuning.maxSpeed, Acceleration=base.acceleration,
  WeightKg=nil, BrakeForce=Config.BrakingDeceleration, PowerWatts=nil,
  WheelieAngle=Config.WheelieFallAngle,
 },Service.Equipped(player,modelName))
 -- Preserve old speed tiers additively; new percent bonuses still use the model base.
 result.Acceleration += tuning.acceleration - base.acceleration
 result.StartBonusPercent += (tuning.acceleration/base.acceleration - 1)*100
 return result,tuning
end

function Service.State(player: Player, modelName: string)
 local stats = Service.Calculate(player,modelName)
 if not stats then return nil end
 local profile = Data.GetProfile(player)
 local state = modelState(profile,modelName)
 return {
  modelName=modelName, stats=stats,
  equipped=if state then table.clone(state.equipped) else {},
  owned=if state then table.clone(state.owned) else {},
  ready=profile ~= nil,
  persistent=player:GetAttribute("DataPersistenceAvailable") == true,
  free=Catalog.FreeInstallation,
 }
end

function Service.Set(player: Player, modelName: string, id: any, enabled: any): (boolean, string)
 if typeof(id) ~= "string" or not Catalog.ById[id] or typeof(enabled) ~= "boolean" then return false,"Niepoprawne ulepszenie." end
 if not Config.Models[modelName] or not Data.OwnsScooter(player,modelName) then return false,"To nie jest Twoja hulajnoga." end
 if not Catalog.FreeInstallation then return false,"Zakupy za walutę są jeszcze wyłączone." end
 local profile = Data.GetProfile(player)
 if not profile then return false,"Poczekaj na wczytanie danych." end
 local state = modelState(profile,modelName)
 if not state then
  state={owned={},equipped={}}
  profile.scooterEquipment[modelName]=state
 end
 if enabled then state.owned[id]=true end
 state.equipped[id]=if enabled then true else nil
 return true,if enabled then "Ulepszenie zainstalowane." else "Wyposażenie zdjęte."
end

return Service
