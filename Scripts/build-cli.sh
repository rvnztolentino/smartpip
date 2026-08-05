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

echo "==> Signing (ad hoc, hardened runtime, sandboxed)"
# Both protections are applied here rather than only by Xcode, so the script and
# SmartPiP.xcodeproj produce the same app. The project sets ENABLE_HARDENED_RUNTIME and
# ENABLE_APP_SANDBOX to match, and this is the build path that is actually used.
#
# The app's one untrusted input is a video file, handed to AVFoundation and parsed in
# process, so it is worth confining. The sandbox comes from the entitlements and the
# hardened runtime from `--options runtime`; both are real with an ad hoc signature, and
# neither needs an account or a certificate.
#
# What ad hoc signing still costs is distribution: Gatekeeper will object to a build sent
# to anyone else. Notarising is the fix for that and needs a paid Developer ID, which this
# build path deliberately does not use.
codesign --force --sign - --options runtime \
  --entitlements "$ROOT/SmartPiP/SmartPiP.entitlements" "$APP"

echo "==> Built $APP"
