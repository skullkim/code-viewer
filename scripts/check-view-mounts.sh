#!/usr/bin/env bash
# Checks that every SwiftUI view is actually reachable from the window.
#
# A view can compile, pass its own tests, and never reach the user because nothing
# instantiates it. That happened repeatedly in this build: at one point nine finished views
# were unmounted while the whole suite was green, and the window showed three grey stand-ins.
#
# The list of views is DISCOVERED, not maintained by hand. An earlier version listed them
# manually, and the three views written after that list was written were silently exempt —
# the checker's default was silence. Now the default is inclusion: a new view is required to
# be mounted unless someone writes down why not.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the self-test can run against a throwaway copy. Planting fixtures in the
# real tree is how a checker creates the thing it exists to prevent: an interrupted run
# leaves an unmounted view behind, which then fails every later check for reasons nobody
# can trace — and can be swept into a commit by `git add -A`.
SOURCES="${VIEW_SOURCES_DIR:-$REPO_ROOT/Sources}"
FAILURES=0
# Script-scoped, not local to the self-test: the EXIT trap fires after the function has
# returned, and a local would be out of scope by then — which under `set -u` turns cleanup
# into its own error.
SELF_TEST_SANDBOX=""
cleanup_sandbox() {
    if [ -n "$SELF_TEST_SANDBOX" ]; then
        rm -rf "$SELF_TEST_SANDBOX"
        SELF_TEST_SANDBOX=""
    fi
}
trap cleanup_sandbox EXIT INT TERM

# Views that are deliberately not mounted, each with the reason. A bare name here would be
# a door for the next person to quiet any failure; the reason is what keeps it a decision.
is_exempt() {
    case "$1" in
        # One view whose feature is still in flight. Exempted by the leader on 2026-08-30 so that
        # a red gate means something again: it is known, tracked, and owned, and leaving it red
        # teaches everyone to read past the failure — which is how the *next* unmounted view
        # goes unnoticed.
        #
        # The second entry (`BlockedResourcePlaceholder`) is gone as of 2026-08-31 — not because
        # it was mounted, but because the view was deleted. It drew the W-15 box in SwiftUI,
        # and the document is HTML inside a web view, so it could never have appeared. The
        # box is markup now. An exemption that ends by removing the thing is the honest ending.
        #
        # The checker still does its job while this sits here: another unmounted view fails.
        #
        # ⚠ The entry is a debt with a named owner, not a decision. Delete it the moment
        # its view is mounted — an exemption that outlives its reason is how this list becomes
        # the hand-maintained list this script was rewritten to get rid of. Tracked as an open
        # item in _workspace/CERTIFICATION.md and must be gone before BUILD_COMPLETE.
        # 렌더 파이프라인이 아직 없다. 이 뷰는 문서 몸통을 주입받는 제네릭 껍데기인데,
        # 그 몸통(WKWebView 호스트)이 존재하지 않아 마운트할 대상이 없다. 지금 꽂으면
        # 이 검사기는 초록이 되고 렌더는 안 되는 — 이 검사기가 막으려는 바로 그 상태가 된다.
        # 렌더 표면 전체. `RenderDocumentView`(크롬)와 `RenderWebView`(문서)를 조립하며,
        # 그 둘은 이 뷰가 인스턴스화하므로 **더 이상 면제가 아니다** — 두 줄이 한 줄이 됐다.
        # 남은 것은 창에 꽂는 일 하나뿐이고 그건 frontend-senior 몫이다(리더가 갈랐다).
        *) return 1 ;;
    esac
}

# Stand-ins that must not survive into the assembled window.
FORBIDDEN_VIEWS=(PlaceholderPane)

# Finds every view, however it is declared. The first version matched only
# `^(public )?struct [A-Za-z]+: View`, which silently skipped four shapes QA measured:
# a name with a digit, any access modifier other than public, an indented or nested
# declaration, and a view conforming to more than one protocol. A discovery pattern that
# is too narrow puts the checker's silence back, just through a different door.
#
# It happened again, and the fifth shape got further than the others: a GENERIC view.
# `struct RenderDocumentView<Document: View>: View` was never discovered, so it was never
# checked, so the gate reported "23 views, all mounted" while an unmounted 24th sat beside
# them. Undiscovered is worse than unmounted — an unmounted view fails loudly, an
# undiscovered one is counted as absent. The report even reads as reassurance.
#
# And a sixth: a view that wraps AppKit conforms to `NSViewRepresentable`, not to `View`.
# `\bView\b` does not match inside `NSViewRepresentable` — that `View` has no word boundary in
# front of it — so every such view was invisible here. `EditorGridView`, the surface the whole
# editor is drawn on, had never once been checked by this script. It happened to be mounted;
# the point is that nothing here knew that.
discover_views() {
    # No `^` anchor: a nested declaration can sit anywhere on its line, including after
    # an enclosing `enum Foo {` on the same line. The word boundary keeps `// struct` in a
    # comment and identifiers ending in "struct" out.
    #
    # `(<[^>]*>)?` steps over a generic parameter list before the conformance colon. It must
    # come BEFORE the colon check, because the list carries its own colons (`<Document: View>`)
    # and holding the name up against the first colon on the line finds the wrong one.
    # Requiring a colon *after* the list is also what keeps `struct Box<T: View> {` — generic
    # over a view, not a view — from being counted: the `View` inside the brackets never
    # reaches the conformance test. Nested generics (`<A<B>>`) would defeat `[^>]*`; no such
    # view exists here, and the self-test below fails loudly if one ever stops being found.
    grep -rhoE "(^|[^A-Za-z0-9_])struct [A-Za-z0-9_]+(<[^>]*>)?[[:space:]]*:[^{]*(\bView\b|\bNSViewRepresentable\b|\bNSViewControllerRepresentable\b)" "$SOURCES" --include="*.swift" \
        | sed -E 's/.*struct ([A-Za-z0-9_]+).*/\1/' \
        | sort -u
}

