# RESUME — 남은 계획 전체 (2026-09-06 착수)

**상태: 진행 중**

> 사용자 지시: "계획한거 멈추지 말고 싹다해. 토큰 다 쓰면 알아서 나중에 다시 시작하고."
> 즉 **이 목록을 다 끝낼 때까지가 한 작업**이다. 중간에 멈췄으면 여기부터 이어간다.
> 완료 판정은 리더가 `_workspace/POLISH_COMPLETE.md` 를 쓰는 시점이다.

## 진행 표 — 끝낸 것에 ✅ 를 찍는다

| # | 항목 | 상태 |
|---|---|---|
| 1 | 편집기 팔레트 구멍 메우기 (StatusLine·EndOfBuffer·NonText·SignColumn) | ✅ |
| 2 | 멈춘 줄 강조 (디버거가 멈추면 그 줄을 편집기에서 보여준다) | ✅ |
| 3 | 브레이크포인트 거터 표시 | ✅ |
| 4 | 스텝 over / into / out | ⬜ |
| 5 | 인증 후 정리: 중복 테스트 삭제 · 게이트 스텝 주석 | ⬜ |
| 6 | v0.3 DMG 릴리스 | ⬜ |
| + | (계획 밖) 파일 감시자 use-after-free — 게이트가 SIGSEGV 로 잡음 | ✅ |

## 각 항목이 무엇인가

### 1. 편집기 팔레트 구멍
라이트 모드에서 편집기 아래 상태줄이 어두운 회색 막대로 남는다. 우리가 색을 주는 nvim
그룹은 `Normal`·`LineNr`·`CursorLineNr`·`Visual` 등인데 `StatusLine` 이 목록에 없다.
`EndOfBuffer`(`~` 표시)·`NonText`·`SignColumn` 도 같은 상태다.
- 손댈 곳: `Sources/CodeNavigatorCore/Editing/NeovimHighlightScript.swift`,
  `Sources/CodeNavigatorContract/EditorSyntaxPalette.swift`, `DesignTokens.swift`
- 검증: 라이트/다크 양쪽에서 스크린샷. 대비는 WCAG 기준으로 재고 못 넘으면 토큰을 고친다.

### 2. 멈춘 줄 강조
디버거가 멈추면 지금은 패널에만 나온다. 편집기가 그 파일을 그 줄로 열고 강조해야 한다.
`CodeNavigatorSameSymbol` 처럼 `nvim_set_hl` + `matchadd` 로 그룹을 하나 더 만든다.
- 멈춘 줄 → 파일 경로는 프레임의 클래스 이름으로 되짚는다. 우리가 건 브레이크포인트면
  경로를 이미 알고 있다(`DebugBreakpoint.path`). 모르는 프레임은 **강조하지 않는다** —
  엉뚱한 파일을 여는 것보다 낫다.

### 3. 브레이크포인트 거터 표시
건 줄을 거터에서 보이게 한다. nvim `sign` 을 쓴다(`sign_define` + `sign_place`).
클릭으로 토글하는 것은 그 다음 — 거터 클릭 좌표를 줄 번호로 바꿔야 한다.

### 4. 스텝
`EventRequest.Set` 의 STEP(kind 1) + Step modifier(kind 10). depth: INTO=0 OVER=1 OUT=2,
size: LINE=1. 한 번 쓰고 지워야 한다 — 안 지우면 매 줄 멈춘다.

### 5. 인증 후 정리
- `MouseInteractionTests.theSelectedRangeIsVisibleOnScreen` 은 AC-3 중복이다(백엔드 것).
- 프론트의 AC-4 중복도 하나 있다.
- 게이트 각 스텝 주석에 "이 검사가 무엇을 읽는지" 를 적는다 — 미커밋 파일을 읽는 검사가
  게이트에 들어가 판정이 흔들린 적이 있다.

### 6. 릴리스
`scripts/package-dmg.sh` → v0.3. Info.plist 버전을 올리고, README 크기를 실제 값으로
고치고, 릴리스 노트에 디버거·외관 전환·참조 좁히기를 적는다.

## 규율 (비싸게 배운 것)

- **TDD** — 실패 테스트 먼저.
- **조용한 실패를 의심하라.** 이번 증분에서만: 리더 없는 연결이 영원히 매달렸고, 모달
  기본값이 테스트를 멈춰 세웠고, 같은 직렬 큐가 소켓을 반이중으로 만들었다. 셋 다 오류가
  안 났다.
- **판정에 `2>/dev/null` 금지**, 0건은 positive control 뒤에 믿는다.
- **관측 도구를 먼저 의심하라.** `⌘⌥B` 를 보낸다면서 option 플래그를 빠뜨려 앱이 안 된다고
  읽을 뻔했고, `swift test | grep` 의 파이프 버퍼링 때문에 멀쩡히 끝난 실행을 두 번
  "멈췄다" 고 판단했다. 로그는 파일로 받아라.
- **게이트는 조용한 창에서** — 실행 정지 + 트리 동결(커밋도 막는다).
- 새 검사기에는 `--self-test` 를 붙이고 자기검사와 실데이터 시운전을 둘 다 돌린다.

## 이어받는 절차

```bash
cd /Users/skull/Documents/repo/code-navigator-mac
git log --oneline -5
swift test --no-parallel > /tmp/t.log 2>&1; grep -E "✘|Test run with" /tmp/t.log
./_workspace/gate.sh
```

**문서보다 실행을 믿어라.** 위 표의 ✅ 도 마찬가지다 — 미심쩍으면 그 기능을 직접 돌려 봐라.
