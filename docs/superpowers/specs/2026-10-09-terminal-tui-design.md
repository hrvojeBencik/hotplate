# Hotplate 1.1 — terminal (TUI) — dizajn

Datum: 2026-10-09

## Cilj

Komanda `hotplate` koja radi sve što radi Hotplate prozor, ali u terminalu:
pokreće Flutter app, radi hot reload na snimanje `.dart` fajla bez ručnog
osvežavanja, nudi lako biranje uređaja, launch.json konfiguracija i run
argumenata, prikazuje log sa linkovima koji otvaraju fajl na liniji u editoru,
i sve to preko prečica sa tastature. Korisnik tako ostaje u terminalu i ne
prebacuje se na Hotplate prozor.

Uspeh: dnevni rad (pokreni, menjaj kod, gledaj log, skoči na grešku u
editoru, promeni uređaj/konfiguraciju, zaustavi) može da se obavi samo iz
terminala, sa istim ponašanjem kao GUI.

## Odluke iz razgovora

- **Samostalna komanda.** `hotplate` sam pokreće `flutter run --machine`,
  watcher i sve ostalo. GUI ne mora biti otvoren. Sa GUI-jem deli samo
  podešavanja.
- **Full-screen TUI** (alternate screen, kao lazygit/htop), a ne inline stream.
- **Tastatura i miš.** Točkić skroluje, a klik na link otvara fajl. Obično
  selektovanje teksta radi uz Shift (u iTerm-u Option), a `y`/`Y` kopiraju bez
  miša.
- **Pristup A:** logika sesije se izdvaja iz GUI-ja u `HotplateCore`, a TUI
  ima sopstveni mali ANSI renderer. Bez spoljnih zavisnosti.

## Van opsega (1.1)

- Kačenje terminala na sesiju otvorenog GUI-ja (IPC).
- Podesive prečice.
- Menjanje putanje do flutter-a i debounce-a iz TUI-ja. To ostaje u GUI
  podešavanjima i opciji `--flutter`.
- Linux; globalne prečice ⌃⌥R / ⌃⌥⇧R za CLI.

## 1. Komanda i opcije

```
hotplate [putanja] [opcije] [-- <flutter run argumenti>]
```

- `putanja` je opciona; podrazumevano je trenutni direktorijum. Od nje se ide
  naviše do prvog `pubspec.yaml` koji je Flutter projekat (ista provera kao
  `Project.load`). Zato `hotplate` radi i iz `lib/src/...`.
- Ako projekat nije nađen, a postoje nedavni projekti, TUI se otvara sa listom
  nedavnih projekata. Ako nema ni njih, na stderr ide poruka, izlazni kod je 1
  i ne ulazi se u full-screen.
- Podrazumevano se app **odmah pokreće** na zapamćenom uređaju sa zapamćenom
  konfiguracijom/argumentima. Ako uređaj nije zapamćen ili nije dostupan, prvo
  se otvara lista uređaja, a run kreće posle izbora.

| Opcija | Značenje |
|---|---|
| `-d, --device <id\|ime>` | uređaj; dovoljan je deo imena („iphone“, „chrome“) |
| `-c, --config <ime>` | konfiguracija iz `.vscode/launch.json` |
| `--no-run` | otvori TUI bez automatskog pokretanja |
| `--no-auto-reload` | isključi reload na save za ovu sesiju |
| `--flutter <putanja>` | putanja do `flutter`-a; inače ista detekcija kao GUI (`FlutterLocator`) |
| `-- <args>` | sve posle `--` ide u `flutter run` kao run argumenti (prebacuje na Custom) |
| `-h, --help`, `--version` | pomoć, verzija |

Nepoznata opcija ili `-c` bez vrednosti: poruka i kratka upotreba na stderr,
izlazni kod 2. Ako stdin ili stdout nije terminal: poruka `hotplate: needs an
interactive terminal`, izlazni kod 2.

**Pravilo pamćenja.** Opcije sa komandne linije važe samo za tu sesiju i
nikad se ne upisuju. Izbori napravljeni unutar TUI-ja (uređaj, konfiguracija,
argumenti, auto-reload) pamte se po projektu, isto kao u GUI-ju.

**Izlaz.** `q` ili Ctrl+C: uredan stop (`app.stop`, pa čekanje na izlaz
procesa), vraćanje terminala i izlaz sa kodom 0. Drugi Ctrl+C u roku od 2 s
odmah prekida flutter (`terminate`) i izlazi.

## 2. Ekran i prečice

