# QA 리포트 — Round 1 (점진 검증)

- 검증자: qa · 검증 시각 **2026-08-29 17:19–17:26**
- 프로젝트: code-navigator-mac (Swift 네이티브, SPM + Swift Testing)

## 0. 이 라운드의 범위 (점진 검증)

**완성분인 백엔드 코어만 검증했다.** 개발이 진행 중이므로 아래는 이번 라운드에서 **수행하지 않았다**:

| 미수행 항목 | 사유 | 언제 |
|---|---|---|
| **방어선 실측**(일부러 깨뜨려 빨간불 확인) | 코어가 계속 변경 중 — 깨뜨린 채 두면 팀의 게이트를 오염시킨다 | **최종 라운드** |
| **라이브 앱 실행 E2E** | `.app` 셸 미구현(F-19 대기), `CodeNavigatorApp`은 placeholder 1줄 | **최종 라운드** |
| **디자인 충실도 대조**(`02_design.md` + `prototype/shots/`) | 렌더할 UI가 아직 없다 | **최종 라운드** |
| 프론트 F-04·05·06·11 | 계약 #1 미확정으로 대기 중 — 검증 대상 아님 | 완료 보고 시 즉시 |
| 백엔드 BE-08·09·10 | 배치 대기 | 완료 보고 시 즉시 |

> 이 표의 3개 항목은 **리더 인증 대기 항목**이다. 이 리포트의 어떤 PASS도 "빌드 완료"를 뜻하지 않는다.

## 1. TDD 게이트

### 테스트 실행 (QA 직접 실측)
```
$ swift test          # 17:19:47 실행
✔ Test run with 243 tests in 27 suites passed after 4.030 seconds.
```
- **243 tests / 27 suites 전부 통과.** 실패 0.
- 실행 전 확인: `swift-build`/`swiftc` 프로세스 없음, `.build` 락 없음 → **빌드 락 충돌로 인한 가짜 실패 아님**.
- 잔여 `nvim` 프로세스 없음 확인 → 장수 프로세스 착시 배제.
- **필터를 쓰지 않았다.** `swift test --filter`가 매칭 0건이면 "0 tests passed"로 초록불이 뜨는 함정(frontend-senior 발견)을 피하려 전체 실행 수치만 인용한다.
- 리더가 17:14에 본 **192/21**과 다른 이유: 그 사이 `AcceptanceScenarioTests`(8) 등이 추가됐다. 코드가 검증 중에도 변하고 있다.

### 커버리지 매트릭스 — ⚠️ 불완전 (반려 아님, 갱신 요청)
`_workspace/04_coverage_matrix.md`에는 **7행뿐이고 전부 backend-junior 기여분**이다. backend-senior가 직접 구현한 영역의 행이 없다.

| 매트릭스에 행이 없는 REQ | 실제 테스트 존재 여부 |
|---|---|
| REQ-001 (프로젝트 열기·전환) | **있다** — `ProjectScannerTests`(12), `ProjectIndexerTests`(13) |
| REQ-002 (심볼 인덱싱 4언어) | **있다** — `SymbolExtractorTests`(22), `SymbolIndexTests`(14) |
| REQ-004 (Neovim 임베드) | **있다** — `NeovimChannelTests`(12), `NeovimEditorSessionTests`(10), `NeovimGridStateTests`(16) |
| REQ-005 (정의로 이동) | **있다** — `AcceptanceScenarioTests` SC-1·SC-2 |
| REQ-009 (자동 재인덱싱) | **있다** — `ProjectIndexerTests`, `FileSystemWatcherTests`(5), `FileChangeBatchTests`(7) |
| REQ-NF-001 (성능) | **있다** — `IndexingPerformanceTests`(3) |
| INV-1·3·4 | **있다** — `ProjectIndexerTests`, `NeovimChannelTests`(INV-3·INV-4 명시 테스트) |

### 통과용 테스트 판별 (전 22개 테스트 파일 정독)
단언 없음 · 구현 미러링 · 하드코딩 기대값 · "무언가 일어났다"류 약한 단언 · 빈 컬렉션 위 공회전 루프를 기준으로 전수 검토했다. **252개 `@Test` 중 실질 결함 2건.**

| 판정 | 건수 | 내용 |
|---|---|---|
| 항진 단언(무조건 참) | 1 | `SymbolExtractorTests.swift:287` → **관찰 #5** |
| 이름이 주장하는 동작에 단언 없음 | 1 | `AcceptanceScenarioTests.swift:38-58` SC-1 → **관찰 #3** |
| 조건부 스킵(숨은 커버리지 구멍) | 1 | `DirectoryTreeListerTests.swift:155` `guard getuid() != 0 else { return }` — root 실행 시 권한 테스트가 조용히 통과. 로컬 개발에선 합리적이며 **결함 아님**. 다만 CI를 root로 돌리면 이 테스트가 사라진다는 점만 기록해둔다 |
| `.enabled(if:)` / `.disabled` | **0** | Neovim 부재 시 조용히 스킵하는 테스트 없음 — `NeovimChannelTests`는 미설치를 **명시적 에러 테스트**로 다룬다(스킵이 아니라 단언). 좋은 설계다 |

검토했으나 **결함이 아니라고 판정**한 것들(기록용):
- `NeovimEditorSessionTests`의 `#expect(x != nil)` 4건(:129·133·203·219)은 약한 단언이 **아니다**. `firstValue(from:where:)`가 술어에 맞는 값이 왔을 때만 non-nil을 돌려주므로 실제 단언은 술어가 지고 있다(`isDirty` / `hasSuffix("App.kt")` / `case .disconnected` / `columns==100 && rows==30`). 더티 테스트는 디스크 내용까지 추가 단언한다.
- `MessagePackCodecTests`의 왕복 테스트는 인코더·디코더 쌍을 함께 쓰지만, 폭 경계 테스트가 **msgpack 스펙이 정한 전이점(127/128, 255/256…)의 바이트 수를 단언**하고, `NeovimChannelTests`가 실제 Neovim(독립 구현)과 와이어로 통신하므로 상쇄 버그가 빠져나갈 경로가 막혀 있다.
- `FuzzyMatcherTests:71-77`의 하드코딩 점수(20/10/5)는 관찰값 복사가 아니라 `FuzzyMatcher` 문서 주석의 예제를 고정한 것이다(대조 확인). 의도적 계약 고정.
- ✅ `NeovimEditorSessionTests:139-160`(부착 전 키 큐잉)은 팀이 저널에 기록한 "가짜 초록"의 **수정된 버전**이다. 이제 실제 버퍼 내용(`contains("queued text")`)을 단언해 큐잉 코드를 지우면 빨간불이 뜬다. 같은 함정의 재발 없음을 확인했다.

