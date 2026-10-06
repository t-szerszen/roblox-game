# Liczniki hulajnogi

Pierwsza wersja nawiązuje do zaakceptowanej grafiki: grafitowa obudowa ze ściętymi
narożnikami, czarny ekran, duże białe cyfry segmentowe, turkusowy napis KuKirin
i czerwona kontrolka hamowania. Prędkość jest centrowana jako cała liczba
(jedna, dwie albo trzy cyfry). Ekran pokazuje też tryb ECO / SPORT i uproszczoną
baterię: stałe 67%, cztery jasne i dwie przygaszone kreski. Bateria nie zużywa
energii i nie wpływa na prędkość.

- [Podgląd projektu](../assets/scooter/dashboard-preview.svg) pokazuje 47 km/h,
  SPORT, baterię 67% i aktywny hamulec. To widok frontowy, nie zrzut z gry.
- [Model Roblox](../assets/scooter/ScooterDashboard.rbxmx) zawiera obudowę,
  mocowanie i SurfaceGui. Startuje od 0 km/h, SPORT i przygaszonej kontrolki.
- `scripts/generate_scooter_dashboard.py` jest źródłem geometrii, kolorów
  i układu ekranu. Generuje model i podgląd; wymaga Python 3 oraz Rojo z PATH:

```sh
python3 scripts/generate_scooter_dashboard.py
```

Model ma szerokość 1,85, wysokość obudowy 0,74 i głębokość 0,24 studa.
To początkowy rozmiar do dopasowania w Studio. Ekran znajduje się na ścianie
`Front` części `DisplaySurface`. Obracaj i skaluj cały Model, aby zachować
położenie obudowy względem ekranu i mocowania.

## Utworzenie i montaż w Studio

1. Zatrzymaj Play i zsynchronizuj Rojo. W Explorer powinien pojawić się
   `ReplicatedStorage.ScooterDashboardTemplate` oraz
   `ServerScriptService.Scooter.DevScooterDashboard`. Jeśli szablonu nie ma,
   uruchom ponownie `rojo serve default.project.json` i połącz plugin Rojo;
   projekt ma nowe mapowanie assetu poza katalogiem `src`.
2. W Server Command Bar utwórz osobny, zakotwiczony model przed kamerą:

```lua
require(game.ServerScriptService.Scooter.DevScooterDashboard).Create()
```

3. Ustaw cały `Workspace.ScooterDashboard` na środku kierownicy. Pochyl ekran
   w stronę kierowcy. Najwygodniej pracować przy zainstalowanym szablonie
   `ServerStorage.ScooterModels.scooter`; można go tymczasowo pokazać w Workspace
   w Edit mode, a po montażu przywrócić do ServerStorage.
4. Zaznacz jednocześnie licznik i kompletny Folder/Model hulajnogi. Uruchom:

```lua
require(game.ServerScriptService.Scooter.DevScooterDashboard).MountSelection()
```

Polecenie zachowuje wybraną pozycję. Dodaje wewnętrzne weldy i łączy ekran
z `HandleBar`, więc obudowa skręca razem z kierownicą. Części są bezmasowe,
niezakotwiczone i nie uczestniczą w kolizjach. Powtórny montaż nie zastępuje
istniejącego licznika. Można też zaimportować plik `.rbxmx`, nazwać model
`ScooterDashboard` i użyć tego samego polecenia montażu.

5. Jeśli licznik zamontowano na oryginalnym Folderze, zainstaluj cały model
   przez istniejące `ScooterWorkflow.Assemble()` zgodnie z
   [instrukcją modelu](SCOOTER_MODEL.md). Montaż na zainstalowanym szablonie
   nie wymaga ponownego Assemble. Zapisz place i rozpocznij nową sesję Play.

Nie montuj licznika na hulajnodze istniejącej tylko podczas Play: jej kopia
znika po zakończeniu sesji. Obecne polecenia nie zapisują place automatycznie.
Narzędzie nie dodaje licznika do produkcyjnego modelu przy starcie serwera.

### Aktualizacja wcześniej ustawionego licznika

