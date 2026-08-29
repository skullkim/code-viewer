# 백엔드(코어 엔진) 아키텍처 — code-navigator-mac

- 작성: backend-senior · 2026-08-29
- 대상 REQ: REQ-001·002·004·005·006·007·008·009·010 의 엔진 측면, INV-1~4, REQ-NF-001~005
- **이 문서 §3이 프론트엔드와의 모듈 계약 단일 소스다.** 프론트엔드는 제안하고, 반영은 백엔드 시니어가 한다.

## 1. 스택

| 항목 | 선택 | 근거 |
|---|---|---|
| 언어/빌드 | Swift 6.3.3 (language mode 6, strict concurrency) + SPM | 맥 네이티브 요구. 실측: 빌드·테스트 정상 |
| 테스트 | Swift Testing (`swift test`) | 표준 도구. 실측: 통과 확인 |
| 파싱 | tree-sitter C 런타임 + `swift-tree-sitter` | ADR-0002 |
| 문법 | kotlin 1.1.0 / java 0.23.5 / typescript+tsx 0.23.2 | 웹앱판이 검증한 것과 같은 문법 계열·버전 |
| 파일 열거·검색 | 네이티브 Swift (`FileManager` + UTF-8 바이트 탐색 + `NSRegularExpression`) | ADR-0004. 외부 바이너리 0 |
| 파일 감시 | FSEvents (CoreServices) | ADR-0005 |
| 편집 | Neovim 0.12.5 `--embed` + 자체 MessagePack-RPC | ADR-0006 |
| 영속성 | 없음 (인덱스는 인메모리 파생물) | ADR-0003 / INV-2 |

**외부 런타임 의존은 Neovim 하나뿐이다.** ripgrep을 쓰지 않기로 한 결정(ADR-0004)이 이를 지킨다.

## 2. 타깃 구조

```
Package.swift
Sources/
  CodeNavigatorContract/   ← 계약. 의존성 0. 백엔드 소유
  CodeNavigatorCore/       ← 엔진. 백엔드 소유
    Indexing/  Scanning/  Searching/  Watching/  Editing/  Support/
  CodeNavigatorApp/        ← SwiftUI 셸. 프론트엔드 소유
Tests/CodeNavigatorCoreTests/
docs/adr/                  ← 0001~0007 (백엔드), 01xx (프론트엔드)
```

의존 방향은 `App → Contract ← Core` 한 방향이다. 앱은 조립 지점에서만 Core를 안다.
**계약이 바뀌면 양쪽이 동시에 컴파일 실패한다** — 이것이 경계면 드리프트 방어선이다.

### 2.5 아키텍처 결정 기록 (ADR)
본문은 프로젝트 레포 `docs/adr/`에 있다. 이 문서는 링크만 둔다.

- [0001 모듈 구조와 계약 경계](../docs/adr/0001-module-structure-and-contract-boundary.md)
- [0002 tree-sitter 통합 방식과 문법 확보](../docs/adr/0002-tree-sitter-integration.md)
- [0003 인덱스 자료구조와 동시성 모델](../docs/adr/0003-index-structure-and-concurrency.md)
- [0004 파일 열거·전문 검색 = 네이티브 Swift](../docs/adr/0004-file-enumeration-and-search.md)
- [0005 파일 감시 전략](../docs/adr/0005-file-watching-strategy.md)
- [0006 Neovim RPC 계층](../docs/adr/0006-neovim-rpc-layer.md)
- [0007 텍스트 오프셋 규약 = UTF-16 코드 유닛](../docs/adr/0007-text-offset-convention.md)

## 3. 모듈 계약 (단일 소스)

HTTP가 없으므로 **Swift 프로토콜과 값 타입이 계약**이다. 코드의 단일 소스는
`Sources/CodeNavigatorContract/`이며, 아래는 그 요약이다. **코드와 이 표가 어긋나면 코드가 맞다.**

### 3.1 값 타입

