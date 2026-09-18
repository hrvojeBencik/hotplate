# FlutterRunner — dizajn

Datum: 2026-09-18

## Cilj

Mala macOS aplikacija (SwiftUI, bez spoljnih zavisnosti) koja pokreće Flutter
projekte i drži hot reload živim, tako da korisnik može da koristi bilo koji
editor (Zed, Neovim, ...) umesto VSCode-a. Aplikacija zamenjuje samo onaj deo
VSCode-a koji pokreće `flutter run` i šalje hot reload na snimanje fajla.

## Van opsega

- Debugger, breakpoint-i, DevTools integracija.
- Više istovremeno pokrenutih projekata.
- Mac App Store distribucija (nema sandbox-a, vidi ispod).

## Odluke

- **Protokol:** `flutter run --machine`. Flutter tada radi kao daemon i priča
  JSON preko stdin/stdout. Svaka linija je JSON niz sa jednim objektom:
  `[{"event":"app.started","params":{...}}]`. Komande se šalju isto tako:
  `[{"id":1,"method":"app.restart","params":{"appId":"...","fullRestart":false}}]`.
  Odgovor stiže sa istim `id` i poljem `result` ili `error`. Linije koje nisu
  validan JSON se tretiraju kao običan tekst za log.
- **Bez App Sandbox-a.** Podproces nasleđuje sandbox, a `flutter` mora da piše
  u `~/.pub-cache`, pokreće Xcode alate i simulatore. Zato je sandbox isključen,
  a putanje projekata se čuvaju kao obični stringovi u `UserDefaults`.
- **Build sistem:** Swift Package (`Package.swift`) sa executable target-om.
  Skripta `scripts/build_app.sh` pravi `FlutterRunner.app` bundle, upisuje
  `Info.plist`, ad-hoc potpisuje i pakuje u zip za slanje. Package se može
  otvoriti i u Xcode-u.
- **Minimalni macOS:** 14 (Sonoma), zbog `MenuBarExtra` i `@Observable`.
- **Pronalaženje `flutter` binarnog fajla:** redom: putanja koju je korisnik
  ručno uneo u podešavanjima, `which flutter` kroz login shell
  (`/bin/zsh -lc`), pa standardne lokacije (`~/Documents/flutter/bin`,
  `~/flutter/bin`, `~/development/flutter/bin`, `/opt/homebrew/bin`,
  `/usr/local/bin`, `~/fvm/default/bin`).

## Komponente

### `FlutterDaemon`

Vlasnik `Process`-a. Pokreće
`flutter run --machine -d <deviceId> <dodatni argumenti>` u folderu
projekta. Čita stdout liniju po liniju, parsira kroz `DaemonProtocol`,
emituje `DaemonEvent` kroz `AsyncStream`.

Metode: `start(project:device:extraArgs:)`, `hotReload()`, `hotRestart()`,
`stop()`. Reload/restart šalju `app.restart` sa `appId` dobijenim iz
`app.start` događaja; rezultat (`code == 0`) se vraća pozivaocu.
`stop()` šalje `app.stop`, čeka do 5 s, pa `terminate()` ako proces još živi.

### `DaemonProtocol` (čista logika, testirana)

- `parseLine(String) -> DaemonMessage?` — prepoznaje `event` + `params`,
  odgovor (`id` + `result`/`error`), ili vraća `nil` za ne-JSON tekst.
- `encodeCommand(id:method:params:) -> String` — pravi liniju za stdin.
- `ArgumentSplitter.split(String) -> [String]` — deli dodatne argumente
  poštujući navodnike.

Događaji koje aplikacija koristi: `daemon.connected`, `daemon.logMessage`
(level, message), `app.start` (appId, deviceId, supportsRestart),
`app.started`, `app.progress` (message, finished), `app.log` (log, error),
`app.stop`, `app.webLaunchUrl`.

### `DeviceService`

Poziva `flutter devices --machine` i dekodira niz uređaja:
`id`, `name`, `targetPlatform`, `emulator`, `isSupported`. Nepodržani se
filtriraju. Ima timeout od 30 s.

### `FileWatcher`

