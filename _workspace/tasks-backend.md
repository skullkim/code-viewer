# 작업 분해와 소유권 — 코어 엔진 (backend)

소유자 규칙: 한 파일은 한 사람만 편집한다. 다른 사람이 owner인 작업의 파일은 건드리지 않는다.
주니어 작업은 **계약 타입만 의존**하므로 시니어 작업과 병렬로 진행해도 충돌하지 않는다.

| ID | 작업 | REQ | 소유자 | 상태 | 산출 파일 | 완료 기준 |
|---|---|---|---|---|---|---|
| BE-01 | `SourceLanguage` 확장자 매핑 | 002 AC-3 | senior | 완료 | `Support/SourceLanguage.swift` | 9개 확장자 매핑 + 미지원 확장자 nil |
| BE-02 | `SymbolExtractor` (tree-sitter 4언어) | 002 | senior | 완료 | `Indexing/SymbolExtractor.swift` 외 | 4언어 전 종류 추출, 파싱 실패 시 그 파일만 스킵 |
| BE-03 | `SymbolIndex` actor (정방향/역방향) | 005·006·007 | senior | 완료 | `Indexing/SymbolIndex.swift` | 교체·삭제·이름변경 후 유령 0(INV-1) |
| BE-04 | `FuzzyMatcher` 점수 알고리즘 | 007 AC-1 | **junior** | 완료(리뷰 승인) | `Searching/FuzzyMatcher.swift` | 아래 §BE-04 명세의 점수·순위 전부 재현 |
| BE-05 | `PreviewTextBuilder` (오프셋 환산·절단) | 006·008 | **junior** | 완료(리뷰 승인) | `Support/PreviewTextBuilder.swift` | UTF-8→UTF-16 환산, 한글 픽스처 통과 |
| BE-06 | `GitignoreMatcher` | 001 AC-4 | senior | 완료 | `Scanning/GitignoreMatcher.swift` | 부정·디렉토리전용·`**`·앵커링·중첩 |
| BE-07 | `ProjectScanner` (열거+제외) | 001 AC-4 | senior | 완료 | `Scanning/ProjectScanner.swift` | 기본 제외+gitignore+심링크 미추적 |
| BE-08 | `TextSearcher` (리터럴·정규식·상한) | 008 | **junior** | 완료(리뷰 승인) | `Searching/TextSearcher.swift` | 잘못된 정규식은 에러, 빈 결과 금지 |
| BE-09 | `ReferenceSearcher` (단어 경계) | 006 | **junior** | 완료(리뷰 승인) | `Searching/ReferenceSearcher.swift` | 부분 단어 불일치, 정의 플래그 |
| BE-10 | `DirectoryTreeLister` | 003 | **junior** | 완료(리뷰 승인) | `Scanning/DirectoryTreeLister.swift` | 디렉토리 우선 정렬, 제외 반영 |
| BE-11 | `ProjectIndexer` (상태기계·진행률) | 001·002·009 | senior | 완료 | `Indexing/ProjectIndexer.swift` | 상태표(§6) 전이 전부 |
| BE-12 | `FileWatcher` + `ChangeDebouncer` | 009 | senior | 완료 | `Watching/*.swift` | 디바운스 300ms, 50개 폴백, 드롭 신호 |
| BE-13 | `MessagePack` 인코더/디코더 | ADR-0006 | **junior** | 완료(리뷰 승인) | `Editing/MessagePackValue.swift` 외 | 전 타입 왕복, 부분 프레임 안전 |
| BE-14 | `NeovimProcess` + RPC 클라이언트 | 004 AC-1·AC-5 | senior | 완료 | `Editing/NeovimProcess.swift` 외 | 기동·요청·알림·사망 감지 |
| BE-15 | `NeovimGridState` (redraw→스냅샷) | 004 AC-2 | senior | 완료 | `Editing/NeovimGridState.swift` | grid_line·scroll·hl 반영 |
| BE-16 | `NeovimEditorSession` (조립) | 004·005·010 | senior | 완료 | `Editing/NeovimEditorSession.swift` | 계약 §3.3 전 메서드 |
| BE-17 | `StandardInputTranslator` — 설계 변경으로 삭제, 근거는 `NeovimStandardMode` 주석으로 이관 | 010 AC-2·AC-5 | **junior** | 완료(삭제·이관, 리뷰 승인) | `Editing/StandardInputTranslator.swift` | 화살표·⌘조합·선택·복사 매핑 |
| BE-18 | `CodeNavigatorEngine` (ProjectSession 조립) | 전체 | senior | 완료 | `CodeNavigatorEngine.swift` | 계약 §3.2 전 메서드 |
| BE-19 | `gate.sh` (빌드·테스트·민감정보) | — | senior | 완료 | `_workspace/gate.sh` | 리크 픽스처 양방향 실측 |