**판정: 테스트는 있는데 매트릭스가 낡았다.** 게이트 미충족으로 반려하지 않는다 — 다만 지금 상태의 매트릭스로는 **게이트를 평가할 수 없다**(대부분의 REQ가 미커버로 보인다). backend-senior에게 자기 기여분 행 추가를 요청했다. 게이트 상태란도 "(미실행)"이라 실제 실행 결과와 어긋난다.

## 2. 계약 표면 전수 대조 (최우선)

`03_backend_architecture.md §3` ↔ `Sources/CodeNavigatorContract/` ↔ 구현을 **하나씩** 대조했다.
"전체 그린"은 존재하는 테스트의 그린일 뿐이므로, 문서에 있는 항목이 **실재하는지**를 개별 확인했다.

### 2.1 값 타입 (§3.1) — 22행 전수 대조: **일치**
`SymbolKind`(7케이스) · `SymbolDefinition`(5필드) · `MatchRange` · `SymbolSearchResult` · `Reference` · `ReferenceSearchResult` · `TextSearchItem` · `TextSearchResult` · `TextSearchMode` · `DirectoryEntry` · `IndexProgress` · `IndexState`(5케이스) · `EditorSessionState`(4케이스) · `EditorMode`(7케이스) · `InputMode` · `EditorGridSnapshot`(8필드) · `EditorGridLine` · `EditorTextRun` · `EditorTextStyle` · `EditorColor` · `EditorCursorPosition` · `EditorStatus`(6필드) · `ProjectDescriptor` · `NavigatorError`(**10케이스** + 한국어 `errorDescription` 전 케이스).

- 문서는 `NavigatorError`를 "9개 케이스"로 적었으나 실제는 **10개**(`editorRequestFailed` 포함). §3 자체가 "코드와 이 표가 어긋나면 코드가 맞다"고 규정하므로 **버그 아님** — 문서 숫자만 낡았다.
- ⚠️ `EditorTextRun`이 계약 표면의 유일한 실질 결함이다 → **버그 #1**.

### 2.2 `ProjectSession` (§3.2) — 9개 메서드 전수 대조: **전부 구현됨**
구현체 `ProjectEngine`(`Sources/CodeNavigatorCore/ProjectEngine.swift:10`).
`openProject` · `currentProject` · `indexState` · `indexStateUpdates` · `definitions(named:)` · `searchSymbols(matching:)` · `references(to:)` · `searchText(_:mode:)` · `directoryEntries(atRelativePath:)` — 9/9 존재, 시그니처 일치, **TODO·빈 구현 없음**.

> 17:20 시점 재확인 결과다. 17:19에는 `ProjectSession` 구현체가 **0개**였다(BE-18 `ProjectEngine`/`CodeNavigatorEngine`이 검증 도중 랜딩). 낡은 실측을 피하려 재스캔했다.

계약 외 공개 메서드 3개(`reindexSavedFile` · `waitUntilIndexIsIdle` · `closeProject`)가 있다 — 엔진 조립·테스트 지원용이며 `ProjectSession` 프로토콜에는 없다. **스펙 초과로 분류하되 문제 없음**(프로토콜 표면은 오염되지 않았다).

### 2.3 `EditorSession` (§3.3) — 16개 메서드 전수 대조: **전부 구현됨**
구현체 `NeovimEditorSession`(`Sources/CodeNavigatorCore/Editing/NeovimEditorSession.swift:10`).
`start` · `restart` · `state` · `stateUpdates` · `gridUpdates` · `statusUpdates` · `resizeGrid` · `sendKeys` · `setInputMode` · `inputMode` · `openFile` · `jumpBack` · `wordUnderCursor` · `savedFilePaths` · `shutDown` — 16/16 존재, 시그니처 일치, **TODO·빈 구현 없음**.

### 2.4 계약이 표현하지 않는 연결부 — 실제 배선 확인
문서에 "엔진이 처리한다"고 적힌 것들이 **실제로 배선됐는지** 코드로 확인했다(존재≠연결):

| 연결 | 확인 결과 |
|---|---|
| `savedFilePaths` → 재인덱싱 (REQ-009 AC-5) | ✅ `CodeNavigatorEngine.beginObservingSaves()`(:61-69)가 스트림을 소비해 `project.reindexSavedFile`을 호출. SC-3 종단 테스트로 실동작 확인 |
| 조회는 **모든 인덱스 상태**에서 응답 | ✅ `ProjectEngine`의 조회 경로에 인덱스 상태 게이트 없음 |
| `ProjectSession`에 쓰기 API 없음 (INV-3 타입 강제) | ✅ 9개 메서드 전부 읽기 전용 |

## 3. REQ별 검증 (완성분 = 백엔드 측면만)

| REQ-ID | 결과 | 근거 |
|--------|------|------|
| REQ-001 (프로젝트 열기·전환) | **PASS**(백엔드) | AC-3 "실패 시 이전 프로젝트 유지" 명시 테스트 존재·통과. AC-4 gitignore·제외목록 `GitignoreMatcherTests`(23)+`ProjectScannerTests`. AC-1·AC-2의 UI 측면은 미구현 |
| REQ-002 (심볼 인덱싱 4언어) | **PASS** | AC-1 Kotlin/Java: class·interface·enum·object·record·함수·프로퍼티·필드 전부 단언. AC-2 TS/JS: 전 선언 종류 + 화살표 상수 vs 값 상수 구분. JS는 TSX 문법으로 파싱해도 동일 결과 명시 테스트. AC-4 "일부만 깨진 소스에서 정상 부분 추출" 테스트 통과. `SymbolKind` 7종 전부 단언됨 |
| REQ-002 AC-3 | **PASS (테스트 갭 있음)** | 구현은 **올바르다** — 실측 확인: 검색은 `scan.filePaths`(전체), 인덱서는 `scan.indexableFilePaths`(소스만)를 쓴다. 다만 후반부("전문 검색 대상에는 포함된다")를 지키는 테스트가 없다 → **관찰 #1** |
| REQ-004 (Neovim 임베드) | **PASS**(엔진 측) | AC-1 기동·미설치 에러 / AC-2 키 입력·모드 전이 / AC-3 사용자 설정 로드(INV-4 명시 테스트) / AC-4 `:w`→저장 경로 통지 / AC-5 프로세스 사망 감지·재기동 — 전부 **실제 Neovim 통합 테스트**로 커버. 렌더 측면은 **버그 #1**로 미충족 |
| REQ-005 (정의로 이동) | **PASS**(엔진 측) | SC-1·SC-2 통과. `definitions`는 경로→라인 결정적 정렬로 후보 순서 고정. AC-4 점프목록은 `openFile(recordJump:)`로 엔진이 담당 → **관찰 #3** |
| REQ-006 (참조 목록) | **PASS** | `ReferenceSearcherTests`(11) — 단어 경계(부분 단어 불일치), 정의 플래그 구분(AC-2), 상한 1000 경계, AC-4 0건. UTF-8 연속바이트를 식별자 문자로 처리해 `사용자Index`가 `Index`에 오탐되지 않음 |
| REQ-007 (심볼 퍼지 검색) | **PASS**(엔진 측) | `FuzzyMatcherTests`(10) 부분수열·대소문자 무시·점수 순위·강조 구간 + `SymbolSearcherTests`. 상한 50. AC-3·AC-4는 UI |
| REQ-008 (전문 텍스트 검색) | **PASS** | `TextSearcherTests`(15) — AC-1 리터럴, AC-2 **잘못된 정규식이 빈 결과가 아니라 에러**(SC-6 종단 테스트로도 확인), AC-3 제외 미노출, AC-4 상한 500 + `truncated`. 한글 줄의 강조 구간이 UTF-16 오프셋으로 나오는 것까지 단언 |
| REQ-009 (자동 재인덱싱) | **PASS** | AC-1 변경분만 재인덱싱 / AC-2 삭제 시 심볼 소멸("유령 결과 금지") / AC-3 이름 변경 잔재 없음 / AC-4 대량 변경→전체 재스캔 폴백 / AC-5 앱 내부 `:w` 경로 = SC-3 종단 통과. **restart 후 경로만 미검증** → **관찰 #2** |
| REQ-NF-001 (성능) | **PASS** | 실측 로그: 정의 조회 **0.0ms**(목표 100ms), 단일 파일 증분 갱신 **1.8ms**(목표 500ms) |
| **INV-1 (스테일 0)** | **PASS** | "파일이 삭제되면 심볼이 사라진다", "이름이 바뀌면 옛 경로 잔재가 남지 않는다", "gitignore에 새로 걸린 파일은 삭제처럼 빠진다", "대량 변경은 전체 재스캔으로 폴백하고 INV-1이 성립한다" — 4개 테스트 통과 |
| **INV-3 (편집 단일 경로)** | **PASS (코드로 실측)** | 아래 §3.1 |
| **INV-4 (설정 비침범)** | **PASS** | `NeovimChannelTests`에 INV-4 명시 테스트 |
| REQ-003 · 010 · 011 | **미검증(UI 대기)** | 백엔드 측 부품(`DirectoryTreeLister` 13, `StandardInputTranslator` 14)은 통과. 끝단은 프론트 완료 후 |

