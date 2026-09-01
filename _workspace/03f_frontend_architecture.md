# 프론트엔드 아키텍처 — 증분 3 (REQ-015 ~ REQ-017)

- 작성: frontend-senior
- 날짜: 2026-09-01
- 기준 트리: `c7a6bf7` (+ 이 증분의 미커밋 변경)
- 영역: `Sources/CodeNavigatorAppKit/` — 그리드 렌더 · 키 라우팅 · 셸 · 디자인 토큰

> 이 문서는 **결정과 분해**만 담는다. 결정의 근거 본문은 `docs/adr/` 이 단일 소스다.

---

## 0. 이번 증분에서 실제로 무엇이 문제였나

**REQ-017(마우스)은 "안 만든 기능"이 아니라 "죽은 기능"이었다.**

```
NSInternalInconsistencyException  'Invalid message sent to event "NSEvent: type=LMouseDown …"'
  -[NSEvent keyCode]
  ← KeyStroke.init(NSEvent)
  ← EditorGridNSView.forward(_:action:button:)
  ← EditorGridNSView.mouseDown(with:)
```

`forward()` 가 수식어 하나를 읽으려고 `KeyStroke(event)` 를 통째로 만들었고, 그 init 이
`keyCode`·`characters` 를 읽는다. **셋 다 키보드 전용**이고 AppKit 은 마우스 이벤트에 기본값을
주는 대신 예외를 던진다. 예외는 AppKit 이벤트 루프가 삼켜서 **크래시도 로그도 사용자에게
보이지 않았다.**

엔진(`sendMouse`)은 처음부터 옳았고, 실제 nvim 을 띄우는 라이브 테스트가 커서 이동·드래그
선택까지 검증하며 **계속 통과 중이었다.** 좌표 변환도 옳았고 배선도 전 구간 연결돼 있었다.

> **지난 빌드 교훈 2번의 네 번째 사례다** — 미마운트 뷰 · 반쪽 연결된 번역기 · 호출부 0건인
> 카운터 · 안 읽히는 활성 플래그에 이어, **값은 전부 옳은데 경로가 없는** 다섯 번째 형태.

**왜 아무도 못 봤나**: `EditorFocusTests` 가 `view.mouseDown(with:)` 을 부르지만 **포커스만**
단언한다. `onMouse` 가 불리는지 보는 테스트가 **어느 계층에도 없었다.** 엔진 테스트는
`session.sendMouse` 에서 시작하는데, 그건 문제가 난 지점보다 **뒤**다.

---

## 1. 결정 (ADR 본문은 링크가 단일 소스)

| ADR | 결정 | REQ |
|---|---|---|
| [0112](../docs/adr/0112-editor-syntax-colour-ownership.md) | 에디터 구문 색은 **앱 디자인 시스템이 소유**한다. 색 6종을 `ColorToken` 으로 승격하고, `02_design.md:10`·`:289` 의 "Neovim 소유" 문구를 대체한다 | REQ-016 AC-3·AC-6 |
| [0113](../docs/adr/0113-gd-gr-without-a-swift-prefix-machine.md) | `gd`/`gr` 은 **Neovim 매핑**으로 붙인다. `EditorKeyInput.route` 는 건드리지 않는다 | REQ-015 |
| [0010](../docs/adr/0010-syntax-highlight-source.md) (백엔드) | 분류는 Neovim `syntax` 엔진, 색은 앱이 `nvim_set_hl` 로 덮는다 | REQ-016 |

**두 ADR 이 서로 맞물리는 지점**: 0010 이 "앱이 색을 준다"고 정했고, 0112 가 "그 색은
디자인 토큰이다"를 정한다. 0010 없이 0112 는 갈 곳이 없고, 0112 없이 0010 은 **어떤 색인지가
안 정해진다.**

### `route()` 표를 먼저 봤다 — 늘어나는 칸은 없다

리더 지시대로 `NamedKeyRoutingTableTests` 를 먼저 읽었다. 그 표는 **`NamedKey` 14종**만
다루고, `g`·`d`·`r` 은 이름 있는 키가 아니라 **평범한 글자**다. 노멀 모드의 글자는 `route()`
첫 분기에서 표기법으로 바뀌어 곧장 나가므로 **결함이 세 번 났던
`return .interpretForComposition` catch-all 에 닿지도 않는다.**

→ **이번 증분은 그 표의 칸을 늘리지 않는다.** ADR-0113 은 늘리지 않는 쪽을 일부러 골랐다.

---

## 2. 데이터 계층 매핑 — 계약을 화면으로

