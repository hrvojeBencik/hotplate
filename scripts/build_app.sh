#!/bin/bash
# Builds FlutterRunner.app (universal), signs it, optionally notarizes it, and packages a zip and a DMG in dist/.
#
# Signing modes (picked automatically):
#   1. Developer ID  – set SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" (or let the script
#                      find one in the keychain). Add NOTARY_PROFILE=<notarytool keychain profile> to notarize
#                      and staple, which is what makes the app open without Gatekeeper warnings on other Macs.
#   2. Ad-hoc        – no Developer ID found: recipients must allow the app in System Settings › Privacy & Security.
#
# One-time notarytool setup (needs an Apple Developer Program membership):
#   xcrun notarytool store-credentials FlutterRunnerNotary --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#   NOTARY_PROFILE=FlutterRunnerNotary scripts/build_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="dist/FlutterRunner.app"
ZIP="dist/FlutterRunner-$VERSION.zip"
DMG="dist/FlutterRunner-$VERSION.dmg"

echo "▸ Building release binary (v$VERSION)…"
# Ask SwiftPM where the products land: the directory differs between toolchains.
if swift build -c release --arch arm64 --arch x86_64 >/tmp/flutterrunner-build.log 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/FlutterRunner"
else
  echo "  universal build failed (see /tmp/flutterrunner-build.log), falling back to native arch"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/FlutterRunner"
fi
if [ ! -f "$BIN" ] || [ -n "$(find Sources -newer "$BIN" -name '*.swift' | head -1)" ]; then
  echo "error: $BIN is missing or older than the sources" >&2; exit 1
fi
echo "  binary: $BIN"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlutterRunner"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Generating icon…"
ICONSET="dist/AppIcon.iconset"
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# --- Signing -------------------------------------------------------------------------------
IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [ -n "$IDENTITY" ]; then
  echo "▸ Signing with Developer ID: $IDENTITY"
  codesign --force --options runtime --timestamp --entitlements Resources/FlutterRunner.entitlements \
           --sign "$IDENTITY" "$APP"
  SIGNED="developer-id"
else
  echo "▸ Signing ad-hoc (no Developer ID certificate found)"
  codesign --force --sign - "$APP"
  SIGNED="ad-hoc"
fi
codesign --verify --deep --strict "$APP"

# --- Packaging -----------------------------------------------------------------------------
echo "▸ Packaging…"
cp Resources/README-dist.txt dist/README.txt
ditto -c -k --keepParent "$APP" "$ZIP"

STAGING="dist/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "FlutterRunner" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# --- Notarization ----------------------------------------------------------------------------
if [ "$SIGNED" = "developer-id" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing (this takes a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the stapled app
  echo "  notarized and stapled"
elif [ "$SIGNED" = "developer-id" ]; then
  echo "  (set NOTARY_PROFILE=<notarytool profile> to notarize; without it Gatekeeper still warns on other Macs)"
fi

echo "Done ($SIGNED): $APP, $ZIP, $DMG"