## 주니어 즉시 착수 가능 배치 (의존성 없음 — 계약 타입만 사용)
**BE-04, BE-05, BE-13, BE-17** 네 건. 서로 다른 파일이고 시니어 작업과 겹치지 않는다.

---

## BE-04 명세 — `FuzzyMatcher`

순수 함수 하나. `func match(query: String, candidate: String) -> FuzzyMatch?`
`FuzzyMatch`는 `score: Int`와 `matchRanges: [MatchRange]`를 갖는다.

알고리즘 (웹앱판에서 이식 — 순위가 그대로 재현되어야 한다):
1. 빈 질의는 `nil`.
2. 질의·후보를 소문자화해 비교한다. **탐욕적·역추적 없는 최좌측 부분수열 매칭**:
   질의 문자를 순서대로, 직전 매치 다음 위치부터 찾는다. 하나라도 못 찾으면 `nil`.
3. 점수:
   - 매치 문자당 **+1**
   - 위치 보너스(배타적): 후보의 0번 위치면 **+3**, 아니면 경계면 **+2**
   - 인접 보너스: 직전 매치와 간격 0이면 **+2**, 아니면 `-min(간격, 3)`
   - 전체 일치(소문자 비교로 질의==후보)면 **+10**
4. 경계 판정은 **원본 대소문자** 문자열에서 한다:
   직전 문자가 `_ - . / $` 중 하나이거나, 직전이 소문자 글자이고 현재가 대문자 글자면 경계.
5. `matchRanges`는 연속된 인덱스를 하나로 병합한 반열린 구간 목록.

정렬(호출자 쪽 규칙, `SymbolSearchResult` 목록에 적용): 점수 내림차순 → 이름 길이 오름차순 →
경로 오름차순 → 라인 오름차순. 상한 **50**.

반드시 통과해야 할 테스트:
`SymIdx`→`SymbolIndex` 매치 / `symidx` 대소문자 무시 매치 / `xdi`→`index` 불일치 /
`symz`→`SymbolIndex` 불일치 / 빈 질의 `nil` / `sym`→`SymbolIndex` 구간 `[0,3)` /
`Idx`→`SymbolIndex` 구간 `[6,7) [8,9) [10,11)` / 완전일치 > 접두 > 흩어진 매치 점수 순서.

## BE-05 명세 — `PreviewTextBuilder`

`func makePreview(line: String, utf8MatchRanges: [Range<Int>]) -> (previewText: String, matchRanges: [MatchRange])`

- `previewText` = 원본 줄을 **앞뒤 공백 제거** 후 **200 UTF-16 코드 유닛**으로 절단.
  서로게이트 페어를 가운데서 자르지 않는다.
- 입력 매치 구간은 **UTF-8 바이트 오프셋**이다. 이를 UTF-16 코드 유닛 오프셋으로 환산한다
  (유니코드 스칼라 단위로 순회하며 UTF-8 바이트 길이와 UTF-16 길이를 각각 누적).
- 앞쪽에서 제거된 공백의 UTF-16 길이만큼 구간을 왼쪽으로 민다.
- `[0, previewText.utf16.count]`로 클램프하고, `start < end`가 아니게 된 구간은 버린다.
- 시그니처 절단용 `func makeSignature(line: String) -> String`도 같은 파일에:
  trim 후 **120 UTF-16 코드 유닛** 절단.

반드시 통과해야 할 테스트:
`"한글 needle 값"`에서 needle의 UTF-8 구간이 UTF-16 구간 `[3,9)`로 환산될 것 /
선행 공백이 구간을 정확히 왼쪽으로 밀 것 / 200자 초과 절단 / 절단으로 사라진 구간은 제거될 것 /
이모지가 포함된 줄에서 서로게이트 페어가 쪼개지지 않을 것.

## BE-13 명세 — `MessagePack`

`MessagePackValue` 열거형(nil·bool·int·uint·double·string·binary·array·map·ext)과
인코더/디코더. Neovim이 실제로 보내는 전 타입을 다뤄야 한다.

- 디코더는 **부분 프레임에서 실패를 알려야 한다**(예외 또는 nil). 파이프는 msgpack 프레임
  경계에서 잘려 오지 않으므로, 호출자가 "더 기다린다"를 판단할 수 있어야 한다.
