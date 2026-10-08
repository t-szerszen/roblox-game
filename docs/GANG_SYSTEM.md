# Gangi i flagi

System działa lokalnie w sesji serwera. Tworzenie gangu jest bezpłatne, a telefon
obsługuje nazwę, kolor, członków, zaproszenia i prośby o dołączenie. Lider może
wyrzucać członków, zmieniać nazwę i kolor; każdy może opuścić gang. Limit członków
wynosi `max(1, floor(Players.MaxPlayers / 3))`. Zarezerwowane miejsce lidera offline
liczy się do limitu.

Po dobrowolnym wyjściu lidera przywództwo przechodzi na najstarszego obecnego
członka według kolejności dołączenia. Rozłączenie lidera rozpoczyna 30 minut
oczekiwania; jego powrót na ten sam serwer anuluje licznik. Po upływie czasu lider
zostaje usunięty i rolę przejmuje najstarszy obecny członek. Inni rozłączeni
członkowie są usuwani od razu. Gang bez obecnych członków rozpada się natychmiast,
nawet jeśli jego lider ma niewykorzystany czas na powrót. Rozwiązanie neutralizuje
flagi. Restart zeruje wszystkie gangi, zaproszenia, prośby i własność flag.

## Nazwy i kolory

Nazwy mają 3–20 znaków: litery ASCII, cyfry i spacje. Serwer normalizuje spacje,
sprawdza unikalność bez rozróżniania wielkości liter oraz używa Roblox TextService
`FilterStringAsync` i `GetNonChatStringForBroadcastAsync`. Niedostępny filtr lub
ocenzurowana nazwa powodują odrzucenie; surowa nazwa nigdy nie jest publikowana.
Po filtrowaniu serwer ponownie sprawdza uprawnienia, członkostwo i unikalność.

Paleta zachowuje sześć istniejących kolorów RGB i generuje kolejne do pojemności
serwera. Kolor może należeć tylko do jednego gangu naraz; rozwiązanie zwalnia go.
Telefon pokazuje dostępne kolory. Nazwa i kolor są widoczne nad postacią oraz przy
statusie flagi. Przy dużej liczbie gangów odcienie mogą być podobne, dlatego status
zawsze zawiera też nazwę.

## Przejmowanie

Serwer liczy pozycję HumanoidRootPart żywych członków wewnątrz obróconego
CaptureZone, co 0,25 sekundy. Jazda hulajnogą również się liczy; pusta hulajnoga,
niezrzeszony, martwy lub chroniony gracz nie wpływają na strefę. Gaz wywraca i
ogłusza na trzy sekundy bez obrażeń. Żywy ogłuszony gracz pozostający w granicach
strefy nadal uczestniczy. Śmierć korzysta z istniejącego respawnu, a gracz musi
wrócić do strefy.

Przewaga to liczba członków największego gangu minus suma członków pozostałych
gangów. Przy dodatniej przewadze powstaje postęp; w innym przypadku strefa jest
sporna i postęp stopniowo zanika. Przy braku uczestników również zanika.

| Obecność | Przewaga | Czas od zera |
| --- | ---: | ---: |
| 1 | 1 | 45 s |
| 2 | 2 | 22,5 s |
| 2v1 | 1 | 45 s |
| 3v1 | 2 | 22,5 s |
| 2v2 | 0 | Brak przejmowania |
| 4v2v1 | 1 | 45 s |
| 2v1v1 | 0 | Brak przejmowania |

Próg wynosi 45 osobosekund. Remis/pusta strefa odbierają 0,5 osobosekundy na
sekundę. Gdy przewagę uzyska inny gang, najpierw kasuje poprzedni postęp z szybkością
swojej przewagi, a potem buduje własny. Dotychczasowy właściciel zachowuje flagę i
jej dochód do pełnego przejęcia przez przeciwnika; powrót obrońców z przewagą kasuje
postęp rywala. Wyeliminowanie obrońców samo nie neutralizuje flagi.

