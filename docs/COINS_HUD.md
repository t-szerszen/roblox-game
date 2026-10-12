# Coins HUD

`StarterGui/CoinsHUD/CoinsHUDClient.client.luau` displays the player's balance in
the bottom-left corner. It reads the server-replicated `leaderstats.Coins` IntValue
published by `Activity/PlayerDataService` and uses the existing UI theme,
components, number formatter and cleanup scopes. It sends no remote requests and
does not change currency, rewards or purchases.

The display shows `— Coins` until the value is available, then updates through
property-change events, including after purchases and rewards. It handles delayed
profile loading and replacement/removal of the stats folder or Coins value.
The direct `StarterGui.CoinsHUD` ScreenGui has `ResetOnSpawn = false`, so both its
controller and panel persist through respawns without creating duplicate counters.
It disconnects listeners when destroyed.

`Shared/UI/CoinsHUDConfig` controls the panel dimensions, spacing and icon image.
`IconImage` is intentionally empty; the transparent `CoinIcon` ImageLabel reserves
space for future artwork. The existing minimap sits above the counter using the
same margin, panel height and gap to prevent overlap. Both HUDs retain the default
ScreenGui safe-area behavior.
