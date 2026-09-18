# Announcement drafts

Post these yourself; adjust tone as you like. Keep the Flutter trademark line in the Reddit post.

---

## r/FlutterDev

**Title:** Hotplate: a small macOS app that runs your Flutter project and hot reloads on save, so you can use Zed/Neovim/any editor

**Body:**

VS Code got painfully slow for me when running Flutter apps (10-second freezes), and switching to Zed meant
losing hot reload, since the run + reload part lives in the VS Code extension. So I built a tiny native macOS
app that does only that part:

- Pick a project and a device, press Run. It drives `flutter run --machine`, the same protocol the VS Code extension uses.
- Hot reload on save: watches `lib/` and reloads the moment you save a `.dart` file, from any editor.
- Reads your `.vscode/launch.json` configs (flavors, `--dart-define-from-file`, targets), so nothing to reconfigure.
- Logs with clickable file paths: click `package:app/…/x.dart:42` in a stack trace and it opens the file at that line in your editor.
- Menu bar panel plus global shortcuts (⌃⌥R reload, ⌃⌥⇧R restart) so you never leave the editor.
- Open the project in Zed, VS Code, Cursor, Sublime, Android Studio, Xcode or a custom command.

Free, open source (MIT), Swift/SwiftUI with zero dependencies, signed and notarized.

GitHub + download: https://github.com/hrvojeBencik/hotplate
Homebrew: `brew install hrvojebencik/tap/hotplate`

Requires macOS 14+ and a Flutter SDK. Feedback and issues welcome, especially from Neovim users: I'd like to know
which "open file at line" command works best for your setup.

*Flutter and the related logo are trademarks of Google LLC. Hotplate is not endorsed by or affiliated with Google LLC.*

---

## Flutter Community Discord (#showcase)

Built a small macOS menu bar app for people who want to use Zed/Neovim/etc. for Flutter without losing hot reload.
Hotplate runs `flutter run` for you, hot reloads on every save in `lib/`, reads your launch.json, and turns file paths
in the log into "open at line" links for your editor. Global ⌃⌥R reloads from anywhere. Free, MIT, Swift, notarized.
https://github.com/hrvojeBencik/hotplate

---

## X / LinkedIn

I moved from VS Code to Zed for Flutter and missed exactly one thing: hot reload on save. So I built Hotplate,
a tiny macOS app that runs your Flutter project and keeps it hot from any editor. Menu bar controls, global shortcuts,
clickable stack traces. Free and open source: https://github.com/hrvojeBencik/hotplate

---

## Hacker News (Show HN)

**Title:** Show HN: Hotplate – run Flutter apps with hot reload on save from any editor (macOS)

**Text:** VS Code became too slow for me to run Flutter apps, and other editors have no hot reload integration.
Hotplate is a small native macOS app (Swift, no dependencies) that speaks the `flutter run --machine` protocol,
watches your project for saves, and hot reloads. It reads launch.json, links stack traces to your editor at the
right line, and adds global shortcuts. MIT licensed, notarized. https://github.com/hrvojeBencik/hotplate
