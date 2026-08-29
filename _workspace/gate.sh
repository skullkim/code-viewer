#!/usr/bin/env bash
# 게이트: 이 스크립트가 exit 0 이어야 인계·완료 주장이 가능하다.
#
# 규율: 이 파일을 수정할 때마다 "검사기 자체를 검사"한다.
#   _workspace/gate.sh --self-test
# 시크릿 스캔은 조용히 실패하는 종류의 방어선이라, 통과만 확인하는 것은 절반이다.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILURES=0
SECTION=""

section() {
    SECTION="$1"
    printf '\n=== %s ===\n' "$SECTION"
}

fail() {
    printf '  FAIL: %s\n' "$1"
    FAILURES=$((FAILURES + 1))
}

pass() {
    printf '  ok: %s\n' "$1"
}

# ---------------------------------------------------------------------------
# 민감정보 스캔 (공통)
# ---------------------------------------------------------------------------
# 검사 대상 파일 목록은 find 로 만든다. grep 의 --include 에 중괄호 glob 을 주면
# 셸이 아니라 grep 인자로 넘어가 확장되지 않고, 검사 대상이 0건이 되어도 exit 0 이 난다.
scan_targets() {
    find . \
        -path ./.build -prune -o \
        -path ./.git -prune -o \
        -path ./.swiftpm -prune -o \
        -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.json' -o -name '*.plist' \
                   -o -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) -print
}

SECRET_PATTERNS='(aws_secret_access_key|aws_access_key_id|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{30,}|sk-[0-9A-Za-z]{32,})'
# 이름=값 형태의 자격증명. 값이 플레이스홀더('', "", <...>, YOUR_, xxx, $VAR, env 참조)면 제외한다.
CREDENTIAL_PATTERNS='(api_?key|secret|passwd|password|access_?token|private_?key)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$<{[:space:]]{8,}'

secret_scan() {
    local files
    files="$(scan_targets)"
    if [ -z "$files" ]; then
        fail "스캔 대상 파일이 0건이다 — 검사기가 아무것도 보고 있지 않다"
        return
    fi

    local hits
    # -I 는 바이너리 제외, -n 은 줄번호, -E 확장정규식, -i 대소문자 무시(camelCase apiKey 를 놓치지 않게).
    hits="$(printf '%s\n' "$files" | tr '\n' '\0' \
        | xargs -0 grep -HInE -i -e "$SECRET_PATTERNS" -e "$CREDENTIAL_PATTERNS" 2>/dev/null \
        | grep -vE 'gate\.sh:' \
        | grep -vE 'SECRET_PATTERNS|CREDENTIAL_PATTERNS')"

    if [ -n "$hits" ]; then
        fail "민감정보로 보이는 문자열 발견"
        printf '%s\n' "$hits" | sed 's/^/    /'
    else
        pass "민감정보 스캔 (대상 $(printf '%s\n' "$files" | wc -l | tr -d ' ')건)"
    fi
}

# ---------------------------------------------------------------------------
# 검사기 자체 검사 — 리크 픽스처로 양방향 실측
# ---------------------------------------------------------------------------
self_test() {
    printf '=== 검사기 자체 검사 (리크 픽스처 양방향) ===\n'
    local fixture="./_gate_leak_fixture.swift"
    local status=0

    # 1) 잡아야 할 것을 심고 -> 검출되어야 한다
    # 패턴 갈래마다 하나씩 심는다. 하나로 뭉뚱그리면 한 갈래가 죽어도 통과한다.
    local -a probes=(
        'let awsKey = "AKIAIOSFODNN7EXAMPLE"'
        'let token = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"'
        'let apiKey = "abcdefghijklmnop"'
    )
    local probe
    for probe in "${probes[@]}"; do
        printf '%s\n' "$probe" > "$fixture"
        FAILURES=0
        secret_scan >/dev/null 2>&1
        if [ "$FAILURES" -gt 0 ]; then
            printf '  ok: 검출 — %s\n' "${probe:0:40}"
        else
            printf '  FAIL: 심었는데 검출 못함 — %s\n' "$probe"
            status=1
        fi
    done

    # 2) 치우고 -> 깨끗해야 한다
    rm -f "$fixture"
    FAILURES=0
    secret_scan >/dev/null 2>&1
    if [ "$FAILURES" -eq 0 ]; then
        printf '  ok: 픽스처 제거 후 깨끗하다 (오탐 없음 확인)\n'
    else
        printf '  FAIL: 픽스처를 지웠는데도 검출된다 — 오탐이다\n'
        status=1
    fi

    rm -f "$fixture"
    return $status
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

# ---------------------------------------------------------------------------
# 백엔드 (코어 엔진)
# ---------------------------------------------------------------------------
section "백엔드: swift build"
if swift build 2>&1 | tail -3; then
    pass "swift build"
else
    fail "swift build"
fi

section "백엔드: swift test"
if swift test 2>&1 | tail -5; then
    pass "swift test"
else
    fail "swift test"
fi

# ---------------------------------------------------------------------------
# 프론트엔드 블록은 frontend-senior 가 이 아래에 추가한다.
# ---------------------------------------------------------------------------

section "공통: 민감정보 스캔"
secret_scan

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'GATE: PASS\n'
    exit 0
fi
printf 'GATE: FAIL (%d)\n' "$FAILURES"
exit 1
