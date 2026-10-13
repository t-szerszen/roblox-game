# Rojo i elementy authorowane w Studio

Repozytorium pozostaje źródłem prawdy dla kodu. Place `gra roblox` (`127535941224851`) może jednak zawierać ręcznie authorowane obiekty mapy i assety, których Rojo nie powinien odtwarzać ani usuwać.

## Aktualny zakres

Elementy widoczne w Studio, ale wcześniej nieobecne w repo, zostały przejęte do źródeł:

- `ReplicatedStorage.Shared.DaylightConfig`
- `ReplicatedStorage.Shared.ScooterUpgradeCatalog`
- `ReplicatedStorage.Shared.ScooterUpgradeStats`
- `ReplicatedStorage.Shared.ScooterUpgradeThumbnails`
- `ReplicatedStorage.Shared.ScooterUpgradeUI`
- `ServerScriptService.DaylightService`

Nazwy plików używają rozszerzenia `.server.luau` dla skryptów serwerowych, więc Rojo mapuje je do `Script`, tak jak pozostałe skrypty tego repo.

## Zasada synchronizacji

`Workspace` nie jest mapowany w `default.project.json`, dlatego ręcznie authorowana `Workspace.Map` i pozostałe obiekty mapy pozostają poza zakresem synchronizacji Rojo. `ServerStorage` ma jawne `$ignoreUnknownInstances`, ponieważ przechowuje natywne kopie robocze i backupy narzędzi Studio.

Nie włączamy globalnego ignorowania nieznanych instancji w `ReplicatedStorage` ani `ServerScriptService`: brakujący kod ma zostać wykryty i dodany do repo, zamiast być cicho ukrywany przed synchronizacją.

Synchronizacja do Studio jest zabroniona bez wyraźnej zgody użytkownika na konkretną synchronizację. Współpracownik edytuje projekt bezpośrednio w Studio. Zmiany, buildy i testy przygotowujemy lokalnie; nie łączymy Rojo ani nie przesyłamy kodu przez MCP. Odczyt struktury mapy nie upoważnia do jej modyfikacji. Zobacz również `AGENTS.md`.
