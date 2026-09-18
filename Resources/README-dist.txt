FlutterRunner
=============

Mala macOS aplikacija koja pokrece Flutter projekte i drzi hot reload zivim,
tako da mozes da koristis bilo koji editor (Zed, Neovim, VSCode...).

SR: Kako pokrenuti
------------------
1. Raspakuj FlutterRunner.zip i prevuci FlutterRunner.app u Applications.
2. Aplikacija nije notarizovana kod Apple-a, pa ce macOS prvi put da je blokira.
   - Desni klik na FlutterRunner.app -> Open -> Open.
   - Ako i dalje nece: System Settings -> Privacy & Security -> skroluj dole ->
     "Open Anyway" pored FlutterRunner, pa ponovo otvori aplikaciju.
   - Alternativa iz terminala:  xattr -cr /Applications/FlutterRunner.app
3. Zahteva macOS 14 (Sonoma) ili noviji i instaliran Flutter SDK.
4. U aplikaciji: izaberi projekat (folder sa pubspec.yaml), izaberi uredjaj,
   klikni Run. Svako snimanje .dart fajla u lib/ automatski salje hot reload.
   Cmd+R = hot reload, Cmd+Shift+R = hot restart, Cmd+. = stop.
5. Ako aplikacija ne nadje flutter: Settings (Cmd+,) -> upisi putanju do
   flutter/bin/flutter.

EN: How to run
--------------
1. Unzip FlutterRunner.zip and drag FlutterRunner.app to Applications.
2. The app is not notarized, so macOS blocks it the first time:
   - Right-click FlutterRunner.app -> Open -> Open.
   - If still blocked: System Settings -> Privacy & Security -> scroll down ->
     "Open Anyway" next to FlutterRunner, then open the app again.
   - Or from Terminal:  xattr -cr /Applications/FlutterRunner.app
3. Requires macOS 14 (Sonoma) or newer and an installed Flutter SDK.
4. Pick a project (folder with pubspec.yaml), pick a device, press Run.
   Saving any .dart file under lib/ triggers a hot reload automatically.
   Cmd+R = hot reload, Cmd+Shift+R = hot restart, Cmd+. = stop.
5. If flutter is not found: Settings (Cmd+,) -> enter the path to flutter/bin/flutter.
