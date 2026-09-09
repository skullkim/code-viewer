#!/usr/bin/env bash
# 실제 앱을 띄워 핵심 흐름을 눌러 보는 E2E 스모크.
#
# 왜 있나: 단위 테스트 1800개를 전부 통과한 채로 사용자가 결함 셋을 발견했다 —
# GUI 앱의 PATH, 거터 브레이크포인트, 저장 전 변경 표시. 셋 다 "코드가 맞는가" 가 아니라
# "띄워서 눌렀을 때 되는가" 의 문제라, 실행해 보는 검사만이 잡을 수 있다.
#
# **Finder 와 같은 방식(`open`)으로 띄운다.** 터미널에서 띄우면 셸의 PATH 를 물려받아
# 사용자가 겪는 것과 다른 환경이 되고, 그래서 PATH 결함이 개발 중에는 안 보였다.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/.build/CodeNavigator.app"
BINARY="$APP/Contents/MacOS/CodeNavigator"
FIXTURE="${E2E_FIXTURE:-$(mktemp -d)/e2e-project}"
FAILURES=0
DEFAULTS_DOMAIN="dev.local.code-navigator-mac"

pass() { printf '  ok: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() {
    local running
    running="$(pgrep -f "$BINARY" || true)"
    if [ -n "$running" ]; then
        # 내가 띄운 것만 지목해서 내린다. **TERM 으로 곱게 내린다** — `kill -9` 로 죽이면
        # macOS 가 다음 실행에서 "예기치 않게 종료됨" 을 띄우고, 그 상자가 창을 가린다.
        kill $running 2>/dev/null
        local waited=0
        while [ "$waited" -lt 10 ] && pgrep -f "$BINARY" >/dev/null 2>&1; do
            /bin/sleep 1
            waited=$((waited + 1))
        done
    fi
    rm -rf "$FIXTURE"
}
trap cleanup EXIT INT TERM

hexof() { /usr/bin/python3 -c "import sys;print(sys.argv[1].encode('utf-8').hex())" "$1"; }

# ---------------------------------------------------------------------------
# 픽스처 — git 저장소 + 자바 파일 + 실행할 것
# ---------------------------------------------------------------------------
build_fixture() {
    mkdir -p "$FIXTURE"
    cat > "$FIXTURE/App.java" <<'JAVA'
package demo;
public class App {
    public static void main(String[] args) {
        System.out.println("one");
        System.out.println("two");
    }
}
JAVA
    cat > "$FIXTURE/package.json" <<'JSON'
{ "name": "e2e", "scripts": { "dev": "node --version" } }
JSON
    (
        cd "$FIXTURE" || exit 1
        git init -q -b main
        git config user.email e2e@example.invalid
        git config user.name E2E
        git add .
        git commit -q -m first --no-verify
    )
    # 커밋 뒤에 한 줄을 고친다 — 변경 막대가 나와야 할 자리다.
    /usr/bin/python3 - "$FIXTURE/App.java" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().split("\n")
lines[3] = '        System.out.println("CHANGED");'
open(path, "w").write("\n".join(lines))
PY
}

launch() {
    # macOS 의 "이전에 예기치 않게 종료됨 — 창을 다시 열까요?" 대화상자를 막는다.
    # 그것이 뜨면 창 대신 그 상자가 앞에 오고, 이 검사는 앱이 안 뜬 것으로 읽는다.
    # 실제로 그렇게 한 번 실패했다.
    defaults write "$DEFAULTS_DOMAIN" ApplePersistenceIgnoreState -bool YES

    defaults write "$DEFAULTS_DOMAIN" "shell.openTabs" -data \
        "$(hexof "$(/usr/bin/python3 -c "import json,sys;print(json.dumps([sys.argv[1]]))" "$FIXTURE")")"
    defaults write "$DEFAULTS_DOMAIN" "shell.activeTab" -data "$(hexof "$FIXTURE")"
    defaults write "$DEFAULTS_DOMAIN" "shell.bottomPanelTab" -data "$(hexof "terminal")"
    defaults write "$DEFAULTS_DOMAIN" "shell.debugPanelVisible" -data "$(hexof "1")"
    defaults delete "$DEFAULTS_DOMAIN" "shell.runConfigurations" >/dev/null 2>&1

    open "$APP"
    local waited=0
    while [ "$waited" -lt 30 ]; do
        if swift "$REPO_ROOT/scripts/window-id.swift" CodeNavigator >/dev/null 2>&1; then
            /bin/sleep 4
            return 0
        fi
        /bin/sleep 1
        waited=$((waited + 1))
    done
    fail "앱 창이 뜨지 않았다"
    return 1
}

# 접근성 트리에서 이름으로 찾는다. 없으면 실패다 — **빈 결과를 통과로 읽지 않는다.**
ax_contains() {
    swift "$REPO_ROOT/scripts/click-ax.swift" CodeNavigator "" --list 2>/dev/null | grep -qF "$1"
}

# 화면은 비동기로 채워진다. **한 번 보고 없다고 하면 대부분 우리가 빨랐던 것이다** —
# 기다렸다가 그래도 없으면 그때 실패다. 실패하면 화면을 덤프한다: 무엇이 있었는지 모르면
# 결함인지 검사기 문제인지 가릴 수 없다.
expect_visible() {
    local needle="$1" what="$2" waited=0
    while [ "$waited" -lt 15 ]; do
        if ax_contains "$needle"; then
            pass "$what"
            return 0
        fi
        /bin/sleep 1
        waited=$((waited + 1))
    done
    fail "$what (화면에서 \"$needle\" 을 못 찾았다)"
    printf '    --- 그때 화면에 있던 것 ---\n' >&2
    swift "$REPO_ROOT/scripts/click-ax.swift" CodeNavigator "" --list 2>/dev/null \
        | sed 's/^/    /' | head -30 >&2
    return 1
}

