Hotplate
========

Keeps your Flutter app hot: runs a Flutter project, hot reloads it whenever you
save a .dart file, shows the logs, and lives in the menu bar. Use any editor.

SR: Kako pokrenuti
------------------
1. Otvori Hotplate-<verzija>.dmg i prevuci Hotplate u Applications.
2. Aplikacija je potpisana Developer ID sertifikatom i notarizovana kod Apple-a,
   pa se otvara bez upozorenja.
3. Zahteva macOS 14 (Sonoma) ili noviji i instaliran Flutter SDK.
4. Izaberi projekat (folder sa pubspec.yaml), izaberi uredjaj, klikni Run.
   Svako snimanje .dart fajla u lib/ automatski salje hot reload.
   Cmd+R = hot reload, Cmd+Shift+R = hot restart, Cmd+. = stop,
   Ctrl+Alt+R / Ctrl+Alt+Shift+R = reload / restart iz bilo koje aplikacije.
5. Ako aplikacija ne nadje flutter: Settings (Cmd+,) -> upisi putanju do flutter/bin/flutter.

EN: How to run
--------------
1. Open Hotplate-<version>.dmg and drag Hotplate to Applications.
2. The app is signed with a Developer ID and notarized by Apple, so it opens without warnings.
3. Requires macOS 14 (Sonoma) or newer and an installed Flutter SDK.
4. Pick a project (folder with pubspec.yaml), pick a device, press Run.
   Saving any .dart file under lib/ triggers a hot reload automatically.
   Cmd+R = hot reload, Cmd+Shift+R = hot restart, Cmd+. = stop,
   Ctrl+Alt+R / Ctrl+Alt+Shift+R = reload / restart from any app.
5. If flutter is not found: Settings (Cmd+,) -> enter the path to flutter/bin/flutter.

Source and issues: https://github.com/hrvojeBencik/hotplate
