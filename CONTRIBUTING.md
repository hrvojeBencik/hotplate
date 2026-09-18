# Contributing

Thanks for helping. Hotplate is a small Swift Package with no dependencies.

```bash
swift build          # debug build
swift test           # unit tests (core: protocol, watcher, parsers, editor commands)
swift run Hotplate   # run from source
scripts/build_app.sh # .app, .zip and .dmg in dist/ (ad-hoc signed unless you have a Developer ID)
```

`Package.swift` opens directly in Xcode if you prefer.

Useful while working on the UI: `.build/debug/Hotplate --snapshot /tmp/shots` renders the main window
and the menu bar panel to PNG files (light and dark) with sample data, no screen recording needed.
`HOTPLATE_LOG_STDERR=1 .build/debug/Hotplate` mirrors the in-app log to the terminal.

An optional end-to-end test runs a real `flutter run` against a project you name:

```bash
HOTPLATE_E2E_PROJECT=/path/to/flutter/project HOTPLATE_E2E_DEVICE=chrome swift test --filter RealFlutterE2ETests
```

Please keep pull requests focused, add a unit test for logic in `HotplateCore`, and run `swift test` before opening one.
