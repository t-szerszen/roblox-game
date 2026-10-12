# Studio → worktree → PR → jeden sync

Użytkownik 2026-10-12 jawnie zlecił przejęcie wszystkich zmian Studio do lokalnego worktree, logiczne commity, PR i jedną synchronizację. Ta zgoda nie włącza stałego synchronizowania kolejnych zmian.

## Zachowanie pracy

- Worktree: `/Users/tobiasz/dev/github/roblox-game-integration`, branch `feat/studio-economy-integration`, baza `2483ae7` zgodna z `origin/main` przy rozpoczęciu integracji.
- Oryginalne `/Users/tobiasz/dev/github/roblox-game` pozostaje nietknięte, ze swoimi wcześniejszymi lokalnymi zmianami. Nie wykonano tam resetu ani czyszczenia.
- Lokalny backup przed scalaniem: `/Users/tobiasz/.codex/backups/studio-integration-20261012` — patch, wszystkie pliki, źródła Studio, native scene/terrain, manifest i późniejszy pre-sync backup.
- Snapshot w Git: `assets/studio-snapshots/` — 690 buforów źródłowych, 3114 natywnych korzeni obiektów, cały sparse TerrainRegion oraz odczytywalne serializowane ustawienia usług i kolory materiałów terenu.
- 173 skrypty z usług mapowanych przez Rojo trafiły do `src/`; osadzone skrypty Workspace/ServerStorage pozostały z obiektami w snapshotcie. Nie zostały osobno wgrane do ręcznie authorowanych modeli.

## Rozwiązanie różnic

Źródła scalono trójstronnie z bazą Git, bieżącym Studio i wcześniejszą lokalną implementacją. Aktualne ustawienia skrętu, lean, wheelie, fizyka, rider pose oraz modele hulajnogi mają wersję Studio. Lokalna ekonomia dołącza do istniejącego kontrolera jego autorytatywny stan jazdy i wyposażenie kosmetyczne.

Zachowano nowsze, wcześniej niewersjonowane systemy Studio: personalizację i części hulajnogi, melee, ragdoll, loading screen w ReplicatedFirst oraz daylight. Mapa i modele nie są odtwarzane z repo. Osobny garaż pozostaje wyłączony; wcześniejsza stacja personalizacji zachowana. Dostawy korzystają z telefonu i punktów istniejących sklepów/budynków.

Import `ReplicatedFirst` otrzymał jawne mapowanie w `default.project.json`. Scene/terrain recovery snapshot nie został dodany jako źródło Workspace do tego projektu Rojo.

## Logiczne commity

1. Snapshot sceny i terenu Studio.
2. Import kodu personalizacji, hulajnogi, walki i ekranu ładowania ze Studio.
3. Poprawki cyklu życia i bezpieczeństwa ruchu NPC.
4. Poprawki pościgu, zatrzymania i integracji policji z ruchem.
5. Ekonomia, sklep, trwałe odblokowania i dostawy z telefonu.
6. Dokumentacja procesu, zachowania hulajnogi i testów integracji.

## Walidacja przed PR

- Kompilacja wszystkich 186 źródeł Luau i lokalny build Rojo: PASS.
- Ekonomia: 110 asercji PASS; gang/terytoria/gaz/transport telefonu: 143 PASS.
- Hulajnoga `--runtime-only`: 230 PASS; smooth arcade `--arcade-only`: 8332 PASS.
- UI: 129 PASS; policja: 809 PASS; ruch: 2655 PASS; integracja policja/ruch: 75 PASS.
- Test natywny finalnych źródeł w prywatnym, nieparentowanym sandboxie Studio: 16 asercji PASS — rzeczywiste Vector3, wheelie x2, teleport, sesje na table-double DataStore, kopia rzeczywistego rig/gazu, Classic/Premium, radio, wyłączony garaż i cleanup UI. Wczytano 186 prywatnych kopii źródeł. Zmieniono **0 istniejących skryptów gry**, wykonano **0 rzeczywistych operacji DataStore**. Sandbox usunięto po teście.
- Dane wspierające native test nie były wstawiane do DataModel. Ten test nie jest dodatkowymi synchronizacjami do gry.
- Pełny legacy pakiet wizualny hulajnogi nadal zatrzymuje się na brakującym helperze `make` w istniejącym fixture. Nie deklarujemy jego zaliczenia. Nowy natywny melee hitbox ma istniejący fixture Studio i nie jest symulowany w testach gangów.

## Zakres pojedynczej synchronizacji

Jedna operacja aktualizuje scalone źródła w usługach mapowanych przez Rojo. Przed zmianą sprawdza, czy wszystkie przejęte źródła edytora nadal odpowiadają snapshotowi; niespodziewana edycja kolegi przerywa operację przed zapisami. Robiony jest dodatkowy pre-sync backup.

Operacja nie usuwa nieznanych obiektów. Nie zapisuje do Workspace, terenu, StarterPack ani istniejących modeli ServerStorage; modele hulajnogi zachowują tożsamość i części. Dopuszczone nowe obiekty to brakujące moduły/skrypty, dwa własne ScreenGui HUD oraz brakujący serwerowy template gazu, sklonowany z istniejącego narzędzia. Mapa i modele nie są synchronizowane z archive snapshotu. Żaden place nie jest publikowany w Roblox.

Po operacji porównuje się wszystkie docelowe źródła, sprawdza tożsamość mapy i modeli i wyłącza lokalny most synchronizacji. Wynik ma być zapisany w PR. Dalsza synchronizacja wymaga nowej, konkretnej zgody.

## Pozostałe ograniczenia

Game Pass IDs są nadal nieuzupełnione, brak modelu Surona, a radio ma odblokowanie i stan wyposażenia bez odtwarzania audio. Prawdziwe płatności i DataStore/rejoin wymagają osobnego środowiska i konfiguracji. Ręczne testy przejazdów, wejść dostaw, multiplayera i mobile są wymienione w `ECONOMY_IMPLEMENTATION.md`.
