#!/usr/bin/env bash
# 조립된 .app 을 실제로 띄워 런타임 예산을 잰다 (REQ-NF-003 기동 ≤2초, SC-8 유휴 메모리 ≤150MB).
#
# 왜 따로 있나: 테스트 프로세스의 숫자는 .app 의 숫자가 아니다. `swift test` 안에서 잰 메모리는
# 테스트 러너와 다른 테스트들의 잔재를 함께 재고, 앱의 UI·프레임워크 비용은 아예 포함하지 않는다.
#
# 규율: 재기 전에 측정기부터 검사한다.
#   _workspace/measure-app-runtime.sh --self-test
# 죽은 측정기는 예산 안의 숫자를 영원히 돌려준다. BE-33 에서 실제로 그 일이 있었다.
#
# 사용법:
#   measure-app-runtime.sh              기동 시간 + 프로젝트 미개방 유휴 메모리
#   measure-app-runtime.sh --idle-only  이미 떠 있는 앱의 유휴 메모리만 (수동 SC-8 단계용)
#   measure-app-runtime.sh --self-test  측정기 자체 검사

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLICATION_BUNDLE="$REPO_ROOT/.build/CodeNavigator.app"
APPLICATION_BINARY="$APPLICATION_BUNDLE/Contents/MacOS/CodeNavigator"
WINDOW_OWNER_NAME="CodeNavigator"

# 요구사항의 숫자 그대로.
STARTUP_BUDGET_MILLISECONDS=2000
IDLE_MEMORY_BUDGET_MEGABYTES=150
# 창이 이 안에 안 뜨면 "느리다"가 아니라 "측정 불가"로 다룬다 — 화면 잠금 등 환경 문제일 수 있다.
WINDOW_WAIT_TIMEOUT_MILLISECONDS=15000

WINDOW_FINDER_BINARY=""
FAILURES=0
# 재지 못한 항목. 실패와 구분한다 — "예산을 넘었다"와 "재지 못했다"는 다른 결론이다.
UNMEASURED=0

