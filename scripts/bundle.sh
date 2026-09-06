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

# Release cuts need both architectures; a developer loop does not, and paying for the second one
# on every build is minutes nobody gets back. `package-dmg.sh` turns this on rather than
# assembling a bundle of its own — two assembly paths mean the next resource added to one of them
# is missing from the other, which is exactly how the published DMG ended up with no tree-sitter
# parsers and no icon while the local bundle had both.
# 빈 배열을 `"${a[@]}"` 로 펼치면 macOS 기본 bash(3.2)는 `set -u` 아래에서 unbound 로 죽는다.
# 유니버설 경로는 배열이 안 비어서 멀쩡하고 평소 빌드만 깨지는데, 그 조합이 제일 늦게
# 발각된다 — 릴리스는 되는데 개발 빌드가 안 되는 형태다. 그래서 인자를 문자열로 둔다.
UNIVERSAL="${UNIVERSAL:-0}"
ARCH_FLAGS=""
if [ "$UNIVERSAL" = "1" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

echo "building $EXECUTABLE_NAME ($CONFIGURATION${ARCH_FLAGS:+, universal})…"
# shellcheck disable=SC2086  # 분리되어야 하는 인자다
swift build --package-path "$PACKAGE_PATH" -c "$CONFIGURATION" $ARCH_FLAGS --product "$EXECUTABLE_NAME" >&2

# shellcheck disable=SC2086
BIN_PATH="$(swift build --package-path "$PACKAGE_PATH" -c "$CONFIGURATION" $ARCH_FLAGS --show-bin-path)"
if [ ! -x "$BIN_PATH/$EXECUTABLE_NAME" ]; then
    echo "FAIL: 빌드 산출물이 없다: $BIN_PATH/$EXECUTABLE_NAME" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# 아이콘. 없으면 Dock 에 기본 아이콘이 뜨는데, 그건 "빌드 실패" 처럼 안 보이고
# "아직 안 만들었나 보다" 처럼 보여서 아무도 신고하지 않는다.
ICON_SOURCE="$REPO_ROOT/Resources/AppIcon.icns"
if [ ! -f "$ICON_SOURCE" ]; then
    echo "FAIL: $ICON_SOURCE 가 없다 — scripts/build-app-icon.sh 를 먼저 돌려라" >&2
    exit 1
fi
cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"

# The tree-sitter parsers the embedded Neovim loads. Checked rather than copied blindly: without
# them Neovim falls back to regex syntax files, and that failure shows up as "this language has
# no highlighting" rather than as a missing file.
TREESITTER_SOURCE="$REPO_ROOT/Resources/treesitter"
if [ ! -d "$TREESITTER_SOURCE/parser" ]; then
    echo "FAIL: $TREESITTER_SOURCE/parser 가 없다 — scripts/build-treesitter-parsers.sh 를 먼저 돌려라" >&2
    exit 1
fi
cp -R "$TREESITTER_SOURCE" "$APP_DIR/Contents/Resources/treesitter"

# Neovim itself. This is what makes installing the app the whole installation — before it, a Mac
# without Neovim showed an empty editor pane and a start-up message, which reads as a broken app
# rather than as a missing prerequisite.
#
# The layout inside `Resources/nvim` is load-bearing: Neovim locates its runtime relative to its
# own executable, so `bin/nvim` must keep `share/nvim/runtime` as its sibling's child.
NVIM_SOURCE="$REPO_ROOT/Resources/nvim"
if [ ! -x "$NVIM_SOURCE/bin/nvim" ]; then
    echo "FAIL: $NVIM_SOURCE/bin/nvim 이 없다 — scripts/vendor-neovim.sh 를 먼저 실행하라" >&2
    exit 1
fi
cp -Rc "$NVIM_SOURCE" "$APP_DIR/Contents/Resources/nvim" 2>/dev/null \
    || cp -R "$NVIM_SOURCE" "$APP_DIR/Contents/Resources/nvim"

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
