#!/usr/bin/env bash
# ⌘Q 로 종료했을 때 자식 nvim 이 남는가 (D-20 · D-2).
#
# 왜 따로 있나: `pgrep -f 'nvim --embed'` 를 그냥 세면 **다른 사람이 띄워 둔 앱의 nvim 까지
# 센다.** QA 가 앱을 잡고 있는 동안 그 숫자는 절대 0 이 되지 않고, 그러면 "고아 없음"을
# 영원히 증명할 수 없다. 그래서 **우리가 띄운 앱의 자식**만 세고, 종료 뒤 그 pid 들이
# 사라졌는지 + 고아(부모 1)로 갈아탔는지를 본다.
#
# 규율: 재기 전에 측정기부터 검사한다.
#   _workspace/measure-quit-orphans.sh --self-test
# 죽은 측정기는 "고아 0" 을 영원히 돌려준다 — 그게 이 결함의 원래 모양이다.
#
# 사용법:
#   measure-quit-orphans.sh <경로.app>     띄우고 → 종료하고 → 남은 자식을 센다
#   measure-quit-orphans.sh --self-test    측정기 자체 검사
set -uo pipefail

FAILURES=0
pass() { printf '  ok: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
note() { printf '  note: %s\n' "$1"; }

# 한 프로세스의 자식 nvim pid 들. macOS `pgrep` 에는 `-c` 가 없다 — 쓰면 usage 를 뱉고
# 호출한 쪽은 그것을 0 으로 읽는다(리더가 실제로 밟았다). 세는 것은 `wc -l` 이 한다.
children_of() {
    local parent="$1"
    pgrep -f 'nvim --embed' | while read -r pid; do
        [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$parent" ] && echo "$pid"
    done
}

# 부모가 1 인 nvim — 부모가 죽고 launchd 가 물려받은 것. 이것이 고아다.
orphans() {
    pgrep -f 'nvim --embed' | while read -r pid; do
        [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "1" ] && echo "$pid"
    done
}

self_test() {
    printf '=== measure-quit-orphans 자체 검사 ===\n'

    # 1. 세는 명령이 살아 있는 프로세스를 실제로 잡는가. 이걸 안 보면 뒤의 0 이
    #    "없음"인지 "명령이 못 잡음"인지 갈리지 않는다.
    sleep 30 &
    local probe=$!
    local seen
    seen=$(pgrep -f "sleep 30" | grep -c "^${probe}$")
    if [ "$seen" -eq 1 ]; then
        pass "pgrep 이 살아 있는 프로세스를 잡는다"
    else
        fail "pgrep 이 방금 띄운 프로세스를 못 잡는다 — 이 측정기는 무엇도 증명 못 한다"
    fi

    # 2. 부모 판별이 실제로 부모를 가르는가.
    local parent_of_probe
    parent_of_probe=$(ps -o ppid= -p "$probe" 2>/dev/null | tr -d ' ')
    if [ "$parent_of_probe" = "$$" ]; then
        pass "부모 판별이 맞다 (probe 의 부모 = 이 셸)"
    else
        fail "부모 판별이 틀렸다: $parent_of_probe ≠ $$"
    fi
    kill "$probe" 2>/dev/null

    # 3. 죽은 뒤에는 안 잡히는가 — 잡히면 이 측정기는 항상 "남아 있다"고 말한다.
    wait "$probe" 2>/dev/null
    if [ -z "$(pgrep -f 'sleep 30' | grep "^${probe}$")" ]; then
        pass "죽은 프로세스는 안 잡힌다 (오탐 없음)"
    else
        fail "죽은 프로세스를 아직 잡는다"
    fi

    # 4. `pgrep -c` 함정이 이 기계에 실재하는지 기록한다.
    if pgrep -c -f 'nvim --embed' >/dev/null 2>&1; then
        note "이 기계의 pgrep 은 -c 를 받는다"
    else
        pass "pgrep -c 는 이 기계에서 실패한다 — wc -l 로 세는 이유"
    fi

    return $FAILURES
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

BUNDLE="${1:-}"
if [ -z "$BUNDLE" ] || [ ! -d "$BUNDLE" ]; then
    printf '사용법: %s <경로.app>\n' "$0" >&2
    exit 2
fi

printf '=== 종료 후 고아 측정 ===\n'
note "다른 앱 인스턴스의 nvim: $(pgrep -f 'nvim --embed' | wc -l | tr -d ' ')건 (우리 것과 섞이지 않게 부모로 가른다)"
# 0단계. **측정 전에 이미 있던 고아를 세어 둔다.**
# 없으면 남의 옛 고아가 우리 결과에 섞여 "⌘Q 가 고아를 남긴다"로 오독된다 — QA 측정에서
# 실제로 그럴 뻔했다(옛 번들의 2시간짜리 고아 1건). 양성 대조는 그때도 통과하므로
# **이 단계가 없으면 그 오독을 막을 방법이 없다.**
BEFORE_ORPHANS=$(orphans | sort | tr '\n' ' ')
if [ -n "$(printf '%s' "$BEFORE_ORPHANS" | tr -d ' ')" ]; then
    note "측정 전 고아 ${BEFORE_ORPHANS}— 남의 것이다. 우리 결과에서 뺀다"
    note "  (치우고 재는 쪽이 더 깨끗하다: kill -9 위 pid)"
else
    pass "측정 전 고아 0 — 기준선이 깨끗하다"
fi

# 실행 파일 **이름**으로 찾는다. 경로 패턴(`-f`)으로 찾으면 보존본 이름이
# `CodeNavigator-20260831-180216.app` 처럼 붙을 때 `CodeNavigator.app/...` 에 안 걸린다 —
# QA 와 리더가 각각 그걸 밟았다. 번들 이름은 바뀌지만 실행 파일 이름은 안 바뀐다.
EXECUTABLE_NAME=$(basename "$(ls "$BUNDLE/Contents/MacOS/" 2>/dev/null | head -1)")
if [ -z "$EXECUTABLE_NAME" ]; then
    fail "번들 안에 실행 파일이 없다 — 측정 불가"
    exit 1
fi
open -n "$BUNDLE"
APP_PID=""
for _ in $(seq 1 60); do
    APP_PID=$(pgrep -n -x "$EXECUTABLE_NAME" 2>/dev/null | head -1)
    [ -n "$APP_PID" ] && break
done
if [ -z "$APP_PID" ]; then
    fail "앱이 뜨지 않았다 — 측정 불가(실패와 다르다)"
    exit 1
fi
note "우리 앱 pid $APP_PID"

# 자식 nvim 이 생길 때까지 기다린다. 안 생기면 이 측정은 아무것도 안 잰다.
OURS=""
for _ in $(seq 1 100); do
    OURS=$(children_of "$APP_PID" | sort | tr '\n' ' ')
    [ -n "$OURS" ] && break
done
if [ -z "$OURS" ]; then
    fail "우리 앱의 자식 nvim 이 하나도 안 생겼다 — 종료 후 0 은 증거가 못 된다"
    exit 1
fi
pass "자식 nvim 확보: $OURS  ← 이제 종료 후의 0 이 의미를 갖는다"

printf '\n⌘Q 를 눌러 종료한 뒤 Enter 를 눌러라 (탭 2개 이상 열고 하는 것이 요점이다)\n'
read -r _

if kill -0 "$APP_PID" 2>/dev/null; then
    fail "앱이 아직 살아 있다 — 종료가 안 됐다"
else
    pass "앱이 종료됐다"
fi

REMAINING=$(for pid in $OURS; do kill -0 "$pid" 2>/dev/null && echo "$pid"; done | tr '\n' ' ')
if [ -z "$REMAINING" ]; then
    pass "우리 앱의 자식 nvim 이 하나도 안 남았다"
else
    fail "남은 자식 nvim: $REMAINING"
    for pid in $REMAINING; do
        printf '    %s ← 부모 %s\n' "$pid" "$(ps -o ppid= -p "$pid" | tr -d ' ')"
    done
fi

AFTER_ORPHANS=$(orphans | sort | tr '\n' ' ')
NEW_ORPHANS=$(comm -13 <(printf '%s\n' $BEFORE_ORPHANS | sort) <(printf '%s\n' $AFTER_ORPHANS | sort) | tr '\n' ' ')
if [ -z "$(printf '%s' "$NEW_ORPHANS" | tr -d ' ')" ]; then
    pass "새로 생긴 고아 0"
else
    fail "새 고아: $NEW_ORPHANS"
fi

printf '\n'
[ "$FAILURES" -eq 0 ] && printf '판정: 종료 경로가 자식을 정리한다\n' || printf '판정: 고아가 남는다 (%d건 실패)\n' "$FAILURES"
exit $FAILURES
