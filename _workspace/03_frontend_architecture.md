# 프론트엔드 아키텍처: code-navigator-mac

> 입력: `01_requirements.md`(REQ-001~011·INV-1~4·§6) · `02_design.md`(W-1~W-10·§4 토큰·§6 데이터 요구·§11 리더 판정) ·
> `prototype/shots/`(시각 기준물 21장) · `Sources/CodeNavigatorContract/`(계약 — 단일 소스는 `03_backend_architecture.md §3`)
> 이 문서는 **앱 셸**을 다룬다. 에디터 영역의 텍스트·구문 강조·정의 이동 하이라이트는 Neovim이 그린다(02 §0.1).

## 1. 기술 스택 (선택 근거 포함)

| 항목 | 선택 | 근거 |
|------|------|------|
| 언어 | Swift 6.3.3 (엄격 동시성) | 백엔드와 동일 패키지. 실측 확인 |
| 셸 UI | SwiftUI (macOS 14+) | REQ-011의 창·메뉴·다크모드 추종을 표준으로 얻는다. Apple 공식 관례 |
| 에디터 그리드 | AppKit `NSViewRepresentable` + CoreText `CTFontDrawGlyphs` | SwiftUI 텍스트는 그리드 정렬을 보장하지 못한다 — 실측 근거는 ADR-0101 |
| 상태 관리 | `@MainActor @Observable` (Observation) | 언어·프레임워크의 공식 기본값. 의존성 0. ADR-0103 |
| 테스트 | **Swift Testing** | 프리플라이트에서 동작 실측 완료(Xcode 필요) |
| 번들 | SPM 산출물 + `Info.plist` 조립 스크립트 | REQ-011 AC-1. Xcode 프로젝트를 늘리지 않는다. ADR-0105 |
| 외부 의존성 | **없음** | 전부 표준 프레임워크(SwiftUI·AppKit·CoreText·Observation). 목적당 라이브러리 하나 컨벤션 준수 |

### 1.1 테스트·빌드 실행 명령
```bash
swift build --target CodeNavigatorAppKit      # 작업 중 컴파일 확인
swift test --filter CodeNavigatorAppKitTests  # 작업 중 스코프 테스트
swift build && swift test                     # 게이트 판정 (백엔드 시니어 단독 러너)
./scripts/bundle.sh && ./scripts/verify-bundle.sh   # .app 조립 + 실행 확인
```

### 1.2 빌드/테스트 실행 프로토콜 (공유 워크스페이스 직렬화)
`swift build`·`swift test`는 **패키지 전체**를 대상으로 하고 `.build/` 락을 공유한다.
동시 실행은 가짜 실패를 만든다.
- **풀빌드(`swift test`)는 backend-senior가 단독 러너**다. 게이트 판정도 거기서 1회.
- 나는 작업 중 `--target` / `--filter`로 범위를 좁혀 돌린다. 풀빌드가 필요하면 시간을 겹치지 않게 조율한다.
- 게이트는 **최종 편집 직후 1회** 실행해 보고한다. "아까 그린이었다"는 근거가 아니다.

### 1.3 게이트 정의 (프론트 블록)
`_workspace/gate.sh`는 backend-senior가 먼저 만들고(민감정보 스캔 + 백엔드 블록),
프론트 블록은 **중복 없이** 아래만 추가한다 — `swift build`/`swift test`는 이미 백엔드 블록에 있다.
1. `./scripts/bundle.sh` — `.app` 조립이 성공하는가
2. `./scripts/verify-bundle.sh` — 조립된 앱을 **실제로 띄워** 번들 식별자·메뉴·창이 살아 있는지 확인
   → **디렉토리가 생겼다는 것은 동작의 증거가 아니다.** 존재가 아니라 실행을 확인한다.

---

## 2. 구조

### 2.1 타깃
```
CodeNavigatorAppKit  (라이브러리 — 뷰·모델·순수 로직 전부, 테스트 대상)
  └─ CodeNavigatorContract, CodeNavigatorCore
CodeNavigatorApp     (executable — @main 조립 루트만)
  └─ CodeNavigatorAppKit
CodeNavigatorAppKitTests
```
executable 타깃에는 테스트를 붙일 수 없어서(`main` 심볼로 링크가 깨진다) 분리가 **TDD의 전제**다.
Package.swift는 backend-senior 소유이므로 반영을 요청했다.

