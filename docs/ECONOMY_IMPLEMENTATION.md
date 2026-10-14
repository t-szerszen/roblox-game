# Ekonomia, sklep i dostawy — raport implementacji

Stan: implementacja i testy lokalne. **Bez synchronizacji do Studio, publikacji i zmian na mapie.** Poprzednia nieautoryzowana synchronizacja została wycofana: 30 źródeł przywrócono i porównano z kopią, dodane obiekty usunięto. Kopie znajdują się w `/Users/tobiasz/.codex/backups/studio-before-economy-sync-20261012/`. Po wycofaniu wykonano wyłącznie odczyt struktury folderów budynków w Studio.

## 1. Analiza i zakres

Projekt miał `PlayerDataService` z `PlayerProfiles_v1`, leaderstats, sklep i telefon, tagowane punkty dostaw, gangi/terytoria, rzeczywistą fizykę wheelie i burnout, gaz oraz personalizację hulajnogi. Nie było wspólnego bezpiecznego rozliczania wszystkich nagród ani zakupów z trwałym potwierdzeniem zapisu. Dotychczasowe dostawy rozpoczynały się przy punkcie odbioru, a telefon tylko wyświetlał status.

Wdrożenie rozszerza te systemy. Zgodnie z korektą użytkownika wycofano do wcześniejszej wersji `GarageService` i `GarageClient`, pozostawiono `GarageEnabled=false` oraz usunięto nowe uruchamianie garażu i `GarageRequest` z kontrolera hulajnogi. Nie dodano nowego panelu garażu ani zakupu ulepszeń przez niego. Istniejąca personalizacja `ScooterCustom` i wcześniej napisane ulepszenia części zostały zachowane. Kosmetyczne dodatki wyposaża się w zaakceptowanym sklepie.

## 2. Architektura i bezpieczeństwo

- `EconomyConfig`: wspólne stawki, jednostki, częstotliwość próbkowania i parametry ochrony danych.
- `PlayerDataService`: autorytatywne saldo, trwałe odblokowania, wyposażenie i ułamkowe postępy nagród. API: `AddCoins`, `SpendCoins`, `AddCurrency`, `PurchaseProduct`, `SelectScooter`, `GrantProduct`, `RecordRide`, `RecordTimedReward`.
- `ProfilePersistence`: sesyjny zapis przez `UpdateAsync`, używający istniejącego `PlayerProfiles_v1`; nie powstał drugi DataStore profili.
- `ShopService` / `PremiumService` / `ItemEquipment`: żądania sklepu, weryfikacja Roblox Marketplace i rzeczywiste wyposażenie gazu.
- `ScooterCosmetics`: zapisane efekty i malowanie, bez panelu garażu i własnego systemu tuningu.
- Istniejące `ActivityService`, `TerritoryService` i `TerritoryRewards`: serwerowe rozliczanie rzeczywistej aktywności.

Klient przesyła wyłącznie identyfikator produktu lub dozwoloną akcję. Cena, własność, uprawnienia, bliskość punktu, czas oraz mnożnik są ustalane przez serwer. Transport odrzuca błędne typy i nadmiarowe argumenty; żądania mają ograniczenia częstotliwości oraz blokadę równoczesnego przetwarzania. Coins w leaderstats są prezentacją profilu; bezpośrednie zmiany wartości nie przyznają monet. Zmiany salda trafiają do ograniczonego dziennika z powodem.

## 3. Dostawy z telefonu

1. W aplikacji **Dostawy** gracz naciska **Przyjmij zlecenie**. `PhoneRequest` przekazuje `AcceptDelivery` do istniejącego `ActivityService`. Klient nie wybiera dystansu, sklepu, adresu ani nagrody.
2. Serwer wybiera istniejący sklep i budynek. Etap `Pickup` wymaga podjechania do przypisanego sklepu i użycia jego promptu. Sam prompt bez zlecenia z telefonu nie rozpoczyna dostawy.
3. Odebranie zamówienia przełącza etap na `Dropoff`. Serwer mierzy prawidłowy ruch do celu. Prompt przy innym sklepie/budynku, brak odbioru i zbyt krótka poprawnie przejechana trasa nie rozliczają zlecenia.
4. Dostarczenie zużywa zlecenie przed wypłatą. Nagroda: `round(100 + 150 * clamp(dystans sklepu do budynku / 2000 studów, 0, 1))`. To długość wyznaczonej trasy między punktami; dodatkowe krążenie jej nie zwiększa. Zaakceptowany ruch służy weryfikacji przejazdu, nie zwiększaniu ceny.
5. **Anuluj zlecenie** nie wypłaca monet. Odrodzenie, wykryty teleport i usunięcie punktu anulują zlecenie. Ostatni skok pozycji jest sprawdzany również podczas dostarczenia, zanim nadejdzie kolejny heartbeat.