### 2.1 강조 (REQ-016) — 색은 나가고, 픽셀은 들어온다

```
DesignTokens.syntax*  ──(팔레트, 앱→세션)──▶  nvim_set_hl        ← 나가는 방향. 새로 만드는 유일한 배관
                                                   │
                                      nvim 이 분류하고 색을 붙임
                                                   ▼
hl_attr_define → EditorTextStyle → EditorTextRun → GridFrameBuilder → GridRenderer → 픽셀
                                                   ▲
                                       ── 이미 전부 있다. 손대지 않는다 ──
```

**들어오는 방향은 이미 끝까지 뚫려 있다.** 이것이 ADR-0010 이 "계약 변경 0"이라고 쓴 근거이고,
내 쪽 작업이 작은 이유다. 새 배관은 **한 방향 호출 하나**다.

| 계약 | 앱 쪽 소비 |
|---|---|
| `EditorSyntaxPalette` (백엔드 정의 대기) | `DesignTokens.syntaxTokens` + 평탄화된 `match` 로 조립 |
| `EditorTextStyle.foreground/background` | `GridFrameBuilder.resolvedColours` — **변경 없음** |
| `EditorGridSnapshot.defaultForeground/Background` | 동일 — **변경 없음** |

✅ **합의 완료** — 백엔드가 `EditorSyntaxPalette` 를 **8필드**로 정의했다(구문 6 + `sameSymbolBackground` + `selectionBackground`). 색 타입은 `EditorColor`. 내가 제안한 7개에 **선택 배경이 하나 더** 붙었고, 그래서 REQ-017 AC-3 의 선택 색도 이제 우리 토큰(`accent-dim`)에서 온다.

### 2.2 `gd`/`gr` (REQ-015) — 의도만 들어온다

```
nvim 매핑 ──rpcnotify──▶ 세션 ──▶ 앱 ──▶ MenuCommandRouter.perform(.goToDefinition / .showReferences)
                                              │
                                    ⌘B · ⇧⌘B 와 같은 입구
```

**같은 결과를 보장하는 방법은 같은 코드를 부르는 것이다.** AC-1·AC-2·AC-4 가 전부 "⌘B/⇧⌘B와
같은 결과"로 쓰여 있고, AC-3(기존 키가 그대로 동작)은 메뉴 경로를 안 건드리므로 구조로 지켜진다.

⚠ **지름길 금지**: `AppModel.showReferences` 를 직접 부르면 `wordUnderCursor` 해소가 통째로
빠진다 — `showReferences` 는 라우터가, `goToDefinition` 은 `AppModel` 이 푸는 **비대칭**이 있다.
라우터로 들어가야 둘 다 제 방식대로 돈다. AC-5 문구도 라우터 것이 따라온다.

### 2.3 마우스 (REQ-017) — 수식어만 읽는다

`KeyModifiers.init(NSEvent)` 로 분리했다. `modifierFlags` 는 **모든 이벤트 종류가 답하는 유일한
속성**이고, `KeyStroke.init` 이 이것을 재사용하므로 플래그 매핑은 여전히 한 곳이다.

---

## 3. 작업 분해

| # | 작업 | REQ / AC | 소유 | 상태 |
|---|---|---|---|---|
| F1 | `forward()` 가 `KeyStroke` 를 만들지 않게 — `KeyModifiers.init(NSEvent)` 분리 | 017 AC-1·2 | frontend-senior | ✅ 완료 |
| F2 | 뷰 계층 마우스 전달 테스트(발신·순서·세로축·가로축) | 017 AC-1·2 | frontend-senior | ✅ 완료 |
| F3 | 선택이 **화면에 보이는지** 라이브 단언 | 017 AC-3 | frontend-senior | ✅ 완료 |
| F3b | 마우스 선택에 Vim 명령이 먹는지 라이브 단언 | 017 AC-4 · SC-12 | frontend-senior | ✅ 완료 |
| F4 | 구문 색 6종 `ColorToken` 승격 + 대비·발행값·teal 동기 테스트 | 016 AC-3 | frontend-senior | ✅ 완료 |
| F5 | `TranslucentColorToken.flattened(over:for:)` — 알파 없는 곳으로 넘길 색 | 016 AC-2 | frontend-senior | ✅ 완료 |
| F6 | ADR-0112 · ADR-0113 | 015·016 | frontend-senior | ✅ 완료 |
| F7 | 팔레트 조립(`SyntaxPaletteBuilder`) + 연결 시 전달 | 016 AC-1·3·6 | frontend-senior | ✅ 완료 |
| F8 | 외형 전환 시 팔레트 재전송(`viewDidChangeEffectiveAppearance`) | 016 AC-6 | frontend-senior | ✅ 완료 |
| F9 | `navigationRequests` → `MenuCommandRouter` 배선 (합성 루트) | 015 AC-1·2·5 | frontend-senior | ✅ 완료 |
| F10 | 최종 프론트 게이트(tsc 해당 없음 — `swift build` + 전체 테스트 + 디자인 충실도) | 전체 | frontend-senior | ⏸ 트리 그린 뒤 |

