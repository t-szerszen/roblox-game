--!strict

local CombatConfig = {}

CombatConfig.RemoteFolderName = "CombatRemotes"
CombatConfig.ActionRemoteName = "CombatAction"

CombatConfig.MaxHealth = 100
CombatConfig.SpawnProtectionDuration = 3
CombatConfig.SafeZoneRadius = 100
CombatConfig.ProtectionToggleCooldown = 3
CombatConfig.ProtectionCombatLock = 5

CombatConfig.MeleeDamage = 15
CombatConfig.MeleeCooldown = 0.8
CombatConfig.MeleeRange = 6
CombatConfig.MeleeFacingDot = 0.35

CombatConfig.RamDamage = 25
CombatConfig.RamStunDuration = 2
CombatConfig.RamMinimumSpeed = 12
CombatConfig.RamHitRadius = 3.5
CombatConfig.RamPairCooldown = 2.5
CombatConfig.RamCheckInterval = 0.1

CombatConfig.PepperStunDuration = 3
CombatConfig.PepperCooldown = 5
CombatConfig.PepperRange = 14
CombatConfig.PepperFacingDot = 0.6
CombatConfig.PepperOwnershipAttribute = "OwnsPepperSpray"

CombatConfig.RemoteRateLimit = 0.05

return CombatConfig
