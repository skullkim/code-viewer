#!/usr/bin/env bash
# Turns the source SVG into the `.icns` the application bundle carries.
#
# Two things about the source matter and are handled here rather than in the SVG:
#
# 1. **The caret animates.** `<animate>` is right for a web preview and wrong for an icon —
#    the renderer catches whatever frame it happens to land on, which is how the first attempt
#    produced a caret that was half faded out. The element is stripped, so the caret is drawn
#    solid at its declared fill.
# 2. **The SVG declares a fixed 512×512.** Asked for 1024 it drew 512 in the corner of a 1024
#    canvas and left the rest transparent. The width/height attributes are dropped so the
#    `viewBox` scales to whatever size is being rendered.
#
# There is no SVG rasteriser on this machine (no rsvg, inkscape or ImageMagick), so the renderer
# is headless Chrome with a transparent backdrop. macOS icons need the corners transparent —
# the artwork is a rounded rectangle and the space around it must not be painted white.
#
#   build-app-icon.sh              build Resources/AppIcon.icns
#   build-app-icon.sh --self-test  prove the render is sized, opaque and transparent where it should be
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SVG="${SOURCE_SVG:-$HOME/Downloads/icon4_lines.svg}"
OUTPUT_ICNS="$REPO_ROOT/Resources/AppIcon.icns"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# `iconutil` insists on exactly these names. A missing one is not an error — it is an icon that
# looks fine in the Finder and blurry in the Dock, which nobody reports.
ICON_SIZES=(16 32 64 128 256 512 1024)

prepare_html() {  # <size> → an HTML file that draws the artwork at that size
    local size="$1" html="$WORK/render-$size.html"
    python3 - "$SOURCE_SVG" "$html" "$size" <<'PY'
import re, sys
source, destination, size = sys.argv[1], sys.argv[2], sys.argv[3]
svg = open(source).read()

# The animation would otherwise be sampled at an arbitrary moment.
svg = re.sub(r'<animate\b[^>]*/>', '', svg)
svg = re.sub(r'<animate\b.*?</animate>', '', svg, flags=re.S)

# Let CSS size it; keep the viewBox so the artwork scales instead of being cropped.
svg = re.sub(r'(<svg\b[^>]*?)\s+width="[^"]*"', r'\1', svg, count=1)
svg = re.sub(r'(<svg\b[^>]*?)\s+height="[^"]*"', r'\1', svg, count=1)

open(destination, 'w').write(
    '<!doctype html><html><head><meta charset="utf-8"><style>'
    'html,body{margin:0;padding:0;background:transparent;overflow:hidden}'
    f'svg{{width:{size}px;height:{size}px;display:block}}'
    '</style></head><body>' + svg + '</body></html>'
)
PY
    printf '%s\n' "$html"
}

render() {  # <size> <destination.png>
    local size="$1" destination="$2" html
    html="$(prepare_html "$size")"
    "$CHROME" --headless --disable-gpu --force-device-scale-factor=1 \
        --default-background-color=00000000 --hide-scrollbars \
        --screenshot="$destination" --window-size="$size,$size" \
        "file://$html" >/dev/null 2>&1
    [ -f "$destination" ]
}