Ochrona jest dostępna dla wszystkich. Chroniony gracz nie walczy, nie przejmuje i
nie blokuje strefy. Zmiana ochrony ma cooldown 3 sekundy, a jej włączenie jest
zablokowane przez 5 sekund po skutecznym zadaniu/otrzymaniu obrażeń lub gazu.
Dotychczasowe safe zone, ochrona po respawnie i brak friendly fire nadal obowiązują.
Flagi należy umieszczać poza safe zone, aby obrońcy mogli walczyć o strefę.

## Wypłaty

Co 60 sekund każda posiadana flaga dodaje do puli gangu 60 Coins. Pula jest
dzielona równo między członków obecnych w chwili wypłaty, którzy mają poprawnie
załadowany profil i dostępną persystencję. Nagrody trafiają do istniejącego
PlayerDataService; offline nie zarabia, a pominięte interwały nie są nadrabiane.

Dwie flagi i trzech członków dają po 40 Coins na minutę. Jedna flaga i siedmiu
członków dają po 8 Coins, z resztą 4; kolejna pula wynosi 64, więc każdy dostaje
9 Coins, z resztą 1. Reszta pozostaje przy gangu w sesji, także po zmianie liczby
członków. Rozwiązanie gangu lub restart ją usuwa. Podgląd telefonu pokazuje
przybliżony dochód na osobę, bez reszty.

## Konfiguracja i bezpieczeństwo

| Moduł | Ustawienia |
| --- | --- |
| `Shared/Gang/GangConfig` | Limit 1/3; zaproszenia/prośby 30 s; ponowienie dla tej samej pary 15 s; ponowne dołączenie po wyjściu/wyrzuceniu 30 s; nazwa/kolor 60 s; próba tworzenia z filtrem 2 s; maks. 5 zaproszeń odebranych i 3 prośby wysłane; lider offline 1800 s |
| `Shared/Gang/TerritoryConfig` | Próg 45; zanik 0,5/s; próbka 0,25 s; maks. krok po opóźnieniu 1 s; wypłata 60 Coins/flagę co 60 s; domyślna strefa 36×24×36 studów |
| `Shared/Combat/CombatConfig` | Gaz 3 s; zmiana ochrony 3 s; blokada ochrony po walce 5 s |
| `Shared/Phone/PhoneConfig` | Wspólny limit wywołań telefonu 0,25 s |

RemoteFunction telefonu przyjmuje tylko obsługiwane polecenia i ich dozwolone
pola. Identyfikatory zaproszeń/prośb tworzy serwer; odpowiedź zawiera `{id, accept}`
i jest wiązana z właściwym adresatem/gangiem. Serwer sprawdza datę ważności,
uprawnienia, aktualne członkostwo, limit i cooldown. GetState również podlega
limitowi; gracz może mieć tylko jedno aktywne wywołanie. Klient nie określa
właściciela flagi, postępu, czasu ani kwoty wypłaty.

## Przygotowanie flag w Studio

Mapa pozostaje ręcznie edytowana pod `Workspace.Map`. W Studio rozmieszczono trzy
flagi pod `Workspace.Map.Territories` (2026-10-08):

| Model | Lokalizacja | Odległość od spawnu | Pozycja podstawy X / Y / Z |
| --- | --- | ---: | --- |
| `ParkZachodni` | Park z fontanną i rampami | 741 studów | −440 / 1,672 / 45 |
| `SkwerOsiedlowy` | Skwer przy rzeźbie, środek osiedla parkowego | 1075 studów | −514 / 0,320 / −664 |
| `BoiskoKamienice` | Przy bocznej linii boiska między kamienicami | 740 studów | 850 / 5,344 / −460 |

Każdy model zawiera flagę na 14-studowym maszcie, niewidoczny CaptureZone
36×24×36 studów i cztery niekolizyjne linie obrysu. Punkty leżą poza ochroną
spawnu, są od siebie oddalone o co najmniej 700 studów i mają dostępne podłoże.
Flaga i obrys są neutralne do przejęcia; serwer nadaje im kolor właściciela,
aktualizuje po zmianie koloru gangu i neutralizuje po rozwiązaniu. Nie blokują jazdy.

Przesuwaj **cały model**, aby jednocześnie przenieść flagę, obrys i strefę.
Po zmianach zapisz place w Studio i wykonaj `Serialize()`, aktualizując
TerritoryData. Snapshot zapisano z faktycznie umieszczonych stref; nie zapisuje
własności ani nie generuje mapy przy uruchomieniu.