Aplikacja pokazuje etap, cel, pozostały dystans i ustaloną nagrodę. Cel `Z` pojawia się na istniejącej minimapie, także przy jej krawędzi dla odległego adresu. Aktualizacja dystansu zmienia etykietę lokalnie z atrybutów serwera, bez odpytywania RemoteFunction w pętli.

`DeliveryLocations` zawiera trzy wcześniej rozpoznane wejścia sklepów. `DeliveryStations` podczas uruchomienia gry sprawdza obecność sklepów, podłoże i wyszukuje rzeczywiste budynki w `Workspace.Map.Budynki` oraz `Workspace.Map.Osiedle_Parkowe.Bloki`. Nie wymaga unikalnych nazw modeli. Punkt przekazania powstaje obok istniejącego budynku, po raycaście i sprawdzeniu wolnego miejsca. Maksymalnie 48 adresów; brak dostępnych punktów daje komunikat zamiast fikcyjnego zlecenia.

Wszystkie markery należą do runtime `Workspace.DeliveryStations`, **poza `Workspace.Map`**. Mapa, geometria i nazwy obiektów pozostają nietknięte. Zniszczenie/usunięcie budynku usuwa jego marker. Ręcznie oznaczone tagi `DeliveryPickup` / `DeliveryDestination` mają pierwszeństwo osobno dla każdego rodzaju punktów. Faktyczna dostępność wejść i wygoda podjazdu wymagają późniejszego testu na mapie; nie były testowane po korektach w Studio.

## 4. Jazda, wheelie, burnout i gangi

- **Jazda:** 100 Coins/km, wypłacane co **10 m** (1 Coin na krok, `EconomyConfig.RideCoinStepMeters`). Skala wynika z istniejącego `ScooterConfig.StudsPerKmH`: 1,6 studa/s na km/h, czyli **5760 studów/km** i 57,6 studa na krok 10 m. Nie zakłada się 1 stud = 1 metr. Postęp niepełnego kroku i ułamki Coins są zapisywane. Profile z dawnym postępem niepełnego kilometra przenoszą już naliczone Coins do reszty (`rideRemainder`), która wypłaca się przy następnym kroku. Kolejne wypłaty tego samego typu w ciągu 60 s są scalane w jeden wpis historii transakcji, aby częste małe kwoty nie wypierały reszty historii.
- **Wheelie:** x1.00 → x2.00 liniowo przez **20 sekund** poprawnego wheelie, w krokach **0,01** (wartość zaokrąglana w dół; ta sama wartość jest wyświetlana i wypłacana). Zakończenie, postój lub nieprawidłowa próbka resetuje x1. Kontrola uwzględnia właściciela/kierowcę, kontakt tylnego koła, brak kontaktu przedniego, rzeczywiste pochylenie co najmniej 8° z istniejącej konfiguracji i limit ruchu pionowego. Podstawa fizyki wheelie nie została zastąpiona nową mechaniką. Wypłata jest ważona mnożnikiem poszczególnych fragmentów dystansu.
- **Ochrona dystansu:** próbkowanie co 0,25 s, limit prędkości aktualnego pojazdu, brak kredytu za teleport, duży skok pionowy, lot, długą przerwę w próbkowaniu i lokalne oscylowanie. Wymagane przemieszczenie netto ogranicza sztuczne nabijanie dystansu.
- **Burnout:** 25 Coins/min rzeczywistego poślizgu tylnego koła z kontaktem z podłożem. Sam przycisk nie wystarcza. Ułamki są akumulowane i monety wypłacane w krótszych interwałach. W próbce burnout dystans nie daje jednocześnie zarobku za jazdę. Nagrody za gang lub zakończenie dostawy mogą działać równolegle.
- **Gangi:** 100 Coins/min/flagę **dla każdego obecnego na serwerze członka gangu z dostępnymi danymi**. Dwóch członków i dwie flagi przez minutę daje po 200 Coins każdemu. Pula nie jest dzielona. Rozliczany jest rzeczywisty upływ czasu; zmiana własności, członkostwa i rozpad gangu aktualizują naliczanie istniejącego systemu terytoriów. Ten sam timestamp nie płaci drugi raz.

HUD Coins znajduje się w lewym dolnym rogu; miejsce grafiki jest puste.