```
 Hotplate · my_app   ● Running   iPhone 16 Pro   cfg: dev   ↻ auto
 ────────────────────────────────────────────────────────────────────
 12:01:03  Change detected in lib/ → hot reload
 12:01:03  Hot reload done in 412 ms.
▶12:01:09  Error at lib/home.dart:42:7
 12:01:09    #0 _HomeState.build (package:my_app/home.dart:42:7)
 ────────────────────────────────────────────────────────────────────
 ⏎ run  r reload  R restart  s stop  d device  c config  a args  ? help
```

- **Gornja traka:** ime projekta, stanje u boji (isti tekstovi kao
  `statusText` u GUI-ju), uređaj, `cfg: <ime>` ili `cfg: custom`, i `↻ auto`
  kad je auto-reload uključen.
- **Log:** boje po vrsti (error crveno, warning žuto, info prigušeno, success
  zeleno), prigušen timestamp `HH:mm:ss`. Linkovi koje prepozna
  `LogLinkParser` su podvučeni. Duge linije se prelamaju, a nastavak se
  uvlači ispod teksta (ne ispod timestamp-a). Izabrana linija ima marker `▶`
  i inverznu pozadinu.
- **Donja traka:** generiše se iz tabele prečica za trenutni mod. Prikazuje
  onoliko stavki koliko staje, a `? help` je uvek poslednja. Dok app radi
  prikazuje `s stop`, inače `⏎ run`.
- Ispod 60×12 se umesto rasporeda prikazuje samo „Terminal too small
  (min 60×12)“.

### Prečice (normalni mod)

| Taster | Akcija |
|---|---|
| `⏎` | Run (kad je stanje idle/failed); ako je linija izabrana, otvori njen link |
| `r` / `R` | Hot reload / hot restart |
| `s` | Stop |
| `q`, Ctrl+C | Stop + izlaz |
| `d` | Lista uređaja |
| `c` | Lista konfiguracija iz launch.json + „Custom“ |
| `a` | Uredi run argumente (polje za unos) |
| `A` | Auto-reload uključi/isključi |
| `e` / `E` | Otvori projekat u editoru / izaberi editor |
| `p` | Nedavni projekti |
| `o` | Izaberi poslednju liniju sa linkom (najnovija greška ima prednost) |
| `[` / `]` | Prethodna / sledeća linija sa linkom |
| `y` / `Y` | Kopiraj izabranu liniju / ceo log (`pbcopy`) |
| `/` | Pretraga; `n` / `N` sledeći / prethodni pogodak |
| `j` `k` `↑` `↓` | Skrol za liniju (ako je linija izabrana, pomera izbor) |
| PgUp / PgDn, Ctrl+U / Ctrl+D | Skrol za ekran / pola ekrana |
| `g` / `G` | Vrh / kraj; `G` ponovo uključuje praćenje |
| `f` | Praćenje novih linija uključi/isključi |
| `K` | Očisti log |
| `Esc` | Zatvori popup / poništi izbor linije / poništi pretragu |
| Ctrl+L | Pun redraw ekrana |
| `?` | Pomoć sa svim prečicama |

Skrol nagore ili izbor linije isključuju praćenje novih linija, a `G` ili
skrol do dna ga vraćaju (isto kao `followLogs` u GUI-ju).

### Miš

SGR mouse mod (1006) sa praćenjem klikova (1000), bez praćenja pokreta.
Točkić skroluje log 3 linije po koraku. Klik na liniju je bira. Klik na
podvučen link odmah otvara fajl u editoru. Klik van popup-a zatvara popup.

### Popup liste

Uređaji, konfiguracije, editori, nedavni projekti. Otvaraju se na sredini
ekrana, a log iza njih nastavlja da teče. Kucanje filtrira (podstring, bez
obzira na velika/mala slova), ↑↓ ili Ctrl+P/Ctrl+N pomeraju izbor, ⏎ bira,
Esc zatvara. Trenutna vrednost je označena sa `●`.

- **Uređaji:** `displayName` + platforma. Ctrl+R osvežava (`flutter devices`),
  a dok traje prikazuje se „Refreshing…“. Prazno stanje: „No devices. Start one,
  then press Ctrl+R.“
- **Konfiguracije:** sve iz launch.json + „Custom (keep current args)“.
- **Editori:** detektovani editori (`EditorLauncher.detectInstalled`), ručno
  izabrani editor ako postoji, i „Custom command“ ako je podešena u GUI-ju.
- **Projekti:** nedavni projekti iz `ProjectStore`; dok app radi, izbor
  drugog projekta prvo zaustavlja trenutni.

