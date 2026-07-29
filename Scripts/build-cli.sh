#!/bin/bash
#
# Builds SmartPiP.app using only the Command Line Tools.
#
# Xcode is the primary way to build this project; this script exists so the app
# can still be compiled, verified and run on a machine that only has the
# Command Line Tools installed. It produces build/SmartPiP.app.
#
#   Scripts/build-cli.sh            # debug build
#   Scripts/build-cli.sh release    # optimised build
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/SmartPiP.app"
CONFIGURATION="${1:-debug}"

case "$CONFIGURATION" in
  debug)   SWIFT_FLAGS=(-Onone -g) ;;
  release) SWIFT_FLAGS=(-O) ;;
  *) echo "usage: $(basename "$0") [debug|release]" >&2; exit 1 ;;
esac

SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macos14.0"

echo "==> Compiling ($CONFIGURATION, $TARGET)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Sorted so the compile order is stable between runs.
SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT/SmartPiP" -name '*.swift' | sort)

swiftc \
  -o "$APP/Contents/MacOS/SmartPiP" \
  -swift-version 5 \
  -target "$TARGET" \
  -sdk "$SDK" \
  "${SWIFT_FLAGS[@]}" \
  "${SOURCES[@]}"

echo "==> Assembling bundle"
cp "$ROOT/SmartPiP/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The asset catalog needs actool (Xcode only), so build an .icns from the same
# PNGs instead. The AppIcon.appiconset filenames already match what iconutil
# expects from an .iconset, so this is a straight copy.
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ROOT"/SmartPiP/Assets.xcassets/AppIcon.appiconset/*.png "$ICONSET/"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"

echo "==> Signing (ad hoc)"
codesign --force --sign - "$APP"

echo "==> Built $APP"