Po synchronizacji wybierz jeden Model `ScooterDashboard` albo kompletną hulajnogę,
która go zawiera. W Edit mode uruchom:

```lua
require(game.ServerScriptService.Scooter.ScooterDashboardWorkflow).Update()
```

Workflow ładuje świeżą wersję narzędzia, również jeśli wcześniej używano Create
lub MountSelection. Aktualizacja zastępuje wyłącznie GUI i zachowuje rozmiar,
położenie obudowy oraz weldy. Poprzedni ekran zostaje wyłączony i przeniesiony
do `ServerStorage.ScooterDashboardBackups`. Zapisz place i rozpocznij nową
sesję Play, aby skrypty sterowania oraz serwer użyły aktualnych modułów.

## ECO / SPORT i podpowiedź

Tryby są funkcją hulajnogi, a licznik odzwierciedla ich zatwierdzony stan.
Po wejściu na własną hulajnogę pojawia się krótki popup
`P — ECO / SPORT · L — światła`. Na urządzeniach dotykowych dostępny jest także
przycisk ECO / SPORT. Sterowanie znika po zejściu z hulajnogi; pisanie w czacie,
brak focusu i otwarte okna blokujące gameplay nie wysyłają zmian trybu.

Nowa hulajnoga startuje w SPORT. ECO ustawia limit napędu 25 km/h (nie podnosi
niższego bazowego limitu), SPORT przywraca pełną prędkość istniejącego tuningu.
ECO używa 70% przyspieszenia SPORT; prędkość maksymalna cofania pozostaje 18 km/h. Tryb można zmienić
podczas ruchu; kod nie zmienia bezpośrednio velocity. Przy gazie istniejący
kontroler sił stopniowo dochodzi do nowego limitu, a bez gazu zostaje normalne
wytracanie prędkości. Limit napędu nie zatrzymuje fizycznie zjazdu z górki.
Wybór jest pamiętany po zsiadaniu i ponownym wejściu na ten sam model, ale nie
po jego usunięciu, ponownym przywołaniu ani ponownym dołączeniu do gry.

Serwer odrzuca argumenty żądania `ToggleDriveMode`, weryfikuje właściciela,
zajęte siedzenie, życie, ogłuszenie i stan upadku oraz stosuje cooldown 0,4 s.
Klient nie wybiera limitu ani nie przekazuje prędkości. Konfiguracja trybów
jest w `Shared.ScooterConfig.DriveModes`.

## Dane i cykl życia

`ScooterDashboardClient` wykrywa opcjonalny
`ScooterDashboard.DisplaySurface.DashboardGui` w modelach istniejącego folderu
hulajnóg. Czeka na kompletną replikację elementów ekranu. Wspólny moduł
`ScooterDashboard` aktualizuje GUI tylko przy zmianach atrybutów:

- `SpeedKmh`: liczba obliczana przez serwer według istniejącej skali gry.
  Także jazda do tyłu pokazuje dodatnią wartość. Maksymalny odczyt to 999;
  brak lub nieprawidłowe dane pokazują kreskę.
- `BrakeActive`: hamowanie przeciw aktualnemu kierunkowi ruchu — S podczas jazdy
  do przodu lub W podczas cofania — oraz W+S. Sama jazda wstecz nie pokazuje BRAKE.
  Tylna lampka ma osobny stan `StopLightActive` i świeci również przy cofaniu.
- `DriveMode`: ECO wyświetla się na zielono, SPORT na fioletowo. Bez
  zatwierdzonego stanu etykieta pokazuje kreskę. Starszy GUI bez etykiety Mode
  nadal pokazuje prędkość i hamulec; użyj Update, aby dodać nowe elementy.

Moduł licznika nie wysyła remote calls. Sterowanie hulajnogą wysyła tylko
żądanie przełączenia; serwer odpowiada za siły i limit. Obserwatorzy odczytują
te same atrybuty. SurfaceGui podlega
zasłanianiu przez geometrię, a własne podświetlenie zachowuje czytelność
w ciemności; zobacz [SurfaceGui w dokumentacji Roblox](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui).

