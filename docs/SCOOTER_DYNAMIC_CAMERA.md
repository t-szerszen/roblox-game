# System dynamicznej kamery hulajnogi (Scooter Dynamic Camera)

Dokumentacja architektury i konfiguracji dynamicznej kamery hulajnogi oraz trybów widoku.

---

## 1. Architektura

System kamery jest uruchamiany lokalnie w [ScooterClient.client.luau](file:///Users/tobiasz/dev/github/roblox-game/src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau) w momencie wejścia gracza na hulajnogę (`startController`) i automatycznie sprzątany przy zejściu (`Dismount` / `cleanupController`) poprzez `Maid`.

### Pliki:
- `src/ReplicatedStorage/Shared/Scooter/ScooterCameraConfig.luau` — zcentralizowana, data-driven konfiguracja (FOV, kąty przechyłu, bezwładność, offsety kinowe).
- `src/StarterPlayer/StarterPlayerScripts/ScooterCamera.luau` — główny kontroler renderowania kamery (`RunService.RenderStepped` na priorytecie `Camera.Value + 2`).
- `src/StarterPlayer/StarterPlayerScripts/ScooterClient.client.luau` — integracja sterowania (`ContextActionService`, akcja `ScooterCameraView` pod klawiszem `V` / `ButtonR3` i przyciskiem dotykowym).

---

## 2. Tryby widoku (Camera Modes)

Gracz przełącza widoki w pętli za pomocą klawisza **`V`** (PC), **`R3`** (Gamepad) lub przycisku na ekranie dotykowym:

### Tryb 1: Trzecia osoba (Third Person Dynamic — Domyślny)
- **Natywna kontrola kamery Roblox:** Zachowuje pełną obsługę myszki, rozglądania się i standardowy Poppercam silnika (`CameraType.Custom`).
- **Inteligentne podążanie za wektorem jazdy (Auto-Follow):** Podczas jazdy (ruch/skręcanie) kamera automatycznie i płynnie podąża za wektorem jazdy hulajnogi (`root.CFrame.LookVector`), eliminując konieczność ciągłego korygowania kąta patrzenia prawym przyciskiem myszy.
- **Natychmiastowe przejęcie kontroli (Free-look):** Gracz może w każdej chwili przejąć pełną, ręczną kontrolę nad kamerą, przytrzymując prawy przycisk myszy (RMB), dotykając ekranu lub ruszając prawą gałką pada.
- **3-sekundowy bufor powrotu:** Po puszczeniu prawego przycisku myszy kamera czeka 3 sekundy, a następnie — jeśli gracz jedzie — płynnie i łagodnie wraca do bazowej osi za hulajnogą. Jeżeli gracz stoi w miejscu, kamera pozostaje w wybranym przez gracza kierunku.
- **Dynamiczne FOV:** Kąt widzenia płynnie rozszerza się od bazowego 70° do 84° w przedziale prędkości 10–90 km/h (prędkość KuKirin G4).
- **Przechył w zakrętach (Corner Banking / Roll):** Kamera delikatnie kładzie się w łuk w stronę skrętu (do 3.5°), potęgując dynamikę.
- **Speed Pullback:** Przy przyspieszaniu kamera łagodnie odsuwa się do tyłu (do 1.8 studa).
- **Stabilność podczas Wheelie:** Kamera zachowuje stabilną, naturalną perspektywę i nie ingeruje w wysokość ani kąt natywnej kamery, eliminując ryzyko wpadania pod mapę.
- **Wibracje i Burnout:** Mikro-drgania powyżej 50 km/h oraz podczas palenia gumy.

### Tryb 2: Pierwsza osoba (First Person — Autentyczny Kokpit z podążaniem za pojazdem)
- **Naturalne podążanie za wektorem jazdy hulajnogi:** Głowa jest bazowo skierowana w stronę kierunku jazdy hulajnogi (`root.CFrame.LookVector`). W zakrętach widok obraca się płynnie razem z hulajnogą i kierownicą, bez efektu "zostawania głowy w starym kierunku świata".
- **Swobodne rozglądanie się myszką:** Gracz może w każdej chwili ruszyć głową myszką, gałką pada lub dotykiem, aby rozejrzeć się na boki.
- **Blokada obrotu do tyłu (Clamp Yaw do ±75°):** Człowiek na hulajnodze nie może obrócić szyi o 180° — kąt obrotu głowy w lewo/prawo jest ograniczony do 75°.
- **Sprężysty opór i automatyczny powrót (Auto-centering):**
  - Przy próbie przeciągnięcia głowy powyżej 75° pojawia się miękki, sprężysty opór (do max 84°), który natychmiast ściąga wzrok z powrotem.
  - Po zaprzestaniu ruszania myszką (po 1.0 s) wzrok łagodnie i płynnie wraca na wprost w oś wektora jazdy.
- **Obniżona, wysunięta pozycja oczu:** Kamera umieszczona jest w osi wizjera kasku (`EyeForwardOffset = 0.60`, `EyeUpOffset = -0.10`), idealnie nad mostkiem kierownicy, wysunięta w przód tak, by nie zahaczać o tors awatara.
- **Naturalny spoczynek wzroku na drodze i liczniku (DefaultPitch = -14.0°):** Przy neutralnej pozycji głowy (bez dotykania myszki) wzrok jest skierowany pod naturalnym kątem 14° w dół ku nawierzchni. Dzięki temu cały cyfrowy licznik prędkości `ScooterDashboard` (okrągły zegar, cyfry km/h, tryb ECO/SPORT, wskaźnik baterii oraz kontrolki świateł) jest w 100% widoczny na ekranie bez konieczności ciągłego zerkania myszką w dół.
- **Klamrowanie kątów góra/dół (Pitch Clamp):**
  - **W dół (max -36°):** Umożliwia swobodne zerknięcie na podest i koło, przy 100% wyeliminowaniu przenikania przez tors awatara.
  - **W górę (max +42°):** Umożliwia obserwację sygnalizacji świetlnej, budynków i nieba bez nienaturalnego patrzenia pionowo w chmury.
- **Czystość widoku:** Głowa i akcesoria (włosy, czapki, okulary) awatara są w 100% niewidoczne lokalnie (`LocalTransparencyModifier = 1`), eliminując jakiekolwiek zasłanianie ekranu.
- **Przechył głowy (Head Roll):** W zakręcie widok przechyla się w stronę wierzchołka zakrętu (do 3.5°), symulując odruch motocyklisty.
- **Bezwładność wzdłużna:** Lekkie cofnięcie głowy przy zrywie (0.15 studa) i pochylenie do przodu przy ostrym hamowaniu (0.22 studa).
- **Stabilność przy Wheelie:** Zero sztucznego pochylania wzroku w osi pitch; widok zachowuje w 100% naturalną orientację.
- **Inteligentne poziomowanie wzroku podczas Wheelie (Wheelie Pitch Compensation):** Podczas jazdy na jednym kole kamera nie unosi się sztywno z ramą hulajnogi w chmury. Głowa kierowcy naturalnie kompensuje przechył w przód (`WheeliePitchCompensation = 0.85`), utrzymując wzrok równo na linii drogi. Dzięki temu uniesiona kierownica i licznik prędkości znajdują się dokładnie w centrum pola widzenia, a gracz cały czas widzi drogę przed sobą bez dotykania myszki.
- **Wibracje manetek:** Drgania kierownicy przy prędkościach > 45 km/h i burnout.

---

## 3. Przełączanie i interfejs (UX)
- **Klawiatura:** Klawisz `V` (ContextActionService).
- **Gamepad:** Wciśnięcie prawej gałki (`ButtonR3`).
- **Mobile:** Automatyczny, dotykowy przycisk na ekranie dotykowym.
- **Płynny Zoom kółkiem myszy w obie strony:**
  - **Przybliżenie (Zoom In):** Zescrollowanie kółkiem myszy w przód do samych oczu awatara (ogniskowa <= 1.2 studa) automatycznie przełącza kamerę w kokpit pierwszej osoby (`FirstPerson`).
  - **Oddalenie (Zoom Out):** Zescrollowanie kółkiem myszy w tył (bądź gest oddalenia na touchpadzie) w trybie pierwszej osoby natychmiast płynnie wycofuje kamerę do trzeciej osoby (`ThirdPerson`) na odległość 5.0 studów i umożliwia dalsze swobodne oddalanie.
- **Niezawodny klawisz `V` w obie strony:** Naciśnięcie klawisza `V` (lub przycisku na padzie/ekranie) w dowolnym momencie natychmiast przełącza widok między `FirstPerson` a `ThirdPerson`. Przy powrocie do 3. osoby kamera jest zawsze ustawiana **za plecami postaci w kierunku jazdy** na klasyczny dystans (12.8 studa), z 0.8s buforem zapobiegającym jakiemukolwiek zapętleniu lub blokowaniu w głowie.
- **Brak fałszywego przybliżenia na kierownicę:** `CameraSubject` jest ustawiany na `Head`, dzięki czemu kamera w trzeciej osobie nigdy nie przybliża się do mostka kierownicy czy siedziska.
- **Pojedyncze powiadomienie bezwzględnie znikające po 2–3 sekundach:** Każda zmiana trybu zastępuje poprzedni toast w tym samym miejscu (`feedback.Replace`), wykonując animację podmiany tekstu i bezwzględnie znikając po 2.0 sekundach (komunikat startowy po 3.0 s), z gwarantowanym niszczeniem instancji ramki (zero powidoków i wiszących ramek).
- **Niezawodne przywracanie kamery przy zejściu z hulajnogi (Dismount):** Przy zejściu (`cleanupController` / `ScooterCamera.Destroy`) kamera natychmiast i bezwarunkowo ustawia `CameraSubject` na `Humanoid` gracza oraz `CameraType = Enum.CameraType.Custom`. Kamera nigdy nie pozostaje zogniskowana na hulajnodze, a awatar natychmiast odzyskuje standardowe sterowanie kamerą pieszego.
