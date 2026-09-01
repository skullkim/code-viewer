#!/usr/bin/env bash
# Builds a universal .app and wraps it in a drag-to-Applications disk image.
#
# Universal on purpose: `swift build` defaults to the host architecture, so a release cut on
# Apple Silicon would silently exclude every Intel Mac. A download that cannot run is worse
# than no download — it fails at launch with a message the user cannot act on.
#
# The app is **ad-hoc signed, not notarized**. Gatekeeper will still warn on first open, and
# the README says how to get past it. Signing it properly needs a paid Developer ID, which
# this project does not have; pretending otherwise in the docs would be the worse choice.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodeNavigator"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.build}"
STAGE="$OUTPUT_DIR/dmg-stage"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/Resources/Info.plist")"
DMG="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

echo "building universal ($APP_NAME $VERSION)…" >&2
swift build --package-path "$REPO_ROOT" -c release --arch arm64 --arch x86_64 --product "$APP_NAME" >&2

BIN="$(swift build --package-path "$REPO_ROOT" -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

# Checked rather than trusted: `--arch` is silently ignored by some toolchain versions, and a
# thin binary looks identical from the outside. The failure would only show on someone else's
# Mac, which is the worst place to find it.
ARCHS="$(lipo -archs "$BIN")"
for want in arm64 x86_64; do
    case " $ARCHS " in
        *" $want "*) ;;
        *) echo "FAIL: 유니버설이 아니다 — $want 가 없다 (실제: $ARCHS)" >&2; exit 1 ;;
    esac
done
echo "  아키텍처: $ARCHS" >&2

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$REPO_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signature. It does not remove the Gatekeeper prompt, but without any signature at all
# macOS 15+ refuses the app outright rather than offering the right-click override.
codesign --force --deep --sign - "$APP_DIR" >&2
codesign --verify --deep "$APP_DIR" >&2 || { echo "FAIL: 서명 검증 실패" >&2; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# The drag target only reads as an instruction if both icons are in one window, so the volume
# name carries the rest of the instruction.
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >&2
rm -rf "$STAGE"

echo "  크기: $(du -h "$DMG" | cut -f1)" >&2
echo "$DMG"
