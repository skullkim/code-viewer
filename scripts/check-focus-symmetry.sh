#!/usr/bin/env bash
# Every surface that gives the keyboard back must also be able to take it.
#
# D-11 survived a fix twice because of this asymmetry. First the modal set
# `isQueryFocused` on appear and the search panel did not. Then the decision moved into a
# coordinator — and the modal got an open path while the panel got only a close path, so
# the panel's field could never be told it had the keyboard and typing went to the editor.
#
# Unit tests cannot see this: the coordinator answers correctly when asked, and the missing
# call means nobody asks. Measured — deleting the panel's `.onAppear` leaves all 12
# coordinator tests green. So the check is on the wiring, where the defect actually lives.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Script-scoped, not local to the self-test: the EXIT trap fires after the function has
# returned, and a local would be out of scope by then — which under `set -u` turns cleanup
# into its own error. Learned this once already in check-view-mounts.sh.
SELF_TEST_SANDBOX=""
cleanup_sandbox() {
    if [ -n "$SELF_TEST_SANDBOX" ]; then
        rm -rf "$SELF_TEST_SANDBOX"
        SELF_TEST_SANDBOX=""
    fi
}
trap cleanup_sandbox EXIT INT TERM
SOURCES="${FOCUS_SOURCES_DIR:-$REPO_ROOT/Sources}"
FAILURES=0

surfaces_for() {
    grep -rhoE "surfaceDid$1\(\.[A-Za-z0-9_]+\)" "$SOURCES" --include="*.swift" \
        | sed -E "s/surfaceDid$1\(\.([A-Za-z0-9_]+)\)/\1/" \
        | sort -u
}

check_symmetry() {
    local opened closed surface
    opened="$(surfaces_for Open)"
    closed="$(surfaces_for Close)"

    for surface in $closed; do
        if ! printf '%s\n' $opened | grep -qx "$surface"; then
            printf '  FAIL: %s 는 닫히는 경로만 있고 열리는 경로가 없다 — 그 표면은 키보드를 가질 수 없다\n' "$surface"
            FAILURES=$((FAILURES + 1))
        fi
    done
    for surface in $opened; do
        if ! printf '%s\n' $closed | grep -qx "$surface"; then
            printf '  FAIL: %s 는 열리는 경로만 있고 닫히는 경로가 없다 — 사라진 표면이 키보드를 붙든다\n' "$surface"
            FAILURES=$((FAILURES + 1))
        fi
    done

    local count
    count="$(printf '%s\n' $opened | grep -c . || true)"
    # A check that finds nothing to check is not a passing check. The discovery pattern is
    # the part most likely to rot, and its silence reads exactly like success.
    if [ "$count" -eq 0 ]; then
        printf '  FAIL: 포커스 표면을 하나도 못 찾았다 — 검사 대상이 없으면 통과가 아니다\n'
        FAILURES=$((FAILURES + 1))
    fi
    printf '  검사한 표면: %s개\n' "$count"
}

self_test() {
    local status=0
    SELF_TEST_SANDBOX="$(mktemp -d)"
    local sandbox="$SELF_TEST_SANDBOX"
    mkdir -p "$sandbox/View"

    printf '=== check-focus-symmetry 자체 검사 ===\n'

    # 대칭인 트리는 통과해야 한다 — 이게 없으면 "항상 실패하는 검사기"가 아래를 다 통과한다.
    printf 'focus.surfaceDidOpen(.paired)\nfocus.surfaceDidClose(.paired)\n' > "$sandbox/View/A.swift"
    if FOCUS_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  ok: 통과 — 열림·닫힘이 짝지어진 트리\n'
    else
        printf '  FAIL: 대칭인데도 실패한다 — 항상 실패하는 검사기다\n'
        status=1
    fi

    # 닫힘만 있는 표면 — D-11 이 정확히 이 모양이었다.
    printf 'focus.surfaceDidOpen(.paired)\nfocus.surfaceDidClose(.paired)\nfocus.surfaceDidClose(.orphan)\n' > "$sandbox/View/A.swift"
    if FOCUS_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  FAIL: 닫힘만 있는 표면을 못 잡는다 (D-11 형태)\n'
        status=1
    else
        printf '  ok: 검출 — 닫힘만 있는 표면\n'
    fi

    # 열림만 있는 표면 — 반대 방향도 결함이다.
    printf 'focus.surfaceDidOpen(.paired)\nfocus.surfaceDidClose(.paired)\nfocus.surfaceDidOpen(.stuck)\n' > "$sandbox/View/A.swift"
    if FOCUS_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  FAIL: 열림만 있는 표면을 못 잡는다\n'
        status=1
    else
        printf '  ok: 검출 — 열림만 있는 표면\n'
    fi

    # 아무것도 없는 트리는 통과가 아니다.
    printf 'let x = 1\n' > "$sandbox/View/A.swift"
    if FOCUS_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  FAIL: 표면이 0개인데 통과했다 — 침묵을 성공으로 읽는다\n'
        status=1
    else
        printf '  ok: 검출 — 검사 대상 0개\n'
    fi

    return $status
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

check_symmetry
if [ "$FAILURES" -eq 0 ]; then
    printf '  ok: 모든 포커스 표면이 열림·닫힘 짝을 갖는다\n'
    exit 0
fi
exit 1
