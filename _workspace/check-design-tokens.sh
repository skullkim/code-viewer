#!/usr/bin/env bash
# 편집기 색 토큰이 세 곳에서 같은 값을 말하는지 검사한다.
#
#   1. _workspace/02_design.md §4.1.1        ← 단일 소스 (여기가 이긴다)
#   2. _workspace/prototype/styles.css       ← 시각 기준물(스크린샷)이 쓰는 값
#   3. Sources/.../Design/DesignTokens.swift ← 앱이 Neovim 에 바르는 값
#
# 왜 스크립트인가: 같은 hex 가 세 곳에 있고, 손으로 대조하면 반쪽만 고쳐진다.
# 이 빌드에서 실제로 그렇게 됐다 — 프론트가 `:289` 산문에서 승격한 값이 개정된 §4.1.1
# 값보다 낡아 있었고, 두 문서를 나란히 열기 전까지 아무도 몰랐다.
#
# ⚠ 이 검사가 재는 것과 안 재는 것 (초록을 잘못 읽지 마라)
#   재는 것   — 세 곳의 **값이 같은가**. 토큰이 선언돼 있고 hex 가 일치하는가.
#   안 재는 것 — **그 토큰을 실제로 쓰는가.** 팔레트가 다른 토큰(예: `match`)을 넘기고 있어도
#                토큰만 선언돼 있으면 이 스크립트는 초록이다. 실제로 그런 상태가 있었다
#                (2026-09-01 14:50, 리더 실측: `backgroundSameSymbol` 선언 + 팔레트는 `match`).
#   그러므로 **초록 = 값 정합**이지 **초록 ≠ 반영 완료**다. 사용처 단언은 프론트 테스트가 한다.
#
# 규율: 이 파일을 고칠 때마다 검사기 자체를 검사한다.
#   _workspace/check-design-tokens.sh --self-test
# 통과만 보는 것은 절반이다. 죽은 검사기가 가장 잘 통과한다.
#
# 사용:
#   check-design-tokens.sh              # 이 레포를 검사
#   check-design-tokens.sh <루트>       # 다른 트리를 검사 (자기검사가 쓴다)
#   check-design-tokens.sh --self-test  # 검사기가 실제로 잡는지 양방향 확인

set -uo pipefail

SELF_TEST=0
ROOT=""
for arg in "$@"; do
    case "$arg" in
        --self-test) SELF_TEST=1 ;;
        *) ROOT="$arg" ;;
    esac
done

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