### 2.2 소스 배치
```
Sources/CodeNavigatorAppKit/
  Model/        AppModel · ProjectModel · EditorModel · IndexModel · SearchModel
  Logic/        ShellLayout · KeyNotation · StatusBarPresentation · PathDisplay ·
                FileGrouping · MenuAvailability · DefinitionRouting      ← 순수 함수, 테스트의 주 표면
  Grid/         EditorGridView(NSViewRepresentable) · GridRenderer · GlyphCache · GridGeometry
  View/         MainWindow · Toolbar · FileTree · RightPanel · StatusBar ·
                SymbolSearchModal · DefinitionPopover · EditSessionOverlay · WelcomeView
  Design/       DesignTokens (02 §4와 1:1) · SymbolKindBadge
  Menu/         AppMenu (W-9)
Sources/CodeNavigatorApp/CodeNavigatorMain.swift    ← @main. 톱레벨 코드 금지(ADR-0105)
```

### 2.3 상태 모델
엔진의 `AsyncStream` 4개를 `AppModel`이 소유한 `Task`에서 소비하고 MainActor에서 모델을 갱신한다.

| 모델 | 보관 | 출처 |
|------|------|------|
| `ProjectModel` | 현재 프로젝트 · 트리 노드 · 펼침 상태 · **최근 프로젝트(UserDefaults)** | `ProjectSession` |
| `IndexModel` | `IndexState` · 진행률 · 통계 | `indexStateUpdates()` |
| `EditorModel` | `EditorSessionState` · `EditorStatus` · 최신 `EditorGridSnapshot` · `InputMode` | `EditorSession` 3개 스트림 |
| `SearchModel` | 심볼 검색 · 참조 · 전문 검색 각각의 질의/결과/에러/로딩 | `ProjectSession` 조회 |
| `AppModel` | 위 4개 합성 · 상태바 메시지 큐 · 창 복원 상태 | — |

**뷰가 무엇을 보여줄지 정하는 판단은 모델이 아니라 `Logic/`의 순수 함수가 한다.**
02 §3의 상태 정의가 그대로 테이블 테스트 케이스가 된다.

### 2.4 그리드 렌더 파이프라인
```
EditorGridSnapshot ──▶ GridRenderer(순수: 스냅샷 → 드로잉 명령) ──▶ CTFontDrawGlyphs 배치
                                                                    ▲
                        GridGeometry(순수: 뷰 크기 → 행·열 수) ──────┘ ──▶ resizeGrid(columns:rows:)
```
- 좌표는 전부 `컬럼 × 셀폭` 산술. 텍스트 엔진에 컬럼을 맡기지 않는다(ADR-0101).
- 셀 폭은 폰트의 space advance에서 얻는다. 내용에 따라 흔들리면 그리드가 아니다.
- `revision`이 작은 스냅샷은 버린다(늦게 도착한 프레임).
- 커서 셀·선택 배경은 앱이 그린다. **정의 이동 하이라이트는 Neovim이 그린다**(02 §0.1, INV-3).

### 2.5 핵심 아키텍처 결정 (ADR 목록 — 본문 단일 소스는 `docs/adr/`)
- [ADR-0101 에디터 그리드 렌더링](../docs/adr/0101-editor-grid-rendering.md) — CoreText 셀 단위 글리프 배치. 통짜 렌더는 CJK 22px·결합 문자 88px 드리프트(실측)
- [ADR-0102 키 라우팅](../docs/adr/0102-key-routing.md) — 앱은 ⌘ 조합만 claim, 표기법 생성까지만 소유. AppKit 기본 동작으로 성립(실측)
- [ADR-0103 상태 관리](../docs/adr/0103-state-management.md) — `@Observable` + 판단을 순수 함수로 분리
- [ADR-0104 창 레이아웃](../docs/adr/0104-shell-layout.md) — 고정 크롬 먼저 배치, 가변 영역이 잔여를 갖는다(PD 실측 결함 재발 방지)
- [ADR-0105 `.app` 번들·타깃 분리](../docs/adr/0105-app-bundle-and-target-split.md) — 맨 실행 파일은 key window가 안 된다(실측)

---

## 3. 경계면 (계약 소비) — 단일 소스는 `03_backend_architecture.md §3`

