#!/usr/bin/env bash
# Assembles the SPM executable into a .app bundle (REQ-011 AC-1).
#
# A bare SPM executable has no bundle identity: measured on 2026-08-29, its
# Bundle.main.bundleIdentifier is nil and its window never becomes key. Wrapping it in a
# bundle with an Info.plist fixes both. See docs/adr/0105.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-CodeNavigator}"
APP_NAME="${APP_NAME:-CodeNavigator}"
PACKAGE_PATH="${PACKAGE_PATH:-$REPO_ROOT}"
INFO_PLIST="${INFO_PLIST:-$REPO_ROOT/Resources/Info.plist}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.build}"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

echo "building $EXECUTABLE_NAME ($CONFIGURATION)…"
swift build --package-path "$PACKAGE_PATH" -c "$CONFIGURATION" --product "$EXECUTABLE_NAME" >&2

BIN_PATH="$(swift build --package-path "$PACKAGE_PATH" -c "$CONFIGURATION" --show-bin-path)"
if [ ! -x "$BIN_PATH/$EXECUTABLE_NAME" ]; then
    echo "FAIL: 빌드 산출물이 없다: $BIN_PATH/$EXECUTABLE_NAME" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# The plist names the executable; a mismatch produces a bundle that launches to nothing.
PLIST_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_DIR/Contents/Info.plist")"
if [ "$PLIST_EXECUTABLE" != "$EXECUTABLE_NAME" ]; then
    echo "FAIL: Info.plist의 CFBundleExecutable($PLIST_EXECUTABLE)이 실행 파일($EXECUTABLE_NAME)과 다르다" >&2
    exit 1
fi

echo "$APP_DIR"
