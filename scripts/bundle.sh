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

# macOS reads these strings aloud when it asks the user for access. Without them the dialog
# cannot say why, and a user deciding blind tends to deny.
#
# Checked rather than trusted, because losing one is silent: the app still builds, still
# launches, and only a sentence in a dialog nobody on the team sees goes missing. That dialog
# was D-7 — while it sat waiting for an answer the app reported `Neovim 이 응답하지 않습니다`,
# and a day went into suspecting Neovim.
for usage_key in NSDocumentsFolderUsageDescription NSDesktopFolderUsageDescription NSDownloadsFolderUsageDescription; do
    if ! /usr/libexec/PlistBuddy -c "Print :$usage_key" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1; then
        echo "FAIL: Info.plist에 $usage_key 가 없다 — 권한 대화상자가 이유를 설명하지 못한다" >&2
        exit 1
    fi
done

# Keeps every build, because `.build/CodeNavigator.app` is one path and each build overwrites it.
#
# That cost us a fallback: the plan for a bad change was "revert to the last known-good bundle",
# and when we went to use it there was none — three builds had passed over the same path while
# QA was still measuring the first. A revert plan with no control group is not a plan.
#
# Copies are clones (`cp -Rc`), so they cost almost nothing on APFS until the source changes.
ARCHIVE_DIR="$OUTPUT_DIR/bundles"
mkdir -p "$ARCHIVE_DIR"
BUILD_STAMP="$(stat -f '%Sm' -t '%Y%m%d-%H%M%S' "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME")"
ARCHIVED="$ARCHIVE_DIR/$APP_NAME-$BUILD_STAMP.app"
if [ ! -d "$ARCHIVED" ]; then
    cp -Rc "$APP_DIR" "$ARCHIVED" 2>/dev/null || cp -R "$APP_DIR" "$ARCHIVED"
fi

# Records what the build was made from, because a bundle cannot be identified after the fact.
#
# The tree moves while this script runs. Measured: a check said "two untracked files, nothing
# wired" and twenty-two seconds later the build had swept a half-finished feature that had been
# wired in between — the check and the build were not one action. Someone then measured that
# bundle believing it was HEAD.
#
# So the answer is not to forbid building on a dirty tree (the gate does it every run, and
# in-progress work is normal here). It is to make every bundle say what it contains.
MANIFEST="$ARCHIVED.manifest.txt"
{
    echo "built:     $(date '+%F %T')"
    echo "HEAD:      $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'not a repo')"
    echo "clean:     $([ -z "$(git -C "$REPO_ROOT" status --porcelain -- Sources Tests 2>/dev/null)" ] && echo yes || echo 'NO — 아래 파일이 HEAD 와 다르다')"
    git -C "$REPO_ROOT" status --porcelain -- Sources Tests 2>/dev/null | sed 's/^/  /'
} > "$MANIFEST"

echo "보존: $ARCHIVED" >&2
if grep -q '^clean:     NO' "$MANIFEST"; then
    echo "⚠ 이 번들은 HEAD 가 아니다 — 미커밋 소스가 들어갔다. $MANIFEST 를 보고 판정하라." >&2
fi

echo "$APP_DIR"