HTTP가 없다. 계약은 **Swift 프로토콜 + 값 타입**이고, 어긋나면 **양쪽이 동시에 컴파일 에러**가 난다.
아래는 내가 **소비하는 방식**의 기록이다. 계약 자체를 여기서 정의하지 않는다.

| 화면 | 소비하는 계약 | 비고 |
|------|-------------|------|
| W-1 트리 | `directoryEntries(atRelativePath:)` | `""`가 루트. 지연 로드 |
| W-1 에디터 | `gridUpdates()` · `resizeGrid(columns:rows:)` · `sendKeys(_:)` | 프레임 통째 교체 |
| W-2 열기 | `openProject(at:)` → `NavigatorError.projectNotFound` / `.projectNotReadable` | 사유별 시트 문구 분기. **마스킹 금지** |
| W-2 최근 | **앱 소유(UserDefaults)** | REQ-011 AC-3이 창 크기·분할 비율과 같은 묶음으로 규정 |
| W-3 심볼 검색 | `searchSymbols(matching:)` → `[SymbolSearchResult]` | `matchRanges`는 **UTF-16 오프셋** |
| W-4 정의 후보 | `wordUnderCursor()` → `definitions(named:)` → `openFile(atRelativePath:line:recordJump:)` | 1건 즉시 이동 / N건 팝오버 / 0건 상태바 |
| W-5 참조 | `references(to:)` → `ReferenceSearchResult` | `total`은 **조기 중단 시 관측된 건수**(레포 전체 수 아님) |
| W-6 전문 검색 | `searchText(_:mode:)` → `TextSearchResult` / `.invalidRegularExpression` | 정규식 에러는 **에러로** 받는다. 빈 결과 아님 |
| W-7 상태바 | `statusUpdates()` · `indexStateUpdates()` · `stateUpdates()` · `inputMode()` | 폴링 없음 |
| W-8 오버레이 | `EditorSessionState` · `restart()` | 기동 실패 ↔ 끊김 구분 필요(제안 중) |
| W-10 인덱스 | `indexState()` · `indexStateUpdates()` · 통계 조회 | 통계는 제안 중 |

### 3.1 소비 규칙 (경계면 버그 예방)
- **`matchRanges`는 UTF-16 오프셋**이다(`MatchRange` 주석). SwiftUI 강조 시 `String.Index`로
  변환할 때 반드시 `utf16` 뷰를 경유한다 — `String.count` 기반 인덱싱은 이모지·한글에서 어긋난다.
- **`total`은 레포 전체 건수가 아니다.** `truncated == true`면 "관측된 건수"다.
  02 §3 W-6의 상한 경고 바 문구는 이 의미에 맞춰야 한다("N건 표시").
- **경로 정규화**: `EditorStatus.filePath`는 절대, `DirectoryEntry.path`는 프로젝트 상대다.
  트리 강조(REQ-003 AC-3)는 루트 기준 상대화 후 비교한다. 심링크·`/private` 접두 차이로
  **조용히 매칭 실패**할 수 있어 양쪽 다 `standardizedFileURL`로 정규화한다.
- **런의 그리드 컬럼은 `text`에서 유도하지 않는다** — 계약이 싣는 값을 그대로 쓴다(ADR-0101 실측).
- **에러 문구는 계약의 `errorDescription`을 그대로 쓰지 않는다.** `NavigatorError`는 로그에 맞게 위반 패턴까지 싣는데, 전문 검색 패널에서는 그 패턴이 바로 위 입력창에 이미 보인다. 02 §2 F-6이 요구하는 것은 **원인**이므로 패널이 자기 문구를 만든다(그 외 에러는 `errorDescription` 사용).
- **`Reference.id`·`TextSearchItem.id`가 `"경로:라인"`이므로 항목은 줄당 하나다.** 한 줄에 여러 번 일치하면 `matchRanges`가 복수로 담긴다 — 목록을 줄당 여러 행으로 펼치면 id가 충돌한다.