### 주니어에게 위임하지 않는다 — 이유

**독립적이고 기반이 준비된 배치가 없다.** 남은 작업 F7·F8·F9 는 전부 **백엔드 계약 합의에
매달려 있고**(팔레트 필드·색 타입·알림 이름), 셋 다 파일 한두 개 규모다. 위임의 이득보다
**소유권 조율 비용이 크다** — 지난 빌드에서 주니어 2명이 marginal 했고 visibility 충돌이 3회
났다. 기반이 서고 나면 남는 것은 배선 몇 줄이라 시니어가 마무리하는 것이 맞다.

*(주니어 스폰은 리더 소관이다. 필요해지면 리더에게 요청한다 — 스폰 여부를 가정하지 않는다.)*

---

## 4. 커버리지 — REQ ↔ 테스트

| REQ / AC | 테스트 | 상태 |
|---|---|---|
| 017 AC-1 (클릭 → 커서) | `EditorMouseForwardingTests` 발신·세로축·가로축 + `NeovimMouseInputTests` 좌표 | ✅ |
| 017 AC-2 (드래그 → 선택) | `EditorMouseForwardingTests` 순서 + `NeovimMouseInputTests.dragCreatesSelection` | ✅ |
| 017 AC-3 (선택이 보인다) | `NeovimMouseInputTests.theSelectionIsVisibleOnScreen` | ✅ |
| 017 AC-4 (선택에 Vim 명령) | `NeovimMouseInputTests.vimCommandsApplyToASelectionMadeWithTheMouse` (SC-12) | ✅ |
| 017 AC-5 (휠·더블클릭 범위 밖) | 해당 없음 (명시적 범위 밖) | — |
| 016 AC-3 (색이 토큰에서) | `DesignTokenTests` 발행값 일치 · 대비 · teal 동기 | ✅ |
| 016 AC-2 (같은 심볼 배경색) | `TranslucentTokenFlatteningTests` + `SyntaxPaletteBuilderTests` 평탄화 | 🟡 색만. 커서 따라 갱신은 백엔드 `matchadd` |
| 016 AC-6 (앱 테마가 이긴다) | `SyntaxPaletteWiringTests` 연결·재연결·외형전환·중복억제 | ✅ |
| 016 INV-8 (강조 실패가 편집을 안 막는다) | `SyntaxPaletteWiringTests` 팔레트 실패 | ✅ |
| 016 AC-1·4·5 | 백엔드 spike + 라이브 | ⏸ |
| 015 AC-1·2 (신호가 앱에 닿는다) | `SyntaxPaletteWiringTests` gd/gr 도착 + `NavigationRequestRoutingTests` 매핑 | ✅ |
| 015 AC-3·4·5·6 | 라우터 재사용으로 구조 충족 — 라이브 확인 대기 | ⏸ |

**⚠ 이 표의 ✅ 는 "테스트가 있다"이지 "라이브로 봤다"가 아니다.** 아래 5절이 그것을 가른다.

---

## 5. 아직 주장하지 않는 것

- **마우스는 라이브로 아무도 안 눌러봤다.** 경로가 열린 것까지가 측정된 것이다. 지난 빌드의
  방향키가 정확히 이 자리에서 샜다 — 테스트 1,407건·게이트 31종·라이브 검증 6회를 통과하고
  **사용자가 찾았다.** 리더 인증 때 실물 클릭·드래그가 필요하다.
- ~~`syntax-number` 4.60:1 · `syntax-comment` 4.69:1~~ — **철회한다. PD 개정으로 없는 값이다.**
  내가 `02_design.md:289` **산문**에서 승격했는데 PD 가 그 사이 **§4.1.1 표**를 발행해 5개 값이
  갈라졌다. 발행값 기준 최악은 다크 `syn-cmt` **4.73**(여유 0.23), 전 항목 4.5 이상.
  **교훈은 수치가 아니라 출처다** — 산문은 "이런 색들이 있다"를 적고 표는 "어느 표면에서
  얼마인가"를 적는다. 구현이 읽어야 하는 것은 표였다.
