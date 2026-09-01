#!/usr/bin/env bash
# 한글 자판에서 Vim 화음이 Neovim 에 도달하는가 — 사람 손 검증 (D-19 · D-21 · 회귀)
#
# 왜 사람이 필요한가:
#   입력 소스를 프로그램으로 앱에 먹이지 못했다. `/tmp/qa_imswitch` 는 "선택했다"고
#   보고하지만 앱은 라틴 문자를 받는다(QA 실측 §38.2 — `ㄱ` 을 친 자리에 `r` 이 저장됐다).
#   `TISSelectInputSource` 로 우회하지 않는다: 게이트가 "시스템 입력 소스를 바꾸는 호출 0건"
#   을 검사하고, 그것이 REQ-014 AC-4 의 방어선이다. 검증 도구가 그 규칙을 깨면 규칙이
#   무의미해지고, 중간에 죽으면 사용자 자판이 바뀐 채로 남는다.
#
# 사람이 하는 일: **자판을 한글로 바꾸고, 안내대로 몇 글자 + 화음 한 번.** 그 외 전부 자동.
#
# 사용법:
#   verify-korean-chords.sh <경로.app>      실측
#   verify-korean-chords.sh --self-test     측정기 자체 검사 (앱 없이)
set -uo pipefail

FIXTURE=/tmp/qa-korean-fixture
SRC="$FIXTURE/src"
PASS=0; FAIL=0; RETRY=0

ok()    { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  🔴 %s\n' "$1"; FAIL=$((FAIL+1)); }
again() { printf '  ⚠  %s\n' "$1"; RETRY=$((RETRY+1)); }
note()  { printf '     %s\n' "$1"; }

# ── 판정 도우미 ──────────────────────────────────────────────────────────────
# 바이트가 입력 소스의 증인이다. 사용자가 자판 전환을 잊으면 라틴이 들어오는데,
# 그때는 "통과"가 아니라 "다시 해 주세요"다.
has_hangul() { LC_ALL=C grep -q $'\xe1\x84\|\xe3\x84\|\xea\|\xeb\|\xec\|\xed' "$1" 2>/dev/null; }
has_latin_marker() { LC_ALL=C grep -qE '[a-zA-Z]' <(head -c 12 "$1") 2>/dev/null; }
# 탈출 실패의 지문: 노멀 모드였다면 명령이었을 `:w` 가 텍스트로 찍힌다.
leaked_excommand() { LC_ALL=C grep -q ':w' "$1" 2>/dev/null; }

self_test() {
    printf '=== verify-korean-chords 자체 검사 ===\n'
    local t; t=$(mktemp)
    printf '하SEED\n' > "$t"
    has_hangul "$t" && printf '  ok: 한글 바이트를 잡는다\n' || { printf '  FAIL: 한글 미검출\n'; return 1; }
    printf 'rSEED\n' > "$t"
    has_hangul "$t" && { printf '  FAIL: 라틴을 한글로 오검출\n'; return 1; } || printf '  ok: 라틴을 한글로 세지 않는다\n'
    printf '하:wSEED\n' > "$t"
    leaked_excommand "$t" && printf '  ok: 탈출 실패 지문(:w 누출)을 잡는다\n' || { printf '  FAIL: :w 누출 미검출\n'; return 1; }
    printf '하SEED\n' > "$t"
    leaked_excommand "$t" && { printf '  FAIL: 정상 결과를 누출로 오판\n'; return 1; } || printf '  ok: 정상 결과를 누출로 세지 않는다\n'
    rm -f "$t"
    printf '  → 자체 검사 통과. 죽은 측정기는 모든 칸을 통과로 돌려준다 — 그래서 먼저 검사한다.\n'
}

[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }

# 인자를 안 주면 가장 최근 보존 번들을 쓴다.
#
# 인자를 필수로 두었더니 호출이 길어졌고, 긴 한 줄은 터미널에서 접히면서 경로가 잘렸다
# (실측: `.../code-navigator` + `-mac/.build/...` 두 조각으로 갈라져 두 명령이 됐다).
# 사람에게 부탁하는 명령은 짧아야 한다 — 길이가 곧 실패 확률이다.
#
# 기본값이 "가장 최근"인 이유: 이 스크립트는 방금 자른 번들을 재려고 쓴다. 그리고 무엇을
# 골랐는지 아래에서 매니페스트와 함께 출력하므로, 기본값이 조용히 틀린 것을 고를 수는 없다.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$(ls -td "$REPO_ROOT"/.build/bundles/*.app 2>/dev/null | head -1)}"
[ -d "$APP" ] || {
    printf '사용법: %s [경로.app] | --self-test\n' "$0"
    printf '  인자를 생략하면 %s/.build/bundles 의 최신 번들을 쓴다.\n' "$REPO_ROOT"
    printf '  지금 그 디렉토리에서 .app 을 찾지 못했다.\n'
    exit 2
}

# ── 준비: 픽스처 · 앱 · 프로젝트 ─────────────────────────────────────────────
rm -rf "$FIXTURE"; mkdir -p "$SRC"
for f in c1 c2 c3 c4 c5 c6 c7 c8; do printf 'SEED\n' > "$SRC/$f.txt"; done
printf '# 한글 화음 검증용\n' > "$FIXTURE/README.md"

printf '\n=== 준비 ===\n'
BIN="$APP/Contents/MacOS/CodeNavigator"
note "실행파일: $BIN"
note "빌드시각: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BIN")"
open "$APP"; sleep 7
PID=$(pgrep -x CodeNavigator | head -1)
[ -n "$PID" ] || { printf '  측정 불가: 앱이 뜨지 않았다 (실패가 아니라 측정 불가다)\n'; exit 3; }
note "PID $PID · 기동 $(ps -o lstart= -p "$PID" | tail -1 | sed 's/^ *//')"

