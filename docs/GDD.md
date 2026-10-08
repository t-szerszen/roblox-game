# Game Design Document (GDD) - Wiralowa Gra Roblox (Warszawa)

## 1. Wytyczne Architektoniczne i Reguły dla Agentów AI

Ten dokument definiuje logikę i mechaniki gry. Agenty AI modyfikujące kod muszą bezwzględnie przestrzegać poniższych zasad strukturalnych:

- **Autorytet Serwera (Server Authority):** Serwer jest absolutnym autorytetem w grze[cite: 4]. Klientowi (graczowi) nigdy nie wolno ufać w kwestiach waluty, zakupów, ekwipunku, zadawania obrażeń, nagród, progresji ani egzekwowania czasów odnowienia (cooldownów)[cite: 4]. Wszelkie dane z RemoteEvents muszą być ściśle walidowane na serwerze[cite: 4].
- **Potok Zasobów (Assets):** Wszystkie modele 3D muszą być generowane, przetwarzane i eksportowane wyłącznie w formacie `.fbx`[cite: 2].
- **Budowa Mapy:** Mapa produkcyjna jest budowana ręcznie w Roblox Studio wewnątrz `Workspace.Map`. Można dzielić ją na logiczne podfoldery, np. `Roads`, `Trees` i `Buildings`. Automatyczne generowanie mapy przy uruchomieniu serwera jest wyłączone. Zachowujemy `MapBuilder`, `AssetRegistry`, `MapData`, `DevMapTool` i `MapWorkflow` jako narzędzia deweloperskie oraz awaryjne. Co pewien czas ręcznie zbudowana mapa jest serializowana ze Studio do `src/ServerScriptService/Map/MapData.luau` i zapisywana w Git jako wersjonowany snapshot układu mapy. Na etapie MVP nie tworzymy niestandardowego pluginu do edycji map[cite: 2].
- **Wydajność i Pamięć:** Zawsze należy czyścić połączenia eventów (np. używając Maid, Janitor lub explicit disconnect) po zniszczeniu instancji, aby zapobiegać wyciekom pamięci[cite: 4].
- **Zarządzanie Kodem:** Głównym i ostatecznym źródłem prawdy dla kodu jest repozytorium Git[cite: 4]. Kod jest synchronizowany do Roblox Studio za pomocą narzędzia Rojo, a narzędziami zarządza Rokit[cite: 4, 5].

---

## 2. Świat Gry i Mapa

- **Wymiary i Siatka:** Mapa podzielona jest na 9 dystryktów w formacie siatki 3x3.
- **Skala Dystryktów:** Pojedynczy dystrykt ma stałe wymiary **500x500 studów**. Całkowity rozmiar siatki mapy wynosi **1500x1500 studów**.
- **Centrum Mapy (Środek Siatki):** Inspirowane centrum Warszawy z Pałacem Kultury (odwzorowanie w proporcjach bliskich 1:1). Większość budynków na mapie to zamknięte makiety (optymalizacja). Otaczające dystrykty są ręcznie komponowane w Roblox Studio z zaimportowanych modeli, w tym zasobów `.fbx`.
- **SafeZone (Spawn):** Zlokalizowany pod Pałacem Kultury. Obejmuje strefę o promieniu ok. **100 studów**. W tej strefie zablokowane są obrażenia (PvP) oraz pościgi policji.
- **Cykl Dnia i Nocy:** Gra posiada dynamiczny czas. W nocy serwer spawnuje o **30% mniej** patroli policyjnych (NPC).
- **Rogatki (Toll Gates - Misja Poboczna):** Interaktywne szlabany/przejazdy kolejowe, pojawiające się losowo kilka razy dziennie w różnych częściach mapy. Ich zniszczenie (taranowaniem) to misja – nie niszczy to mapy permanentnie, ale natychmiast nadaje graczowi **1 gwiazdkę poszukiwań**.

---

## 3. Moduł Walki, PvP i Obrażeń

Moduł ten wymaga ścisłej walidacji serwerowej każdego uderzenia[cite: 4]. Walka jest zręcznościowa i zbalansowana, aby nie faworyzować jednej metody (meta).

