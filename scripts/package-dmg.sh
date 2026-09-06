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

# Assembly is delegated rather than repeated. This script used to build its own bundle — copy the
# binary, copy the Info.plist, done — and every resource added to `bundle.sh` afterwards was
# missing from the download. Measured on the published v0.1.0: no tree-sitter parsers, no icon,
# while the local bundle had both and looked correct to everyone testing locally.
echo "building universal ($APP_NAME $VERSION)…" >&2
UNIVERSAL=1 CONFIGURATION=release APP_NAME="$APP_NAME" OUTPUT_DIR="$OUTPUT_DIR" \
    "$REPO_ROOT/scripts/bundle.sh" >/dev/null

BIN="$APP_DIR/Contents/MacOS/$APP_NAME"

# Checked rather than trusted: `--arch` is silently ignored by some toolchain versions, and a
# thin binary looks identical from the outside. The failure would only show on someone else's
# Mac, which is the worst place to find it.
#
# The bundled Neovim is checked for the same reason and separately — it is fetched per
# architecture and `lipo`'d, so it can be thin while ours is fat.
check_universal() {  # <label> <mach-o path>
    local archs; archs="$(lipo -archs "$2")"
    for want in arm64 x86_64; do
        case " $archs " in
            *" $want "*) ;;
            *) echo "FAIL: $1 이 유니버설이 아니다 — $want 가 없다 (실제: $archs)" >&2; exit 1 ;;
        esac
    done
    echo "  $1: $archs" >&2
}
check_universal "앱 실행 파일" "$BIN"
check_universal "번들된 nvim" "$APP_DIR/Contents/Resources/nvim/bin/nvim"

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