- **순서 위험 (미해결, 미측정)**: `MainWindowView` 가 이벤트마다 `Task { }` 를 따로 만든다.
  `AppModel` 은 `@MainActor`, `NeovimEditorSession` 은 `actor` 라 **액터 홉에서 FIFO 가 언어
  보장이 아니다** — press/drag/release 가 뒤집힐 수 있다. 다만 **키 입력이 같은 경로를 훨씬 높은
  빈도로 쓰는데 타이핑이 뭉개지지 않는다** — 실측 증거가 "순서가 지켜진다" 쪽이다. 그래서
  **재지 않은 문제에 기계를 만들지 않는다.** 기록해 두고, 실제로 뒤집힌 사례가 나오면 직렬 큐를
  ADR 로 올린다.

---

## 6. 측정 기록 (커밋 해시 병기)

| 잰 것 | 결과 | 시각 |
|---|---|---|
| `EditorMouseForwardingTests` @ `c7a6bf7` (수정 전) | **crash** — NSInternalInconsistencyException | 13:48 |
| 같은 스위트 (수정 후) | 4/4 통과 | 13:50 |
| AppKit 전체 `--no-parallel` | **980건 / 100 스위트 통과** | 13:51 |
| `NeovimMouseInputTests` (AC-3 신규 포함) | 6/6 통과 | 14:0x |
| 같은 스위트 — **변이 클론**(`style(fromAttributes:)` 가 배경을 버림) | **AC-3 만 실패, 나머지 5건 통과** | 14:1x |
| `DesignTokenTests` | 12/12 통과 | 14:2x |
| `TranslucentTokenFlatteningTests` | 4/4 통과 | 14:2x |
| `NeovimMouseInputTests` (AC-4 추가, 클론) | 7/7 통과 | 14:3x |
| `SyntaxPaletteBuilderTests` · `NavigationRequestRoutingTests` · `SyntaxPaletteWiringTests` | 5 + 5 + 6 통과 | 15:0x |
| **AppKit 전체 (클론, 배선 완료 후)** | **1,003건 / 104 스위트 통과** | 15:1x |
| **전체 스위트 — 실제 트리, 백엔드 그린 후** | **1,486건 / 191 스위트 통과** @ `c7a6bf7`+미커밋 (직전 인증 1,407) | 15:2x |
| AC-5 테스트 4건 추가 후 **전체 재측정** | **1,499건 / 193 스위트 통과** @ `c7a6bf7`+미커밋 | 16:0x |
| 외형 보고 3건 추가 후 **최종** | **1,502건 / 194 스위트 통과** @ `c7a6bf7`+미커밋 | 16:1x |
| 프론트 시각 회귀(`DesignRegression`, 게이트 443행) | 16건 / 2 스위트 통과 — 토큰 추가가 안 깼다 | 16:0x |
| 같은 스위트 — **변이 클론**(`.drag` 를 `press` 로 뭉갬) | **AC-3·AC-4 실패**, 버퍼 20줄 그대로 | 14:3x |

**변이 실측이 가른 것**: 배경을 버리면 선택이 안 보이는데 **기존 마우스 테스트 5건은 전부
통과한다.** `dragCreatesSelection` 은 *모드*를 묻지 *화면*을 묻지 않기 때문이다. AC-3 테스트만
빨간불이 된다 — **"모드가 바뀌었다"와 "보인다"는 다른 질문**이라는 것의 실측 증거다.

*(변이는 `/tmp/cn-mutant` 클론에서만 했고 되돌렸다. 작업 트리에 변이가 들어간 적 없다 —
`grep MUTANT Sources/ Tests/` 0건으로 확인.)*

---

## 7. 블로커

1. **`EditorSyntaxPalette` 계약 미정** (backend-senior) — F7·F8 착수 불가
2. **`rpcnotify` 알림 이름 미정** (backend-senior) — F9 착수 불가
3. ~~트리 컴파일 실패~~ — **해소됨.** 백엔드가 고쳤고, 실제 트리에서 **1,486건 전부 통과**.

**게이트를 지금 돌리지 않는 이유**: `gate.sh` 의 격리 스텝은 *"머신에서 다른 `swift test` 가
돌지 않는다"* 를 전제한다(gate.sh 61행). 백엔드가 아직 작업 중이라 지금 돌리면 **가짜 빨간불**이
나고 상대 작업도 방해한다 — DECISIONS.md 가 "조용한 창은 셋이 모일 때 한 번만 연다"고 정한 그
이유다. 창은 리더가 연다.