`ScooterPrediction` obsługuje osobną kopię ekranu w lokalnej prezentacji,
gdy ten istniejący system jest używany. Kopia otrzymuje wyłącznie elementy GUI
i nadal korzysta ze stanu prawdziwej hulajnogi. Skrypty i obiekty gameplayowe
nie są kopiowane. Oryginalny ekran jest lokalnie wyłączony na czas prezentacji,
a jego poprzednia widoczność wraca po sprzątaniu. Ta zmiana nie włącza predykcji.

Wszystkie części assetu mają atrybut `ScooterDecoration = true`.
`ScooterRig` zachowuje ich bezmasowość również przy pierwszym Assemble,
aby dodatkowa obudowa nie zmieniała strojenia zawieszenia. GUI i połączenia
są sprzątane po usunięciu ekranu, hulajnogi lub prezentacji oraz zatrzymaniu
skryptu klienta. Obudowa i jej wewnętrzne weldy pozostają częścią szablonu
autorskiego w Studio.

## Weryfikacja

Testy CLI obejmują wskazania, brak danych, trzy cyfry, kontrolkę hamowania,
kopię prezentacji, odłączanie połączeń, blokadę montażu w Play, odrzucenie
drugiego licznika, wewnętrzne weldy, bezpieczną aktualizację GUI i zachowanie
bezmasowości przez rig. Integracja serwera sprawdza limit ECO, łagodne dojście
do 25 km/h, przełączanie podczas ruchu, cooldown, błędne argumenty, obcego
gracza, martwego/ogłuszonego kierowcę, zsiadanie i ponowny spawn.
`tests/scooter_dashboard.studio.luau` sprawdza właściwe Instance Roblox
bez umieszczania obiektów testowych w DataModelu.

Po montażu sprawdź w Studio: czytelność z kamery pierwszej osoby, skręt
w obie strony, wheelie, prędkość 0 i po ulepszeniach, hamowanie, jazdę
wstecz, przełączanie P, podpowiedź po wejściu, pamięć trybu przy ponownym wejściu,
blokadę P podczas pisania w czacie, widoczność z drugiego klienta oraz ponowne spawny. Nie przesuwaj
produkcyjnego `Workspace.Map` podczas tych sprawdzeń. Build i testy logiki
nie zastępują sprawdzenia rozmiaru oraz kąta na autorskim modelu.

## Licznik na ekranie i światła

`ScooterSpeedometer` tworzy okrągły HUD w prawym dolnym rogu po wejściu na
hulajnogę. Ma skalę 0–100 km/h, płynną wskazówkę, duże cyfry, oznaczenia D/R/N,
ECO/SPORT, BRAKE i status światła. Widok dopasowuje rozmiar do rozdzielczości
i pozostaje dostępny podczas jazdy w obu widokach kamery.
Atrybuty odczytuje z prawdziwego modelu; nie wysyła prędkości do serwera.
ScooterClient sprząta GUI oraz połączenia przy zsiadaniu, zniszczeniu modelu
i zatrzymaniu skryptu. Konfiguracja HUD jest w ScooterDashboardConfig.

L przełącza białe światło przednie; na ekranie dotykowym jest przycisk Światła.
Żądanie jest bezargumentowe i weryfikowane przez serwer z cooldownem 0,35 s.
Oba liczniki pokazują BRAKE przy faktycznym hamowaniu. Podczas cofania HUD
pokazuje R, a tylna czerwona lampka pozostaje włączona bez kontrolki BRAKE.

W modelu ScooterFinal skala testowa wynosi 0,30, a cały fizyczny dashboard
ma dodatkowy mnożnik 1,48 wokół DisplaySurface. To około 10% większy ekran
niż przy poprzednim mnożniku 1,35; skala całej hulajnogi pozostaje 0,30. Przebudowa pochodzi z zachowanego źródła i nie
generuje ani nie duplikuje assetu licznika. HUD sprawdzono wizualnie w Play;
ręcznie sprawdź jeszcze L, pierwszą osobę oraz sterowanie dotykowe.
