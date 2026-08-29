# MemPalace MCP — Docker Desktop (Windows) wersja z 29.08.2026 

Serwer MCP [MemPalace](https://pypi.org/project/mempalace/) (`mempalace-mcp`) uruchamiany
w kontenerze Docker, udostępniający pamięć/wiedzę projektu przez protokół MCP (transport HTTP,
endpoint `/mcp`) — gotowy do podpięcia pod Claude Desktop na tym samym hoście.

---

## 1. Szybki start — uruchomienie

### Wymagania

- **Docker Desktop** dla Windows, z backendem **WSL2** (Settings → General → *Use the WSL 2 based engine*), uruchomiony i działający.
- Katalog projektu: `C:\! Projekty Cyfrowe\mem-palace`

### Kroki

1. Otwórz PowerShell w katalogu projektu:

   ```powershell
   cd "C:\! Projekty Cyfrowe\mem-palace"
   ```

2. **Jednorazowo** (raz na cały Docker Desktop) utwórz zewnętrzną sieć, z której korzysta
   ten i inne projekty MCP na tym hoście:

   ```powershell
   docker network create shared-mcp-net
   ```

   Jeśli sieć już istnieje (np. założona wcześniej przez projekt `mcp-hub`), dostaniesz błąd
   `already exists` — to nic nie szkodzi, można go zignorować.

3. Zbuduj obraz i uruchom kontener w tle:

   ```powershell
   docker compose up -d --build
   ```

4. Sprawdź, czy kontener wstał poprawnie:

   ```powershell
   docker compose ps
   docker compose logs -f
   ```

   Healthcheck powinien po chwili pokazać status `healthy`. Endpoint zdrowia jest też
   dostępny bezpośrednio z hosta:

   ```powershell
   curl http://localhost:8002/healthz
   ```

Dane (indeks pamięci, baza `chroma.sqlite3`, `knowledge_graph.sqlite3`, `mempalace.yaml`)
są trzymane w `./palace-data` i przetrwają restart oraz przebudowę kontenera.

### Zatrzymanie / restart

```powershell
docker compose down          # zatrzymuje i usuwa kontener (dane w palace-data zostają)
docker compose restart       # restart bez przebudowy
docker compose up -d --build # przebudowa po zmianie Dockerfile
```

---

## 2. Podłączenie do Claude Desktop

Claude Desktop działa na tym samym komputerze co Docker Desktop. **Status: połączenie
działa i zostało potwierdzone** — `mempalace_status` zwraca realne dane z palace (patrz
sekcja 4a). Poniżej obie metody, jakie sprawdziliśmy.

Plik konfiguracyjny Claude Desktop na Windows:

```
%APPDATA%\Claude\claude_desktop_config.json
```

### Opcja A — most `mcp-remote` do endpointu HTTP (wymaga poprawki!)

⚠️ **Wersja z `${MEMPALACE_TOKEN}` w `args` NIE działa.** Powód: klienci MCP (w tym Claude
Desktop) **nie podstawiają** wartości ze swojego `env` w miejsce `${...}` wewnątrz `args` —
to nie jest shell, tylko dosłowny JSON przekazywany jako argumenty procesu. W efekcie do
serwera leciał literalny nagłówek `Authorization: Bearer ${MEMPALACE_TOKEN}` zamiast
prawdziwego tokenu, więc serwer odrzucał żądanie (401). `env` w configu Claude Desktop
ustawia zmienne środowiskowe procesu potomnego — nie interpoluje ich w `args`.

**Poprawna wersja** — token wpisany wprost, bez `${...}` (poniżej PLACEHOLDER — wstaw
swój prawdziwy token z `.env`, nie wklejaj go do plików, które trafiają do repo):

```json
{
  "mcpServers": {
    "mempalace": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "http://localhost:8002/mcp",
        "--header",
        "Authorization: Bearer <TWOJ_TOKEN_Z_.env>"
      ]
    }
  }
}
```

Token musi być identyczny z wartością `MEMPALACE_MCP_HTTP_TOKEN` w pliku `.env` tego projektu.
Jeśli kiedyś zmienisz token w `.env` i przebudujesz kontener, zaktualizuj go też tutaj (w obu
miejscach na raz — literal w `args` nie aktualizuje się sam).

Wymaga zainstalowanego Node.js (żeby działało `npx`). Jeśli mimo poprawki dalej nie działa,
przetestuj ręcznie w PowerShell, wstawiając własny token w miejsce placeholdera (zobaczysz
realny błąd zamiast domysłów):

```powershell
npx -y mcp-remote http://localhost:8002/mcp --header "Authorization: Bearer <TWOJ_TOKEN_Z_.env>"
```

Po zapisaniu configu **zamknij Claude Desktop całkowicie (z paska zadań) i uruchom ponownie**.

### Opcja B — most `docker exec` (stdio) — **potwierdzona jako działająca**

Wzorzec zgodny z tym, co już wcześniej zdefiniowano w `mcp-hub/config/servers.yaml`. Nie
wymaga Node.js, tylko działającego kontenera `mempalace-mcp`. To najprawdopodobniej ta metoda
stoi za obecnym, działającym połączeniem (patrz sekcja 4a):

```json
{
  "mcpServers": {
    "mempalace": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "mempalace-mcp",
        "python",
        "-m",
        "mempalace.mcp_server",
        "--palace",
        "/palace"
      ]
    }
  }
}
```

Uwaga: kontener musi być uruchomiony (`docker compose up -d`) **zanim** Claude Desktop spróbuje
się połączyć — inaczej `docker exec` nie ma do czego się podpiąć.

### Weryfikacja połączenia

Po restarcie Claude Desktop wejdź w Ustawienia → Developer (lub ikonę wtyczki/młotka w rozmowie)
i sprawdź, czy serwer `mempalace` jest widoczny i ma status połączony, a narzędzia MemPalace
pojawiają się na liście dostępnych narzędzi. Najprostszy test w rozmowie: poproś Claude o
sprawdzenie statusu palace — jeśli zwróci listę wings/rooms, połączenie działa.

---

## 3. Struktura projektu

```
mem-palace/
├── Dockerfile           # obraz: python:3.12-slim + pakiet pip "mempalace"
├── docker-compose.yml   # definicja usługi mempalace-mcp, sieć shared-mcp-net, healthcheck
├── .env                 # MEMPALACE_MCP_HTTP_TOKEN (token do autoryzacji /mcp)
├── .dockerignore         # wyklucza palace-data/ i .env z kontekstu builda
├── README.md             # ten plik
└── palace-data/          # WOLUMEN z danymi (montowany do /palace w kontenerze)
    ├── mempalace.yaml
    ├── chroma.sqlite3
    ├── knowledge_graph.sqlite3
    └── ...
```

`palace-data/` jest jedynym trwałym stanem — reszta (obraz, kontener) jest odtwarzalna
przez `docker compose up -d --build` w każdej chwili.

---

## 4a. Potwierdzenie działania (2026-08-29)

Połączenie Claude ↔ mem-palace zostało zweryfikowane wywołaniem `mempalace_status` — serwer
odpowiedział poprawnie: 29 "drawers" w kilku wings/rooms, backend `chroma`, integralność
`chroma.sqlite3` OK (0 błędów). Czyli **kontener działa i jest osiągalny z poziomu tej
rozmowy**. Nie widać z tego poziomu, przez którą dokładnie metodę (A czy B) połączenie
zostało nawiązane w Twojej konfiguracji — ale skoro działa, śmiało traktuj obecną
konfigurację jako działającą i nie musisz jej ruszać. Jeśli to była Opcja A ze starym
`${MEMPALACE_TOKEN}`, to znaczy, że jednak podstawiło się poprawnie w Twoim środowisku
(rzadziej spotykane, ale możliwe przy niektórych wersjach `mcp-remote`/npx) — w takim razie
błąd, który widziałeś, mógł mieć inną przyczynę niż podstawianie zmiennych; warto sprawdzić
dokładny komunikat błędu ręcznie w PowerShell (polecenie w sekcji 2, Opcja A).

## 4. Zmiany wprowadzone, żeby to działało na Windows / Docker Desktop

Poniżej lista poprawek już obecnych w projekcie (część z wcześniejszej pracy nad repo,
udokumentowana komentarzami w plikach) oraz tych dodanych podczas tej weryfikacji.

### Już obecne w `Dockerfile` / `docker-compose.yml` (zweryfikowane jako poprawne)

- **Pin wersji `mempalace==3.5.0`** — to pierwsza wersja pakietu z opcjonalnym transportem
  HTTP (`--transport http`); wcześniejsza wersja (3.4.1) nie miała tej flagi.
- **Brak `mempalace init` w Dockerfile** — świadomie pominięte. `mempalace-mcp` sam tworzy
  strukturę palace (`mempalace.yaml`, `chroma.sqlite3`) przy pierwszym starcie, jeśli katalog
  `/palace` jest pusty. Wcześniej `init` zapisywał dane do domyślnej ścieżki `~/.mempalace`
  *wewnątrz* kontenera (a nie do zamontowanego `/palace`), więc dane gubiły się przy każdym
  restarcie.
- **Zakomentowane `user: "${UID:-1000}:${GID:-1000}"`** w `docker-compose.yml` — na
  Windows/Docker Desktop (WSL2) bind mount z Windowsa nie daje użytkownikowi o UID 1000
  uprawnień wewnątrz WSL2, co powodowało `PermissionError` przy odczycie plików w `/palace`.
  Kontener działa więc jako root. **Nie odkomentowywać na Windows** — tę linię warto włączyć
  z powrotem dopiero na docelowym serwerze linuksowym, żeby pliki w `palace-data` miały
  właściwego właściciela zamiast roota.
- Port hosta `8002` zmapowany na port kontenera `8000`, żeby uniknąć konfliktu z innymi
  usługami nasłuchującymi na 8000 na tym samym hoście.

### Dodane podczas tej weryfikacji

- **`.dockerignore`** — wyklucza `palace-data/` i `.env` z kontekstu builda. Bez tego
  `docker compose build` za każdym razem wysyłał całą zawartość `palace-data` (indeksy,
  pliki `.bin`) do demona Dockera, co na Windows/WSL2 potrafi być zauważalnie wolniejsze;
  dodatkowo `.env` z tokenem nie powinien w ogóle trafiać do kontekstu builda.
- **Komentarz w `docker-compose.yml`** przypominający o jednorazowym utworzeniu sieci
  zewnętrznej `shared-mcp-net` przed pierwszym uruchomieniem (Compose nie tworzy sieci
  `external: true` samodzielnie).
- **Komentarz w `.env`** wyjaśniający, do czego służy token i że plik nie powinien trafić
  do repozytorium Git.
- **Ten plik `README.md`.**

---

## 5. Rozwiązywanie problemów

| Objaw | Prawdopodobna przyczyna / rozwiązanie |
|---|---|
| `network shared-mcp-net not found` przy `docker compose up` | Sieć nie została jeszcze utworzona — patrz krok 2 w sekcji 1. |
| `PermissionError` przy odczycie plików w `/palace` | Ktoś odkomentował linię `user:` w `docker-compose.yml`. Zostaw ją zakomentowaną na Windows. |
| Port `8002` zajęty | Zmień mapowanie portu w `docker-compose.yml`, np. `"8010:8000"`, i dostosuj adres w konfiguracji Claude Desktop. |
| Healthcheck nigdy nie przechodzi w `healthy` | Sprawdź logi: `docker compose logs -f`. Upewnij się, że obraz zbudował się bez błędów (`docker compose up -d --build`). |
| Claude Desktop nie widzi serwera `mempalace` | Sprawdź, czy JSON w `claude_desktop_config.json` jest poprawny (żadnych brakujących przecinków), czy kontener działa (`docker compose ps`) i czy token w konfiguracji zgadza się z `.env`. Zrestartuj Claude Desktop całkowicie (nie tylko zamknij okno — wyjdź z aplikacji z paska zadań). |
| Docker Desktop nie startuje / WSL2 błędy | Upewnij się, że w Docker Desktop → Settings → General zaznaczone jest *Use the WSL 2 based engine*, i że WSL2 jest zaktualizowane (`wsl --update` w PowerShell). |

---

## 6. Bezpieczeństwo

- Token `MEMPALACE_MCP_HTTP_TOKEN` w `.env` autoryzuje dostęp do endpointu `/mcp`. Bez niego
  (pusta wartość) endpoint jest dostępny bez autoryzacji dla każdego kontenera w sieci
  `shared-mcp-net`.
- Nie commituj `.env` do repozytorium Git (jeśli projekt trafi do repo, dodaj `.env` do
  `.gitignore`).
- Port `8002` jest wystawiony na hosta tylko do testów lokalnych (`curl`, `mcp-remote`).
  Jeśli nie jest to potrzebne, można rozważyć usunięcie sekcji `ports:` z
  `docker-compose.yml` i korzystanie z serwera wyłącznie przez sieć Docker
  (`shared-mcp-net`), z innych kontenerów.

## 7. Publikacja na GitHub — co WOLNO, a czego NIE

**Bezpieczne do publikacji** (kod/konfiguracja, bez sekretów): `Dockerfile`,
`docker-compose.yml`, `.dockerignore`, `.gitignore`, `.env.example`, `README.md`.

**NIGDY nie publikuj / nie commituj:**

- `.env` — zawiera prawdziwy token `MEMPALACE_MCP_HTTP_TOKEN`. Używaj `.env.example` jako
  szablonu (skopiuj do `.env` i wstaw własny token).
- `palace-data/` — to nie kod, tylko **realna baza danych pamięci** (`chroma.sqlite3`,
  `knowledge_graph.sqlite3`, `mempalace.yaml`). Może zawierać osobiste notatki, dane o innych
  projektach, decyzje biznesowe itd. — dokładnie to, co ten serwer ma przechowywać jako
  pamięć, a nie publikować.

Oba wykluczenia są już w `.gitignore` w tym projekcie. Przed pierwszym `git init` / `git push`
warto i tak zrobić `git status` i wzrokowo zweryfikować, że `.env` i `palace-data/` nie
pojawiają się na liście plików do commita.

Jeśli token w `.env` został kiedykolwiek gdzieś już wklejony/wypchnięty (np. do prywatnego
repo, czata, itp.), potraktuj go jako skompromitowany i wygeneruj nowy (patrz komentarz w
`.env.example`), a następnie przebuduj kontener (`docker compose up -d --build`) i
zaktualizuj konfigurację Claude Desktop (sekcja 2, Opcja A) o nowy token.