click() {
    # 앱이 앞에 있지 않으면 좌표 클릭이 Dock 이나 다른 창으로 간다 — 실제로 Dock 의
    # 컨텍스트 메뉴를 열어 버린 적이 있다.
    /usr/bin/osascript -e 'tell application "System Events" to tell process "CodeNavigator" to set frontmost to true' >/dev/null 2>&1
    /bin/sleep 1
    swift "$REPO_ROOT/scripts/click-ax.swift" CodeNavigator "$1" --mouse >/dev/null 2>&1
}

menu_click() {
    /usr/bin/osascript -e "tell application \"System Events\" to tell process \"CodeNavigator\" to set frontmost to true" >/dev/null 2>&1
    /usr/bin/osascript -e "tell application \"System Events\" to tell process \"CodeNavigator\" to click menu item \"$2\" of menu \"$1\" of menu bar item \"$1\" of menu bar 1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 검사기 자기 시험 — 이 스크립트가 무언가를 실제로 볼 수 있는지 먼저 확인한다.
# 못 보는 상태와 "기능이 없다" 는 화면에서 구별되지 않는다.
# ---------------------------------------------------------------------------
self_test() {
    printf '=== e2e 자기 시험 ===\n'
    if ax_contains "CodeNavigator"; then
        pass "접근성 트리를 읽는다 (positive control)"
    else
        fail "접근성 트리를 아예 못 읽는다 — 이 뒤의 0건은 아무 뜻이 없다"
        return 1
    fi
    if ax_contains "이런_것은_없다_확실히"; then
        fail "없는 것을 있다고 했다"
    else
        pass "없는 것은 없다고 한다 (negative control)"
    fi
}

# ---------------------------------------------------------------------------
# 검사기 자체 검사 — **잡아야 할 것을 심어 보고 잡는지 본다.**
#
# 통과만 확인하는 검사기는 초록불과 구별되지 않는다. 실제로 이 스크립트는 처음 돌렸을 때
# 두 건을 실패로 보고했는데, 원인은 앱이 아니라 우리가 화면을 너무 빨리 본 것이었다.
# ---------------------------------------------------------------------------
run_self_test() {
    local status=0
    printf '=== e2e-smoke 자체 검사 ===\n'

    # 없는 것을 있다고 하면 안 된다. 기다림이 들어간 뒤에도 이 성질이 유지되는지 본다.
    E2E_SELFTEST_QUIET=1
    # `expect_visible` 을 쓰지 않는다 — 그 함수는 실패 수를 올리므로, 일부러 실패시키는
    # 자체 검사에서 쓰면 통과했는데도 실패로 집계된다. 실제로 그랬다.
    if ax_contains "절대_없는_문구_확실히"; then
        printf '  FAIL: 없는 것을 있다고 했다\n'
        status=1
    else
        printf '  ok: 없는 문구는 없다고 한다\n'
    fi

    # 정지를 누르면 머리줄이 "대기" 로 돌아가야 한다. 상태가 **바뀌는 것**까지 봐야
    # 그 값을 진짜 읽는다고 할 수 있다.
    menu_click "실행" "정지"
    /bin/sleep 3
    if ax_contains "대기"; then
        printf '  ok: 상태 변화를 읽는다 (실행 중 → 대기)\n'
    else
        printf '  FAIL: 정지했는데 대기로 안 바뀌었다\n'
        status=1
    fi
    return $status
}

main() {
    if [ ! -x "$BINARY" ]; then
        echo "FAIL: 번들이 없다 — scripts/bundle.sh 를 먼저 돌려라" >&2
        exit 1
    fi
    build_fixture
    launch || exit 1
    self_test || exit 1

    printf '=== e2e 흐름 ===\n'

    # 1. 프로젝트가 열린다
    expect_visible "App.java" "프로젝트 트리에 파일이 보인다"

    # 2. 실행 설정이 자동으로 감지된다 (package.json → npm run dev)
    expect_visible "감지됨" "실행 설정이 자동으로 감지된다"

    # 3. 파일을 연다
    click "App.java"
    /bin/sleep 3
    expect_visible "App.java" "파일이 열린다"

    # 4. 실행이 실제로 뜬다.
    #
    #    터미널 **출력**을 읽고 싶었지만 그리드는 우리가 직접 그리는 뷰라 접근성 트리에
    #    글자를 안 내준다. "command not found 가 없으면 통과" 로 짰다가 **항상 통과하는
    #    가짜**가 됐고 자체 검사가 그것을 잡았다. 볼 수 없는 것을 근거로 쓰지 않는다.
    menu_click "실행" "실행"
    expect_visible "실행 중" "실행이 시작된다"

    if [ "${1:-}" = "--self-test" ]; then
        printf '\n'
        run_self_test || FAILURES=$((FAILURES + 1))
    fi

    printf '\n'
    if [ "$FAILURES" -eq 0 ]; then
        printf 'E2E: PASS\n'
        exit 0
    fi
    printf 'E2E: FAIL (%d건)\n' "$FAILURES"
    exit 1
}

main "$@"
