# KuKirin G4 — analiza przed migracją

Odczyt 2026-10-13 przez integrację Roblox Studio, place `127535941224851`,
w trybie Edit. Sprawdzono aktualne źródła Studio, hierarchię, właściwości,
połączenia aktywnego szablonu oraz widok nowego modelu. Nie uruchamiano Play,
nie synchronizowano kodu i nie zmieniano modeli ani skryptów Studio.
Poniższe zachowania wynikają z analizy implementacji; nie są nowym testem jazdy.

## Aktualna mechanika

Aktywny szablon to `ServerStorage.ScooterModels.scooter`, a nie model wystawiony
w Workspace. Wszystkie pozycje katalogu korzystają obecnie z tego samego rigu;
wybór produktu ustala parametry i wyposażenie. Nazwa nowego modelu sama nie
przełącza szablonu ani nie nadaje parametrów produktu G4.

- `ScooterServer`, `ScooterInput` i `ScooterPhysics`: serwerowa kontrola ruchu,
  własność sieciowa serwera, walidacja właściciela i kierowcy, życia/stun,
  argumentów i częstotliwości wejścia. Klient wysyła intencje sterowania.
  `VectorForce` obsługuje napęd, hamowanie, toczenie i bieg wsteczny;
  `AlignOrientation` utrzymuje orientację i równowagę.
- W przyspiesza; S hamuje, następnie poniżej progu 2 km/h włącza wsteczny
  z limitem 18 km/h. A/D steruje fizycznym zawiasem Servo kierownicy.
  Aktualny serwer wyznacza obrót podwozia z zaakceptowanego polecenia skrętu;
  nie czeka na osiągnięcie kąta przez zawias. Odczyt kąta jest nadal publikowany.
  Maksymalny kąt kierownicy wynosi 48°, a limit przechyłu podwozia 28°.
  Skręt słabnie wraz z prędkością. Bez burnout podwozie nie obraca się w miejscu.
- E służy do wsiadania/zsiadania; postać jest związana natywnym `SeatWeld`
  z niewidocznym `DriverSeat`. Skok podczas jazdy jest blokowany.
- P przełącza SPORT/ECO; ECO ma limit napędu 25 km/h. SPORT korzysta
  z parametrów wybranego produktu, np. bazowe G4 ma 90 km/h.
  L wysyła żądanie przełączenia przedniego światła.
- Shift/C wyzwala wheelie przy prędkości do przodu powyżej 10 km/h,
  kontakcie tylnego koła i spełnieniu cooldownu. Początkowy cel to 5°;
  W podnosi w kierunku punktu równowagi około 35–38°, puszczenie W opuszcza,
  S opuszcza szybciej. Limit równowagi to 45°, bazowy próg upadku 68°;
  wyposażenie może ustalić inny `WheelieMaxAngle`. Faktyczne wheelie
  potwierdzają kontakt tyłu, brak kontaktu przodu i fizyczny kąt co najmniej 8°.
  Upadek lub silna kolizja powoduje wyrzucenie/stun kierowcy.
- W+S przy niskiej prędkości uruchamia burnout: silnik tylnego zawiasu,
  dym i możliwość donutów. Efekty zależą od serwerowego stanu kontaktu/inputu.
  Osobny system iskier sprawdza kąt i rzeczywisty kontakt z podłożem.
- `ScooterArcadeSteps` jest włączony: zweryfikowane małe przeszkody,
  do skonfigurowanego limitu 2,5 studa, obsługuje płynna ścieżka wysokości
  z ruchem zawieszenia. To nie sama pasywna fizyka sprężyn.
  `ScooterTerrain` pozostaje wariantem odzyskiwania/deweloperskim.

Aktualny rig ma 65 części fizycznych, 7 `HingeConstraint`, 2
`SpringConstraint`, 24 attachmenty i 59 `WeldConstraint`.
`CentralShockRig=true`, `IndependentFrontSteering=false`: kolumna i przedni
moduł skręcają razem; po dwa zawiasy wahaczy na każdą oś, dwa zawiasy kół,
jeden zawias skrętu. Masa i geometria zawieszenia są kalibrowane dla szablonu.

## Postać i animacje

`ScooterBaseRidingPose` i `Shared/Scooter/ScooterBasePose` tworzą proceduralną
pozę R15 po ewaluacji Animatora. Obsługują `Motor6D` oraz połączenia
`AnimationConstraint`; zachowują długości kończyn i proporcje awatara.
Stopy są rozwiązywane względem `FootRest`, dłonie względem
`HandleBar.LeftHandGrip` i `RightHandGrip` na ruchomej kierownicy.
R6 nie otrzymuje tej własnej pozy.