run_check() {
    python3 - "$1" <<'PYTHON'
import re, sys, os

root = sys.argv[1]
design = os.path.join(root, "_workspace", "02_design.md")
css = os.path.join(root, "_workspace", "prototype", "styles.css")
swift = os.path.join(root, "Sources", "CodeNavigatorAppKit", "Design", "DesignTokens.swift")

failures = []
notes = []


def read(path):
    if not os.path.exists(path):
        failures.append("파일이 없다: %s" % path)
        return ""
    return open(path, encoding="utf-8").read()


design_text = read(design)
css_text = read(css)
swift_text = read(swift)

# --- 1. 단일 소스 파싱: §4.1.1 의 두 표 ---------------------------------------
# 구문 표: | `syn-kw` | `#A626A4` | `#C792EA` | ...
syntax = {}
for name, light, dark in re.findall(
    r"^\|\s*`(syn-[a-z]+)`\s*\|\s*`(#[0-9A-Fa-f]{6})`\s*\|\s*`(#[0-9A-Fa-f]{6})`\s*\|",
    design_text, re.M,
):
    syntax[name] = (light.upper(), dark.upper())

# 표면 표: | `bg-selection` (`Visual`) | `#E0EFFF` | `#233043` | ...  (강조 `**` 허용)
surfaces = {}
for name, light, dark in re.findall(
    r"^\|\s*\**`(bg-selection|bg-same-symbol)`\**[^|]*\|\s*\**`(#[0-9A-Fa-f]{6})`\**\s*\|\s*\**`(#[0-9A-Fa-f]{6})`\**\s*\|",
    design_text, re.M,
):
    surfaces[name] = (light.upper(), dark.upper())

EXPECTED_SYNTAX = {"syn-kw", "syn-type", "syn-fn", "syn-str", "syn-num", "syn-cmt"}
missing = EXPECTED_SYNTAX - set(syntax)
if missing:
    failures.append("§4.1.1 구문 표에서 못 읽은 토큰: %s (표 형식이 바뀌었나 — 검사기가 눈이 먼다)"
                    % ", ".join(sorted(missing)))
for want in ("bg-selection", "bg-same-symbol"):
    if want not in surfaces:
        failures.append("§4.1.1 표면 표에서 `%s` 를 못 읽었다" % want)

# --- 2. 프로토타입 CSS ---------------------------------------------------------
# 라이트는 :root 블록, 다크는 [data-theme="dark"] 와 prefers-color-scheme 블록 둘 다.
def css_blocks():
    light = css_text.split('[data-theme="dark"]')[0]
    dark = css_text[css_text.find('[data-theme="dark"]'):] if '[data-theme="dark"]' in css_text else ""
    return light, dark


light_css, dark_css = css_blocks()

def css_value(block, var):
    hits = re.findall(r"--%s:\s*(#[0-9A-Fa-f]{6})" % re.escape(var), block)
    return [h.upper() for h in hits]


for token, (light, dark) in sorted(syntax.items()):
    var = token.replace("syn-", "syn-")  # CSS 변수명은 문서의 토큰명과 같다
    got_light = css_value(light_css, var)
    got_dark = css_value(dark_css, var)
    if not got_light:
        failures.append("styles.css 라이트에 --%s 가 없다" % var)
    elif got_light[0] != light:
        failures.append("--%s 라이트 불일치 — 문서 %s / CSS %s" % (var, light, got_light[0]))
    if not got_dark:
        failures.append("styles.css 다크에 --%s 가 없다" % var)
    else:
        odd = [v for v in got_dark if v != dark]
        if odd:
            failures.append("--%s 다크 불일치 — 문서 %s / CSS %s (다크 정의는 %d곳, 전부 같아야 한다)"
                            % (var, dark, odd[0], len(got_dark)))

for var, (light, dark) in sorted(surfaces.items()):
    got_light = css_value(light_css, var)
    got_dark = css_value(dark_css, var)
    if not got_light or got_light[0] != light:
        failures.append("--%s 라이트 불일치 — 문서 %s / CSS %s" % (var, light, got_light[0] if got_light else "없음"))
    if not got_dark or any(v != dark for v in got_dark):
        failures.append("--%s 다크 불일치 — 문서 %s / CSS %s" % (var, dark, got_dark[0] if got_dark else "없음"))

# --- 3. Swift 토큰 -------------------------------------------------------------
SWIFT_NAMES = {
    "syn-kw": "syntax-keyword",
    "syn-type": "syntax-type",
    "syn-fn": "syntax-function",
    "syn-str": "syntax-string",
    "syn-num": "syntax-number",
    "syn-cmt": "syntax-comment",
}

def swift_token(name):
    m = re.search(r'token\(\s*"%s"\s*,\s*"(#[0-9A-Fa-f]{6})"\s*,\s*"(#[0-9A-Fa-f]{6})"\s*\)'
                  % re.escape(name), swift_text)
    return (m.group(1).upper(), m.group(2).upper()) if m else None


for token, (light, dark) in sorted(syntax.items()):
    got = swift_token(SWIFT_NAMES[token])
    if got is None:
        failures.append("DesignTokens.swift 에 `%s` 토큰이 없다 — 아직 반영 안 됨" % SWIFT_NAMES[token])
    elif got != (light, dark):
        failures.append("%s 불일치 — 문서 %s/%s / Swift %s/%s"
                        % (SWIFT_NAMES[token], light, dark, got[0], got[1]))

# teal 은 syn-type 과 한 값이다 (§4.1.1 배지 항목). 갈라지면 한쪽만 고쳐진다.
teal = swift_token("teal")
if teal is None:
    failures.append("DesignTokens.swift 에 `teal` 토큰이 없다")
elif "syn-type" in syntax and teal != syntax["syn-type"]:
    failures.append("teal 이 syn-type 과 갈라졌다 — teal %s/%s vs syn-type %s/%s (§4.1.1: 한 값이다)"
                    % (teal[0], teal[1], syntax["syn-type"][0], syntax["syn-type"][1]))

# 편집기 배경 2종: §4.1.1 이 불투명으로 발행하므로 Swift 에도 그 hex 가 있어야 한다.
# (nvim_set_hl 이 알파를 거절한다 — 값이 어딘가에서 불투명해져야 하고, 그 값이 이것이어야 한다.)
design_dir = os.path.join(root, "Sources", "CodeNavigatorAppKit", "Design")
swift_all = ""
if os.path.isdir(design_dir):
    for entry in sorted(os.listdir(design_dir)):
        if entry.endswith(".swift"):
            swift_all += open(os.path.join(design_dir, entry), encoding="utf-8").read()

for var, (light, dark) in sorted(surfaces.items()):
    for scheme, value in (("라이트", light), ("다크", dark)):
        if value not in swift_all.upper():
            failures.append("`%s` %s 값 %s 가 Design/*.swift 어디에도 없다 — 아직 반영 안 됨"
                            % (var, scheme, value))

# --- 결과 ---------------------------------------------------------------------
print("검사 대상: %s" % root)
print("§4.1.1 구문 토큰 %d종 · 편집기 표면 %d종" % (len(syntax), len(surfaces)))
for note in notes:
    print("  note: %s" % note)
if failures:
    for f in failures:
        print("  FAIL: %s" % f)
    print("\n%d건 불일치. **문서(§4.1.1)가 단일 소스다** — 문서에 맞춰 나머지를 고쳐라." % len(failures))
    sys.exit(1)
print("  ok: 세 곳이 같은 값을 말한다")
print("       (값의 일치만 잰다 — 팔레트가 그 토큰을 실제로 쓰는지는 이 검사 밖이다)")
sys.exit(0)
PYTHON
}

