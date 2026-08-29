#!/usr/bin/env bash
# QA 합성(composition) 층 검사 — "뷰가 존재하는가"가 아니라 "화면에 올라가는가"를 본다.
#
# 왜 필요한가:
#   `swift test`는 순수 함수를 검증하고, `GridRenderingTests`는 글리프가 올바른 픽셀에
#   찍히는지를 검증한다. 둘 다 **무엇이 화면에 올라가는가**는 보지 않는다. 실측(2026-08-29
#   22:56): 완성된 뷰 3개(ProjectOpenView·FileTreeView·EditorGridView)가 마운트 0곳이고
#   창에는 회색 플레이스홀더 3장이 떠 있는데 게이트는 전부 초록이었다.
#
# 규율: 이 스크립트도 검사기다. 검사기가 조용히 통과하는 상태는 초록불과 구분되지 않는다.
#   _workspace/qa-render-check.sh --self-test
#
# 소유: QA. 프론트엔드가 채택하면 gate.sh 로 옮겨도 된다(그때는 소유권도 함께 넘어간다).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

VIEW_DIRS="Sources/CodeNavigatorAppKit"
# 화면에 올라가서는 안 되는 자리표시자. 이 값이 0이 되어야 합성 층이 완료다.
PLACEHOLDER_NAME="${PLACEHOLDER_NAME:-PlaceholderPane}"
# 루트 뷰는 NSHostingView 가 마운트하므로 뷰 참조 규칙에서 제외한다.
ROOT_VIEW="${ROOT_VIEW:-MainWindowView}"

FAILURES=0

fail() { printf '  FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf '  ok: %s\n' "$1"; }

# SwiftUI 뷰 타입 이름을 전부 찾는다. public/internal 둘 다.
# 하드코딩 목록을 쓰지 않는 이유: 새 뷰가 추가되면 자동으로 검사 대상이 되어야 한다.
# 목록을 손으로 유지하면 빠뜨린 뷰가 조용히 검사를 통과한다.
discover_views() {
    grep -rhoE '^\s*(public )?struct [A-Za-z_][A-Za-z0-9_]*: View' "$VIEW_DIRS" 2>/dev/null \
        | sed -E 's/.*struct ([A-Za-z_][A-Za-z0-9_]*): View/\1/' \
        | sort -u
}

# 정의부를 제외한 참조 수 = 마운트 횟수.
mount_count() {
    local view="$1"
    grep -rn "${view}(" "$VIEW_DIRS" --include='*.swift' 2>/dev/null \
        | grep -vE "struct ${view}\b" \
        | grep -cE "${view}\("
}

check_views() {
    local views
    views="$(discover_views)"

    if [ -z "$views" ]; then
        fail "SwiftUI 뷰를 하나도 찾지 못했다 — 검사기가 아무것도 보고 있지 않다"
        return
    fi
    pass "뷰 발견 $(printf '%s\n' "$views" | wc -l | tr -d ' ')종"

    local view count
    for view in $views; do
        [ "$view" = "$ROOT_VIEW" ] && continue

        count="$(mount_count "$view")"

        if [ "$view" = "$PLACEHOLDER_NAME" ]; then
            if [ "$count" -gt 0 ]; then
                fail "$view 가 아직 ${count}곳에 마운트돼 있다 — 자리표시자가 화면에 남아 있다"
            else
                pass "$view 마운트 0곳 (자리표시자 제거됨)"
            fi
            continue
        fi

        if [ "$count" -eq 0 ]; then
            fail "$view 가 어디에도 마운트되지 않았다 — 작성됐지만 화면에 올라가지 않는다"
        else
            pass "$view 마운트 ${count}곳"
        fi
    done
}

# ---------------------------------------------------------------------------
# 검사기 자체 검사 — 잡아야 할 것을 심고, 치운 뒤 깨끗한지 본다 (양방향)
# ---------------------------------------------------------------------------
self_test() {
    printf '=== qa-render-check 자체 검사 (미마운트 픽스처, 양방향) ===\n'
    local fixture="$VIEW_DIRS/View/_QaRenderCheckFixture.swift"
    local status=0

    # 1) 아무 데서도 쓰이지 않는 뷰를 심는다 -> 반드시 잡아야 한다.
    cat > "$fixture" <<'SWIFT'
import SwiftUI

/// QA 검사기 자체 검사용 임시 픽스처. 어디에서도 마운트되지 않는다.
struct QaRenderCheckOrphanView: View {
    var body: some View { EmptyView() }
}
SWIFT

    FAILURES=0
    check_views >/dev/null 2>&1
    if [ "$FAILURES" -gt 0 ]; then
        printf '  ok: 미마운트 뷰를 잡는다\n'
    else
        printf '  FAIL: 미마운트 뷰를 심었는데 통과했다\n'
        status=1
    fi

    # 2) 치우고 -> 픽스처가 원인이던 실패는 사라져야 한다 (오탐 없음 확인).
    rm -f "$fixture"
    FAILURES=0
    check_views >/dev/null 2>&1
    local after="$FAILURES"
    if ! grep -rq "QaRenderCheckOrphanView" "$VIEW_DIRS" 2>/dev/null; then
        printf '  ok: 픽스처 제거됨 (잔재 없음)\n'
    else
        printf '  FAIL: 픽스처 잔재가 남았다\n'
        status=1
    fi

    # 3) 발견 로직이 실제로 뷰를 찾는지 (0건이면 무엇이든 통과시킨다).
    if [ "$(discover_views | wc -l | tr -d ' ')" -gt 0 ]; then
        printf '  ok: 뷰 발견 로직이 동작한다 (%s종)\n' "$(discover_views | wc -l | tr -d ' ')"
    else
        printf '  FAIL: 뷰를 하나도 발견하지 못한다 — 검사 대상이 0건이다\n'
        status=1
    fi

    printf '  (참고: 픽스처 제거 후 남은 실패 %s건 = 실제 미마운트 뷰)\n' "$after"
    rm -f "$fixture"
    return $status
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

printf '=== 합성 층: 뷰 마운트 검사 ===\n'
check_views

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'RENDER-CHECK: PASS\n'
    exit 0
fi
printf 'RENDER-CHECK: FAIL (%d)\n' "$FAILURES"
exit 1