Aktualny kod zawiera już reakcje tułowia na przyspieszanie i hamowanie,
skręt tułowia i korektę zasięgu rąk, przechył w zakręcie, przeciwruch podczas
wheelie, ugięcie przy rozpoczęciu wheelie oraz amortyzację lądowania.
Serwer publikuje m.in. `RidingState`, `WheeliePhysical`, `FrontGrounded`
i `RearGrounded`. Każdy klient oblicza pozy obserwowanych kierowców;
cleanup przy zsiadaniu/śmierci/usunięciu przywraca stawy i ustawienia Animatora.
Nie jest potrzebny osobny przesłany klip animacji, by zachować te zachowania.

`ScooterSpringVisuals` wygładza obrót kół i animuje dekoracyjne sprężyny
na lokalnych kopiach MeshPartów. Nowe koła złożone z wielu części i segmentowe
sprężyny wymagają dopasowania tego istniejącego modułu.

Starsze opisy o wyłącznie neutralnej pozie i przechyle 16° nie opisują w pełni
obecnego Studio. Aktualne `ScooterConfig`, `ScooterServer` i `ScooterPhysics`
różnią się od repozytorium; nie nadpisano ani nie importowano tych zmian.

## Znaleziony model

`Workspace.KuKirin G4` znajduje się około `(303.68, 7.76, 23.33)`.
Obok jest `Workspace.KuKirin G4v2`, z takimi samymi policzonymi klasami
obiektów i rozmiarami; nie badano pełnej identyczności obu modeli.
Przedmiotem tej analizy jest dokładnie `KuKirin G4`.

Model ma osiem grup: `Body`, `Stem`, `Cockpit`, `Cables`, `FrontSuspension`,
`RearSuspension`, `FrontWheel`, `RearWheel`. Zawiera 1919 potomków,
w tym 1731 części fizycznych: 1691 `Part`, 39 `UnionOperation`, 1 `WedgePart`.
Wszystkie są Anchored, niekolizyjne i bez Massless. Nie ma `PrimaryPart`,
attachmentów, constraintów, weldów ani skryptów. Obecne zwoje i amortyzatory
są geometrią dekoracyjną: po dwa amortyzatory z przodu i z tyłu.

Wymiary obwiedni to około `12.23 × 11.81 × 6.24` studa w osiach świata.
Rozstaw osi wynosi około 9,38 studa, rozstaw środków chwytów 5,03 studa,
a chwyty znajdują się około 8,84 studa nad powierzchnią GripTape.
Obwiednia kompletnych kół ma średnicę około 2,55 studa, wraz z bieżnikiem.
Aktywny szablon ma rozstaw osi około 7,70, chwyty oddalone o 3,74 studa
i koła o średnicy 1,95 studa. Dopasowanie postaci wymaga osobnego pomiaru;
nie ustalono ani nie zastosowano automatycznie nowej skali.

## Co trzeba przygotować

1. **Zespoły mechaniczne i weldy.** Oddzielić podwozie, kolumnę/kokpit,
   wahacze z osiami oraz obracające się koła. Dekoracje przypisać do odpowiednich
   zespołów. Nie spawać wahaczy ani kół na sztywno do podwozia. W grupach kół
   są również zaciski i elementy osi: nie powinny obracać się z oponą i tarczą.
   Przewody przechodzą przez ruchome zespoły i również wymagają przypisania.
2. **Attachmenty i zawiasy.** Zmierzyć oś skrętu, współosiowe mocowania
   czterech wahaczy oraz centra/osi obrotu obu kół. Zachować Servo skrętu,
   pasywne zawiasy wahaczy z limitami i zawiasy kół, w tym napęd burnout tyłu.
3. **Sprężyny fizyczne.** Dodać attachmenty górnych/dolnych mocowań i
   `SpringConstraint`. Obecny aktywny wariant ma dwie sprężyny centralne;
   nowy model ma cztery wizualne amortyzatory. Istnieje też starszy wariant
   czterech sprężyn, ale nie jest gotowym adapterem tego modelu. Wybór między
   dwiema sprężynami z czterema dekoracjami a czterema fizycznymi sprężynami
   pozostaje do ustalenia w etapie zawieszenia. Parametry trzeba przeliczyć
   dla nowych ramion, skali, mas i skoku; nie kopiować wartości w ciemno.
4. **Kontrakt kierowcy i kolizji.** Przygotować `Root` jako PrimaryPart,
   `DriverSeat`, `FootRest`, `RiderRootAttachment`, dwa grip attachmenty,
   osie pomocnicze i uproszczone collidery kół/podestu. `ScooterRig.Prepare`
   generuje część tych helperów dla zgodnego wejścia; nowy model jeszcze nim
   nie jest. Siły napędu, stabilizację i emitery tworzą istniejące moduły runtime.