if [ "$SELF_TEST" -eq 0 ]; then
    run_check "$ROOT"
    exit $?
fi

# ---------------------------------------------------------------------------
# 자기검사 — 양방향
#   (a) 값이 맞는 합성 트리에서 통과하는가  (죽은 검사기가 아닌가)
#   (b) 세 소스를 각각 흔들면 잡는가        (실제로 무언가를 재는가)
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/_workspace/prototype" "$TMP/Sources/CodeNavigatorAppKit/Design"

cat > "$TMP/_workspace/02_design.md" <<'FIXTURE'
### 4.1.1 편집기 색
| 표면 | 라이트 | 다크 | 무엇 | 유래 |
|---|---|---|---|---|
| `bg-selection` (`Visual`) | `#E0EFFF` | `#233043` | 선택 | 합성 |
| **`bg-same-symbol`** | **`#E8E8E8`** | **`#343438`** | 같은 심볼 | 신규 |

| 토큰 | 라이트 | 다크 | 그룹 | L | D | ΔE | 비고 |
|---|---|---|---|---|---|---|---|
| `syn-kw` | `#A626A4` | `#C792EA` | `Keyword` | 1 | 1 | 1 | - |
| `syn-type` | `#0E7166` | `#57C7B8` | `Type` | 1 | 1 | 1 | - |
| `syn-fn` | `#1A56C4` | `#82AAFF` | `Function` | 1 | 1 | 1 | - |
| `syn-str` | `#2B742E` | `#C3E88D` | `String` | 1 | 1 | 1 | - |
| `syn-num` | `#9E4F00` | `#F78C6C` | `Number` | 1 | 1 | 1 | - |
| `syn-cmt` | `#606570` | `#9AA0AD` | `Comment` | 1 | 1 | 1 | - |
FIXTURE

