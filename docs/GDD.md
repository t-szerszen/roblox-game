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
  - Efekt: Obezwładnia i wywraca zaatakowanego gracza na **5 sekund**, pozwalając na zadawanie mu obrażeń wręcz.

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

- **Zarządzanie:** Gracz może na stałe wykupić możliwość założenia gangu za walutę Coins. Limit wielkości pojedynczego gangu wynosi około **33% maksymalnej pojemności serwera**.
- **Brak systemów zaawansowanych:** Brak rang wewnątrz gangu (tylko lider i członkowie). Brak wspólnego budżetu i wspólnej bazy. Lider posiada uprawnienie do wyrzucania członków.
- **Identyfikacja wizualna:** Nickname gracza (Tag) nad głową postaci przyjmuje oficjalny kolor założonego gangu.
- **Zasady PvP i Ryzyko:**
  - Członkowie gangu mają **całkowicie zablokowaną możliwość używania Trybu Ochronnego (Pasywnego)** z poziomu telefonu, co oznacza, że zawsze ryzykują atak PvP (np. taranowanie czy gaz).
  - Gracze niezrzeszeni mogą swobodnie włączać/wyłączać ochronę PvP w telefonie.
  - **Friendly Fire:** Bezwzględnie wyłączony. Członkowie tego samego gangu nie mogą zadawać sobie obrażeń.

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
- Przełączania Trybu Ochronnego (Pasywnego) dla graczy bez gangu.

**Mechanika Wyścigów 1v1:**

- Wyzwanie inicjuje się poprzez użycie klaksonu/trąbki hulajnogi blisko innego gracza.
- Zaczepiony gracz dostaje powiadomienie na ekranie oraz charakterystyczny dźwięk. Ma **10 sekund na akceptację**.
- W przypadku odrzucenia (timeout) nakładany jest cooldown: rzucający wyzwanie nie może wyzwać tego samego gracza przez kolejne **5 minut**.
- Po akceptacji serwer wyznacza losową metę oddaloną o **20%–35%** całkowitej szerokości mapy.
- Zwycięzca wyścigu otrzymuje **100 Coins** oraz **30 XP**.