**Panel WHEELIE** (`RideMultiplierClient`, wygląd w `Shared/UI/WheelieHUDConfig`) pojawia się u góry ekranu tylko podczas wheelie: tytuł z zielonymi liniami, czas na kole (`4.3s`), dystans na kole (`m`, powyżej 1 km `km`), mnożnik `x1.21 Pieniędzy`, rekord gracza `Najlepszy` (`LongestWheelie`) i pasek postępu do x2 (złoty przy x2). Po zakończeniu wheelie panel trzyma końcowy wynik przez 1 s i znika. Dane mierzy serwer (`RewardMath`) i publikuje jako atrybuty gracza `RideWheelieActive`, `RideWheelieSeconds`, `RideWheelieMeters` oraz `RideRewardMultiplier` co 0,25 s; stan wheelie jest publikowany przed resetem mnożnika, więc panel pokazuje końcowy mnożnik. Klient jedynie płynnie dolicza czas między próbkami (maks. 0,3 s ponad wartość serwera), a połączenie `RenderStepped` istnieje tylko podczas aktywnego wheelie. Rekord liczony jest z atrybutu `WheelieActive` pojazdu, więc może minimalnie różnić się od czasu w panelu (przerwanie przez lot resetuje mnożnik). Układ mobilny wymaga ręcznej kontroli na urządzeniu.

## 5. Zapis i współbieżność

Profil zachowuje dotychczasowe własności, statystyki, ulepszenia części i trzy zapisane projekty malowania. Nieznane istniejące pola DataStore są zachowywane przy zapisie. Rozpoznane stare odblokowania modeli są migrowane; wcześniej kupione G3 Pro/G4 pozostają dostępne, choć nie są ponownie sprzedawane.

`UpdateAsync` sprawdza token sesji; obca aktywna sesja blokuje przejęcie, a obcy token blokuje nadpisanie. Lease trwa 180 s i jest odnawiany zapisami. Błędy mają trzy próby z odstępami. Nieudany odczyt oznacza dane tylko do prezentacji i blokuje zarabianie/zakupy — domyślny profil nie nadpisuje rzeczywistego zapisu.

Zakup monetowy zapisuje kopię profilu z pobraniem Coins i odblokowaniem **przed** zatwierdzeniem operacji klientowi. Błąd zapisu nie pobiera monet. Blokada transakcji i kolejka równoczesnych nagród zabezpieczają saldo podczas yieldów DataStore. Przy utracie sesji gospodarka gracza jest blokowana.

Autosave co 60 s, zapis przy wyjściu i zamykaniu serwera. Nieudany końcowy zapis ma dodatkowe próby z zachowaniem snapshotu. To obsługa przejściowych awarii, nie gwarancja zachowania niezapisanych danych przy długotrwałej awarii Roblox lub nagłym przerwaniu serwera. Poprawnie zapisany postęp jest odtwarzany.

## 6. Status katalogu i Marketplace

| Produkt | Cena | Stan lokalnej integracji |
|---|---:|---|
| KuKirin 1 | darmowy | bazowa konfiguracja `KuKirin G2 Pro` |
| KuKirin 2 | 10 000 Coins | zakup i trwała własność `KuKirin G2 Max` |
| KuKirin 3 | 40 000 Coins | zakup i trwała własność `KuKirin G2 Master` |
| Suron | 800 Robux | zablokowany: brak modelu/tuningu i Game Pass ID |
| Gaz | 500 Robux | istniejący model `gaz`, wyposażenie i serwerowa walka; brak Game Pass ID |
| RGB pod hulajnogą | 100 Robux | podświetlenie i włączanie w sklepie; brak Game Pass ID |
| Kolorowy dym | 100 Robux | istniejący emitter burnout i kolor; brak Game Pass ID |
| Tęczowe malowanie | 100 Robux | wariant istniejących grup malowania; brak Game Pass ID |
| Radio | 500 Robux / 250 000 Coins | trwałe odblokowanie za Coins działa w logice; Robux wymaga ID; odtwarzanie audio niezaimplementowane i opis jasno o tym informuje |

KuKiriny korzystają z rzeczywistego istniejącego `ServerStorage.ScooterModels.scooter`, z różnymi konfiguracjami projektu. Nie dodano referencji do nieistniejących trzech osobnych modeli. Sklep sprawdza dostępność template przed sprzedażą/spawnem.

Wszystkie produkty premium są trwałymi odblokowaniami **Game Pass**. Integracja weryfikuje własność po stronie serwera przez Marketplace, potwierdza realną cenę i dostępność sprzedaży przed promptem, obsługuje błędy i anulowanie, a ponowne potwierdzenie nie przyznaje ponownie przedmiotu. Informacja klienta nie przyznaje własności. Zapisane, wcześniej zweryfikowane odblokowanie nie znika wskutek późniejszej awarii Marketplace.