### Polje za argumente i pretragu

Jednolinijski unos u donjoj traci, sa pomeranjem kursora (←/→, Ctrl+A/E),
brisanjem (Backspace, Ctrl+W, Ctrl+U) i lepljenjem (bracketed paste, 2004).
⏎ potvrđuje, Esc odustaje. Potvrđeni argumenti prebacuju konfiguraciju na
Custom, isto kao ručna izmena u GUI-ju.

## 3. Arhitektura

### Targeti

```
HotplateCore      library     postojeće + Session, LogLine/LogKind, ProjectStore, ProjectLocator,
                              DeviceMatcher, HotplateVersion
HotplateTUI       library     sav TUI kod, bez main-a, testabilan
hotplate          executable  Sources/hotplate/main.swift: opcije, TTY provera, pokretanje TUIApp
Hotplate          executable  GUI, tanak omotač oko Session
HotplateCoreTests             + SessionTests, ProjectLocatorTests, DeviceMatcherTests, ProjectStoreTests
HotplateTUITests              novo
```

Izvršni proizvod `hotplate` i GUI `Hotplate` se razlikuju samo po veličini
slova. U `.build` su u istom direktorijumu, a na case-insensitive disku bi
se pregazili. Zato se CLI proizvod u `Package.swift` zove `hotplate-cli`, a
`build_app.sh` ga kopira kao `Contents/Helpers/hotplate`. Za razvoj se koristi
`swift run hotplate-cli`.

### Session (HotplateCore)

`SessionViewModel` se seli u Core kao `Session` (`@MainActor @Observable`;
Observation ne zavisi od SwiftUI-ja). Seli se bez promene ponašanja:
stanje, uređaji, launch.json, argumenti, run/stop/reload/restart, watcher +
debouncer, pending reload, logovi (`LogLine`, `LogKind`, limit od 5000),
otvaranje projekta i linkova u editoru, detekcija flutter-a.

Ostaje u GUI targetu, kao ekstenzija ili omotač: `openProjectPanel()` i
`chooseEditorApp()` (`NSOpenPanel`), `NSSound.beep()`. `Session` za to
izlaže `var onError: ((String) -> Void)?`, a GUI na njega pušta beep.
`Snapshot`/`preview()` ostaju u GUI-ju.

**Injektovanje radi testova.** `Session.init` prima:
- `store: ProjectStore`
- `makeDaemon: (DaemonConfig) -> SessionDaemon`. `SessionDaemon` je protokol
  sa `events`, `start()`, `stop()`, `terminate()`, `restart(full:)` i
  `wasStopRequested`. `FlutterDaemon` ga implementira, a `terminate()` je novo
  (SIGTERM procesu, za drugi Ctrl+C).
- `listDevices: (String?) async throws -> [FlutterDevice]`
- `locateFlutter: (String) -> String?`
- `makeWatcher: (String, @escaping () -> Void) -> Stoppable`

Produkcioni podrazumevani parametri koriste postojeće klase, pa se GUI kod
ne menja na mestu poziva.

**Overrides.** `Session.overrides: SessionOverrides` (`deviceQuery`,
`configName`, `args`, `autoReload`, sve opcione). CLI ih postavlja pre prvog
`selectProject`. Pravila:
- `selectProject` primenjuje sačuvane vrednosti, pa preko njih override-e:
  config override → `selectLaunchConfig`, args override → custom args, uređaj
  posle `refreshDevices` preko `DeviceMatcher`.
- `persistProjectSettings` za polje koje je trenutno overridovano upisuje
  **sačuvanu** vrednost, a ne efektivnu.
- Promena polja iz TUI-ja briše override za to polje. Od tada se to polje
  pamti normalno.
- Override važi samo za projekat zadat na komandnoj liniji. Promena projekta
  preko `p` briše sve override-e.

**ProjectStore** se seli u Core. Podrazumevani `UserDefaults` je
`UserDefaults(suiteName: "com.hrvojebencik.hotplate")`. GUI ga do sada
koristi kao `.standard` sa istim bundle id-jem, pa su postojeća podešavanja
odmah vidljiva CLI-ju. Ako GUI i CLI rade istovremeno, važi poslednji upis.
GUI ne osluškuje promene uživo. To je prihvatljivo za samostalni režim.

**ProjectLocator.find(from: String) -> String?** ide naviše od putanje (ili
njenog roditelja, ako je fajl) do korena i vraća prvi direktorijum za koji
`Project.load` uspeva.