- **HP Gracza:** Każdy gracz posiada bazowo **100 HP**.
- **Kary za śmierć:** Po utracie całego HP gracz zostaje przeteleportowany na Spawn. **Nie traci pieniędzy ani przedmiotów z ekwipunku** (np. gazu czy radia). Po respawnie otrzymuje **3 sekundy nieśmiertelności** chroniące przed spawn-campingiem.
- **Walka Wręcz:**
  - Obrażenia: **15 HP** (pokonanie gracza wymaga 7 ciosów).
  - Cooldown serwerowy: minimum **0.8 sekundy** między ciosami.
- **Taranowanie Hulajnogą:**
  - Obrażenia: **25 HP** dla potrąconego.
  - Efekt uboczny: Atak jest celowo osłabiony karą ruchu – powoduje wywrócenie (stun) obu graczy (atakującego i ofiary) na **2 sekundy**.
- **Gaz Pieprzowy (Premium):**
  - Obrażenia: **0 HP**.
  - Efekt: Obezwładnia i wywraca zaatakowanego gracza na **3 sekundy**, pozwalając na zadawanie mu obrażeń wręcz.

---

## 4. System Pracy, Aktywności i Rankingi

Główna pętla PvE pozwalająca graczom zarabiać walutę (Coins) oraz Doświadczenie (XP). Kradzież paczek podczas dostawy przez innych graczy jest **zablokowana**. Śmierć podczas dostawy nie anuluje zlecenia.

- **Rozpoczęcie Pracy:** Misje dostawcze nie pojawiają się znikąd w telefonie. Gracz musi fizycznie podjechać do jednego z ustalonych na mapie punktów odbioru (najbliższego dla niego).
- **Ekonomia Dostaw:**
  - Serwer losuje docelowy budynek na mapie.
  - Baza (Gwarantowane): **100 Coins + 50 XP**.
  - Premia Dystansowa: **+15 Coins** za każde przebyte 100 studów odległości w linii prostej.
- **Misje Dzienne (Aplikacja w telefonie):** Dodatkowe nagrody za wykonanie zadań typu: "Przejedź X dystansu", "Dostarcz X paczek", "Ucieknij policji", "Wygraj wyścig 1v1", "Przejedź X km w nocy".
- **Daily Login:** System tygodniowy z narastającymi nagrodami za codzienne logowanie.
- **Globalne Tablice Wyników (Leaderboards na Spawnie):** Najwięcej wygranych wyścigów 1v1, najdłuższy czas palenia gumy (burnout), najdłuższa jazda na kole (wheelie), najwięcej dostarczonych paczek.

---

## 5. Ekonomia Sklepu, Hulajnogi i Ulepszenia (Garaż)

Wszelkie transakcje potrącające walutę (Coins) muszą być wykonywane i walidowane na serwerze[cite: 4]. Zręcznościowy model jazdy: brak fizycznych uszkodzeń sprzętu (brak mechaniki napraw).

- **Wsiadanie:** Gracz wsiada na własną hulajnogę wyłącznie przez interakcję `E`; dotknięcie siedzenia nie może automatycznie posadzić postaci.
- **Skręcanie:** Zmiana kierunku jest możliwa dopiero po rozpoczęciu jazdy; hulajnoga nie obraca się wokół własnej osi na postoju.
- **Wheelie:** Naciśnięcie `Shift` lub `C` jednorazowo rozpoczyna wheelie podczas jazdy do przodu. Po uruchomieniu gaz `W` podnosi przód i pomaga utrzymać prędkość, natomiast hamulec `S` szybko go opuszcza. Brak obu wejść utrzymuje kąt tylko przy wystarczającym pędzie; wraz ze spadkiem prędkości przód coraz szybciej opada, a zatrzymanie natychmiast kończy wheelie. Poza aktywnym wheelie gaz i hamulec nie przechylają sztucznie podwozia. Wheelie nie może rozpocząć się podczas cofania ani w powietrzu. Przekroczenie maksymalnego kąta wyrzuca kierowcę. Skok hulajnogą jest wyłączony; `Space` nie wykonuje akcji podczas jazdy, a `E` pozwala zsiąść.
- **Nierówności i cofanie:** Przytrzymanie `S` po zatrzymaniu uruchamia responsywne cofanie. Kierunkowa asysta przedniego lub tylnego koła pomaga przejechać z małej prędkości przez pasy, łączenia drogi i krawężniki do skonfigurowanej wysokości, bez globalnego podnoszenia podwozia.
- **Tryby jazdy:** `P` podczas jazdy przełącza ECO / SPORT. ECO ogranicza napęd do 25 km/h; SPORT zachowuje pełną prędkość danego tuningu. Przyspieszenie pozostaje bez zmian. Można przełączać podczas ruchu; istniejący kontroler sił stopniowo sprowadza prędkość do limitu. Nowa hulajnoga startuje w SPORT i pamięta wybór do jej usunięcia, także po zsiadaniu. Wybór oraz limit zatwierdza serwer; po wejściu pojawia się podpowiedź o `P`.
- **Licznik:** Wyśrodkowana prędkość w km/h, zapalający się na czerwono napis BRAKE oraz nazwa ECO / SPORT. Uproszczona bateria zawsze pokazuje 67% i cztery z sześciu kresek; energia nie zużywa się i nie ogranicza jazdy.

