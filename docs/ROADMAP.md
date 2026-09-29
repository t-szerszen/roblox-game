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

- [ ] Implementacja modułu `MapData` wykorzystującego parametry rozmieszczenia obiektów, takie jak ID zasobu, pozycja, rotacja i skala[cite: 2].
- [ ] Implementacja modułu `AssetRegistry` obsługującego wyłącznie fizyczne zasoby wyeksportowane w formacie `.fbx`[cite: 2].
- [ ] Implementacja modułu `MapBuilder` do pobierania danych z `MapData`, klonowania modeli i generowania mapy wewnątrz folderu `Workspace.Map`[cite: 2].
- [ ] Stworzenie logiki transformacji oraz napisanie podstawowych testów modułowych dla generowania mapy[cite: 2].

### Etap 3: Rdzeń Rozgrywki (Core Gameplay)

- [ ] Opracowanie podstawowych mechanik rozgrywki[cite: 2].
- [ ] Unikanie rozbudowy złożonych frameworków testowych, dopóki gra nie posiada działających systemów[cite: 2].

### Etap 4: Zawartość i Szlify (Content & Polish)

- [ ] Ustabilizowanie potoku zasobów przez umieszczanie wszystkich modeli przygotowanych przez AI lub z Blendera do folderu `assets/` (jako pliki `.fbx`)[cite: 2].
- [ ] Poprawa wydajności i finalne szlify interakcji[cite: 2].

### Etap 5: Rozwój Narzędzi (Poza zakresem MVP)

- [ ] Tworzenie opcjonalnych narzędzi deweloperskich usprawniających przepływ pracy[cite: 2].
- [ ] Ewentualne zbudowanie niestandardowego pluginu do edytora wewnątrz Roblox Studio wspierającego automatyczną wizualizację `MapData`[cite: 2].