- 디코더는 소비한 바이트 수를 알려준다(한 버퍼에 여러 프레임이 이어 붙는다).
- 정수는 폭별 전 인코딩(positive/negative fixint, uint8~64, int8~64)을 지원한다.
- 참고 구현이 `/tmp/spike-nvim/Sources/nvimspike/MsgPack.swift`에 있다(spike에서 실제 Neovim과
  왕복 검증됨). **그대로 복사하지 말고** 컨벤션(축약어 금지 → `MessagePack…`, 클래스당 파일 하나)에
  맞춰 옮기고, 테스트를 먼저 쓴 뒤 통과시킬 것.

반드시 통과해야 할 테스트:
각 타입 인코드→디코드 왕복 / 경계값(fixint 127/128, -32/-33, uint8/16/32 경계) /
중첩 배열·맵 / UTF-8 문자열(한글·이모지) / 잘린 바이트열에서 "미완성" 판정 /
한 버퍼에 두 프레임이 붙어 있을 때 각각 디코드되고 소비 위치가 정확할 것.

## BE-17 명세 — `StandardInputTranslator`

REQ-010 AC-2의 표준 모드. 맥 키 입력을 **Neovim 키 표기 문자열**로 바꾸는 순수 함수.
`func translate(_ event: StandardKeyEvent) -> String?` (nil이면 앱이 처리하고 Neovim에 안 보냄)

`StandardKeyEvent`는 계약이 아니라 이 파일 안의 값 타입으로 정의한다:
`characters: String`, `keyCode: KeyCodeName`, `modifiers: KeyModifiers(OptionSet: command/option/shift/control)`.

매핑 규칙:
- 화살표 → `<Up> <Down> <Left> <Right>`, ⇧ 조합은 `<S-Up>` 등
- `Home/End` → `<Home> <End>`, ⌘←/⌘→ → `<Home> <End>`, ⌘↑/⌘↓ → `gg` / `G`
- ⌥←/⌥→ → `<C-Left>` / `<C-Right>` (단어 이동)
- ⌘C/⌘X/⌘V → 시스템 클립보드 레지스터 사용: `"+y` `"+d` `"+p` (선택 상태에 맞게)
- ⌘Z → `u`, ⌘⇧Z → `<C-r>`
- ⌘S → `:w<CR>`
- ⌘A → `ggVG`
- Delete/Backspace → `<BS>` / `<Del>`
- Enter/Tab/Esc → `<CR>` `<Tab>` `<Esc>`
- **그 밖의 일반 문자는 삽입 모드로 들어가 그대로 입력된다** — 표준 모드에서 `hjkl`·`:`·`i`는
  명령이 아니라 문자다(AC-5). 삽입 모드 진입은 세션이 담당하므로, 이 함수는 문자를 그대로 돌려준다.
- `<` 는 `<lt>`로 이스케이프해야 한다(Neovim 키 표기 충돌).

반드시 통과해야 할 테스트:
각 매핑 1건씩 / `<` 문자 이스케이프 / ⌘ 조합이 아닌 `i`·`:`·`hjkl`이 그대로 문자로 나올 것 /
알 수 없는 조합은 nil.


## 추가 완료분 (계약 2차 반영 · QA 대응)
| ID | 작업 | REQ | 소유자 | 상태 |
|---|---|---|---|---|
| BE-23 | `EditorTextRun.startColumn`·`cellWidth` (프론트 블로커) | 004 AC-2 | senior | 완료 |
| BE-24 | `EditorSessionState.startupFailed` + 버전 검사 | NF-005 | senior | 완료 |
| BE-25 | `IndexStatistics` (스킵 집계) | 002 AC-4 | senior | 완료 |
| BE-26 | `SavedFile` (줄 수·크기) | 004 AC-4 | senior | 완료 |
| BE-27 | `sendMouse` (그리드 셀 좌표) | 010 AC-2 | senior | 완료 |
| BE-28 | 정의 이동 임시 강조 | 005 AC-1 | senior | 완료 |
| BE-29 | QA 지적 회귀 테스트 4종 | 003·005·009 | senior | 완료 |

## 주니어 진행 중
| ID | 작업 | 소유자 | 상태 |
|---|---|---|---|
| BE-20 | `loadGitignore` 중복 제거 | junior | 완료(리뷰 승인) |
| BE-21 | 게이트 "0매치 초록불" 방어 | junior | 완료(양방향 실측, 리뷰 승인) |
| BE-22 | REQ-002 AC-3 테스트 갭 (엔진 수준으로 상향) | junior | 완료(변이 실측, 리뷰 승인) |
| BE-30 | `filesSearched` (전문 검색 범위 보고) | senior | 완료 |
