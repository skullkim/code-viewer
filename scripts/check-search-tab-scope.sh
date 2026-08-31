#!/bin/bash
# 검색 결과가 탭을 따라가도록 조립됐는지 본다.
#
# `SearchModel` 은 결과에 탭을 찍어 두고, 활성 탭이 다르면 그 결과를 내주지 않는다. 그
# 판단은 `activeTabProvider` 가 활성 탭을 알려줄 때만 성립한다 — 안 넘기면 기본값 `{ nil }`
# 이 들어가고 **모든 결과가 영원히 "같은 탭의 것"** 이 된다. 조용히.
#
# 단위 테스트는 이걸 못 본다: 테스트는 자기 provider 를 넘겨 SearchModel 을 직접 만들므로
# 앱의 조립을 지나간다. 실측 — 조립부의 provider 를 `{ nil }` 로 바꿔도 15건이 전부 초록이었다.
set -u
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

violations=0
checked=0

# 조립부가 렌더 판정을 주입하는가.
#
# 안 넘기면 기본값 `{ _ in false }` 가 들어가고 **렌더 가능한 파일이 하나도 없는 앱**이 된다 —
# 툴바 버튼은 영원히 비활성이고 ⇧⌘V 는 늘 "렌더할 수 없습니다"를 띄운다. 조용히.
# 실측: 이 주입을 지워도 테스트 34건이 전부 초록이었다(테스트는 AppModel 을 직접 만든다).
render_wired() {
    grep -rn "isRenderableDocument:" "$1" --include='*.swift' 2>/dev/null | grep -c "RenderableDocument"
}
while IFS= read -r file; do
    # 한 파일 안의 SearchModel( 호출 수와, 그 뒤 12줄 안에 provider 가 있는 호출 수를 비교
    calls=$(grep -c "SearchModel(" "$file")
    wired=$(grep -A12 "SearchModel(" "$file" | grep -c "activeTabProvider:")
    checked=$((checked + calls))
    if [ "$calls" -ne "$wired" ]; then
        echo "  $file — SearchModel 조립 ${calls}건 중 ${wired}건만 activeTabProvider 를 넘긴다"
        violations=$((violations + 1))
    fi
done < <(grep -rl "SearchModel(" "$ROOT/Sources" --include='*.swift' 2>/dev/null)

RENDER_WIRED="$(render_wired "$ROOT/Sources")"
if [ "$RENDER_WIRED" -lt 1 ]; then
    echo "  조립부가 렌더 판정을 주입하지 않는다 — 렌더 가능한 파일이 하나도 없는 앱이 된다"
    violations=$((violations + 1))
fi

if [ "$checked" -eq 0 ]; then
    echo "  대상 0건 — 검사가 아무것도 안 보고 있다(경로가 틀렸거나 조립부가 사라졌다)"
    exit 1
fi
if [ "$violations" -ne 0 ]; then
    exit 1
fi
echo "  ok: 조립부 배선 ${checked}건 — 검색은 활성 탭을, 렌더는 확장자 판정을 넘겨받는다"