**DeviceMatcher.match(query:in:) -> DeviceMatch** (`.one(FlutterDevice)`,
`.many([FlutterDevice])`, `.none`). Redosled: tačan id → tačno ime (bez
obzira na velika/mala slova) → podstring u imenu ili id-ju. Ako je
rezultat `.many` ili `.none`, otvara se lista uređaja sa upisanim filterom i
ne pokreće se ništa dok korisnik ne izabere.

**HotplateVersion.current** je konstanta u Core-u. `build_app.sh` proverava
da je jednaka `CFBundleShortVersionString` u `Info.plist` i prekida build ako
nije.

### HotplateTUI

| Komponenta | Odgovornost |
|---|---|
| `Terminal` | termios raw mode (bez ECHO/ICANON/ISIG/IXON, sa OPOST), alternate screen (1049), sakriven kursor, miš (1000+1006), bracketed paste (2004), veličina preko `ioctl(TIOCGWINSZ)`, `restore()` koji je idempotentan i registrovan za `atexit` i signale |
| `InputDecoder` | struktura sa baferom: `feed(bytes) -> [InputEvent]`. Pokriva ASCII, UTF-8, Ctrl+slovo, Esc (samostalni Esc posle 30 ms tišine), CSI strelice/Home/End/PgUp/PgDn/Delete, SS3 strelice, SGR miš (klik, točkić), bracketed paste i sekvence podeljene preko više čitanja |
| `ScreenBuffer` | mreža `Cell(char, width, style)`; `put(text, x, y, style, maxWidth)` sa širinom znakova (East Asian Wide/emoji = 2, kombinujući = 0) |
| `Renderer` | poredi sa prethodnim frejmom i emituje samo promene (pozicioniranje + SGR stil). Pun redraw ide posle resize-a i na Ctrl+L. Izlaz se piše jednim `write` pozivom po frejmu |
| `LogViewport` | od `[LogLine]` i širine pravi prelomljene vizuelne redove sa mapiranjem nazad (linija, opseg kolona). Drži offset, follow, izabranu liniju i pogotke pretrage; `hitTest(x, y) -> (lineId, LogLink?)` |
| `StatusBar`, `FooterBar`, `Picker`, `TextInput`, `HelpOverlay` | crtaju u `ScreenBuffer` iz svog stanja; bez I/O |
| `KeyBindings` | tabela `(Mode, Key) -> Action` sa labelom; iz nje se generišu donja traka i `?` pomoć |
| `TUIApp` | mašina stanja modova (`normal`, `picker`, `input(args\|search)`, `help`; izabrana linija i pretraga su stanje `LogViewport`-a), prevodi `Action` u pozive `Session`, zakazuje render |

### Tok podataka i petlja

- `main.swift` parsira opcije, proverava TTY, pravi `Session` (sa
  `--flutter` putanjom, ako je data, kao ručnom putanjom samo za ovu sesiju)
  i `TUIApp`, pa poziva `RunLoop.main.run()`.
- Stdin: `DispatchSource.makeReadSource` na fd 0 → `InputDecoder` →
  događaji na `@MainActor`. Esc tajmer ide preko `DispatchQueue.main.asyncAfter`.
- SIGWINCH: `DispatchSource.makeSignalSource` → nova veličina → pun redraw.
  SIGTERM/SIGHUP/SIGINT: isto, a gase flutter i vraćaju terminal. SIGINT u
  raw modu stiže kao bajt 0x03 i obrađuje se kao taster.
- Render: `withObservationTracking { čitanje polja Session koja se crtaju }`
  → na promenu `scheduleRender()`. Render se spaja: najviše jedan na 16 ms,
  a posle svakog rendera se tracking ponovo registruje. Ulazni događaji takođe
  zakazuju render.
- Neuhvaćena greška ili `fatalError` u našem kodu: `atexit` handler vraća
  terminal.

### Otvaranje linkova

Kao u GUI-ju: `Session.openLogLink(location:line:column:)` (preseljeno iz
`SessionViewModel`). Ako editor nije podešen, u log ide poruka „No editor
found. Press E to choose one.“. Tekst poruke zavisi od front-enda, pa ga
`Session` dobija kao parametar `editorHint`.

## 4. Distribucija

- `Hotplate.app/Contents/Helpers/hotplate`, universal (arm64 + x86_64), u
  istom DMG-u i zip-u.
- `build_app.sh`: gradi oba proizvoda. Helper se potpisuje **pre** aplikacije,
  istim identitetom, sa `--options runtime --timestamp` i istim entitlements
  fajlom (flutter, pod i editor CLI nisu naši potpisi). Ad-hoc režim potpisuje
  i helper ad-hoc. Verifikacija `codesign --verify --strict` ide za oba.
  Notarizacija DMG-a pokriva i helper.