FSEvents stream nad `<projekat>/lib` (rekurzivno). Filtrira samo `.dart`
fajlove; generisani fajlovi (`.g.dart`, `.freezed.dart`) se ne izuzimaju, sve `.dart` promene se
računaju. `Debouncer` (testiran) spaja promene u prozoru od 300 ms u jedan
signal.

### `ProjectStore`

`UserDefaults` model: lista nedavnih projekata (putanja, ime iz
`pubspec.yaml`, zadnji uređaj, dodatni argumenti, auto reload uključen),
maksimalno 10, sortirano po zadnjem otvaranju. Plus globalno: ručna putanja do
`flutter`, poslednje otvoreni projekat.

Validacija projekta: folder mora da sadrži `pubspec.yaml` sa `flutter:`
zavisnošću ili `lib/main.dart`.

### `SessionViewModel` (`@Observable`, `@MainActor`)

Stanje: `idle`, `starting`, `running`, `reloading`, `restarting`, `stopping`,
`failed(String)`. Drži izabrani projekat, listu uređaja, izabrani uređaj,
argumente, `autoReload` prekidač, log bafer (max 5000 linija, ring),
`lastError`.

Ponašanje:
- `run()` — validira, čisti log, pokreće daemon, pretplaćuje se na događaje.
- `hotReload()` / `hotRestart()` — dozvoljeno samo u `running`; ako je reload
  već u toku, postavlja `pendingReload = true` i ponavlja posle završetka.
- Watcher signal → `hotReload()` samo ako je `autoReload` i stanje `running`.
- `app.stop` ili kraj procesa → `idle` (ili `failed` ako je izlazni kod ≠ 0 i
  nije korisnik tražio stop).
- Promena projekta dok radi → prvo `stop()`.

### UI

**Glavni prozor** (`MainWindow`):
- Toolbar red 1: `ProjectPicker` (meni nedavnih + "Otvori folder…"),
  `DevicePicker` (meni + dugme za osvežavanje), `TextField` za argumente.
- Toolbar red 2: Run / Stop, Hot Reload, Hot Restart, Toggle "Auto reload",
  indikator stanja (tačka u boji + tekst).
- Telo: `LogView` — monospace tekst, greške crvene, `daemon.logMessage`
  upozorenja narandžasta, auto-scroll na dno dok je korisnik na dnu, dugme
  "Clear".
- Prečice: ⌘R reload, ⌘⇧R restart, ⌘. stop, ⌘⏎ run, ⌘K clear, ⌘O otvori.

**Menubar** (`MenuBarExtra`): ikonica `play.circle` čija boja prati stanje
(siva idle, zelena running, žuta reloading, crvena failed). Meni: ime
projekta i uređaja (onemogućeno), Run/Stop, Hot Reload, Hot Restart,
Auto reload toggle, "Show Logs", Quit. Zatvaranje glavnog prozora ne gasi
aplikaciju; Quit iz menubara zaustavlja daemon pa izlazi.

**Podešavanja** (`Settings` scene): putanja do `flutter` (auto-detektovana,
sa mogućnošću ručnog unosa), debounce u ms.

## Greške

- `flutter` nije pronađen → stanje `failed` sa porukom i linkom na
  podešavanja.
- Nema uređaja → dugme Run onemogućeno, poruka u pickeru.
- Reload vrati `code != 0` → log crven, stanje ostaje `running`.
- Proces umre neočekivano → `failed` sa zadnjih 20 linija stderr-a.

## Testiranje

`swift test` za `DaemonProtocol` (parsiranje događaja, odgovora, ne-JSON
linija, enkodiranje komandi), `ArgumentSplitter` i `Debouncer`. Ostalo ručno
na pravom projektu (`~/Documents/Projects/Usput/usput`).

## Distribucija

`scripts/build_app.sh` → `dist/FlutterRunner.app` i `dist/FlutterRunner.zip`.
Ad-hoc potpis (nema Developer ID sertifikata), pa primaoci moraju jednom da
prođu Gatekeeper: desni klik → Open, ili System Settings → Privacy & Security
→ Open Anyway. Uputstvo ide u `dist/README.txt`.
