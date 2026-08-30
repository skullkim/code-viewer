#!/usr/bin/env bash
# Captures the running app's window, for comparing against the prototype screenshots.
#
# Uses CGWindowList rather than AppleScript: the latter needs accessibility permission and
# blocks on a system prompt when it is not granted.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP:-$REPO_ROOT/.build/CodeNavigator.app}"
OUT="${1:-$REPO_ROOT/_workspace/app-shots/main.png}"
OWNER="${OWNER:-CodeNavigator}"

# The pattern used to end the app. It must be the bundle's executable *path*, not the
# owner name: `pkill -f CodeNavigator` also matches `CodeNavigatorPackageTests`, so every
# screenshot killed whatever test run happened to be going — anyone's, not just this
# script's. That produced gate failures that died mid-test with no diagnosable cause.
APP_PROCESS_PATTERN="${APP_PROCESS_PATTERN:-$APP/Contents/MacOS/}"

mkdir -p "$(dirname "$OUT")"
open "$APP"

WINDOW_ID=""
for _ in $(seq 1 20); do
    WINDOW_ID="$(swift "$REPO_ROOT/scripts/window-id.swift" "$OWNER" 2>/dev/null)" && [ -n "$WINDOW_ID" ] && break
    /bin/sleep 0.5
done

if [ -z "$WINDOW_ID" ]; then
    echo "FAIL: $OWNER 창을 찾지 못했다" >&2
    pkill -f "$APP_PROCESS_PATTERN" 2>/dev/null
    exit 1
fi

/bin/sleep 1
screencapture -x -o -l"$WINDOW_ID" "$OUT"
pkill -f "$APP_PROCESS_PATTERN" 2>/dev/null
echo "$OUT"
