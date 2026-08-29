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
    mv "$BINARY.selftest-backup" "$BINARY"

    # 3) 되돌린 뒤에는 깨끗하게 통과해야 한다 (오탐 없음).
    if "$0" >/dev/null 2>&1; then
        printf '  ok: 정상 번들은 통과한다 (오탐 없음)\n'
    else
        printf '  FAIL: 정상인데 실패한다 — 오탐이다\n'
        status=1
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

printf 'ok: %s\n' "$OUTPUT"