### 3.1 INV-3 실측 — 앱 코드에 대상 레포 쓰기 경로가 있는가?
`Sources/` 전체를 4가지 축으로 훑었다:

| 검사 축 | 결과 |
|---|---|
| `FileManager` 변경 API (`createFile` `removeItem` `moveItem` `copyItem` `replaceItem` `createDirectory` `setAttributes`) | **0건** |
| 디스크 쓰기 (`.write(to:)` `.write(toFile:)` `atomically:`) | **0건** |
| `FileHandle` 쓰기 (`forWriting` `forUpdating` `truncateFile`) | **1건** |
| 저수준 syscall (`open(` `O_WRONLY` `O_CREAT` `O_TRUNC` `fwrite` `unlink(` `rename(` `mkdir(`) | **0건** |

유일한 쓰기 1건은 `NeovimChannel.swift:144` — **임베드된 Neovim의 stdin 파이프에 RPC 프레임을 쓰는 것**이다. 대상 레포 파일 쓰기가 아니다.

**판정: INV-3 성립.** 파일 수정 경로는 Neovim 하나뿐이며, `ProjectSession` 프로토콜에 쓰기 API가 없어 **타입 수준에서도** 강제된다. `NeovimChannelTests`의 "INV-3: 버퍼를 고쳐도 디스크는 그대로고, `:w` 시점에만 파일이 쓰인다" 테스트가 런타임에서도 이를 지킨다.

## 4. 버그 목록

### 버그 #1 (→ backend-senior, frontend-senior 양쪽 통지 완료 17:22)
**그리드 스냅샷에 컬럼 정보가 없어 한글/CJK 줄에서 뷰가 글리프·커서를 올바른 칸에 놓을 수 없다**

- **위반 REQ**: REQ-004 AC-2(화면·커서 반영). 부수적으로 `03 §7` 함정 #6(오프셋 픽스처에 한글 필수) 위반
- **위치(생산자)**: `Sources/CodeNavigatorCore/Editing/NeovimGridState.swift:191-210`(`makeSnapshot`), `:104-106`(`applyLine`)
- **위치(계약)**: `Sources/CodeNavigatorContract/EditorTextRun.swift:3-4` — 필드가 `text`, `style` 뿐
- **재현(코드 대조)**:
  1. `applyLine`은 와이어 셀 하나당 `column += 1`로 한 칸씩 채운다. 더블폭 문자에 대해 Neovim은 글리프 셀 다음에 **빈 문자열 셀**을 보내고, 그 `""`가 `cells[row][column]`에 저장된다.
  2. `makeSnapshot`은 하이라이트가 같은 이웃 셀의 `cell.text`를 **문자열로 이어붙인다** → `"한"` + `""` = `"한"`. **런 텍스트 1 Character, 실제 점유 2 칸.**
  3. `EditorCursorPosition`은 계약상 **그리드 셀 좌표**(0부터)인데, 스냅샷 어디에도 각 run의 시작 칸이 없다.
- **기대**: 뷰가 각 글리프를 절대 컬럼에 배치할 수 있다(§3.3 "뷰는 완성된 `EditorGridSnapshot`만 그린다")
- **실제**: 유도 불가. 한글이 한 글자라도 있는 줄부터 이후 모든 글리프와 커서가 어긋난다
- **수정 방향**: `EditorTextRun`에 시작 컬럼(또는 셀 점유 수)을 싣는다 — **엔진은 이미 그 값을 안다**(`applyLine`의 `column`). 뷰가 표시폭을 재계산하는 우회는 엔진 로직 복제 + 드리프트이므로 권하지 않는다. 정확한 형태는 계약 소유자(backend-senior)가 결정
- **회귀 테스트 요청**: `NeovimGridStateTests`는 16개 중 **더블폭 문자 픽스처가 0건**이다. 오프셋을 다루는 전 파일 중 유일하게 한글 픽스처가 없는 곳이다(Extractor·TextSearcher·PreviewTextBuilder·MessagePack은 모두 있다)
- **심각도**: **blocker** — F-04·F-05가 "대기(계약 #1)"로 멈춘 원인
- **교차 확인**: frontend-senior가 실제 `grid_line` 덤프로 독립 도달한 결론과 일치(`06_journal.md`). 실측 경로 2개가 수렴

### 버그 #2 (→ frontend-senior, 통지 완료 17:22)
**프론트엔드에 테스트 타깃이 없다 — F-01·02·03이 TDD 게이트를 만족시킬 수 없다**