osascript >/dev/null 2>&1 <<EOF
tell application "System Events"
  set p to first process whose unix id is $PID
  set frontmost of p to true
  delay 0.5
  click menu item "프로젝트 열기…" of menu 1 of menu bar item "파일" of menu bar 1 of p
  delay 2.5
  key code 5 using {command down, shift down}
  delay 1.2
  keystroke "$FIXTURE"
  delay 0.8
  key code 36
  delay 1.5
  key code 36
  delay 6
end tell
EOF

send() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set frontmost to true" -e 'delay 0.3' "$@" >/dev/null 2>&1; }
# `:e! <경로>` 로 버퍼를 연다. 콜론은 shift+세미콜론(키코드 41).
open_file() {
    local path="$1"
    send -e 'tell application "System Events" to key code 41 using shift down'
    osascript -e "tell application \"System Events\" to keystroke \"e! $path\"" >/dev/null 2>&1
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    sleep 1.5
}
enter_insert() { osascript -e 'tell application "System Events" to key code 34' >/dev/null 2>&1; sleep 0.5; }
# 탈출이 실패했더라도 확실히 노멀로 돌린 뒤 저장한다. `⌃[` 는 이 앱에서 살아 있는 경로다.
escape_and_save() {
    osascript -e 'tell application "System Events" to key code 33 using control down' >/dev/null 2>&1; sleep 0.6
    osascript -e 'tell application "System Events" to key code 41 using shift down' >/dev/null 2>&1
    osascript -e 'tell application "System Events" to keystroke "w"' >/dev/null 2>&1
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    sleep 1.5
}

prompt_human() {
    printf '\n────────────────────────────────────────────────────────\n'
    printf '  🧑 사람이 할 일:  %s\n' "$1"
    printf '  (앱 창이 앞에 있고 삽입 모드입니다. 자판을 한글로 두세요.)\n'
    printf '  끝나면 이 터미널에서 Enter\n'
    printf '────────────────────────────────────────────────────────\n'
    read -r _
}

# ── 칸 ① 조합 중 + ⌃C : 탈출 + 음절 보존 (D-19 + 커밋 경로) ─────────────────
printf '\n=== 칸 ① 조합 중 `하` + ⌃C ===\n'
open_file "$SRC/c1.txt"; enter_insert
prompt_human 'ㅎ, ㅏ 를 친 뒤 (조합 중인 상태에서) ⌃C 를 누르세요'
escape_and_save
C1=$(cat "$SRC/c1.txt" | tr -d '\n')
note "디스크: [$C1]  ($(xxd -p "$SRC/c1.txt" | head -1))"
if ! has_hangul "$SRC/c1.txt"; then
    again "한글이 안 들어왔다 — 자판이 라틴이었을 수 있다. 이 칸은 다시 재야 한다 (통과 아님)"
elif leaked_excommand "$SRC/c1.txt"; then
    bad "⌃C 가 삽입 모드를 못 벗어났다 (`:w` 가 텍스트로 찍혔다)"
elif LC_ALL=C grep -q $'\355\225\230' "$SRC/c1.txt"; then
    ok "⌃C 탈출 + 조합본 `하`(U+D558) 커밋"
else
    bad "탈출은 했으나 조합본이 아니다 — 자모가 커밋됐을 수 있다"
fi

# ── 칸 ② 조합 없음 + ⌃W : 화음이 번역되어 도달하는가 (D-21) ─────────────────
printf '\n=== 칸 ② 조합 없음 + ⌃W (두벌식에서 `ㅈ` — 번역 경로를 반드시 탄다) ===\n'
open_file "$SRC/c2.txt"; enter_insert
prompt_human '가 나 (각각 뒤에 스페이스) 를 친 뒤 ⌃W 를 누르세요'
escape_and_save
C2=$(cat "$SRC/c2.txt" | tr -d '\n')
note "디스크: [$C2]"
if ! has_hangul "$SRC/c2.txt"; then
    again "한글이 안 들어왔다 — 다시 재야 한다 (통과 아님)"
elif LC_ALL=C grep -q $'\353\202\230' "$SRC/c2.txt"; then
    bad "⌃W 가 앞 단어를 지우지 않았다 — 화음이 nvim 에 도달하지 않는다 (`나` 가 남아 있다)"
