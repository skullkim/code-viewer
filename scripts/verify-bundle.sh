#!/usr/bin/env bash
# Checks that the assembled bundle actually runs (REQ-011 AC-1).
#
# A .app directory existing is not evidence that anything works. This launches it and
# requires the process to report its bundle identity back, so the gate step measures
# behaviour rather than the presence of a folder.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-CodeNavigator}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-CodeNavigator}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.build}"
EXPECTED_IDENTIFIER="${EXPECTED_IDENTIFIER:-dev.local.code-navigator-mac}"

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
BINARY="$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

# The self-test moves the binary aside to prove it notices its absence. Interrupted between
# the two moves, it would leave the bundle permanently broken — and every later run would
# fail with "실행 파일이 없다", which reads like a build problem rather than a leftover.
# Restoration has to hold on every exit path, not just the happy one.
restore_binary() {
    if [ -e "$BINARY.selftest-backup" ]; then
        mv "$BINARY.selftest-backup" "$BINARY"
    fi
}
trap restore_binary EXIT INT TERM

# ---------------------------------------------------------------------------
# 검사기 자체 검사 — 잡아야 할 것을 심어 보고, 치운 뒤 깨끗한지 본다.
#
# 이 스크립트는 게이트 스텝이다. 게이트 스텝이 아무것도 잡지 못하는 상태는 초록불과
# 구분되지 않으므로, 통과만 확인하는 것은 절반이다.
# ---------------------------------------------------------------------------
self_test() {
    local status=0
    printf '=== verify-bundle 자체 검사 ===\n'

    if [ ! -x "$BINARY" ]; then
        printf '  SKIP: 검사할 번들이 없다 — 먼저 scripts/bundle.sh 를 실행하라\n'
        return 1
    fi

    # 1) 식별자가 다르면 반드시 실패해야 한다.
    if EXPECTED_IDENTIFIER="dev.local.definitely-not-this" "$0" >/dev/null 2>&1; then
        printf '  FAIL: 틀린 식별자인데 통과했다\n'
        status=1
    else
        printf '  ok: 틀린 식별자를 잡는다\n'
    fi

    # 2) 실행 파일이 사라지면 반드시 실패해야 한다.
    mv "$BINARY" "$BINARY.selftest-backup"
    if "$0" >/dev/null 2>&1; then
        printf '  FAIL: 실행 파일이 없는데 통과했다\n'
        status=1
    else
        printf '  ok: 실행 파일 부재를 잡는다\n'
    fi
    restore_binary

    # 3) 되돌린 뒤에는 깨끗하게 통과해야 한다 (오탐 없음).
    if "$0" >/dev/null 2>&1; then
        printf '  ok: 정상 번들은 통과한다 (오탐 없음)\n'
    else
        printf '  FAIL: 정상인데 실패한다 — 오탐이다\n'
        status=1
    fi

    if [ -e "$BINARY.selftest-backup" ]; then
        printf '  FAIL: 백업 파일이 남았다 — 번들이 깨진 채로 끝났다\n'
        status=1
    else
        printf '  ok: 번들 원상 복구 확인\n'
    fi

    return $status
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if [ ! -x "$BINARY" ]; then
    echo "FAIL: 번들 실행 파일이 없다: $BINARY" >&2
    exit 1
fi

# --self-check makes the app report its bundle identity and exit, so the gate does not
# depend on a window server session being available.
OUTPUT="$("$BINARY" --self-check 2>&1)" || {
    echo "FAIL: --self-check 실행이 실패했다" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
}

if ! printf '%s' "$OUTPUT" | grep -q "bundleIdentifier=$EXPECTED_IDENTIFIER"; then
    echo "FAIL: 번들 식별자를 확인하지 못했다 (기대: $EXPECTED_IDENTIFIER)" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

# 번들이 뜨는 것만으로는 창이 성립한다는 증거가 안 된다. --self-check 는 실제 객체 그래프로
# 루트 뷰를 만들고 레이아웃을 한 번 돌린 뒤 결과를 보고한다.
if ! printf '%s' "$OUTPUT" | grep -q "rootView=laidOut"; then
    echo "FAIL: 루트 뷰가 레이아웃되지 않았다 — 바이너리는 떴지만 창이 성립하지 않는다" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

# 메뉴 막대가 ⌘ 조합을 claim 하는 주체다(ADR-0102). 없이 출하되면 ⌘O·⌘P 가 Neovim 으로
# 새어 나가는데, 그건 실행해 보기 전에는 드러나지 않는다.
MENU_COUNT="$(printf '%s' "$OUTPUT" | sed -n 's/.*menus=\([0-9][0-9]*\).*/\1/p')"
if [ -z "$MENU_COUNT" ] || [ "$MENU_COUNT" -lt 6 ]; then
    echo "FAIL: 메뉴 막대가 설치되지 않았다 (menus=$MENU_COUNT) — ⌘ 조합이 Neovim 으로 샌다" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

SUBVIEW_COUNT="$(printf '%s' "$OUTPUT" | sed -n 's/.*subviews=\([0-9][0-9]*\).*/\1/p')"
if [ -z "$SUBVIEW_COUNT" ] || [ "$SUBVIEW_COUNT" -lt 1 ]; then
    echo "FAIL: 루트 뷰가 아무것도 그리지 않았다 (subviews=$SUBVIEW_COUNT)" >&2
    exit 1
fi

printf 'ok: %s\n' "$OUTPUT"
