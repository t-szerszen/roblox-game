# ROADMAP.md

## Cel Projektu

- Priorytet pierwszorzędny: Szybkie zbudowanie grywalnego MVP (Minimum Viable Product)[cite: 2].
- Strategiczne ograniczenia: Zasada "speed > perfect tooling" oraz "working gameplay > infrastructure perfection"[cite: 2].

## Harmonogram Wdrażania

### Etap 1: Środowisko i Weryfikacja

- [ ] Zbudowanie podstawowej architektury projektu[cite: 2].
- [ ] Skonfigurowanie stabilnego przepływu pracy z użyciem platformy GitHub i narzędzia Rojo[cite: 2].
- [ ] Wykonanie pomyślnego testu pipeline'u od gałęzi `feat/test-pipeline` do złączenia z gałęzią `main`[cite: 2].

### Etap 2: System Mapy (Szacowany czas: ~4-6 dni)

- [x] Zachowanie `MapData`, `AssetRegistry` i `MapBuilder` jako jawnie uruchamianych narzędzi podglądu, odbudowy i wersjonowania mapy.
- [x] Wyłączenie automatycznego generowania mapy przy starcie serwera, aby nie nadpisywać ręcznie zbudowanego `Workspace.Map`.
- [x] Dodanie serializacji modeli z `Workspace.Map`, włącznie z obsługą logicznych podfolderów.
- [ ] Ręczne zbudowanie i uporządkowanie produkcyjnej mapy w Roblox Studio pod `Workspace.Map`.
- [ ] Okresowe serializowanie mapy do `src/ServerScriptService/Map/MapData.luau` i commitowanie snapshotów układu do Git.
- [ ] Zweryfikowanie procesu odbudowy mapy ze snapshotu i zarejestrowanych zasobów.

### Etap 3: Rdzeń Rozgrywki (Core Gameplay)

- [ ] Opracowanie podstawowych mechanik rozgrywki[cite: 2].
- [ ] Unikanie rozbudowy złożonych frameworków testowych, dopóki gra nie posiada działających systemów[cite: 2].

### Etap 4: Zawartość i Szlify (Content & Polish)

- [ ] Ustabilizowanie potoku zasobów przez umieszczanie wszystkich modeli przygotowanych przez AI lub z Blendera do folderu `assets/` (jako pliki `.fbx`)[cite: 2].
- [ ] Poprawa wydajności i finalne szlify interakcji[cite: 2].

### Etap 5: Rozwój Narzędzi (Poza zakresem MVP)

- [ ] Tworzenie opcjonalnych narzędzi deweloperskich usprawniających przepływ pracy[cite: 2].
- [ ] Ewentualne zbudowanie pluginu do Roblox Studio usprawniającego wykonywanie snapshotów, walidację tagów i kontrolę zasobów bez zastępowania ręcznej edycji mapy[cite: 2].
