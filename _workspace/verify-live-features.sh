#!/usr/bin/env bash
# REQ-015·016·017 라이브 검증 — 사람 손 + 자동 측정
#
# 왜 사람이 필요한가:
#   이 세 요구는 전부 *입력*이다 — 클릭·드래그·키. 합성 입력을 쓰려면 대상 창이 최전면이어야
#   하는데 그것을 통제하지 못한다. 지난 시도에서 합성 키가 사용자의 다른 창에 타이핑됐고,
#   그때 결과를 "측정"으로 읽었다면 전부 거짓이었다. 그래서 입력은 사람이 하고,
#   판정할 수 있는 것은 스크립트가 잰다.
#
# 사람이 하는 일: 안내대로 클릭·드래그·키 몇 번. 색 판정과 스크린샷은 자동.
#
# 사용법:
#   verify-live-features.sh              실측
#   verify-live-features.sh --self-test  측정 도구 자체 검사 (앱 없이)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/.build/CodeNavigator.app"
FIXTURE=/private/tmp/cn-live-fixture
SHOTS="$REPO_ROOT/_workspace/shots-live"
COUNTER="$REPO_ROOT/scripts/count-code-colours.swift"

# 편집기 안쪽 사각형(창 1280x832 기준). 트리·패널·상태바·탭바를 넉넉히 피한다.
# 절대 임계값을 쓰지 않고 같은 사각형에서 두 파일을 비교하므로, 정확할 필요는 없고
# "확실히 편집기 안"이기만 하면 된다.
EDITOR_X=260; EDITOR_Y=130; EDITOR_W=650; EDITOR_H=600

# 지원 언어와 미지원 언어의 색 개수 차이가 이만큼은 나야 "강조가 붙었다"고 본다.
# 6종을 요구하지 않는 이유: 한 화면에 여섯 그룹이 다 보인다는 보장이 없다(PD 가 기준물에서
# 겪은 그것 — 작은 창에서는 잘린다). 차이를 보는 쪽이 화면 크기에 안 흔들린다.
MIN_COLOUR_GAP=3

PASS=0; FAIL=0; SKIP=0
ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  🔴 %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  ⏭  %s\n' "$1"; SKIP=$((SKIP+1)); }
note() { printf '     %s\n' "$1"; }

frontmost_app() {
    osascript -e 'tell application "System Events" to name of first application process whose frontmost is true'
}

count_colours() {  # <png> → 뚜렷한 색 개수, 못 재면 빈 문자열
    swift "$COUNTER" "$1" "$EDITOR_X" "$EDITOR_Y" "$EDITOR_W" "$EDITOR_H" \
        | sed -n 's/^distinct: //p'
}

shoot() {  # <이름> → 창을 찍어 경로를 반환. 창을 못 찾으면 빈 문자열
    local name="$1" wid
    wid="$(swift "$REPO_ROOT/scripts/window-id.swift" CodeNavigator)" || return 1
    [ -n "$wid" ] || return 1
    mkdir -p "$SHOTS"
    screencapture -x -o -l"$wid" "$SHOTS/$name.png" || return 1
    printf '%s\n' "$SHOTS/$name.png"
}

ask() {  # <질문> → 사람이 y/n. 판정을 사람에게 맡기는 칸에만 쓴다
    local answer
    printf '\n  ❓ %s [y/n/s(건너뜀)] ' "$1"
    read -r answer </dev/tty
    case "$answer" in
        y|Y) return 0 ;;
        s|S) return 2 ;;
        *)   return 1 ;;
    esac
}

# ── 자기 검사 ────────────────────────────────────────────────────────────────
# 죽은 측정기는 모든 칸을 통과로 돌려준다. 이 스크립트가 하는 자동 판정은 색 개수 하나이고,
# 그 판정에 쓰는 도구 셋(색 계수기·창 찾기·픽스처)이 실제로 동작하는지 먼저 건다.
self_test() {
    printf '=== verify-live-features 자체 검사 ===\n'
    local failures=0

    if swift "$COUNTER" --self-test > /dev/null 2>&1; then
        printf '  ok: 색 계수기 자체 검사 통과\n'
    else
        printf '  FAIL: 색 계수기 자체 검사 실패 — 색 판정을 근거로 쓰지 마라\n'
        failures=$((failures + 1))
    fi

    if bash "$REPO_ROOT/_workspace/make-live-fixture.sh" --self-test > /dev/null 2>&1; then
        printf '  ok: 픽스처가 SC-10·SC-11 의 수를 만족한다\n'
    else
        printf '  FAIL: 픽스처 자체 검사 실패 — 수가 안 맞으면 원인이 앱인지 픽스처인지 못 가른다\n'
        failures=$((failures + 1))
    fi

    # 최전면 판정이 실제로 이름을 돌려주는가. 빈 문자열이면 가드가 무력해지고,
    # 무력한 가드는 "확인했다"는 착각만 준다.
    local front; front="$(frontmost_app 2>/dev/null)"
    if [ -n "$front" ]; then
        printf '  ok: 최전면 앱 판정이 동작한다 (지금: %s)\n' "$front"
    else
        printf '  FAIL: 최전면 앱을 못 읽는다 — 어느 창에 입력이 가는지 모르는 상태다\n'
        failures=$((failures + 1))
    fi

    [ "$failures" -eq 0 ] && {
        printf '  → 자체 검사 통과.\n'; return 0
    }
    printf '  → 자체 검사 실패 %s건.\n' "$failures"; return 1
}

