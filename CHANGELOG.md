# Changelog

## 1.2.0 — 2026-11-21

- Reload on save now covers local packages you depend on with `path:`, such as a `ui/` package of shared widgets
  (`path: ui`) or one outside the project (`path: ../shared_ui`), plus their own local packages and pub workspace
  members (from `.dart_tool/package_config.json`). The log lists them when you press Run.
- The whole project folder is watched, not only `lib/` (for example a `-t` target outside `lib/`).
- Saving tests (`test/`, `integration_test/`, `test_driver/`), an `example/` app, platform folders, `build/` or hidden
  folders such as `.dart_tool` doesn't reload.
- The log names the file that changed: `Change detected in ui/lib/button.dart → hot reload`.

## 1.1.1 — 2026-10-09

- Quitting the app right after Stop now waits for flutter to exit (and kills it if it hangs) instead of leaving it running.
- Switching projects no longer carries a launch configuration's device over to the new project.

## 1.1.0 — 2026-10-09

- `hotplate` command: the whole app in your terminal. Run, hot reload on save, devices, launch.json configurations,
  run arguments and a log whose file links open your editor at the line, all from the keyboard (mouse works too).
- Options for one-off runs: `-d <device>`, `-c <config>`, `--no-run`, `--no-auto-reload`, `--flutter <path>`,
  and `-- <flutter run args>`. They never overwrite your saved settings.
- Hotplate → Install Command Line Tool… links `/usr/local/bin/hotplate`; Homebrew: the cask installs the command (with the 1.1.0 cask update).
- The terminal and the app share settings: editor, debounce, and the device/args remembered per project.

## 1.0.0 — 2026-09-18

First release.

- Run, stop, hot reload and hot restart any Flutter project on any device (`flutter run --machine`).
- Hot reload on save: watches `lib/` for `.dart` changes, debounced.
- Reads `.vscode/launch.json` configurations (program, args, toolArgs, flutterMode, deviceId).
- Menu bar panel with the same controls; global shortcuts ⌃⌥R (reload) and ⌃⌥⇧R (restart).
- Log with timestamps and levels; Dart file references are links that open your editor at the line.
- Open the project in Zed, VS Code, Cursor, Windsurf, Sublime Text, Android Studio, IntelliJ, Xcode, or a custom command.
- Signed with Developer ID and notarized.
