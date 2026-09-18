# Changelog

## 1.0.0 — 2026-09-18

First release.

- Run, stop, hot reload and hot restart any Flutter project on any device (`flutter run --machine`).
- Hot reload on save: watches `lib/` for `.dart` changes, debounced.
- Reads `.vscode/launch.json` configurations (program, args, toolArgs, flutterMode, deviceId).
- Menu bar panel with the same controls; global shortcuts ⌃⌥R (reload) and ⌃⌥⇧R (restart).
- Log with timestamps and levels; Dart file references are links that open your editor at the line.
- Open the project in Zed, VS Code, Cursor, Windsurf, Sublime Text, Android Studio, IntelliJ, Xcode, or a custom command.
- Signed with Developer ID and notarized.
