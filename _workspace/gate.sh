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
# 실행 테스트 수 하한 (0매치 초록불 방어)
# ---------------------------------------------------------------------------
# swift test 는 --filter 가 아무것도 매칭하지 않아도 "0 tests passed" 를 찍고 종료 코드 0 을 낸다.
# 실측: `swift test --filter ThisSuiteDoesNotExistXyz` -> "Test run with 0 tests in 0 suites passed", exit 0.
# 통과 문구나 종료 코드만 보는 게이트는 오타 난 필터를 초록불로 통과시킨다. 그래서 건수를 직접 센다.
#
# 이 값은 래칫이다. 테스트가 늘면 올려라. 내리는 것은 테스트를 의도적으로 지웠을 때만이고,
# 그때는 왜 줄었는지 저널에 남긴다.
MINIMUM_TEST_COUNT=240

test_count_from() {
    printf '%s\n' "$1" | sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p' | tail -1
}

check_test_count() {
    local count
    count="$(test_count_from "$1")"

    if [ -z "$count" ]; then
        fail "실행 테스트 수를 읽지 못했다 — 테스트가 아예 돌지 않았거나 출력 형식이 바뀌었다"
        return
    fi
    if [ "$count" -lt "$MINIMUM_TEST_COUNT" ]; then
        fail "실행 테스트 ${count}건 < 하한 ${MINIMUM_TEST_COUNT}건 — 필터나 타깃이 테스트를 걸러내고 있다"
        return
    fi
    pass "실행 테스트 ${count}건 (하한 ${MINIMUM_TEST_COUNT}건)"
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
    printf '=== 검사기 자체 검사 (리크 픽스처 + 건수 하한, 양방향) ===\n'
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

    # 3) 건수 하한 가드도 양방향으로 검사한다. 검사기는 조용히 통과하는 쪽으로 고장난다.
    local -a count_probes=(
        "0|✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.|잡아야 한다"
        "1|error: build failed — 건수 줄 없음|잡아야 한다"
    )
    local probe_case
    for probe_case in "${count_probes[@]}"; do
        FAILURES=0
        check_test_count "${probe_case#*|}" >/dev/null 2>&1
        if [ "$FAILURES" -gt 0 ]; then
            printf '  ok: 건수 가드가 잡는다 — %s\n' "${probe_case##*|}"
        else
            printf '  FAIL: 건수 가드가 통과시켰다 — %s\n' "${probe_case#*|}"
            status=1
        fi
    done

    FAILURES=0
    check_test_count "✔ Test run with $MINIMUM_TEST_COUNT tests in 30 suites passed after 4.0 seconds." >/dev/null 2>&1
    if [ "$FAILURES" -eq 0 ]; then
        printf '  ok: 하한 이상 실행은 통과시킨다 (오탐 없음)\n'
    else
        printf '  FAIL: 정상 실행을 실패로 잡는다 — 오탐이다\n'
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
# 출력을 잡아 두고 통과 여부와 실행 건수 양쪽에 쓴다 — 테스트를 두 번 돌리지 않는다.
#
# --no-parallel 인 이유: 다섯 스위트가 각자 실제 Neovim 프로세스를 띄운다. 병렬로 돌리면
# 동시에 뜬 nvim 들이 서로를 밀어내 마우스 입력이 받아들여지기까지의 시간이 들쭉날쭉해지고,
# 같은 코드가 부하에 따라 통과하기도 실패하기도 한다(실측: 병렬 5회 중 3회 실패, 직렬 3회
# 전부 통과). 무거운 공유 런타임은 단일 러너로 돌린다는 규율의 적용이다. 비용은 7초 -> 20초.
TEST_OUTPUT="$(swift test --no-parallel 2>&1)"
TEST_STATUS=$?
printf '%s\n' "$TEST_OUTPUT" | tail -5
if [ "$TEST_STATUS" -eq 0 ]; then
    pass "swift test"
else
    fail "swift test"
fi

section "백엔드: 실행 테스트 수"
check_test_count "$TEST_OUTPUT"

# ---------------------------------------------------------------------------
# 프론트엔드 (앱 셸)
# ---------------------------------------------------------------------------
# swift build / swift test 는 위 백엔드 블록이 패키지 전체를 대상으로 이미 돌린다.
# 여기서는 중복하지 않고, 백엔드가 검증하지 않는 것만 본다: .app 으로 조립되는지,
# 그리고 조립된 것이 실제로 실행되는지. 디렉토리가 생겼다는 것은 동작의 증거가 아니다.

section "프론트엔드: .app 조립"
if "$REPO_ROOT/scripts/bundle.sh" >/dev/null 2>&1; then
    pass "scripts/bundle.sh"
else
    fail "scripts/bundle.sh — .app 조립 실패"
fi

section "프론트엔드: 번들 실행 검증"
if BUNDLE_OUTPUT="$("$REPO_ROOT/scripts/verify-bundle.sh" 2>&1)"; then
    pass "scripts/verify-bundle.sh — $BUNDLE_OUTPUT"
else
    fail "scripts/verify-bundle.sh — 조립된 앱이 실행되지 않는다"
    printf '%s\n' "$BUNDLE_OUTPUT" | sed 's/^/    /'
fi

section "프론트엔드: 번들 검사기 자체 검사"
if "$REPO_ROOT/scripts/verify-bundle.sh" --self-test >/dev/null 2>&1; then
    pass "verify-bundle --self-test (틀린 식별자·실행 파일 부재를 실제로 잡는다)"
else
    fail "verify-bundle --self-test — 검사기가 잡아야 할 것을 못 잡는다"
fi

section "공통: 민감정보 스캔"
secret_scan

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'GATE: PASS\n'
    exit 0
fi
printf 'GATE: FAIL (%d)\n' "$FAILURES"
exit 1