- **위반**: 하네스 TDD 게이트(모든 in-scope REQ 테스트 커버 + 100% 통과). REQ-011 AC-3·AC-4, REQ-010
- **위치**: `Package.swift:42-46` — `testTarget`이 `CodeNavigatorCoreTests` **하나뿐**, 의존성은 Core/Contract
- **재현**: `Sources/CodeNavigatorApp/`에는 `main.swift`(placeholder `print` 1줄)만 존재. F-01·02·03은 "진행" 상태인데 테스트를 둘 위치가 없다
- **기대**: 프론트 순수 로직(디자인 토큰·ShellLayout 치수 계산·KeyNotation 생성)이 테스트로 커버된다
- **실제**: 테스트 타깃 부재로 커버 불가
- **수정 방향**: 순수 로직을 `main.swift` 밖의 테스트 가능한 타입으로 분리 + `Package.swift`에 프론트 `testTarget` 추가. F-02·F-03은 순수 계산이라 단위 테스트 비용이 특히 싸다. `Package.swift` 소유권이 backend-senior면 조율 필요
- **심각도**: **major** (게이트 차단). 지금이 가장 싸고, F-01~03 마무리 후면 재작업

## 5. 관찰 (버그 아님 — 반려하지 않음)

**관찰 #1 — REQ-002 AC-3 후반부 무방비 (테스트 갭)**
"미지원 언어 파일도 전문 검색 대상에 포함된다"를 지키는 테스트가 없다. 구현은 올바름을 실측 확인했다(`ProjectEngine.swift:54,65`은 `filePaths`, `ProjectIndexer.swift:118,140`은 `indexableFilePaths`). 그러나 `TextSearcherTests` 픽스처는 `.kt`/`.js`뿐이라 **누가 `filePaths`를 `indexableFilePaths`로 바꿔도 아무 테스트도 깨지지 않는다.** `README.md`/`notes.txt`가 검색되는 테스트 1건 요청함.

**관찰 #2 — restart 후 저장→재인덱싱 경로 미검증 (major)**
`CodeNavigatorEngine.beginObservingSaves()`는 `start()`에서만 호출된다. 앱은 계약상 `editor.restart()`를 직접 부를 수 있고(엔진에 restart 패스스루 없음) 그때 재구독이 없다. **현재 구현은 안전하다** — 브로드캐스터가 `shutDown()`에서 재생성되지 않고 인스턴스 프로퍼티로 살아남음을 확인했다(`NeovimEditorSession.swift:30-33`, `:100-108`). 그러나 이 사실에 의존하는 테스트가 없어, 누가 `shutDown()`에서 브로드캐스터를 재생성하면 **재기동 후 모든 저장이 조용히 인덱스에 반영되지 않는다**(INV-1 위반, 무증상). 재기동 후 `:w` → 검색 반영 테스트 1건 요청함.

**관찰 #3 — SC-1 테스트가 커서→심볼 경로를 실제로 타지 않는다 (minor)**
`AcceptanceScenarioTests.swift:46-52` — `sendKeys("^f S")` 후 `definitions(named: "SymbolIndexHolder")`를 **하드코딩 이름**으로 호출한다. REQ-005 AC-1이 말하는 "**커서 위치 심볼에 대해**"가 이 테스트에서는 검증되지 않고, `sendKeys` 줄은 결과에 영향을 주지 않는다. 다만 `wordUnderCursor`는 `NeovimEditorSessionTests.swift:114`에서 별도로 실제 단언되므로 **커버리지 구멍은 아니다**. SC-1을 `wordUnderCursor()` → `definitions(named:)`로 연결하면 시나리오가 실제 경로를 탄다.

**관찰 #4 — 커버리지 매트릭스가 낡았다** (§1 참조). backend-senior 기여분 행 부재 + 게이트 상태 "(미실행)".

**관찰 #5 — 항진 단언 1건 (minor, → backend-senior)**
`Tests/CodeNavigatorCoreTests/SymbolExtractorTests.swift:284-288`
```swift
@Test("완전히 깨진 소스에서도 죽지 않는다")
func survivesCompletelyBrokenSource() {
    let symbols = extractSymbols(from: " {{{{ %%% ]]]] class @@@@ ", path: "broken.kt")
    #expect(symbols.count >= 0)          // ← Swift Array.count는 항상 >= 0. 절대 실패할 수 없다
}
```
`Array.count`는 non-negative `Int`이므로 이 단언은 **어떤 구현에도 통과한다**. 실제로 검증되는 것은 "크래시 없이 다음 줄에 도달했다"뿐이고 그건 `#expect`가 아니라 제어 흐름이 보장한다. REQ-002 AC-4("파싱 실패 파일은 그 파일만 스킵")의 의도를 살리려면 `#expect(symbols.isEmpty)`로 **깨진 소스에서 쓰레기 심볼이 나오지 않음**을 단언하는 편이 맞다(현재 구현이 실제로 무엇을 돌려주는지 확인 후 결정 요망). 참고로 바로 다음 테스트 `extractsHealthySymbolsFromPartiallyBrokenSource`는 제대로 단언하고 있어, AC-4의 핵심은 이미 커버된다 — 그래서 minor다.