5. **Adapter modelu i prezentacji.** Obecny `ScooterRig.Inspect` wymaga
   konkretnych MeshPartów na najwyższym poziomie, np. `ScooterBody`,
   `HandleBarStick`, `HandleBar`, `FrontWheel`, `BackWheel` i cztery wahacze.
   G4 ma zamiast nich grupy Model, Part i UnionOperation, a tył nazywa się
   `RearWheel`. Sama zmiana nazwy modelu i dodanie sprężyn nie wystarczy.
   Trzeba również dopasować animowane koła/sprężyny, ekran, światła,
   punkty efektów oraz istniejące grupy personalizacji.
6. **Koszt modelu.** 1731 części na hulajnogę wobec 65 w aktualnym szablonie
   wymaga przeglądu dekoracji, zwojów i przewodów przed wdrożeniem multiplayer.
   To obserwacja liczby obiektów, nie wynik profilowania. Nie usunięto geometrii.

Proponowana kolejność kolejnych etapów: pomiary i fit awatara; adapter i sztywny
podział zespołów; osie i skręt; zawieszenie i collidery; dopiero potem podpięcie
istniejącego kontrolera, wheelie/burnout i prezentacji. Źródło G4 i obecny
szablon należy zachować, a pierwsze próby wykonywać na osobnej kopii.
Ta analiza nie stanowi autoryzacji żadnej synchronizacji lub instalacji w Studio.

## Przygotowany rig — 2026-10-13

Po analizie użytkownik zlecił przygotowanie modelu i kodu oraz pozwolił dopasować
skalę hulajnogi do awatara. Implementacja znajduje się na branchu
`feat/kukirin-g4-rig`. Oryginalny G4, G4v2, mapa i aktywny szablon pozostały
zachowane. Istniejących źródeł Studio nie zmieniono.

- `Workspace.KuKirin G4 Rig`: osobna zakotwiczona, niekolizyjna kopia do przeglądu.
- `ServerStorage.ScooterModels.scooter_g4`: przygotowany, odkotwiczony kandydat,
  z aktywnymi colliderami. Nie zastępuje `scooter` i nie jest automatycznie spawniony.
- `assets/scooter/kukirin-g4-source.rbxm`: natywny zapis oryginału z UnionOperation.
- `assets/scooter/kukirin-g4-rig.rbxm`: natywny zapis kandydata wraz z połączeniami.
- `assets/scooter/kukirin-g4-manifest.json`: parametry, sumy SHA-256 i wyniki QA.

Źródło ma nadal 1731 części; rig ma 1743 części, 28 attachmentów, siedem zawiasów
i **cztery fizyczne sprężyny**. Osie pochodzą z rzeczywistych śrub wahaczy,
osi kół i SteeringHead. Górne/dolne punkty sprężyn pochodzą z ShockEye.
Wahacze obu stron każdej osi są spawane do wspólnej osi pomocniczej.
Opony, felgi, tarcze i bieżnik tworzą zespoły obrotowe; zaciski i nakrętki osi
pozostają przy zawieszeniu. Kolumna, kokpit i przedni moduł skręcają razem.
Geometria źródłowa jest zachowana, łącznie z segmentami sprężyn i przewodów.
Przewody są przypisane do istniejących zespołów; elastyczne deformowanie
przewodów na całej długości nie zostało dodane.

Skala kopii wynosi `0.6422152444`, wyliczona z wysokości chwytów aktywnego szablonu
nad podestem. Osiągnięto wysokość chwytów 5,674 studa, rozstaw osi 6,023 studa
i promień kontaktowy koła 0,818 studa. Root ma masę 12, kolumna 2, każda opona 2,
każdy wahacz 0,5; zawieszenie uwzględnia referencyjnego kierowcę o masie 40.
Parametry wszystkich czterech sprężyn i limity wahaczy wylicza istniejący
`ScooterSuspension`, z zachowaniem rzeczywistych przełożeń mechanicznych.

`DevScooterG4Build` i `DevScooterG4Config` są jawnym narzędziem authoringu.
`ScooterWorkflow.PreviewG4()` tworzy podgląd; `StageG4()` tworzy osobnego kandydata.
Powtórzenie zachowuje wcześniejsze własne kopie w `ScooterRigDraftBackups`.
Narzędzia nie działają przy starcie serwera i nie podmieniają aktywnego szablonu.
Wykonanie tych komend z modułów gry wymaga wcześniejszej, osobno autoryzowanej
synchronizacji odpowiednich źródeł. W tym zadaniu autorowanie i QA wykonano
przez tymczasowe, nieparentowane moduły; do Studio trafiły wyłącznie modele.