section() { printf '\n=== %s ===\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf '  ok: %s\n' "$1"; }
note() { printf '  note: %s\n' "$1"; }
unmeasured() { printf '  UNMEASURED: %s\n' "$1"; UNMEASURED=$((UNMEASURED + 1)); }

now_milliseconds() { python3 -c 'import time; print(int(time.time() * 1000))'; }

resident_megabytes_of() {
    # ps 의 rss 는 KB 단위다. 프로세스가 사라졌으면 빈 문자열이 나온다.
    ps -o rss= -p "$1" 2>/dev/null | awk 'NF { printf "%.1f", $1 / 1024 }'
}

# 창 탐지는 프론트의 scripts/window-id.swift 를 그대로 쓴다. 같은 판정을 두 벌로 만들지 않는다.
# 폴링마다 `swift` 로 해석하면 한 번에 1초 넘게 걸려 밀리초 측정이 무의미해지므로 한 번만 컴파일한다.
build_window_finder() {
    # 자체 검사가 "창을 찾은" 경로를 실제로 통과시켜 보기 위한 주입점. 이게 없으면 성공 분기는
    # 화면이 잠긴 이 환경에서 한 번도 실행되지 않은 채 남고, 인증 시점에 처음 돌아간다.
    if [ -n "${CODE_NAVIGATOR_WINDOW_FINDER:-}" ]; then
        WINDOW_FINDER_BINARY="$CODE_NAVIGATOR_WINDOW_FINDER"
        return 0
    fi

    WINDOW_FINDER_BINARY="$(mktemp -d)/window-id"
    if ! swiftc -O "$REPO_ROOT/scripts/window-id.swift" -o "$WINDOW_FINDER_BINARY" 2>/dev/null; then
        WINDOW_FINDER_BINARY=""
        return 1
    fi
    return 0
}

application_window_is_on_screen() {
    [ -n "$WINDOW_FINDER_BINARY" ] && "$WINDOW_FINDER_BINARY" "$WINDOW_OWNER_NAME" >/dev/null 2>&1
}

terminate_running_application() {
    pkill -x "$WINDOW_OWNER_NAME" >/dev/null 2>&1
    return 0
}

# ---------------------------------------------------------------------------
# 측정기 자체 검사 — 알려진 값을 실제로 만들어 관측되는지 본다
# ---------------------------------------------------------------------------
self_test() {
    printf '=== 측정기 자체 검사 ===\n'
    local status=0

    # 1) 시계: 1초를 재면 1초로 나와야 한다.
    local before after elapsed
    before="$(now_milliseconds)"
    sleep 1
    after="$(now_milliseconds)"
    elapsed=$((after - before))
    if [ "$elapsed" -ge 900 ] && [ "$elapsed" -le 1400 ]; then
        printf '  ok: 시계가 1초를 %sms 로 잰다\n' "$elapsed"
    else
        printf '  FAIL: 1초를 %sms 로 쟀다 — 시계를 믿을 수 없다\n' "$elapsed"
        status=1
    fi

    # 2) 메모리 측정기: 200MB 를 실제로 만지는 프로세스를 재서 그만큼 관측되는지 본다.
    #    이게 죽어 있으면 150MB 예산은 무엇을 재든 통과한다.
    python3 -c 'import time; block = bytearray(200 * 1024 * 1024); block[::4096] = b"\x01" * len(block[::4096]); time.sleep(6)' &
    local probe_pid=$!
    sleep 2
    local probe_megabytes
    probe_megabytes="$(resident_megabytes_of "$probe_pid")"
    kill "$probe_pid" >/dev/null 2>&1
    wait "$probe_pid" 2>/dev/null

    if [ -z "$probe_megabytes" ]; then
        printf '  FAIL: 200MB 프로브의 메모리를 읽지 못했다\n'
        status=1
    elif [ "${probe_megabytes%%.*}" -ge 150 ]; then
        printf '  ok: 메모리 측정기가 200MB 프로브를 %sMB 로 잰다\n' "$probe_megabytes"
    else
        printf '  FAIL: 200MB 를 만졌는데 %sMB 로 쟀다 — 측정기가 죽어 있다\n' "$probe_megabytes"
        status=1
    fi

    # 3) 창 탐지기: 없는 소유자에게는 반드시 실패해야 한다(거짓 양성 차단).
    if build_window_finder; then
        if "$WINDOW_FINDER_BINARY" "NoSuchApplicationXyz" >/dev/null 2>&1; then
            printf '  FAIL: 존재하지 않는 앱의 창을 찾았다고 한다\n'
            status=1
        else
            printf '  ok: 창 탐지기가 없는 앱을 없다고 한다\n'
        fi
    else
        printf '  FAIL: 창 탐지기를 컴파일하지 못했다 (scripts/window-id.swift)\n'
        status=1
    fi

    # 4) 성공 분기 — 창을 찾았을 때 실제로 숫자가 나오고 PASS 로 끝나는지 끝까지 돌려 본다.
    #    실패 분기(INCOMPLETE)만 검증하면 정작 화면 해제 후 쓰는 경로가 미검증으로 남는다.
    local success_output
    success_output="$(CODE_NAVIGATOR_WINDOW_FINDER=/usr/bin/true bash "$REPO_ROOT/_workspace/measure-app-runtime.sh" 2>&1)"
    if printf '%s' "$success_output" | grep -qE '  ok: 기동 [0-9]+ms'; then
        printf '  ok: 창을 찾은 경우 기동 시간이 실제로 산출된다\n'
    else
        printf '  FAIL: 성공 분기가 기동 시간을 내놓지 못했다\n'
        status=1
    fi
    if printf '%s' "$success_output" | grep -q 'RESULT: PASS'; then
        printf '  ok: 성공 분기가 PASS 로 끝난다\n'
    else
        printf '  FAIL: 성공 분기가 PASS 로 끝나지 않는다\n'
        status=1
    fi

    return $status
}

# ---------------------------------------------------------------------------
# 유휴 메모리
# ---------------------------------------------------------------------------
measure_idle_memory_of_running_application() {
    local pid
    pid="$(pgrep -x "$WINDOW_OWNER_NAME" | head -1)"
    if [ -z "$pid" ]; then
        fail "실행 중인 $WINDOW_OWNER_NAME 프로세스가 없다"
        return
    fi

    local megabytes
    megabytes="$(resident_megabytes_of "$pid")"
    if [ -z "$megabytes" ]; then
        fail "메모리를 읽지 못했다 (pid $pid)"
        return
    fi

    if [ "${megabytes%%.*}" -gt "$IDLE_MEMORY_BUDGET_MEGABYTES" ]; then
        fail "유휴 메모리 ${megabytes}MB > 예산 ${IDLE_MEMORY_BUDGET_MEGABYTES}MB"
        return
    fi
    pass "유휴 메모리 ${megabytes}MB (예산 ${IDLE_MEMORY_BUDGET_MEGABYTES}MB, pid $pid)"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if [ "${1:-}" = "--idle-only" ]; then
    section "유휴 메모리 (이미 떠 있는 앱)"
    measure_idle_memory_of_running_application
    [ "$FAILURES" -eq 0 ] && exit 0
    exit 1
fi

# ---------------------------------------------------------------------------
# 기동 시간 (REQ-NF-003)
# ---------------------------------------------------------------------------
# "조작 가능"의 판정: **앱의 창이 화면에 올라온 시점**.
#
# 근거와 한계를 함께 남긴다.
#   - 요구사항은 "실행부터 조작 가능까지"이고 인덱싱은 배경이라고 못박았다. 그래서 프로젝트를
#     열거나 인덱싱이 끝나기를 기다리지 않는다 — 그걸 포함하면 요구사항이 아닌 걸 재게 된다.
#   - 창이 올라오기 전에는 사용자가 무엇도 누를 수 없으므로, 이 시점은 조작 가능의 **하한**이다.
#   - 반대로 창이 떴다고 메인 스레드가 즉시 입력을 받는다는 보장은 없다. 입력 수용 여부까지
#     재려면 접근성 권한이 필요하고 이 환경에는 없다. 따라서 이 값은 **낙관적일 수 있다** —
#     "이보다 빠를 수는 없다"는 의미로 읽어야 한다.
section "기동 시간 (REQ-NF-003)"

if [ -n "${CODE_NAVIGATOR_WINDOW_FINDER:-}" ]; then
    # 주입된 탐지기는 창을 보지 않는다. 이 모드의 숫자를 인증에 옮겨 적으면 안 된다.
    printf '  WARNING: 창 탐지기가 주입된 상태다 (CODE_NAVIGATOR_WINDOW_FINDER).\n'
    printf '  WARNING: 아래 기동 시간은 자체 검사용이며 실측이 아니다.\n'
fi

if [ ! -x "$APPLICATION_BINARY" ]; then
    fail "앱 번들이 없다: $APPLICATION_BUNDLE (scripts/bundle.sh 로 먼저 조립하라)"
    printf '\nRESULT: FAIL (%d)\n' "$FAILURES"
    exit 1
fi

if ! build_window_finder; then
    fail "창 탐지기를 컴파일하지 못했다 — 기동 시간을 잴 수 없다"
    printf '\nRESULT: FAIL (%d)\n' "$FAILURES"
    exit 1
fi

terminate_running_application
sleep 1

launch_milliseconds="$(now_milliseconds)"
"$APPLICATION_BINARY" >/dev/null 2>&1 &
application_pid=$!

window_milliseconds=""
while true; do
    if application_window_is_on_screen; then
        window_milliseconds="$(now_milliseconds)"
        break
    fi
    if ! kill -0 "$application_pid" 2>/dev/null; then
        fail "앱이 창을 띄우기 전에 종료됐다 (pid $application_pid)"
        break
    fi
    now="$(now_milliseconds)"
    if [ $((now - launch_milliseconds)) -gt "$WINDOW_WAIT_TIMEOUT_MILLISECONDS" ]; then
        break
    fi
done

if [ -n "$window_milliseconds" ]; then
    startup_milliseconds=$((window_milliseconds - launch_milliseconds))
    if [ "$startup_milliseconds" -gt "$STARTUP_BUDGET_MILLISECONDS" ]; then
        fail "기동 ${startup_milliseconds}ms > 예산 ${STARTUP_BUDGET_MILLISECONDS}ms"
    else
        pass "기동 ${startup_milliseconds}ms (창이 화면에 올라온 시점, 예산 ${STARTUP_BUDGET_MILLISECONDS}ms)"
    fi
elif [ "$FAILURES" -eq 0 ]; then
    # 창을 못 찾은 것은 느린 것과 다르다. 화면이 잠겨 있으면 창이 목록에 오르지 않을 수 있다.
    unmeasured "기동 시간 — 창을 ${WINDOW_WAIT_TIMEOUT_MILLISECONDS}ms 안에 찾지 못했다"
    note "화면 잠금 상태에서는 창이 CGWindowList 에 오르지 않을 수 있다. 화면을 해제하고 다시 돌려라."
fi

# ---------------------------------------------------------------------------
# 유휴 메모리 — 프로젝트를 열지 않은 상태
# ---------------------------------------------------------------------------
# 이것은 SC-8 이 아니다. SC-8 은 "중형 레포 인덱싱 후"의 값이고, 앱에는 프로젝트를 비대화식으로
# 여는 경로가 없어(실측: argv·URL 핸들러·자동 복원 모두 없음) 화면 없이 그 상태를 만들 수 없다.
# 아래는 그 값의 **기준선**이며, SC-8 판정에 쓰면 안 된다.
section "유휴 메모리 — 프로젝트 미개방 기준선 (SC-8 아님)"
sleep 2
measure_idle_memory_of_running_application
note "SC-8 판정은 수동 단계가 필요하다: 화면 해제 → 앱에서 중형 레포 열기 → 인덱싱 완료 대기 →"
note "  _workspace/measure-app-runtime.sh --idle-only"

kill "$application_pid" >/dev/null 2>&1
wait "$application_pid" 2>/dev/null
terminate_running_application

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
    printf 'RESULT: FAIL (%d)\n' "$FAILURES"
    exit 1
fi
if [ "$UNMEASURED" -gt 0 ]; then
    # 재지 못한 항목이 있으면 PASS 가 아니다. 통과로 읽히면 인증에서 "쟀다"로 굳는다.
    printf 'RESULT: INCOMPLETE (%d 항목 측정 불가) — 통과로 취급하지 마라\n' "$UNMEASURED"
    exit 2
fi
printf 'RESULT: PASS\n'
exit 0