**전 22개 테스트 파일 정독 결과 위 2건(관찰 #3·#5) 외에 통과용 테스트는 없다.** 파일 스캔·gitignore·퍼지/전문/참조 검색·심볼 추출(4언어)·인덱스 변경·msgpack 코덱·그리드 상태·Neovim 채널/세션 통합·입력 번역·미리보기 생성 전부 픽스처 기반의 구체적 단언을 갖고 있다.

**스펙 초과 점검**: `ProjectEngine`의 계약 외 공개 메서드 3개(`reindexSavedFile`·`waitUntilIndexIsIdle`·`closeProject`)가 유일한 초과분이며, 엔진 조립·테스트 지원 목적으로 정당하다. 어느 REQ에도 속하지 않는 기능·화면은 없다. **범위 크리프 없음.**

## 6. 종합

- **전체 PASS 여부**: **아니오** (blocker 1건 미해결)
- **blocker 1** (버그 #1 그리드 컬럼) · **major 2** (버그 #2 프론트 테스트 타깃, 관찰 #2 restart 재인덱싱) · **minor 3** (관찰 #1 AC-3 테스트 갭, 관찰 #3 SC-1 약한 단언, 관찰 #5 항진 단언)

> **검증 중 코드가 계속 변했다.** 17:19 전수 스캔 시 `ProjectSession` 구현체 0개 → 17:20 `ProjectEngine` 랜딩. 테스트 수는 17:14 리더 실측 **192** → 17:19 내 실행 **243** → 17:26 정적 집계 **252**(`SymbolSearcherTests` 추가). 이 리포트의 실행 수치(243/27)는 **17:19:47 시점**의 것이다. 낡은 실측을 피하려 계약 대조는 재스캔했고, 최종 라운드에서 전량 재실행한다.
- **완성분(백엔드 코어) 자체는 견고하다**: 계약 표면 25개 메서드 + 22개 값 타입 전수 대조에서 누락·TODO·시그니처 불일치 **0건**. 243 테스트 전부 통과. INV-1·3·4 성립. `--filter` 없이 전체 실행한 수치다.
- **다음 라운드**: 버그 #1 수정 통지 시 그리드 경로 재검증(한글 회귀 테스트 실재 여부 포함) + 프론트 완료분 점진 검증.
- **최종 라운드 예약**: 방어선 실측(그리드 컬럼·INV-1 2곳을 일부러 깨뜨려 빨간불 확인 후 원복) · 라이브 `.app` 실행 E2E · `02_design.md`+`prototype/shots/` 디자인 충실도 대조(모바일/데스크톱 해당 없음 — 맥 창 크기별로 대조).

---

# 부록 A — 프론트 스테이징 사전 검증 (17:32, Round 1 이후 추가)

리더 통지("프론트 순수 로직 161 테스트가 타깃 분리를 기다리는 중")를 받고, **이관 전에** 사전 검증했다.
정식 점진 검증은 레포 반영 후 다시 한다. 이 부록은 이관 시 놀랄 일을 줄이기 위한 것이다.

## A.1 테스트 수치 실측 — **161 tests / 16 suites 전부 통과** ✅
frontend-senior가 `*`로 "아직 레포의 `swift test` 결과가 아니다"라고 정직하게 표기했기에, **내가 직접 실행했다.**

- 방법: `_workspace/frontend-staging/`을 `/tmp/qa_fe_verify/`로 복사 → 스테이징 README가 문서화한 심볼릭 링크를 **실제 계약 소스**(`Sources/CodeNavigatorContract`)로 재생성 → `swift test`.
- **누구의 트리도 건드리지 않았다**(소유권 규칙 준수). 격리 복사본에서만 실행.
- 결과: `✔ Test run with 161 tests in 16 suites passed` (17:32:15).
- **의미: 계약 드리프트 없음.** 복사본이 아니라 **실제 `CodeNavigatorContract`에 대해 컴파일·통과**했으므로, 이관 시 계약 불일치로 깨질 위험은 없다.

## A.2 스테이징 디렉토리는 현재 빌드되지 않는다 (이관 시 주의, 심각도 minor)
`_workspace/frontend-staging/`에서 `swift build` 시:
```
error: 'frontend-staging': Source files for target CodeNavigatorContract should be
located under 'Sources/CodeNavigatorContract'
```
- 원인: README가 문서화한 심볼릭 링크(`ln -s ../../Sources/CodeNavigatorContract Sources/CodeNavigatorContract`)가 **현재 존재하지 않는다**(`find . -type l` 0건). 소스 7개 + 테스트 3개 이상이 `import CodeNavigatorContract` 한다.
- **코드 결함이 아니다** — 개발 환경 링크가 사라진 것뿐이고, 이관되면 실제 패키지에서 정상 해소된다. 위 A.1이 그것을 증명한다.
- README의 "현재 상태: **137 테스트 / 14 스위트**(17:22 실측)"는 **낡았다** — 그 뒤 테스트가 늘어 실제로는 161/16이다.

## A.3 ⚠️ `02_design.md`와 구현이 의도적으로 다르다 — 최종 디자인 충실도 라운드에서 오탐 주의
`DesignTokens.swift:59` → `text-3` = `#6A6A73` / `#9898A1`
`02_design.md:274` → `text-3` = `#76767F` / `#86868F` **(5.0:1)**

- 프론트가 토큰을 **의도적으로 바꿨다**. 테스트 주석에 근거가 있다: 발행된 5.0:1은 **콘텐츠 배경 기준**이고, `text-3`이 실제로 놓이는 **툴바에서는 3.81:1로 측정**돼 4.5:1 접근성 바닥을 뚫었다.
- `DesignTokenTests`가 이제 **모든 텍스트 토큰 × 그 토큰이 실제로 그려지는 모든 표면**의 대비를 검사한다(가장 유리한 배경 하나만 보지 않는다). REQ-011 AC-4 관점에서 **구현이 문서보다 옳다.**
- **최종 라운드 지침(나 자신에게)**: 02 §4.1의 색값·대비 수치를 기준물로 그대로 쓰면 **거짓 버그를 낸다.** 이 항목은 구현이 정답이다. `02_design.md`를 실측값으로 갱신하는 게 맞다(문서 소유자 = product-designer).

## A.4 통과용 테스트 판별 (161개 대상)
- 단언 없는 테스트 **0건**, 조건부 스킵·`.enabled(if:)` **0건**, 항진 단언 **0건**.
- `#expect(x != nil)` 4건(`ReferencePresentationTests:62`, `SymbolSearchPresentationTests:56·57`, `TextSearchPresentationTests:104`)은 "안내 문구가 상시 존재하는가"를 묻는 것으로, REQ-006 AC-3·REQ-007 AC-4·REQ-008 AC-2가 요구하는 것이 **존재 그 자체**라 적절하다. 결함 아님.
- 각 스위트 이름이 담당 REQ와 `02_design.md` 절을 명시하고 있어 추적성이 좋다.

### 관찰 #6 — 접근성 바닥 검사가 빈 컬렉션에 무방비 (minor, → frontend-senior)
`DesignTokenTests.swift:15-16`
```swift
for token in DesignTokens.textTokens {
    for surface in DesignTokens.textBearingSurfaces {
```
두 컬렉션이 **비어 있지 않다는 단언이 없다.** 누가 `textTokens`를 비우면 루프가 0회 돌고 **테스트는 초록으로 통과하며 접근성 바닥이 조용히 사라진다.** 이 스위트는 이미 실제 결함(3.81:1)을 잡아낸 방어선이므로 그 자체를 지킬 가치가 있다. `#expect(DesignTokens.textTokens.count >= 8)` 같은 한 줄이면 충분하다.

---

# 부록 B — 리더의 02 갱신 독립 검증 (17:38)

리더가 부록 A.3을 받아 `02_design.md`·`prototype/styles.css`·`shots/`를 갱신했다.
**갱신된 기준물 자체를 아무도 검증하지 않았으므로** 내가 WCAG 2.x 상대휘도 공식을 직접 구현해 재측정했다
(구현 코드에 의존하지 않는 독립 계산 — `ColorContrast.swift`를 쓰면 그 구현의 버그를 함께 물려받는다).

## B.1 리더의 수치 — **정확하다** ✅
| 항목 | 리더/프론트 주장 | QA 독립 측정 | 판정 |
|---|---|---|---|
| 신규 `text-3` 최악 (light) | 4.54:1 | **4.54:1** (`bg-window`) | ✅ 일치 |
| 신규 `text-3` 최악 (dark) | 4.58:1 | **4.58:1** (`bg-elevated`) | ✅ 일치 |
| 초판 `#76767F` 툴바 (light) | 3.81:1 | **3.81:1** (`bg-window`) | ✅ 일치 |
| 초판 `#86868F` (dark) | 3.63:1 | **3.63:1** (`bg-elevated`) | ✅ 일치 |

**전 텍스트 토큰 8종 × 전 표면 6종 = 48조합 재측정 결과 전부 4.5:1 이상.** 게이트를 독립 재현했다.

부수 확인: 초판 `#76767F`는 **콘텐츠 배경에서도 4.50:1**이었다 — 02가 주장하던 5.0:1은 콘텐츠 기준으로도 틀렸다. 그 수치는 애초에 측정된 적이 없다고 보는 게 맞다.

정합성 확인: 낡은 값(`76767F`/`86868F`) 잔재 **0건**(`_workspace/`·`docs/` 전수). `styles.css` 3곳 갱신됨. **`shots/` 재렌더 17:36 > `styles.css` 17:35** — 스크린샷이 css보다 최신이므로 렌더 순서 정합(낡은 shots 착시 배제).

## B.2 ⚠️ 관찰 #7 — 새 측정 규약을 7행 중 1행만 따른다 (minor, → team-lead)
리더가 추가한 주석은 이렇게 선언한다:
> 텍스트 토큰의 대비는 **그 토큰이 실제로 놓이는 모든 표면 중 최악값**으로 잰다(콘텐츠 배경 하나만 재면 안 된다).

그런데 **그 규약을 따르는 행은 `text-3` 하나뿐이고, 나머지는 여전히 콘텐츠 배경 수치다**:

| 토큰 | 02 주장 | 콘텐츠 기준 | **최악(신규 규약)** | 규약 준수 |
|---|---|---|---|---|
| `text-1` | 16:1 / 13.5:1 | 17.01 / 14.06 | **14.42 / 10.74** | ✗ |
| `text-2` | 7.6:1 / 7.3:1 | 7.38 / 7.12 | **6.25 / 5.43** | ✗ |
| `text-3` | 최악 4.54 · 4.58 | 5.35 / 6.00 | **4.54 / 4.58** | ✅ |
| `accent-text` | 5.6:1 / 6.5:1 | 5.63 / 6.31 | **4.77 / 4.82** | ✗ |
| `danger` | 6.3:1 / 6.4:1 | — | **4.76 / 4.74** | ✗ |
| `warning` | 6.5:1 / 8.6:1 | — | **5.02 / 6.83** | ✗ |
| `success` | 5.0:1 / 8.0:1 | 5.34 / 7.75 | **4.53 / 5.92** | ✗ |

- **접근성 결함이 아니다** — 최악값 기준으로도 전 토큰이 4.5:1을 통과한다(B.1).
- **문제는 가드레일이 반쪽이라는 것이다.** 그 주석은 "다음 사람이 같은 실수를 반복하지 않게" 넣은 것인데, 정작 표의 6개 행이 주석이 금지한 방식(콘텐츠 배경 단독 측정)으로 적혀 있다. 다음 사람은 표를 보고 규약을 역추론한다.
- **실질 위험 1건**: `success`의 light 최악값은 **4.53:1로 바닥 위 0.03**이다(전 토큰 중 가장 얇은 여유). 그런데 02는 **5.0:1**이라 적어 여유가 있는 것처럼 보인다. 표면 색을 조금만 어둡게 조정하면 조용히 뚫린다.
- 수정 방향: 나머지 6행도 최악값으로 갱신(위 표의 값을 그대로 쓰면 된다). `DesignTokenTests`가 이미 48조합을 전부 검사하므로 **테스트는 이미 규약대로**이고, 문서만 따라가면 된다.

---

# 부록 C — 재검증 (17:40, blocker #1 수정 후)

수정 통지를 기다리지 않고 레포 상태를 확인하니 수정이 이미 랜딩해 있어 재검증했다.

## C.1 실측
```
$ swift test          # 17:40:42
✔ Test run with 266 tests in 33 suites passed after 4.119 seconds.
```
빌드 락·잔여 `nvim` 없음 확인 후 실행. 필터 없음. (17:19 243/27 → **266/33**)

## C.2 버그 #1 (blocker) — **해소** ✅
- **계약**: `EditorTextRun`에 `startColumn`(0-based, `EditorCursorPosition`과 같은 좌표계) + `cellWidth`(셀 수, 문자 수 아님) 추가. 문서 주석이 더블폭·RLE·결합 시퀀스 세 경로를 모두 설명한다.
- **구현**(`NeovimGridState.makeSnapshot`): 셀 인덱스를 그대로 컬럼으로 쓴다 — 중간 run은 `column - runStartColumn`, 마지막 run은 `row.count - runStartColumn`. runs가 행 전체를 빈틈없이 타일링한다. 빈 행·첫 run 경계 모두 정상.
- **회귀 테스트**: 신규 스위트 `NeovimGridState — 더블폭 문자와 컬럼 좌표` 5건 (그리드 스위트 16 → **21**).

**이 테스트들이 진짜 방어선인지 판별했다**(단순 통과가 아니라 *버그를 구별하는지*):
| 단언 | 올바른 구현 | 문자 수로 유도한 버그 구현 | 구별? |
|---|---|---|---|
| `run.text.count == 7` **와** `run.cellWidth == 10` 동시 단언 | 7 / 10 | 7 / 7 | ✅ |
| 한글 뒤 run의 `startColumn == 6` (+ `runs[0].text.count == 3` 병기) | 6 | 3 | ✅ |
| 타일링: `expectedColumn == snapshot.columns` | 10 | 7 | ✅ |
- 픽스처가 `인`+`""`+`덱`+`""`+`스`+`""` 로 **Neovim의 실제 와이어 형태**(글리프 셀 + 빈 셀)를 재현한다.
- 테스트가 정답값과 오답값을 **함께** 고정하므로 두 값을 혼동하는 구현은 반드시 빨간불이 된다. 공회전 루프도 없다(타일링 테스트는 마지막 단언이 빈 runs를 잡는다).
> 실제로 깨뜨려보는 방어선 실측은 **최종 라운드**에 예약돼 있다(공유 트리 오염 방지). 위는 코드 구조상의 판별 근거다.

## C.3 나머지 지적 — 백엔드 전부 해소 ✅
| 항목 | 상태 | 확인 |
|---|---|---|
| 관찰 #1 (미지원 확장자 전문검색) | **해소** | 신규 `ProjectEngineSearchScopeTests` 3건 — `README.md`·`notes.txt`가 검색·참조에 나오고 인덱싱에는 안 나옴을 각각 단언. 주석이 "`TextSearcher` 단위 테스트는 목록을 인자로 받아 이 구분을 못 잡는다 — 고르는 쪽은 `ProjectEngine`"이라고 명시 |
| 관찰 #2 (restart 후 재인덱싱) | **해소** | `savesAreStillIndexedAfterEditorRestart` — 재기동 후 `:w` → 심볼 검색 반영을 실제 단언 |
| 관찰 #3 (SC-1 약한 단언) | **해소** | `wordUnderCursor()` → `definitions(named:)` 체인으로 교체. 부수로 원래 키 시퀀스 `"^f S"`의 실제 결함까지 발견됨(`f<space>` 다음 `S`가 줄 치환이 되어 버퍼를 망가뜨림) |
| 관찰 #5 (항진 단언) | **해소** | `isEmpty` 단언 3언어(kt·java·ts)로 교체 + 옛 판이 왜 무의미했는지 주석으로 남김 |
| 관찰 #4 (매트릭스 낡음) | **해소** | 7행 → **60행**, 게이트 `PASS` 기록됨. 단 기록값 252/28은 이미 낡았다(현재 266/33) — 인증 시점에 재실행 필요 |
| 관찰 #7 (02 규약 반쪽) | **해소** | 텍스트 토큰 7행 전부 최악값으로 통일 + `success` 취약 경고 명시. QA 측정값과 전 행 일치 확인 |

## C.4 남은 항목 (프론트 이관 대기)
| 항목 | 상태 |
|---|---|
| 버그 #2 (프론트 테스트 타깃) | **미해소** — `Package.swift`에 `AppKit` 타깃 없음, 스테이징 잔존. 이관이 선행 조건 |
| 관찰 #6 (대비 검사 빈 목록 무방비) | **미해소** — `DesignTokenTests`에 비어있지 않음 단언 아직 없음 |

**현 시점 판정: blocker 0 · major 1(버그 #2, 이관 대기) · minor 1(관찰 #6).** 백엔드 코어는 지적 전건 해소.

---

# 부록 D — 프론트 이관 후 재검증 (17:44)

## D.1 실측 — **484 tests / 54 suites 전부 통과**
```
$ swift test          # 17:44:51
✔ Test run with 484 tests in 54 suites passed after 4.232 seconds.
```
⚠ 실행 시점에 **동시 릴리스 빌드가 돌고 있었다**(pid 42480, `swift-build -c release --product CodeNavigator`). 확인했고 테스트는 정상 통과했으므로 결과는 유효하다 — 다만 이후 누군가 여기서 실패를 보면 빌드 락 충돌부터 의심할 것.

## D.2 버그 #2 (major) — **해소** ✅
`Package.swift`에 `CodeNavigatorAppKit` 타깃 + `CodeNavigatorAppKitTests` 테스트 타깃이 모두 들어왔다. 프론트 테스트 21파일 / **215 `@Test`**(내가 스테이징에서 검증한 161에서 증가). `Sources/CodeNavigatorAppKit/`에 `Design·Grid·Logic·Model·View` 구성.
토큰 정합 확인: `textTertiary` = `#6A6A73`/`#9898A1` — **리더가 갱신한 02와 일치**. 이관 과정의 토큰 드리프트 없음.

## D.3 신규 계약 표면 `IndexStatistics` — 검증 완료, 드리프트 없음 ✅
| 항목 | 결과 |
|---|---|
| 타입 존재 | `Sources/CodeNavigatorContract/IndexStatistics.swift` (`fileCount`·`symbolCount`·`skippedCount`·`lastUpdatedAt`) |
| `ProjectSession` 메서드 | `indexStatistics()` 추가 — **9개 → 10개** |
| 구현 배선 | `ProjectEngine.indexStatistics()` → `indexer.statistics()` ✅ |
| **계약 문서 §3.2 갱신** | ✅ **갱신돼 있다** — 문서 드리프트 없음(백엔드가 계약 문서를 같이 유지했다) |
| 테스트 | `skippedCount` 0건·2건·**복구(2→0)** 케이스까지 단언 — REQ-002 AC-4의 "조용한 스킵"을 가시화하는 목적에 부합 |

### 관찰 #8 — `lastUpdatedAt`은 소비자 없는 계약 표면 + 시계 주입 없음 (minor)
- **아무도 읽지 않는다**: `Sources/CodeNavigatorAppKit/` 전체에 `lastUpdatedAt` 참조 0건. 현재는 스펙 초과 표면이다.
- **테스트는 `!= nil` 하나뿐**(`ProjectIndexerTests:220`).
- `ProjectIndexer`가 `Date()`를 **4곳에서 직접 호출**한다(`:151·172·229·235`) — 시계 주입이 없다. 지금은 무해하지만, UI가 "마지막 갱신 N초 전"을 표시하게 되면 **그 표시는 결정적으로 테스트할 수 없다**(우리 지식 베이스의 Clock 주입 패턴이 정확히 이 경우다).
- 조치 제안: 지금 당장은 불필요. **UI가 이 값을 쓰기로 결정되는 시점에** 시계를 주입 가능하게 바꿔라. 쓰지 않을 거면 필드를 빼는 것도 방법이다.

## D.4 남은 항목
| 항목 | 상태 |
|---|---|
| **관찰 #6** (대비 검사 빈 목록 무방비) | **미해소** — 이관된 `Tests/CodeNavigatorAppKitTests/DesignTokenTests.swift`에 여전히 비어있지 않음 단언 없음 |
| `_workspace/frontend-staging/` 잔존 | 정리 대상(minor housekeeping) — 이관 완료됐으므로 두 벌이 남으면 다음 사람이 어느 쪽이 진짜인지 헷갈린다 |

**현 판정: blocker 0 · major 0 · minor 2(관찰 #6, #8).**

---

# 부록 E — 17:48 게이트 파손 + R1 정정

## E.1 🔴 공유 테스트 타깃 컴파일 불가 (blocker, 작업 순서 문제)
17:44 484/54 그린 → **17:48 실행이 컴파일 실패**. `swift test`가 팀 전원에게 실패한다.
- 원인: `Tests/CodeNavigatorAppKitTests/FileTreePresentationTests.swift`(mtime 17:48)가 `FileTreePresentation`·`FileTreeRow`를 참조하나 `Sources/`에 부재(grep 0건). F-12 TDD Red로 보인다.
- **이미 문서화된 함정의 재발**(`06_journal.md:7`): Swift는 `--filter`를 줘도 타깃 전체를 컴파일하므로 **컴파일 에러 Red는 팀 전원을 막는다**. 백엔드가 배운 규율이 새로 스폰된 frontend-junior에게 전달되지 않았다.
- 수정: 스텁 타입을 먼저 넣어 **"단언 실패 Red"**로 바꾼다 → F-12만 빨간불, 나머지 483건은 초록 유지.
- **구조적 위험**: F-13~16·F-18이 같은 방식으로 5건 더 온다. 주니어 스폰 브리핑에 이 규율을 넣지 않으면 다섯 번 더 멈춘다(저널에만 있으면 새 에이전트는 읽지 않는다).

## E.2 신규 계약 표면 3종 — 전수 재대조 (17:44)
backend-senior가 통지에 **곁들여 언급**한 것들이라 다시 훑었다. 통지의 주제가 아닌 변경일수록 검증에서 새기 쉽다.

| 변경 | 확인 |
|---|---|
| `savedFilePaths() -> AsyncStream<String>` → **`savedFiles() -> AsyncStream<SavedFile>`** | 파괴적 변경. `CodeNavigatorEngine:78-81`까지 일관 반영 ✅ |
| **`sendMouse(_: EditorMouseEvent)` 신규** | 계약·구현 존재 ✅ (`EditorSession` 15개 → **16개**) |
| `ProjectSession.indexStatistics()` 신규 | 9개 → **10개** ✅ |
| 신규 타입 `EditorMouseEvent`·`SavedFile`·`IndexStatistics` | 3개 모두 실재 ✅ |
| `03 §3.3` 코드 블록 갱신 | ✅ |

### 관찰 #9 — 계약 문서 반쪽 수정 (minor)
`03_backend_architecture.md:129` 산문이 여전히 **`savedFilePaths`**라고 쓴다 — 코드 블록(:117)은 `savedFiles`로 고쳐졌는데 그 아래 설명 줄만 낡았다. 계약 시맨틱 단일 소스의 반쪽 수정이다.

### 관찰 #10 — `SavedFile.lineCount`·`byteSize`가 `> 0`만 단언 (minor, 백엔드가 자체 발견·배정 완료)
`NeovimEditorSessionTests.swift:171-172`가 `> 0`만 본다 — **nvim이 엉뚱한 값을 줘도 통과한다.** 내가 R1에서 지적한 "무언가 일어났다" 패턴과 같은 종류다. backend-senior가 스스로 발견해 BE-31·32로 디스크 등호 대조를 배정했다(자체 발견이므로 반려하지 않는다).

## E.3 ⚠️ R1 리포트 오류 정정 — `EditorSession` 메서드 수
R1 §2.3에서 **"16/16 구현됨"**이라고 썼으나 **당시 계약은 15개였다**(`git show HEAD~3:...EditorSession.swift` → `func` 15건). 메서드 이름을 15개 나열해놓고 합계를 16으로 적은 **산술 실수**다.
- **검증 자체는 유효하다** — 나열한 15개 전부 실재했고 TODO·빈 구현도 없었다. 결론은 바뀌지 않는다.
- 다만 계약 표면의 **수**를 인증 근거로 제시한 이상, 그 수가 틀렸으면 정정해야 한다. 현재는 `sendMouse` 추가로 실제 16개 — 우연히 일치하게 됐을 뿐이다.
- 재발 방지: 이후 계약 대조는 `grep -cE "^\s+func "`로 **세어서** 적는다(눈으로 세지 않는다).

---

# 부록 F — 17:53 게이트 실패 3건 (컴파일 복구 후)

## F.1 상태 변화
- 17:48 컴파일 파손 → **복구 확인** ✅ (`FileTreePresentation`·`FileTreeRow`가 `Sources/CodeNavigatorAppKit/Logic/`에 랜딩)
- `_workspace/frontend-staging/` **삭제 확인** ✅
- 그러나 **실제 단언 실패 3건**: `523 tests in 59 suites failed with 3 issues`

**결정적 실패다(flaky 아님)** — `--filter NeovimMouseInputTests` 2회 재실행에 같은 2건 재현. 필터 실행 건수 **5 tests in 1 suite** 확인(0건 매칭 초록불 함정 배제).

## F.2 실패 목록
| # | 위치 | 증상 | 담당 |
|---|---|---|---|
| 1 | `ProjectEngineStatisticsTests.swift:28` | `(skippedCount → 0) == 1` — 기대 1, 실제 0 | backend-senior |
| 2 | `NeovimMouseInputTests.swift:65` | 드래그가 비주얼 모드로 진입 못 함 (REQ-010 AC-2) | backend-senior |
| 3 | `NeovimMouseInputTests.swift:109` | ⇧클릭이 선택을 넓히지 못함 (REQ-010 AC-2) | backend-senior |

같은 스위트의 **나머지 3건은 통과** — `"좌표는 버퍼 라인이 아니라 그리드 셀이다"`(스크롤 상태)와 `"기동 전 마우스 입력은 조용히 무시된다"`가 통과하므로 **좌표 변환·기동 가드는 정상**이고 **선택(비주얼 진입) 경로만** 깨졌다.

## F.3 경계면 양쪽 읽기 — 상태 전달 배선은 **정상(배제)**
처음엔 "`reportStatus()` 루아가 `mode`를 안 보낸다"가 원인인 줄 알았으나, **설계상 mode는 redraw 스트림에서 온다**:
- `NeovimEditorSession:441-444` — `snapshot.mode != lastKnownMode`면 갱신 후 `publishStatusWithCurrentMode()`.
- 그 주석이 이미 이 경우를 대비한다: *"A mode change with no accompanying buffer event would otherwise never reach the interface, which is how a visual selection can leave the indicator saying normal."*
- `ModeChanged` autocmd도 등록됨(`:363`).

→ **`snapshot.mode`가 `.visual`이 된 적이 없다.** 원인은 상태 보고가 아니라 마우스 입력이 Neovim에서 선택을 만들지 못하는 쪽. 중복 조사를 막으려 이 배제 결과를 backend-senior에게 함께 보냈다.

## F.4 환경 실측
- 이 머신 `mouse` 옵션 = **`nvi`**(`--clean`·사용자 설정 양쪽) — 마우스 활성. 옵션 미설정은 원인 아님.
- 독립 재현: `nvim --clean --headless`에 `nvim_input_mouse` press+drag 직접 주입 → 모드가 **`n`에 머묾**.
  ⚠ **UI 미부착 상태라 결정적 근거는 아니다** — 저널의 "`nvim_input`은 attach 전 조용히 무시된다"가 마우스에도 적용될 수 있다. 참고 자료로만 기록한다.

## F.5 최종 라운드 발주 조건 — 조정 제안 (리더에게 전달함)
실패가 남은 상태로 라이브 E2E에 들어가면 **앱의 이상 동작이 내가 찾는 통합 결함인지 이미 알려진 단위 실패의 발현인지 구분되지 않는다.** 특히 실패 2건이 **REQ-010 AC-2**인데 리더가 최종 라운드에서 닫으라고 지정한 항목이 바로 REQ-010이다 — 같은 기능이 단위에서 빨간불인 채 라이브 검증에 들어가면 이중으로 헛돈다.
→ 발주 전제를 **`gate.sh` 그린 + `.app` 조립 완료** 둘 다로 하자고 제안했다.

**현 판정: blocker 1(게이트 빨간불, 실패 3건) · major 0 · minor 4**(관찰 #6·#8·#9·#10 — #10은 백엔드 자체 배정 완료).