build() {
    [ -f "$SOURCE_SVG" ] || { echo "FAIL: 원본 SVG 가 없다 — $SOURCE_SVG" >&2; exit 1; }
    [ -x "$CHROME" ] || { echo "FAIL: Chrome 이 없다 — 다른 래스터라이저가 필요하다" >&2; exit 1; }

    local iconset="$WORK/AppIcon.iconset"
    mkdir -p "$iconset"
    for size in "${ICON_SIZES[@]}"; do
        render "$size" "$WORK/$size.png"
    done

    # `iconutil` reads these names, and only these.
    cp "$WORK/16.png"   "$iconset/icon_16x16.png"
    cp "$WORK/32.png"   "$iconset/icon_16x16@2x.png"
    cp "$WORK/32.png"   "$iconset/icon_32x32.png"
    cp "$WORK/64.png"   "$iconset/icon_32x32@2x.png"
    cp "$WORK/128.png"  "$iconset/icon_128x128.png"
    cp "$WORK/256.png"  "$iconset/icon_128x128@2x.png"
    cp "$WORK/256.png"  "$iconset/icon_256x256.png"
    cp "$WORK/512.png"  "$iconset/icon_256x256@2x.png"
    cp "$WORK/512.png"  "$iconset/icon_512x512.png"
    cp "$WORK/1024.png" "$iconset/icon_512x512@2x.png"

    mkdir -p "$REPO_ROOT/Resources"
    iconutil --convert icns --output "$OUTPUT_ICNS" "$iconset"
    printf '  %s · %s\n' "$OUTPUT_ICNS" "$(du -h "$OUTPUT_ICNS" | cut -f1)" >&2
}

# ── 자기 검사 ────────────────────────────────────────────────────────────────
# 아이콘이 틀리는 방식은 조용하다. 크기가 안 맞으면 흐리게 보이고, 배경이 불투명하면
# 흰 사각형이 붙고, 캐럿이 애니메이션 중간이면 반쯤 지워진 채로 굳는다 — 셋 다
# "빌드 성공" 과 구별되지 않는다. 그래서 렌더한 픽셀을 직접 본다.
self_test() {
    printf '=== build-app-icon 자체 검사 ===\n'
    local failures=0
    local probe="$WORK/probe.png"

    render 512 "$probe" || { printf '  FAIL: 렌더 자체가 실패했다\n'; return 1; }

    local width height alpha
    width="$(sips -g pixelWidth "$probe" | awk '/pixelWidth/{print $2}')"
    height="$(sips -g pixelHeight "$probe" | awk '/pixelHeight/{print $2}')"
    alpha="$(sips -g hasAlpha "$probe" | awk '/hasAlpha/{print $2}')"

    check() { [ "$2" = "$3" ] && printf '  ok: %s (%s)\n' "$1" "$2" \
        || { printf '  FAIL: %s — 기대 %s, 실제 %s\n' "$1" "$3" "$2"; failures=$((failures+1)); }; }
    check "요청한 크기로 렌더된다" "$width" "512"
    check "정사각이다" "$height" "512"
    check "알파 채널이 있다" "$alpha" "yes"

    # 모서리는 투명하고 가운데는 불투명해야 한다. **둘 다** 봐야 한다 — 모서리만 보면
    # "전부 투명"(즉 아무것도 안 그려진 이미지)이 통과하고, 가운데만 보면 흰 사각형이 통과한다.
    local cornerAlpha centreAlpha
    cornerAlpha="$(swift "$REPO_ROOT/scripts/probe-image-alpha.swift" "$probe" 2 2 8 8)"
    centreAlpha="$(swift "$REPO_ROOT/scripts/probe-image-alpha.swift" "$probe" 240 240 32 32)"

    if awk "BEGIN{exit !($cornerAlpha < 0.05)}"; then
        printf '  ok: 모서리가 투명하다 (alpha %s)\n' "$cornerAlpha"
    else
        printf '  FAIL: 모서리가 불투명하다 (alpha %s) — Dock 에 흰 사각형이 붙는다\n' "$cornerAlpha"
        failures=$((failures+1))
    fi
    if awk "BEGIN{exit !($centreAlpha > 0.95)}"; then
        printf '  ok: 가운데가 불투명하다 (alpha %s)\n' "$centreAlpha"
    else
        printf '  FAIL: 가운데가 비어 있다 (alpha %s) — 아무것도 안 그려졌다\n' "$centreAlpha"
        failures=$((failures+1))
    fi

    [ "$failures" -eq 0 ] && { printf '  → 자체 검사 통과.\n'; return 0; }
    printf '  → 자체 검사 실패 %s건.\n' "$failures"; return 1
}

case "${1:-}" in
    --self-test) self_test ;;
    *) build; printf '%s\n' "$OUTPUT_ICNS" ;;
esac