### 3.2 계약 제안 현황 (backend-senior 판단 대기 — 단일 소스는 백엔드 문서)
| # | 제안 | 근거 | 상태 |
|---|------|------|------|
| 1 | `EditorTextRun`에 `startColumn`·`cellWidth` | nvim `grid_line` 실측 — `인덱스 abc`는 문자 7·**셀 10** | **블로커** |
| 2 | `EditorSessionState`에 기동 실패를 끊김과 분리(+ 탐색 경로·필요 버전 0.9.0) | W-8 카드 3종 / REQ-NF-005 | 대기 |
| 3 | 인덱스 통계 조회(`fileCount`·`symbolCount`·`skippedCount`·`lastUpdatedAt`) | **스킵 건수는 REQ-002 AC-4의 유일한 UI 표면** | 대기 |
| 4 | 저장 이벤트에 `lineCount`·`byteSize` | 02 F-7 상태바 문구 | 대기(없으면 문구 축약) |
| 5 | 마우스 입력 경로 | REQ-010 AC-2 "클릭으로 커서 이동" | 대기 |
| 6 | 정규식 에러 `position` | 02 §6. 엔진이 못 뽑으면 **UI에서 제거** 제안 | 대기 |
| 7 | 전문 검색 결과에 `filesSearched` | 02 §3 W-6 메타 문구가 "N건 표시 · **M 파일 검색** · T초"인데 계약에 검색한 파일 수가 없다. 없으면 **일치한 파일 수**로 문구를 바꿔 표시한다(숫자를 지어내지 않는다) | 대기 |

---

## 4. 작업 분해

**위임 원칙**: 계약·경계면·그리드·키 라우팅·레이아웃 기반은 시니어. **기반이 선 뒤의 격리된 화면**은 주니어.
주니어 스폰은 리더가 관리한다 — 나는 `tasks.md`에 스펙을 남길 뿐 스폰·생존을 가정하지 않고,
다른 에이전트가 owner인 파일을 동시에 편집하지 않는다.

| # | 작업 | REQ-ID | 복잡도 | 담당 | 완료 기준(통과 테스트) |
|---|------|--------|--------|------|---------------------|
| F-01 | 디자인 토큰(02 §4 색·타이포·간격, 라이트/다크) | REQ-011 AC-4 | 낮음 | senior | 토큰 22색 × 2테마 값이 §4.1 표와 일치. `colorScheme` 분기 |
| F-02 | `ShellLayout` 치수 계산 | REQ-011 AC-3, 02 §4.4 | 중간 | senior | 창 폭 1600·1280·1000·900·820·720에서 트리·에디터·패널 폭·오버레이 여부. **820에서 상태바 26px 생존** |
| F-03 | `KeyNotation` 변환 + 앱 단축키 판별 | REQ-010 AC-5, REQ-011 AC-2 | 중간 | senior | ⌃O·⌃R·⌃V·⌃W·`:`·Esc·화살표·⇧조합 표기법. ⌘ 조합 판별. **spike 버그 2건 회귀 테스트** |
| F-04 | 그리드 렌더러(글리프 캐시·배치·기하) | REQ-004 AC-2 | 높음 | senior | 컬럼 N이 N×셀폭. CJK·결합 문자 드리프트 0. 뷰 크기 → 행·열 역산 |
| F-05 | `EditorGridView` + 키 입력 배선 | REQ-004 AC-2, REQ-010 AC-1 | 높음 | senior | `intrinsicContentSize` 없음. 리사이즈 시 `resizeGrid` 호출. 스냅샷 `revision` 역행 드롭 |
| F-06 | `AppModel` + 스트림 소비 배선 | REQ-004·009·010 | 높음 | senior | 4개 스트림이 모델에 반영. 스트림 종료 시 상태 정합 |
| F-07 | 메인 창 셸(3영역 + 스플리터 + 복원) | REQ-011 AC-1·AC-3 | 높음 | senior | 창 크기·분할 비율·트리/패널 표시가 재시작 후 복원 |
| F-08 | 상태바 W-7 | REQ-004·009·010·011 | 중간 | senior | 모드 6표시 · 경로 축약 · 더티 ● · 메시지 3종(2초/3초/상시) · 좁은 창 숨김 순서. **모드·인덱스 칩은 절대 안 숨김** |
| F-09 | 메뉴 막대 W-9 + 편집 메뉴 모드별 활성 | REQ-010 AC-3·AC-5, REQ-011 AC-2 | 중간 | senior | 6메뉴 항목·단축키. **Vim 모드에서 ⌘Z·⌘C·⌘V·⌘A 비활성, ⌘S만 공통 활성** |
| F-10 | 입력 모드 토글(메뉴·⌃⌘V·툴바 세그먼트) + 복원 | REQ-010 전체 | 중간 | senior | 2수단 + 세그먼트(§11 판정 5). 전환이 저장을 일으키지 않음. 재시작 복원 |
| F-11 | 편집 세션 오버레이 W-8 | REQ-004 AC-1·AC-5, REQ-NF-005 | 중간 | senior | 연결 중·기동 실패·끊김 3카드. 에디터만 흐림, 트리·패널 정상. **[읽기 전용으로 계속] 없음**(§11 판정 6) |
| F-12 | 파일 트리 W-1 좌측 | REQ-003 | 중간 | **junior** | 지연 로드 · 선택 강조 · 더티 ● · 키보드 ↑↓←→Enter. 제외 대상은 코어가 이미 거름 |
| F-13 | 프로젝트 열기 W-2(웰컴·최근·실패 시트) | REQ-001 | 중간 | **junior** | 최근 0/N건 · 여는 중 · 실패 2종 시트(경로/권한 문구 분기) · 제외 규칙 고지 |
| F-14 | 심볼 퍼지 검색 모달 W-3 | REQ-007 | 중간 | **junior** | 입력 전·결과·0건·인덱싱 중 배너·로딩(200ms↑). ↑↓/⏎/esc 키보드 완결 |
| F-15 | 참조 패널 W-5 | REQ-006 | 중간 | **junior** | 초기·로딩·정상·0건. **근사 안내 배너 상시**(0건에도 유지) · [정의] 배지 · 파일별 그룹 |
| F-16 | 전문 검색 패널 W-6 | REQ-008 | 중간 | **junior** | 입력 전·로딩·정상·0건·**정규식 에러(이전 결과 40% 흐림 유지)**·상한 경고 바 |
| F-17 | 정의 후보 팝오버 W-4 | REQ-005 | 중간 | senior | N≥2 목록 · 1건 즉시 이동 · 0건 상태바 3초 · **긴 시그니처 한 줄 말줄임**(PD 실측 결함 2) · 가장자리 플립 |
| F-18 | 인덱스 상태 칩·상세 팝오버 W-10 | REQ-009, REQ-002 AC-4 | 낮음 | **junior** | 5상태 1:1 · 진행률 · 비-최신 툴팁 · 상세 팝오버(스킵 건수) |
| F-19 | `.app` 조립 + 실행 검증 스크립트 | REQ-011 AC-1 | 낮음 | senior | 조립 후 **띄워서** 번들 식별자·메뉴·창 확인 |