Adaptacja `ScooterRig`, `ScooterCollision` i `ScooterRigGeometry` akceptuje
BasePart, zachowując dotychczasowe nazwy i rygor walidacji połączeń.
`AuthoredSuspensionRig` pozwala kalibrować cztery amortyzatory z właściwą masą
i wyłącza starsze automatyczne przesuwanie przedniego mocowania.
Dotychczasowe warianty MeshPart i dwóch sprężyn pozostają obsługiwane.
Kontroler napędu, autorytet serwera, remotes, ekonomia oraz bieżące źródła
`ScooterConfig`, `ScooterServer` i `ScooterPhysics` w Studio nie zostały nadpisane.

`ScooterCompoundVisuals`, wywoływany przez istniejący `ScooterSpringVisuals`,
obsługuje koła z wielu części, segmentowe zwoje i teleskopowe tłoczyska.
Stosuje istniejący limit odległości, jedną zbiorczą operację BulkMoveTo,
reakcje na zmiany koloru/rozmiaru/przezroczystości i cleanup przy usunięciu
lub streamingu. GUI etykiet kół przełącza między oryginałem a kopią, aby uniknąć
podwójnych napisów. Wiązanie obiektów po replikacji jest scalane do jednego
odroczonego przebiegu zamiast osobnego przebiegu dla każdej części.
Personalizacja obejmuje jawnie otagowane części złożonych grup, zachowując
kolejność odczytu kolorów starszych modeli. Wizualne ulepszenie hamulców
rozpoznaje również otagowane tarcze G4.

Root, DriverSeat i RiderRootAttachment korzystają z istniejącego mechanizmu.
Dłonie mają cele na rzeczywistych gripach. FootRest opisuje powierzchnię stania
i objętość baterii, dzięki czemu DeckCollider chroni również spód baterii.
LeftFootTarget/RightFootTarget są markerami authoringu; istniejący solver
wylicza dokładne pozycje stóp z powierzchni FootRest i wymiarów danej postaci.
Ekran używa istniejącego DashboardGui na płaszczyźnie nad DisplayGlass,
skierowanej ku górze. FrontLight i StopLight wskazują rzeczywiste soczewki;
fabryczne dekoracyjne źródła światła w kopii są wyłączone dla kontroli runtime.

## Weryfikacja przygotowania

- Natywny `tests/scooter_g4.studio.luau`: **12208 asercji PASS** na odłączonych
  modelach. Sprawdza zachowanie każdej części, jednorodną skalę, masy,
  przywracający moment sprężyn na krańcach skoku, collidery, połączenia,
  statyczne zaciski, powtarzalność klonowania, odrzucenie blokujących weldów,
  widoczność GUI, reakcje malowania oraz cleanup, także po streamingu.
- Osobna wygenerowana postać R15, dopasowana wyłącznie w teście do wysokości
  8 studów: cele neutralnej pozy osiągalne z błędem poniżej 0,005 studa.
  Nie zmieniono ustawień ani proporcji postaci graczy.
- Natywny zapis i ponowny odczyt RBXM: PASS, wraz z walidacją odczytanego rigu.
- CLI `--runtime-only`: 230 PASS; `--arcade-only`: 8332 PASS.
- Osobny natywny test malowania: 17 PASS, osiem grup G4 oraz zachowanie
  głównego koloru starego szablonu. Kontrakty UI CLI: 129 PASS.
- Kompilacja Luau, Roblox-aware strict type analysis oraz lokalny Rojo build: PASS.
- Pełny starszy runner nadal zatrzymuje się po części runtime na istniejącym
  brakującym helperze `make` w `scooter_visuals.spec.luau`; nie deklarujemy jego PASS.

Nie uruchamiano Play ani nie synchronizowano zmienionego kodu produkcyjnego
do Studio. Natywne kontrole nie symulują pełnej jazdy i replikacji.
Kolejny etap wymaga selektywnej, jawnie autoryzowanej synchronizacji adapterów
oraz próby jazdy na kandydacie: skręt, wheelie, burnout, krawężniki, lądowania
i obserwacja przez drugiego gracza. Koszt 1731 części oraz 1084 lokalnych kopii
wizualnych przy bliskim kierowcy nadal wymaga profilowania przed wdrożeniem
multiplayer. Podgląd viewportu przez MCP zakończył się timeoutem; nie deklarujemy
wizualnego odbioru końcowej kopii na podstawie screenshotu.