cat > "$TMP/_workspace/prototype/styles.css" <<'FIXTURE'
:root {
  --syn-kw: #A626A4; --syn-type: #0E7166; --syn-fn: #1A56C4;
  --syn-str: #2B742E; --syn-num: #9E4F00; --syn-cmt: #606570;
  --bg-selection: #E0EFFF; --bg-same-symbol: #E8E8E8;
}
[data-theme="dark"] {
  --syn-kw: #C792EA; --syn-type: #57C7B8; --syn-fn: #82AAFF;
  --syn-str: #C3E88D; --syn-num: #F78C6C; --syn-cmt: #9AA0AD;
  --bg-selection: #233043; --bg-same-symbol: #343438;
}
FIXTURE

cat > "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift" <<'FIXTURE'
public static let teal = token("teal", "#0E7166", "#57C7B8")
public static let syntaxKeyword = token("syntax-keyword", "#A626A4", "#C792EA")
public static let syntaxType = token("syntax-type", "#0E7166", "#57C7B8")
public static let syntaxFunction = token("syntax-function", "#1A56C4", "#82AAFF")
public static let syntaxString = token("syntax-string", "#2B742E", "#C3E88D")
public static let syntaxNumber = token("syntax-number", "#9E4F00", "#F78C6C")
public static let syntaxComment = token("syntax-comment", "#606570", "#9AA0AD")
public static let selection = token("bg-selection", "#E0EFFF", "#233043")
public static let sameSymbol = token("bg-same-symbol", "#E8E8E8", "#343438")
FIXTURE

SELF_FAILURES=0
expect() {
    local want="$1" label="$2"
    run_check "$TMP" > "$TMP/out.txt" 2>&1
    local code=$?
    if [ "$want" = "pass" ] && [ "$code" -ne 0 ]; then
        printf '  SELF-TEST FAIL: %s — 통과해야 하는데 %d 로 실패\n' "$label" "$code"
        sed 's/^/      /' "$TMP/out.txt"
        SELF_FAILURES=$((SELF_FAILURES + 1))
    elif [ "$want" = "fail" ] && [ "$code" -eq 0 ]; then
        printf '  SELF-TEST FAIL: %s — 잡아야 하는데 통과했다\n' "$label"
        SELF_FAILURES=$((SELF_FAILURES + 1))
    else
        printf '  ok: %s\n' "$label"
    fi
}

printf '=== 자기검사 ===\n'
expect pass "값이 맞는 합성 트리에서 통과한다 (죽은 검사기가 아니다)"

cp "$TMP/_workspace/prototype/styles.css" "$TMP/css.bak"
sed -i '' 's/--syn-cmt: #606570/--syn-cmt: #6E7481/' "$TMP/_workspace/prototype/styles.css"
expect fail "CSS 가 낡은 값을 들고 있으면 잡는다"
cp "$TMP/css.bak" "$TMP/_workspace/prototype/styles.css"

cp "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift" "$TMP/swift.bak"
sed -i '' 's/"syntax-number", "#9E4F00"/"syntax-number", "#B85C00"/' \
    "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift"
expect fail "Swift 가 낡은 값을 들고 있으면 잡는다"
cp "$TMP/swift.bak" "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift"

sed -i '' 's/token("teal", "#0E7166"/token("teal", "#0F7A6E"/' \
    "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift"
expect fail "teal 이 syn-type 과 갈라지면 잡는다"
cp "$TMP/swift.bak" "$TMP/Sources/CodeNavigatorAppKit/Design/DesignTokens.swift"

sed -i '' 's/| `syn-kw` | `#A626A4`/| `syn-kw` | `#AA26A4`/' "$TMP/_workspace/02_design.md"
expect fail "문서만 바뀌어도 (나머지 둘이 안 따라오면) 잡는다"

printf '\n'
if [ "$SELF_FAILURES" -gt 0 ]; then
    printf '자기검사 %d건 실패 — 이 검사기를 믿지 마라.\n' "$SELF_FAILURES"
    exit 1
fi
printf '자기검사 통과: 통과도 하고 실패도 한다.\n'
exit 0