W nowej kopii mapy z istniejącym podłożem możesz jawnie odtworzyć brakujące modele:

```lua
require(game.ServerScriptService.Territory.TerritoryWorkflow).PlaceFlags()
```

Wywołanie działa w Edit mode i zachowuje istniejące modele oraz ich przesunięcia.
Po zmianie nazwy modelu najpierw serializuj snapshot. Wspólny szablon jest w
`ServerStorage.TerritoryFlagTemplate`; źródło assetu generuje
`scripts/generate_territory_flag.py` do `assets/territory/TerritoryFlag.rbxmx`.
Rojo synchronizuje tylko ten szablon, zachowując inne obiekty ServerStorage.

Aby przygotować dodatkowe punkty:

1. W Edit mode wybierz modele flag znajdujące się pod `Workspace.Map`.
2. Uruchom w Command Bar:

   ```lua
   require(game.ServerScriptService.Territory.TerritoryWorkflow).ConfigureSelection()
   ```

3. Narzędzie dodaje niewidoczny, zakotwiczony `CaptureZone` do każdego wybranego
   modelu, z tagiem `GangTerritory`, unikalnym atrybutem `TerritoryId` oraz
   `TerritoryName`. Dostosuj pozycję, orientację, wymiary i nazwę strefy w Studio.
   Model flagi powinien mieć pivot na poziomie gruntu; domyślna strefa rozciąga się
   24 study nad pivotem. Modele tworzące rodziców w ścieżce powinny mieć unikalne
   nazwy w obrębie danego rodzica.
4. Zapisz place, a następnie uruchom:

   ```lua
   require(game.ServerScriptService.Territory.TerritoryWorkflow).Serialize()
   ```

5. Skopiuj wydrukowany moduł do
   `src/ServerScriptService/Territory/TerritoryData.luau`. Ten snapshot wersjonuje
   geometrię/tagi stref niezależnie od assetowego `MapData`. `TerritoryData` nie
   przechowuje własności i nie jest automatycznie odtwarzany.

Jawne odtworzenie stref z tego snapshotu, gdy ich modele/rodzice już istnieją:

```lua
require(game.ServerScriptService.Territory.TerritoryWorkflow).RestoreZones()
```

Narzędzia działają tylko w Edit mode. PlaceFlags tworzy modele flag z szablonu;
ConfigureSelection i RestoreZones konfigurują strefy istniejących modeli. Żadne
z tych narzędzi nie odbudowuje mapy. Przy uruchomieniu gry TerritoryService wykrywa wyłącznie istniejące strefy
pod mapą, publikuje ich status w `ReplicatedStorage.Territories` i dodaje etykietę
światową. Powielone/niepoprawne TerritoryId i niezakotwiczone strefy są odrzucane.
Przy dodawaniu strefy podczas Play najpierw umieść ją pod mapą, potem dodaj tag.

## Weryfikacja

CLI wykonuje rzeczywiste moduły z atrapami usług: 138 sprawdzeń gangów, walki,
terytoriów, wypłat i serwera telefonu. Fixture Studio wykonał 17 sprawdzeń z
natywnymi instancjami: tagi i odtworzenie wyświetlania Humanoida, telefon z paletą,
zaproszeniami/prośbami i ochroną, blokowanie przycisków, cleanup i obrócone granice.
Dotychczasowe zestawy UI (133) i hulajnóg (828) również przechodzą. Rojo build oraz
analiza typów zmienionych modułów przechodzą.

Pełny test kilku klientów, fizycznego upadku po gazie oraz jazdy przez docelowo
rozmieszczone flagi pozostaje do wykonania w Play. W Edit mode dodatkowo wykonano
19 sprawdzeń trzech punktów: unikalne ID, tagi, odległość od spawnu, niekolizyjne
strefy, przesuwanie modelu wraz ze strefą i powtórne wywołanie instalacji bez
przenoszenia/duplikowania istniejących flag. Szczegóły
uruchamiania i scenariusze akceptacyjne: [tests/README.md](../tests/README.md).