[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }

# ── 준비 ─────────────────────────────────────────────────────────────────────
printf '=== REQ-015·016·017 라이브 검증 ===\n'
printf '번들: %s\n' "$APP"
[ -f "$APP/Contents/MacOS/CodeNavigator" ] || { printf '🔴 번들이 없다. ./scripts/bundle.sh 를 먼저 돌려라.\n'; exit 1; }

MANIFEST="$(ls -t "$REPO_ROOT/.build/bundles/"*.manifest.txt 2>/dev/null | head -1)"
[ -n "$MANIFEST" ] && { printf '\n--- 번들 매니페스트 ---\n'; cat "$MANIFEST"; }

self_test || { printf '\n🔴 자체 검사가 실패했다. 이 스크립트의 판정을 근거로 쓰지 마라.\n'; exit 1; }

printf '\n픽스처: %s\n' "$FIXTURE"
bash "$REPO_ROOT/_workspace/make-live-fixture.sh" > /dev/null

printf '\n앱이 떠 있고 cn-live-fixture 가 열려 있어야 한다.\n'
printf '아니면 지금 열어라 (⌘O → /tmp/cn-live-fixture).\n'
printf '준비되면 Enter: '; read -r _ </dev/tty

# ── 1. 구문 강조 — 자동 판정 ─────────────────────────────────────────────────
printf '\n[1] REQ-016 AC-1 · AC-4 — 구문 강조 (자동 측정)\n'
printf '  트리에서 src 를 펼치고 UserService.java 를 열어라.\n'
printf '  준비되면 Enter: '; read -r _ </dev/tty

JAVA_SHOT="$(shoot req016-java)" || JAVA_SHOT=""
if [ -z "$JAVA_SHOT" ]; then
    bad "AC-1: 창을 못 찾아 스크린샷 실패 — 측정 불가(통과 아님)"
else
    JAVA_COLOURS="$(count_colours "$JAVA_SHOT")"
    note "java 코드 영역 뚜렷한 색: ${JAVA_COLOURS:-측정실패}"
fi

printf '\n  이번엔 tool.py 를 열어라 (미지원 언어 — 평문이어야 한다).\n'
printf '  준비되면 Enter: '; read -r _ </dev/tty

PY_SHOT="$(shoot req016-python)" || PY_SHOT=""
if [ -z "$PY_SHOT" ]; then
    bad "AC-4: 창을 못 찾아 스크린샷 실패 — 측정 불가(통과 아님)"
else
    PY_COLOURS="$(count_colours "$PY_SHOT")"
    note "python 코드 영역 뚜렷한 색: ${PY_COLOURS:-측정실패}"
fi

if [ -n "${JAVA_COLOURS:-}" ] && [ -n "${PY_COLOURS:-}" ]; then
    GAP=$((JAVA_COLOURS - PY_COLOURS))
    if [ "$GAP" -ge "$MIN_COLOUR_GAP" ]; then
        ok "AC-1·AC-4: java $JAVA_COLOURS 색 · python $PY_COLOURS 색 (차이 $GAP ≥ $MIN_COLOUR_GAP)"
    else
        bad "AC-1·AC-4: java $JAVA_COLOURS 색 · python $PY_COLOURS 색 (차이 $GAP < $MIN_COLOUR_GAP)"
        note "지원 언어가 안 칠해졌거나, 미지원 언어에 색이 샜다. 두 스크린샷을 열어 보라."
    fi
else
    bad "AC-1·AC-4: 색을 못 쟀다 — 통과로 세지 않는다"
fi

# ── 2. 사람이 판정하는 칸 ────────────────────────────────────────────────────
# 표에 없는 칸은 검증되지 않은 것이다. 각 칸은 하나만 묻는다 — 둘을 묻는 질문은
# "아니오"가 어느 쪽인지 알려주지 않는다.
printf '\n[2] 사람 판정 — UserService.java 를 다시 열고 진행하라\n'
printf '  준비되면 Enter: '; read -r _ </dev/tty