Dla radia jedna własność obsługuje obie waluty. Trwający prompt Robux blokuje płatność Coins; przed alternatywnym zakupem serwer weryfikuje własność Game Pass. Odblokowane radio nie jest ponownie sprzedawane żadną walutą.

**Do uzupełnienia w `ShopConfig.RobuxProducts[].productId`:**

| Klucz | Wymagany Game Pass ID | Cena w Dashboard |
|---|---|---:|
| `suron` | brak, obecnie 0 | 800 Robux |
| `pepper_spray` | brak, obecnie 0 | 500 Robux |
| `scooter_neons` | brak, obecnie 0 | 100 Robux |
| `burnout_smoke` | brak, obecnie 0 | 100 Robux |
| `rainbow_paint` | brak, obecnie 0 | 100 Robux |
| `radio` | brak, obecnie 0 | 500 Robux |

**Developer Product IDs:** żadne; ten katalog nie zawiera produktów zużywalnych, więc nie wprowadzono konkurencyjnego `ProcessReceipt`.

Przed publikacją trzeba utworzyć/podłączyć te Game Passy i ustawić zgodne ceny oraz dostępność w Creator Dashboard. Błędna cena blokuje prompt; ID 0 nie otwiera fikcyjnego zakupu. Do Surona potrzebny jest rzeczywisty model i jego konfiguracja. Radio wymaga osobnego modułu odtwarzania. Zakupy Robux nie są obecnie w pełni gotowe do publikacji.

Mechanizm odpowiada opisowi [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService), a zapis korzysta z [UpdateAsync](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore).

## 7. Faktycznie wykonane testy po korektach

Testy CLI używają faktycznych modułów produkcyjnych i kontrolowanych atrap usług Roblox. Nie są testem prawdziwych płatności ani zapisu kont na Roblox.

| Sprawdzenie | Wynik |
|---|---:|
| `run_economy_tests.py` | 110 asercji PASS |
| `run_gang_tests.py` | 143 asercje PASS |
| `run_scooter_tests.py --runtime-only` | 230 asercji PASS |
| `run_ui_tests.py` | 129 asercji PASS |
| `run_police_tests.py` | 809 asercji PASS |
| `run_traffic_tests.py` | 2655 asercji PASS |
| `run_police_traffic_tests.py` | 75 asercji PASS |
| Kompilacja wszystkich 177 źródeł Luau | PASS |
| `rojo build default.project.json` | PASS, lokalny `/tmp/roblox-game-economy-local.rbxlx` |
| `git diff --check` | PASS |

Ekonomia obejmuje m.in. ceny, brak nadmiernych wydatków, duplikaty, błąd i retry zapisu, kolejkę równoczesnej nagrody, odtworzenie profilu i niepełnego kilometra, sesje różnych serwerów, zachowanie nieznanych pól, idempotencję premium/radio, serwerowy przebieg dostawy, anulowanie, brak odbioru, teleport na heartbeat i tuż przed promptem, wyposażenie efektów bez garażu, odrębność konfiguracji pojazdów, przywrócenie zapisanego malowania po wyłączeniu tęczy oraz sprzątanie zleceń. Testy telefonu obejmują odrzucenie sfałszowanego payloadu dostawy i przekazanie prawidłowych akcji.

Przed wycofaniem synchronizacji poprzednia wersja przeszła 20 natywnych asercji w Studio. **Nie zaliczamy ich jako testu finalnej wersji po korektach.** Nie uruchamiano ponownie Play ani fixture Studio po przywróceniu kodu. Pełny pakiet dodatkowych wizualnych testów hulajnogi nie został zaliczony; wcześniejsza próba zatrzymała się na brakującym helperze `make` w istniejącym fixture wizualnym. Zaliczony jest wskazany powyżej zakres `--runtime-only`.

## 8. Testy wymagające późniejszego ręcznego wykonania

Po osobnej zgodzie na wdrożenie do kopii testowej projektu:

- Dostawy od aplikacji do sklepu i budynku: czy punkty generują się na dostępnym podłożu, wygoda podjazdu, minimapa, błędny sklep/adres, odrodzenie, anulowanie, streaming, usunięcie budynku.
- Realna jazda na każdym modelu, wypłata co 10 m, 1 i 2 km, wheelie x1.00→x2.00 przez 20 s i panel WHEELIE (pojawienie, czas, dystans, ukrycie 1 s po końcu), burnout oraz brak wypłat podczas postoju/teleportacji.
- Multiplayer: zmiany właściciela flag, wejście/wyjście członków, rozpad gangu, równoczesna wypłata i zakup.
- DataStore w osobnym środowisku testowym: rejoin, rozłączenie w trakcie zakupu, zamknięcie serwera, awarie i utrata lease. W poprzednim Play API DataStore w Studio było wyłączone; system poprawnie blokował gospodarkę, więc prawdziwego zapisu kont nie przetestowano.
- Po skonfigurowaniu Game Pass IDs: prawdziwe prompty, ceny, anulowanie, błąd, własność po rejoin, powtórne potwierdzenie oraz obie waluty radia.
- Gaz: wyposażanie/wyłączanie, rzeczywista animacja i trafienie, wspólny cooldown obu dotychczasowych wejść walki.
- Desktop, telefon/tablet i gamepad: układ HUD, mnożnik, telefon i sklep; brak kolizji przycisków i wycieków po ponownym otwieraniu.

## 9. Pliki tego zadania

Nowe:

- `src/ReplicatedStorage/Shared/Activity/EconomyConfig.luau`
- `src/ReplicatedStorage/Shared/Activity/DeliveryLocations.luau`
- `src/ReplicatedStorage/Shared/UI/CoinsHUDConfig.luau`
- `src/ServerScriptService/Activity/ProfilePersistence.luau`
- `src/ServerScriptService/Activity/RewardMath.luau`
- `src/ServerScriptService/Activity/DeliveryStations.server.luau`
- `src/ServerScriptService/Shop/PremiumService.luau`
- `src/ServerScriptService/Shop/ShopService.luau`
- `src/ServerScriptService/Shop/ItemEquipment.luau`
- `src/ServerScriptService/Scooter/ScooterCosmetics.luau`
- `src/StarterGui/CoinsHUD/init.meta.json` i `CoinsHUDClient.client.luau`
- `src/StarterGui/RideMultiplier/init.meta.json` i `RideMultiplierClient.client.luau` (panel WHEELIE)
- `src/ReplicatedStorage/Shared/UI/WheelieHUDConfig.luau`
- `assets/items/gaz.rbxm`
- `tests/run_economy_tests.py`, `tests/economy.spec.luau`, `tests/economy.studio.luau`
- `docs/COINS_HUD.md`, `docs/ECONOMY_IMPLEMENTATION.md`

Zmodyfikowane/integracja:

- `AGENTS.md`, `default.project.json`, `docs/ROJO_STUDIO_SYNC.md`, `tests/README.md`
- `src/ReplicatedStorage/Shared/Activity/ActivityConfig.luau`
- `src/ReplicatedStorage/Shared/Gang/TerritoryConfig.luau`
- `src/ReplicatedStorage/Shared/Shop/ShopConfig.luau`
- `src/ServerScriptService/Activity/PlayerDataService.luau`, `ActivityService.luau`, `ActivityInit.server.luau`
- `src/ServerScriptService/Territory/TerritoryRewards.luau`, `TerritoryService.luau`
- `src/ServerScriptService/Shop/ShopServer.server.luau`
- `src/ServerScriptService/Scooter/ScooterServer.luau`, `ScooterEffects.luau`
- `src/ServerScriptService/PepperSprayService.server.luau`, `Combat/CombatService.luau`
- `src/ServerScriptService/Phone/PhoneServer.server.luau`, `RacingServer.server.luau`
- `src/ReplicatedStorage/Shared/Phone/PhoneTypes.luau`
- `src/StarterGui/Phone/PhoneClient.client.luau`, `PhoneAppsView.luau`
- `src/StarterGui/Shop/ShopClient.client.luau`, `ShopView.luau`
- `src/StarterPlayer/StarterPlayerScripts/Minimap.client.luau`, `ScooterClient.client.luau`
- `tests/gang.spec.luau`, `run_gang_tests.py`, `scooter.spec.luau`, `run_scooter_tests.py`, `ui.spec.luau`, `shop_ui.studio.luau`, `support/roblox_mock.luau`

Kod personalizacji i części z istniejącej wersji Studio został wcześniej zachowany w lokalnych źródłach: `Shared/ScooterCustomConfig`, `Shared/ScooterCustomUI`, `Shared/Scooter/ScooterPhysics`, `Shared/ScooterConfig`, `ServerScriptService/ScooterCustomService.server`, `StarterPlayerScripts/ScooterCustom.client`, `Scooter/ScooterInventory`, `ScooterUpgradeService`, `ScooterUpgradeVisuals`. Zmiany zadań policji/ruchu i inne wcześniejsze lokalne zmiany pozostają w drzewie roboczym; nie należą do powyższego wdrożenia ekonomii i nie zostały wycofane.