else
    ok "⌃W 가 앞 단어를 지웠다 — 화음이 도달한다"
fi

# ── 칸 ③ 조합 없음 + ⌃[ : 회귀 (원래 우연히 살아 있던 경로) ────────────────
printf '\n=== 칸 ③ 조합 없음 + ⌃[ (회귀 확인) ===\n'
open_file "$SRC/c3.txt"; enter_insert
prompt_human '가 (뒤에 스페이스) 를 친 뒤 ⌃[ 를 누르세요'
escape_and_save
C3=$(cat "$SRC/c3.txt" | tr -d '\n')
note "디스크: [$C3]"
if ! has_hangul "$SRC/c3.txt"; then
    again "한글이 안 들어왔다 — 다시 재야 한다 (통과 아님)"
elif leaked_excommand "$SRC/c3.txt"; then
    bad "⌃[ 가 삽입 모드를 못 벗어났다 — 회귀"
else
    ok "⌃[ 탈출 정상 (회귀 없음)"
fi

# ── 칸 ④~⑦ 조합 중 이름 있는 키 (프론트 시니어 요청 — 이 열이 인증 블로커) ──────
# 왜 위험한가: 조합 중이면 방향키·delete 를 IME 에 넘기고, Enter·Home 은 커밋 후 보낸다.
# 그 판단이 틀리면 **사용자가 친 음절이 사라진다** — 고치려던 결함보다 나쁘다.
printf '\n=== 칸 ④ 조합 중 + ← (조합 안에서 움직여야 한다 — IME 것) ===\n'
open_file "$SRC/c4.txt"; enter_insert
prompt_human 'ㅎ 만 치고(조합 중) ← 를 한 번 누른 뒤, ㄱ 을 하나 더 치세요'
escape_and_save
note "디스크: [$(cat "$SRC/c4.txt" | tr -d '\n')]"
note "판정 안내: 음절이 남아 있고 자모 순서가 뒤바뀌지 않았으면 정상. 음절이 사라졌으면 결함."

printf '\n=== 칸 ⑤ 조합 중 + delete (자모 하나만 지워져야 한다) ===\n'
open_file "$SRC/c5.txt"; enter_insert
prompt_human 'ㅎ ㅏ 를 쳐서 하 를 만든 뒤(조합 중) delete 를 한 번 누르세요'
escape_and_save
note "디스크: [$(cat "$SRC/c5.txt" | tr -d '\n')]"
note "판정 안내: ㅎ 만 남으면 정상(자모 하나). 아무것도 안 남으면 음절 통째로 지워진 것 — 결함."

printf '\n=== 칸 ⑥ 조합 중 + Enter (음절이 남고 줄바꿈돼야 한다) ===\n'
open_file "$SRC/c6.txt"; enter_insert
prompt_human 'ㅎ ㅏ 를 쳐서 하 를 만든 뒤(조합 중) Enter 를 누르세요'
escape_and_save
C6=$(cat "$SRC/c6.txt")
note "디스크(줄 단위): $(printf '%s' "$C6" | tr '\n' '|')"
note "판정 안내 — 시니어 해석표:"
note "  하 가 남고 줄바꿈  → 맞다 / 하 가 사라짐 → 커밋이 빈 상태로 돌았다"
note "  하 가 두 번        → IME 도 커밋하고 우리도 보냈다 / 줄바꿈이 하 앞 → 순서 문제"

printf '\n=== 칸 ⑦ 조합 중 + Home (음절이 남고 줄 처음으로) ===\n'
open_file "$SRC/c7.txt"; enter_insert
prompt_human 'ㅎ ㅏ 를 쳐서 하 를 만든 뒤(조합 중) Home 을 누르고, 이어서 ㄱ 을 치세요'
escape_and_save
note "디스크: [$(cat "$SRC/c7.txt" | tr -d '\n')]"
note "판정 안내: 하 가 남아 있고 ㄱ 이 줄 처음에 있으면 정상. 하 가 사라졌으면 결함."

printf '\n=== 칸 ⑧ 대조 — 조합 없이 방향키·Enter (nvim 것) ===\n'
open_file "$SRC/c8.txt"; enter_insert
prompt_human 'ㄱ 을 치고 스페이스로 확정한 뒤, ← 를 한 번, Enter 를 한 번 누르세요'
escape_and_save
note "디스크(줄 단위): $(cat "$SRC/c8.txt" | tr '\n' '|')"
note "판정 안내: 줄이 하나 늘고 글자가 남아 있으면 정상. 조합 유무로 경로가 갈리는지 이 칸이 대조한다."

printf '\n=== 결과 ===\n'
printf '  통과 %d · 실패 %d · 재측정 필요 %d\n' "$PASS" "$FAIL" "$RETRY"
[ "$RETRY" -gt 0 ] && printf '  ⚠ 재측정 필요가 있으면 그 칸은 **통과로 적지 않는다.**\n'
printf '  판정 규율: 모드는 `:w` 누출로, 내용은 디스크 바이트로. 바이트가 입력 소스의 증인이다.\n'
exit $(( FAIL > 0 ? 1 : 0 ))