run_cell() {  # <라벨> <안내> <질문>
    printf '\n  ▸ %s\n' "$2"
    ask "$3"
    case $? in
        0) ok "$1" ;;
        2) skip "$1 — 사람이 건너뜀 (통과 아님)" ;;
        *) bad "$1" ;;
    esac
}

run_cell "REQ-017 AC-1 클릭→커서" \
    "편집 영역 아무 글자나 클릭해라." \
    "커서가 클릭한 그 자리로 갔나?"

run_cell "REQ-017 AC-2·3 드래그→선택 가시" \
    "세 줄 정도를 드래그해라." \
    "드래그한 범위에 선택 배경(파랑)이 보이나?"

run_cell "REQ-017 AC-4 선택에 Vim 명령" \
    "드래그한 상태에서 d 를 눌러라." \
    "그 범위가 삭제됐나? (u 로 되돌려라)"

run_cell "REQ-016 AC-2 같은 심볼 강조" \
    "user 라는 낱말에 커서를 두어라 (5곳에 있다)." \
    "같은 이름들이 함께 강조되나?"

run_cell "REQ-016 AC-2 강조가 따라옴" \
    "커서를 realm 으로 옮겨라." \
    "user 강조가 사라지고 realm 이 강조되나?"

run_cell "REQ-016 AC-2 키워드에 발화 안 함" \
    "커서를 public 또는 return 같은 키워드에 두어라." \
    "키워드는 강조되지 '않'나? (강조되면 결함이다)"

run_cell "REQ-015 AC-1 gd 정의 이동" \
    "AccountController.java 를 열고 UserService 에 커서를 두고 노멀 모드에서 gd." \
    "UserService 정의로 이동했나?"

run_cell "REQ-015 AC-2 gr 참조 목록" \
    "UserService 에 커서를 두고 gr 을 눌러라." \
    "참조 패널에 사용처 3개가 나왔나? (AccountController · ReportJob · Bootstrap.kt)"

run_cell "REQ-015 AC-3 ⌘B 생존" \
    "같은 자리에서 ⌘B 를 눌러라." \
    "gd 와 같게 동작하나? (키가 늘어난 것이지 옮겨간 게 아니다)"

run_cell "REQ-015 AC-5 심볼 아님 안내" \
    "주석이나 빈 곳에 커서를 두고 gr 을 눌러라." \
    "이유를 말하나? (조용히 아무 일도 안 일어나면 실패다)"

run_cell "REQ-016 AC-6 테마 전환" \
    "시스템 설정에서 다크↔라이트를 바꿔라." \
    "구문 색이 따라 바뀌나?"

# ── 결과 ─────────────────────────────────────────────────────────────────────
printf '\n=== 결과: 통과 %s · 실패 %s · 건너뜀 %s ===\n' "$PASS" "$FAIL" "$SKIP"
printf '스크린샷: %s\n' "$SHOTS"

# 이 스크립트가 안 보는 층을 같이 적는다. 안 적으면 "통과 11" 이 "모든 AC 통과"로 읽히고,
# 그 오독은 검사기가 강할수록 더 잘 일어난다.
printf '\n--- 이 스크립트가 확인하지 "않는" 것 ---\n'
printf 'REQ-015 AC-6·7·8 (사용자 nvim 설정과의 상호작용)\n'
if [ -d "$HOME/.config/nvim" ]; then
    printf '  ~/.config/nvim 이 있다. 위 칸들이 그 설정과의 상호작용을 재지는 않는다.\n'
else
    printf '  ⚠ 이 머신에 ~/.config/nvim 이 없다 — 세 AC 는 여기서 원리적으로 못 잰다.\n'
    printf '     AC-6(사용자 매핑을 안 덮는다)은 덮을 매핑이 없어서,\n'
    printf '     AC-7·8(사용자 gr* 을 지키고 이유를 남긴다)은 발동 조건이 없어서다.\n'
    printf '     픽스처 테스트가 메커니즘은 덮지만, 실제 설정으로는 아무도 안 봤다.\n'
    printf '     → 설정을 쓰는 사용자에게 이 앱이 처음 도는 날이 그 검증의 첫날이다.\n'
fi
printf '구문 색이 §4.1.1 의 그 hex 인가 — 여기서는 색 "개수"만 센다.\n'
printf '  어느 그룹이 어느 값인지는 07_fidelity_checklist.md 의 대조가 답한다.\n'
if [ "$SKIP" -gt 0 ]; then
    printf '⚠ 건너뛴 칸은 통과가 아니라 미검증이다. 인증 문서에 그렇게 적어야 한다.\n'
fi
[ "$FAIL" -eq 0 ] && [ "$SKIP" -eq 0 ] && exit 0
[ "$FAIL" -eq 0 ] && exit 2
exit 1