| 타입 | 필드 | 비고 |
|---|---|---|
| `SymbolKind` | `class` `interface` `enum` `object` `function` `property` `typeAlias` | 용어집(§3)과 1:1 |
| `SymbolDefinition` | `name` `kind` `path` `line` `signature` | `path`=프로젝트 상대·POSIX·선행 슬래시 없음, `line`=1부터 |
| `MatchRange` | `start` `end` | **UTF-16 코드 유닛**, 반열린 `[start, end)` |
| `SymbolSearchResult` | `definition` `score` `matchRanges` | 관련도 내림차순 |
| `Reference` | `path` `line` `previewText` `isDefinition` | 정의도 목록에 포함되고 플래그로 구분 |
| `ReferenceSearchResult` | `references` `total` `truncated` `limit` | `truncated`면 `total`은 "중단 시점까지 관측 수" |
| `TextSearchItem` | `path` `line` `previewText` `matchRanges` | |
| `TextSearchResult` | `items` `total` `truncated` `limit` | |
| `TextSearchMode` | `literal` `regularExpression` | |
| `DirectoryEntry` | `name` `path` `isDirectory` | 디렉토리 먼저, 그다음 이름순 |
| `IndexProgress` | `completed` `total` | `total`=0이면 파일 목록 작성 중 |
| `IndexState` | `notIndexed` `indexing(p)` `ready` `updating` `rescanning(p)` | 요구사항 §6 상태표와 1:1 |
| `EditorSessionState` | `notStarted` `connecting` `connected` `disconnected(reason:)` | `reason`은 표시용 문구 |
| `EditorMode` | `normal` `insert` `visual` `replace` `commandLine` `terminal` `other(String)` | 미지 모드도 표시 가능 |
| `InputMode` | `vim` `standard` | 기본 `vim` |
| `EditorGridSnapshot` | `columns` `rows` `lines` `cursor` `mode` `defaultForeground` `defaultBackground` `revision` | `flush`마다 1개. `revision` 단조 증가 |
| `EditorGridLine` / `EditorTextRun` / `EditorTextStyle` / `EditorColor` | — | 뷰가 그대로 그리는 형태 |
| `EditorCursorPosition` | `row` `column` | 그리드 셀 좌표, 0부터 |
| `EditorStatus` | `filePath` `isDirty` `cursorLine` `cursorColumn` `mode` `inputMode` | 커서는 **버퍼** 좌표(1부터) |
| `NavigatorError` | 9개 케이스 + 한국어 `errorDescription` | 빈 결과로 실패를 위장하지 않는다 |

### 3.2 `ProjectSession` (프로젝트·인덱스·검색)

```
func openProject(at rootPath: URL) async throws
func currentProject() async -> ProjectDescriptor?
func indexState() async -> IndexState
func indexStateUpdates() async -> AsyncStream<IndexState>      // 구독 즉시 현재 상태 1회 방출
func definitions(named name: String) async -> [SymbolDefinition]
func searchSymbols(matching query: String) async -> [SymbolSearchResult]
func references(to symbolName: String) async throws -> ReferenceSearchResult
func searchText(_ query: String, mode: TextSearchMode) async throws -> TextSearchResult
func directoryEntries(atRelativePath relativePath: String) async throws -> [DirectoryEntry]
```

- 조회는 **모든 인덱스 상태에서 응답한다.** 갱신 중이면 직전 인덱스로 답하고, 갱신 사실은
  `indexState`가 알린다. 프론트엔드는 조회를 막지 말 것.
- `openProject` 실패 시 **이전 프로젝트 상태는 그대로 유지된다**(REQ-001 AC-3).
- 이 프로토콜에는 **쓰기 API가 없다.** INV-3이 타입 수준에서 강제된다.

### 3.3 `EditorSession` (Neovim)

```
func start(projectRoot: URL, columns: Int, rows: Int) async throws
func restart() async throws
func state() async -> EditorSessionState
func stateUpdates() async -> AsyncStream<EditorSessionState>
func gridUpdates() async -> AsyncStream<EditorGridSnapshot>
func statusUpdates() async -> AsyncStream<EditorStatus>
func resizeGrid(columns: Int, rows: Int) async throws
func sendKeys(_ keys: String) async throws                     // Neovim 키 표기: "ihello<Esc>"
func setInputMode(_ mode: InputMode) async throws
func inputMode() async -> InputMode
func openFile(atRelativePath: String, line: Int?, recordJump: Bool) async throws
func jumpBack() async throws
func wordUnderCursor() async throws -> String?
func savedFilePaths() async -> AsyncStream<String>
func shutDown() async
```