### Cennik i Parametry Hulajnóg (Cel: 200 dostaw do End-game)

| Model                 | Prędkość Bazowa | Cena (Coins)            |
| :-------------------- | :-------------- | :---------------------- |
| **KuKirin G2 Pro**    | 55 km/h         | **0** (Pojazd Startowy) |
| **KuKirin G2 Max**    | 65 km/h         | **1 000 Coins**         |
| **KuKirin G2 Master** | 72 km/h         | **4 500 Coins**         |
| **KuKirin G3 Pro**    | 80 km/h         | **12 000 Coins**        |
| **KuKirin G4**        | 90 km/h         | **26 000 Coins**        |

### Koszty Ulepszeń Szybkości (Perki w Garażu)

Każdy model posiada 3 stopnie ulepszeń. Każdy stopień dodaje **+1.5 km/h** do prędkości maksymalnej (oraz proporcjonalnie wpływa na przyspieszenie widoczne wizualnie).

| Model                 | Wzmocnienie I | Wzmocnienie II | Wzmocnienie III |
| :-------------------- | :------------ | :------------- | :-------------- |
| **KuKirin G2 Pro**    | 300 Coins     | 600 Coins      | 1 200 Coins     |
| **KuKirin G2 Max**    | 600 Coins     | 1 200 Coins    | 2 400 Coins     |
| **KuKirin G2 Master** | 1 500 Coins   | 3 000 Coins    | 6 000 Coins     |
| **KuKirin G3 Pro**    | 4 000 Coins   | 8 000 Coins    | 14 000 Coins    |
| **KuKirin G4**        | 8 000 Coins   | 16 000 Coins   | 24 000 Coins    |

### Sklep Premium (Waluta: Robux)

Walidacja musi odbywać się przez natywne API (Developer Products / Gamepasses)[cite: 4]. Efekty wizualne ulepszeń premium muszą być replikowane przez serwer (widoczne dla wszystkich graczy).

- **Gaz Pieprzowy:** 250 Robux (Odblokowany na stałe w ekwipunku).
- **Radio:** 500 Robux (Dodaje przycisk na ekranie głównym do odtwarzania muzyki).
- **Kolorowy Dym (Burnout):** 100 Robux (Zakup/Wybór RGB w garażu).
- **Neony pod Hulajnogą:** 100 Robux (Zakup/Wybór RGB w garażu).
- Inne pojazdy premium (np. Suron, The Turbo): 500 Robux.
- Mnożnik X2 Coins: 300 Robux.

---

## 6. Gangi (System Frakcji)