**위임 선행 조건**: F-12~F-16·F-18은 F-01(토큰)·F-02(레이아웃)·F-06(모델)이 서 있어야 시작할 수 있다.
그 전에 넘기면 주니어가 기반을 추측하게 되고 그게 재작업이 된다.

## 5. 스타일 완료 정의
토큰 정의로 끝이 아니다. **컴포넌트가 쓰는 모든 시각 속성에 실제 값이 있고, 02 §4.4의 창 폭
적응이 동작해야** 완료다. 테스트는 시각을 검증하지 않으므로, 각 화면은 **실제 앱 스크린샷을
`prototype/shots/`의 대응 화면과 대조**해 완료를 판정한다(작은 창 1000×700 · 큰 창 1600×1000 ·
좁은 창 820×620). 위임 작업의 완료 기준에도 이 대조가 포함된다.

## 6. REQ 역방향 커버리지
| REQ | 작업 |
|-----|------|
| REQ-001 | F-13, F-07(복원) |
| REQ-003 | F-12 |
| REQ-004 | F-04·F-05(그리드) · F-11(세션 상태) · F-08(더티·저장 메시지) |
| REQ-005 | F-17 |
| REQ-006 | F-15 |
| REQ-007 | F-14 |
| REQ-008 | F-16 |
| REQ-009 | F-18 · F-08(인덱스 칩) |
| REQ-010 | F-03·F-09·F-10 · F-08(모드 세그먼트) |
| REQ-011 | F-01(다크모드) · F-02·F-07(창·복원) · F-09(메뉴·단축키) · F-19(`.app`) |
| INV-3 | 앱에 파일 쓰기 경로 없음 — ⌘S조차 `:w` 위임. F-09에서 검증 |
| INV-4 | Neovim 상태줄·명령줄을 가리지 않는다. F-05 프레임 배치에서 검증 |

**미커버 프론트 REQ 없음.**