- **프론트엔드는 Neovim redraw 프로토콜을 몰라도 된다.** 증분 갱신·스크롤 리전·하이라이트 테이블은
  엔진이 처리하고, 뷰는 완성된 `EditorGridSnapshot`만 그린다.
- 정의 이동은 `openFile(…, recordJump: true)` 한 번이면 된다 — 점프 목록 기록까지 엔진이 한다.
- `savedFilePaths`는 엔진이 재인덱싱에 쓰는 스트림이다. 프론트엔드가 구독할 필요는 없다.

### 3.4 경계면 규칙
1. 계약 변경은 **백엔드 시니어만** 반영한다. 프론트엔드는 SendMessage로 제안한다.
2. 2회 교차/불일치하면 즉시 리더 에스컬레이션 → 리더가 값을 정해 파일에 동결한다.
3. 프론트엔드는 `CodeNavigatorContract`만 import해 가짜 구현으로 테스트할 수 있다.

## 4. 성능·자원 설계 근거 (REQ-NF-001·002)

**완성된 엔진 실측** (5,000파일 합성 레포, release, 2026-08-29):

| 항목 | 목표 | 실측 | 여유 |
|---|---|---|---|
| 초기 인덱싱 (5,000파일 / 심볼 25,000) | ≤10초 | **0.28초** | 35배 |
| 심볼 정의 조회 | ≤100ms | **0.0ms** | — |
| 단일 파일 증분 갱신 | ≤500ms | **0.4ms** | 1000배 |
| 피크 메모리(테스트 프로세스 전체) | ≤150MB | **93.7MB** | — |

메모리 수치는 테스트 하네스와 5,000파일 픽스처 생성까지 포함한 프로세스 전체의 피크 RSS다.
앱 유휴 시 실측(SC-8)은 조립 후 리더 인증 단계의 몫이다.

메모리(≤150MB)를 지키는 핵심 규칙: **파일 내용을 보유하지 않는다.**
파싱·검색 중에만 들고 있다가 즉시 버리고, 남기는 것은 인덱스(심볼 레코드)뿐이다.
spike에서 전문을 String으로 보유했을 때 30MB였으므로, 보유하지 않으면 목표에 여유가 크다.

## 5. 작업 분해와 소유권

`_workspace/tasks.md`에 표로 관리한다. 위임 기준: **알고리즘이 명세로 고정되어 있고 파일이 격리된 것**은
주니어, **아키텍처·동시성·외부 프로세스·불변식이 걸린 것**은 시니어가 직접 맡는다.

## 6. 테스트 실행

```
swift build                 # 전체 빌드
swift test                  # 전체 테스트
swift test --filter <이름>   # 단위 테스트 격리 실행
_workspace/gate.sh          # 게이트: 빌드 + 테스트 + 민감정보 스캔
```

## 7. 알려진 함정 (구현자 필독)
1. `signal(SIGPIPE, SIG_IGN)` 없이 죽은 Neovim에 쓰면 **앱이 통째로 종료된다**.
2. `--embed`는 `nvim_ui_attach` 전까지 시동을 멈춘다. 그 전에는 사용자 설정이 로드되지 않았고,
   **키 입력도 처리되지 않는다**(조용히 무시됨). 기동 순서가 계약이다.
3. FSEvents 콜백은 `main.swift`에 두면 컴파일되지 않는다(암묵 `@MainActor`).
4. FSEvents 경로 비교는 `realpath(3)` 기준. `URL.resolvingSymlinksInPath()`는 `/tmp`를 해소하지 않아 전부 빗나간다.
5. 리터럴 검색에 `String.range(of:)`를 쓰지 말 것 — grapheme 비교로 4.6배 느리다.
6. 오프셋은 전부 UTF-16 코드 유닛. 오프셋 테스트 픽스처에는 **반드시 한글을 넣는다**.
7. Kotlin 블록 주석 안에 `/*`를 포함하는 경로·패턴을 쓰지 않는다(중첩 주석 컴파일 실패).