- **Tworzenie i trwałość:** Każdy gracz może bezpłatnie założyć gang. Gangi i własność flag istnieją tylko w bieżącej sesji jednego serwera. Limit członków to `max(1, floor(Players.MaxPlayers / 3))`, np. 30 → 10, 27 → 9, 21 → 7.
- **Telefon:** Tworzenie, zaproszenia, prośby o dołączenie, akceptacja/odrzucenie, lista członków, wyrzucanie przez lidera, opuszczanie, zmiana nazwy i koloru oraz podgląd flag. Zaproszenia i prośby wygasają po 30 sekundach.
- **Przywództwo:** Po świadomym opuszczeniu lidera rolę przejmuje najstarszy obecny członek według kolejności dołączenia. Rozłączony lider zachowuje miejsce przez 30 minut; powrót anuluje licznik. Po upływie tego czasu zostaje usunięty, a rolę przejmuje najstarszy obecny członek. Pozostali rozłączeni członkowie są usuwani od razu. Gang bez obecnych członków zostaje rozwiązany, a jego flagi stają się niczyje.
- **Identyfikacja:** Unikalna nazwa sprawdzana i filtrowana przez serwer, kolor z palety RGB zarezerwowany dla jednego gangu na serwerze oraz nazwa gangu i nick nad głową postaci. Paleta rozszerza się z pojemnością serwera.
- **Ochrona i PvP:** Każdy może korzystać z ochrony w telefonie. Chroniony gracz nie walczy i nie bierze udziału w przejmowaniu ani blokowaniu flag. Zmiana ochrony ma cooldown 3 sekundy; włączenie wymaga 5 sekund od ostatniej skutecznej interakcji bojowej. Friendly fire jest wyłączony.
- **Przejmowanie:** Żywi, niechronieni członkowie w strefie liczą się także podczas jazdy i 3-sekundowego ogłuszenia gazem. Śmierć usuwa ich z liczenia do powrotu po zwykłym respawnie. Samotny gracz przejmuje flagę w 45 sekund. Szybkość wynika z przewagi nad sumą przeciwników: 2v1 → 45 sekund, 3v1 → 22,5 sekundy, 4v2v1 → 45 sekund. Remis lub brak uczestników stopniowo zmniejsza postęp o 0,5 osobosekundy na sekundę. Nowy przejmujący musi najpierw wyzerować postęp poprzednika. Dotychczasowy właściciel zachowuje flagę do pełnego przejęcia; eliminacja obrońców sama nie neutralizuje flagi.
- **Ekonomia:** Co 60 sekund gang otrzymuje pulę 60 Coins za każdą posiadaną flagę, dzieloną po równo między obecnych członków z poprawnie załadowanym profilem. Reszta z dzielenia przechodzi na następny okres. Offline nie zarabia; restart zeruje własność flag i reszty. Brak wspólnej bazy, budżetu do wydawania i dodatkowych rang.

Konfiguracja, architektura i ręczne przygotowanie flag: [GANG_SYSTEM.md](GANG_SYSTEM.md).

---

## 7. Prawo i Porządek (Policja NPC)

Policja jest obsługiwana w pełni przez sztuczną inteligencję (NPC). Brak podziału na klasy jednostek. Należy dbać o optymalizację zdarzeń logicznych jednostek, unikając sprawdzania wszystkich graczy co klatkę (Performance rules)[cite: 4].

- **Wyzwalacze Pościgu:**
  1. Jazda z prędkością powyżej **20 km/h**.
  2. Skoki (robienie ewolucji/skoków na hulajnodze blisko policji).
  3. Rozwalenie rogatki/szlabanu.
  4. Zaatakowanie innego gracza (PvP).
  5. Misje specjalne.
- **Logika Pościgu (Wydajność):** System pościgu uaktywnia się **tylko u lokalnych jednostek** w promieniu ok. 100 studów od popełnienia wykroczenia. Inne patrole ignorują gracza, dopóki ten nie wjedzie w ich promień.
- **Zatrzymanie (Areszt):** Gdy policjant dogoni gracza, następuje odliczanie **10 sekund**.
- **Kary za mandat:** Po odliczeniu 10 sekund gracz otrzymuje mandat karny w wysokości **50 Coins**. Jeśli gracz ma 0 Coins (lub brakuje mu środków), nic się nie dzieje – po prostu traci czas spędzony w areszcie, po czym jest wolny (brak ujemnego salda).

---

## 8. Telefon (Główny Interfejs i Wyścigi 1v1)

Telefon to główne menu interakcji, pozbawione jednak czatu, wewnętrznej mapy czy własnych ulepszeń. Służy do:

- Przywoływania (spawnowania) wykupionej hulajnogi.
- Aplikacji Dostawczej (śledzenie misji).
- Aplikacji Gangu (zarządzanie).
- Śledzenia Misji Dziennych.
- Przełączania Trybu Ochronnego (Pasywnego) dla wszystkich graczy.

**Mechanika Wyścigów 1v1:**

- Wyzwanie inicjuje się poprzez użycie klaksonu/trąbki hulajnogi blisko innego gracza.
- Zaczepiony gracz dostaje powiadomienie na ekranie oraz charakterystyczny dźwięk. Ma **10 sekund na akceptację**.
- W przypadku odrzucenia (timeout) nakładany jest cooldown: rzucający wyzwanie nie może wyzwać tego samego gracza przez kolejne **5 minut**.
- Po akceptacji serwer wyznacza losową metę oddaloną o **20%–35%** całkowitej szerokości mapy.
- Zwycięzca wyścigu otrzymuje **100 Coins** oraz **30 XP**.
