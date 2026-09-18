#!/bin/bash
# Builds FlutterRunner.app (universal when possible), ad-hoc signs it and zips it into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Building release binary…"
if swift build -c release --arch arm64 --arch x86_64 >/tmp/flutterrunner-build.log 2>&1; then
  BIN=".build/apple/Products/Release/FlutterRunner"
else
  echo "  universal build failed (see /tmp/flutterrunner-build.log), falling back to native arch"
  swift build -c release
  BIN=".build/release/FlutterRunner"
fi

APP="dist/FlutterRunner.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlutterRunner"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Generating icon…"
ICONSET="dist/AppIcon.iconset"
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "▸ Zipping…"
cp Resources/README-dist.txt dist/README.txt
ditto -c -k --keepParent "$APP" dist/FlutterRunner.zip
echo "Done: $APP and dist/FlutterRunner.zip"