# Every source line except the declarations themselves and the contents of `#Preview`
# blocks.
#
# A `#Preview` instantiates the view it sits beside, so counting it would let any unmounted
# view pass by simply having a preview — and a preview is a SwiftUI idiom, not an oddity.
# Same-file references outside a preview do count: a private sub-view used by its own
# file's mounted parent is genuinely reachable.
mountable_lines() {
    find "$SOURCES" -name '*.swift' -exec awk '
        /^[[:space:]]*#Preview/ { inPreview = 1; depth = 0 }
        inPreview {
            depth += gsub(/{/, "{")
            depth -= gsub(/}/, "}")
            if (depth <= 0) { inPreview = 0 }
            next
        }
        { print FILENAME ":" $0 }
    ' {} +
}

# Counts uses of a view outside its own declaration. Generic views are instantiated with a
# trailing closure rather than plain parentheses, so both forms count.
mount_count() {
    mountable_lines \
        | grep -E "\b$1[({]" \
        | grep -vE "struct $1[[:space:]]*:" \
        | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# 검사기 자체 검사 — 잡아야 할 것을 심어 보고, 치운 뒤 깨끗한지 본다.
#
# 이 스크립트의 첫 판은 손목록이라 새 뷰를 조용히 빠뜨렸고, 발견 기반으로 뒤집은 두 번째
# 판은 정규식이 좁아 네 가지 선언 형태를 다시 조용히 빠뜨렸다(QA 실측). 둘 다 "검사기가
# 도는 것"과 "검사기가 잡는 것"의 차이였다. 그 차이를 스스로 증명하게 한다.
# ---------------------------------------------------------------------------
self_test() {
    local status=0

    # A throwaway copy, cleaned up on every exit path including a kill. The shared tree is
    # never modified, so a self-test running during someone else's build cannot make their
    # sources momentarily wrong.
    # A synthetic tree, not a copy of the real one. The question this self-test answers is
    # "does the checker discriminate", and copying the real Sources ties that answer to
    # whether the real tree currently passes — so the day someone lands an unmounted view,
    # the checker reports itself broken. Worse, with a failing baseline a checker that
    # ALWAYS failed would pass every case here, because failing is what each case expects.
    # Building the tree by hand keeps the clean baseline true by construction.
    SELF_TEST_SANDBOX="$(mktemp -d)"
    local sandbox="$SELF_TEST_SANDBOX"
    mkdir -p "$sandbox/CodeNavigatorAppKit/View"
    printf 'import SwiftUI\nstruct QaRootView: View { var body: some View { QaMountedView() } }\n' \
        > "$sandbox/CodeNavigatorAppKit/View/QaRoot.swift"
    # A non-view entry point, so the root view is mounted too. Without it the root is
    # itself unmounted and the "clean tree" baseline is not clean.
    printf 'import SwiftUI\nenum QaComposition { static func make() -> some View { QaRootView() } }\n' \
        > "$sandbox/CodeNavigatorAppKit/View/QaComposition.swift"
    printf 'import SwiftUI\nstruct QaMountedView: View { var body: some View { EmptyView() } }\n' \
        > "$sandbox/CodeNavigatorAppKit/View/QaMounted.swift"

    local fixture="$sandbox/CodeNavigatorAppKit/View/_SelfTestProbe.swift"

    printf '=== check-view-mounts 자체 검사 ===\n'

    # 깨끗한 트리를 통과시키는지부터 본다. 이걸 안 보면 "항상 실패하는 검사기"가 아래의
    # 검출 케이스를 전부 통과한다 — 각 케이스가 기대하는 것이 실패이기 때문이다.
    if VIEW_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  ok: 통과 — 마운트된 뷰만 있는 트리 (항상 실패하는 검사기가 아니다)\n'
    else
        printf '  FAIL: 깨끗한 트리를 통과 못 시킨다 — 검사기가 항상 실패한다\n'
        status=1
    fi

    # 잡아야 할 선언 형태들. 전부 "마운트되지 않은 뷰"이므로 검사기가 실패해야 한다.
    local -a probes=(
        'struct QaPlainView: View { var body: some View { EmptyView() } }|평범한 미마운트'
        'struct QaPane2View: View { var body: some View { EmptyView() } }|이름에 숫자'
        'private struct QaPrivView: View { var body: some View { EmptyView() } }|private 선언'
        'enum QaNest { struct QaNestedView: View { var body: some View { EmptyView() } } }|중첩·들여쓰기'
        'struct QaMultiView: View, Equatable { var body: some View { EmptyView() } }|다중 프로토콜'
        # 제네릭 뷰. 실제로 놓쳤던 형태다 — 이름 뒤가 `:` 가 아니라 `<` 라서 발견 자체가 안 됐고,
        # 그래서 "전부 마운트됨"이 미마운트 뷰 옆에서 출력됐다.
        'struct QaGenericView<Content: View>: View { var body: some View { EmptyView() } }|제네릭 선언'
        # AppKit 을 감싸는 뷰. `NSViewRepresentable` 안의 `View` 는 단어 경계가 아니라
        # `\bView\b` 로는 안 걸렸고, 그래서 **에디터 그리드가 한 번도 검사된 적이 없었다.**
        'struct QaRepresentableView: NSViewRepresentable { func makeNSView(context: Context) -> NSView { NSView() } }|NSViewRepresentable'
    )

    local probe declaration label
    for probe in "${probes[@]}"; do
        declaration="${probe%%|*}"
        label="${probe##*|}"
        printf 'import SwiftUI\n%s\n' "$declaration" > "$fixture"
        if VIEW_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
            printf '  FAIL: 심었는데 검출 못함 — %s\n' "$label"
            status=1
        else
            printf '  ok: 검출 — %s\n' "$label"
        fi
    done

    # #Preview 안에서만 참조되는 뷰는 마운트가 아니다 — 프리뷰는 SwiftUI 관용구라
    # 이걸 마운트로 세면 미마운트 뷰에 프리뷰 하나만 붙이면 검사기를 통과한다.
    printf 'import SwiftUI\nstruct QaPreviewOnlyView: View { var body: some View { EmptyView() } }\n#Preview { QaPreviewOnlyView() }\n' > "$fixture"
    if VIEW_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  FAIL: 심었는데 검출 못함 — #Preview 에서만 참조\n'
        status=1
    else
        printf '  ok: 검출 — #Preview 에서만 참조되는 뷰\n'
    fi

    # 치우면 다시 깨끗해야 한다.
    rm -f "$fixture"
    if VIEW_SOURCES_DIR="$sandbox" "$0" >/dev/null 2>&1; then
        printf '  ok: 픽스처 제거 후 깨끗하다 (오탐 없음)\n'
    else
        printf '  FAIL: 픽스처를 지웠는데도 실패한다 — 오탐이다\n'
        status=1
    fi

    # 실제 트리를 한 번도 건드리지 않았음을 확인한다. 이 검사기의 부작용이 검사 대상을
    # 오염시키면, 자기가 막으려던 것을 스스로 만드는 셈이다.
    if [ -e "$REPO_ROOT/Sources/CodeNavigatorAppKit/View/_SelfTestProbe.swift" ]; then
        printf '  FAIL: 실제 소스 트리에 픽스처가 남았다\n'
        status=1
    else
        printf '  ok: 실제 소스 트리 무변경 (샌드박스에서만 변이)\n'
    fi

    return $status
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

VIEWS="$(discover_views)"
if [ -z "$VIEWS" ]; then
    echo "  FAIL: 뷰를 하나도 찾지 못했다 — 검사기가 아무것도 보고 있지 않다" >&2
    exit 1
fi

CHECKED=0
for view in $VIEWS; do
    if is_exempt "$view"; then
        continue
    fi
    CHECKED=$((CHECKED + 1))
    if [ "$(mount_count "$view")" -lt 1 ]; then
        printf '  FAIL: %s 가 어디에서도 인스턴스화되지 않는다 — 사용자에게 도달할 수 없다\n' "$view"
        FAILURES=$((FAILURES + 1))
    fi
done

for view in "${FORBIDDEN_VIEWS[@]}"; do
    count="$(mount_count "$view")"
    if [ "$count" -ne 0 ]; then
        printf '  FAIL: %s 가 아직 %s곳에서 쓰인다 — 플레이스홀더가 창에 남아 있다\n' "$view" "$count"
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$FAILURES" -eq 0 ]; then
    printf '  ok: 발견한 뷰 %d종 전부 마운트됨, 플레이스홀더 0\n' "$CHECKED"
    exit 0
fi
exit 1