- **Homebrew:** cask u repou `hrvojebencik/homebrew-tap` dobija
  `binary "#{appdir}/Hotplate.app/Contents/Helpers/hotplate"`. To se radi pri
  izdavanju 1.1.0, van ovog repoa.
- **GUI:** meni *Hotplate → Install Command Line Tool…* pravi symlink
  `/usr/local/bin/hotplate` → helper u trenutno pokrenutoj aplikaciji, uz
  admin prompt (`osascript … with administrator privileges`, `mkdir -p
  /usr/local/bin && ln -sf`). Settings → General prikazuje status: „Installed“
  / „Not installed“ / „Points to another copy“, sa dugmićima Install i Remove.
- Verzija 1.1.0 u `Info.plist` i `HotplateVersion`. CHANGELOG stavka i README
  sekcija „Terminal“ sa primerima i tabelom prečica.

## 5. Greške i ivični slučajevi

| Situacija | Ponašanje |
|---|---|
| flutter nije nađen | TUI se otvara; status `Failed: flutter not found`; log savetuje `--flutter` ili GUI Settings; `⏎` ne radi ništa |
| nema uređaja | lista uređaja sa praznim stanjem i Ctrl+R |
| `-d` nema tačan pogodak | lista uređaja sa filterom = upit; nema automatskog pokretanja |
| `-c` ne postoji u launch.json | poruka u logu, ostaje sačuvana konfiguracija; app se pokreće |
| nije Flutter projekat i nema nedavnih | stderr poruka, izlaz 1, pre full-screen-a |
| editor nije podešen | poruka u logu sa „Press E“ |
| terminal premali | poruka umesto rasporeda; prečice i dalje rade |
| flutter izađe sa greškom | status Failed sa kodom; `⏎` pokreće ponovo |
| SIGKILL na hotplate | flutter može ostati da radi (isto kao GUI danas) |

## 6. Testiranje

Sve u `swift test`, po TDD-u.

**HotplateCoreTests**
- `SessionTests` (lažni daemon, uređaji, watcher, `ProjectStore` sa
  privremenim suite-om): override se ne upisuje; promena polja briše override
  i upisuje se; `p` briše override-e; izbor launch config-a puni args i
  uređaj; ručna izmena args-a prebacuje na Custom; prelazi stanja
  (starting → running → reloading → running, stop → idle, izlaz sa kodom →
  failed); promena fajla tokom reloada daje tačno jedan dodatni reload;
  auto-reload off ignoriše promene.
- `ProjectLocatorTests`: koren, poddirektorijum, fajl kao ulaz, nema projekta.
- `DeviceMatcherTests`: id, ime, deo imena, više pogodaka, nijedan.
- `ProjectStoreTests`: čuvanje i učitavanje sa suite-om, recents limit 10.

**HotplateTUITests**
- `InputDecoderTests`: svaka podržana sekvenca; sekvenca podeljena na dva
  `feed`-a; samostalni Esc; UTF-8; SGR klik i točkić sa koordinatama;
  bracketed paste.
- `RendererTests`: prvi frejm; promena jedne ćelije daje jedno pozicioniranje
  i jedan znak; promena stila; širok znak.
- `LogViewportTests`: prelamanje sa uvlačenjem; follow na dnu; skrol nagore
  gasi follow; `G` ga vraća; `hitTest` pogađa link na tačnoj koloni i u
  prelomljenom delu; pretraga n/N sa kruženjem.
- `PickerTests`: filtriranje, kretanje, izbor, prazno stanje.
- `KeyBindingsTests`: nema duplih tastera u istom modu; svaka `Action` ima
  labelu; footer staje u zadatu širinu i završava sa `? help`.
- `TUIAppTests` (prava `Session` sa lažnim zavisnostima iz zajedničkog test targeta `HotplateTestSupport`):
  `⏎` u idle zove run; `⏎` sa izabranom linijom otvara link; `q` zove stop
  pa exit; dupli Ctrl+C u 2 s zove terminate.

**Ručno, pre izdavanja**
Terminal.app, iTerm2, Ghostty, kitty, WezTerm i tmux u jednom od njih:
boje, miš (klik, točkić, Shift-selekcija), resize, paste, izlaz u svim
varijantama vraća terminal. Ceo GUI još jednom ručno (run, reload na save,
launch.json, uređaji, editor, log linkovi, menu bar panel, globalne
prečice), zbog selidbe `Session`-a.
