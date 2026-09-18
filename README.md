# FlutterRunner

A tiny native macOS app that runs a Flutter project with `flutter run --machine`,
exposes Run / Stop / Hot Reload / Hot Restart, hot-reloads automatically when a
`.dart` file under `lib/` is saved, shows the logs, and sits in the menu bar.
Use any editor you like; this replaces only the "run + hot reload" part of VSCode.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 15+ command line tools (to build)
- Flutter SDK installed

## Build & run from source

```bash
swift build
swift run FlutterRunner
```

Or open `Package.swift` in Xcode and run the `FlutterRunner` scheme.

## Tests

```bash
swift test
```

## Build the distributable .app

```bash
scripts/build_app.sh
```

Produces `dist/FlutterRunner.app`, `dist/FlutterRunner.zip` and `dist/README.txt`
(recipient instructions, since the app is ad-hoc signed and not notarized).

## How it works

- `FlutterDaemon` runs `flutter run --machine -d <device> <args>` and speaks its
  JSON protocol (`app.restart`, `app.stop`, `app.started`, `app.log`, …).
- `FileWatcher` (FSEvents) watches `lib/` for `.dart` changes, debounced (300 ms
  by default), and triggers a hot reload while the app is running.
- `DeviceService` runs `flutter devices --machine` for the device picker.
- Recent projects, the last device and extra args per project are stored in
  UserDefaults.

## Layout

```
Sources/FlutterRunnerCore   # protocol, process, watcher, models (unit-tested)
Sources/FlutterRunner       # SwiftUI app
Tests/FlutterRunnerCoreTests
scripts/build_app.sh        # .app + zip
docs/superpowers/           # design spec and implementation plan
```
