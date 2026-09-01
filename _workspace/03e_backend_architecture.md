# 백엔드 아키텍처 — 증분 3 (REQ-015 · 016 · 017)

- 작성: backend-senior · 2026-09-01
- 대상: REQ-015(`gd`/`gr`) · REQ-016(구문 강조 + 같은 심볼 강조) · REQ-017(마우스), INV-7 · INV-8
- 기준 트리: `c7a6bf7` (인증 완료 상태에서의 증분)
- **이 문서 §3이 프론트엔드와의 계약 단일 소스다.** 프론트엔드는 제안하고, 반영은 백엔드 시니어가 1회 한다.
- 선행 문서: `03_backend_architecture.md`(증분 1) · `03c_multi_project_contract_draft.md`(증분 2)

---

## 0. 한 줄 요약

**세 요구 모두 기존 계층 위에 얹힌다. 새 계층도, 새 의존성도 없다.**
강조는 nvim이 이미 하고 있고 색은 이미 계약까지 흐른다 — 우리가 더하는 것은 *색을 누가 정하는가*를
뒤집는 한 방향 호출과, 편집기가 앱을 부르는 신호 하나다.

---

## 1. 스택 — 변경 없음

증분 1의 표(`03_backend_architecture.md §1`)를 그대로 쓴다. **의존성을 하나도 더하지 않는다.**

특히 기록해 둔다: REQ-016을 위해 **tree-sitter 파서를 추가하지 않는다.** 우리가 번들한 문법
(Java·Kotlin·TypeScript)은 심볼 추출용이고, 강조는 Neovim이 자기 구문 파일로 한다 — 근거는 ADR-0010.

| 항목 | 명령 |
|---|---|
| 테스트 | `swift test` |
| 게이트 | `bash _workspace/gate.sh` (변경 없음 — 이 증분은 게이트 스텝을 더하지 않는다) |
| 스코프 테스트 | `swift test --filter <SuiteName>` |

**빌드/테스트 실행 프로토콜**: 증분 1과 동일. 게이트 판정 풀런은 시니어 단독 1회, 개발 중에는
`--filter` 스코프 실행만. 이 프로젝트는 테스트마다 실제 nvim 프로세스를 띄우므로 동시 풀런은
프로세스 경합으로 가짜 실패를 만든다.

---

## 2. 구조 — 무엇이 어디에 붙는가

세 요구가 전부 **`NeovimEditorSession` 한 타입**에 붙는다. 새 파일은 계약 DTO 3개와 세션을 돕는
값 타입뿐이다(클래스당 파일 하나 — 코딩 컨벤션).

```
Sources/CodeNavigatorContract/
  EditorNavigationRequest.swift     [신규] gd/gr 이 앱에 보내는 신호
  EditorSyntaxPalette.swift         [신규] 앱이 세션에 내려주는 색
  EditorKeyMappingOutcome.swift     [신규] AC-6 판정 결과 (세 상태)
  EditorSession.swift               [수정] 위 셋을 쓰는 메서드 3개 추가

Sources/CodeNavigatorCore/Editing/
  NeovimEditorSession.swift         [수정] 매핑 설치·팔레트 적용·허용목록·마우스 옵션
  NeovimKeyMappingClassifier.swift  [신규] 세 상태 분류 (순수)
  NeovimSyntaxAllowList.swift       [신규] 파일타입 허용목록 (순수)
  NeovimHighlightScript.swift       [신규] 세션에 심는 Lua 를 한곳에
```

**바뀌지 않는 것 (명시)**: `EditorGridSnapshot` · `EditorGridLine` · `EditorTextRun` ·
`EditorTextStyle` · `EditorColor` · `EditorMouseEvent`. 색과 마우스는 이미 이 여섯 개로 끝까지
흐른다 — 실측으로 확인했다(§5).

### 기동 순서 (ADR-0006 의 순서에 세 단계가 추가된다)

```
spawn → nvim_ui_attach → [사용자 init.lua 실행] → 알림 훅 → ★매핑 판정·설치 → ★마우스 옵션 → 입력 수용
                                                                                        ↑
                                                            앱이 준비되면 ★팔레트 적용 (그리고 테마 바뀔 때마다)
```

**★ 셋이 전부 "설정 로드 이후"인 것이 핵심이다.** ADR-0006이 실측한 대로 사용자 `init.lua`는
`nvim_ui_attach` 시점에야 실행된다. 그 전에 판정하면 **사용자 매핑이 항상 "없음"으로 읽히고**
(AC-6이 조용히 무력화), 그 전에 옵션을 걸면 사용자 설정이 우리를 덮는다.

---

## 2.5 아키텍처 결정 기록 (ADR — 본문은 `docs/adr/` 이 단일 소스)

- [ADR-0010 구문 강조의 출처](../code-navigator-mac/docs/adr/0010-syntax-highlight-source.md) —
  Neovim이 분류하고 앱이 색을 정한다. ②(우리 tree-sitter로 토큰 계산) 기각.
- [ADR-0011 세션 한정 내비게이션 키](../code-navigator-mac/docs/adr/0011-session-scoped-navigation-keys.md) —
  세션 안에만 매핑, 빈 신호로 앱 호출, 사용자 매핑 우선(세 상태 구별), `gr` 접두 충돌 해소.
- [ADR-0012 마우스 상호작용](../code-navigator-mac/docs/adr/0012-mouse-interaction-session-options.md) —
  `mouse=a`를 세션에서 보장한다. 계약 변경 없음.

---

## 3. 계약 (경계면) — 백엔드 정의, 양 시니어 합의

> **상태: 엔진 구현·테스트 완료. 프론트엔드 시니어 회신 대기.**
> 아래 표면은 전부 구현됐고 게이트를 통과했다(`swift test --no-parallel` 1,502건, `GATE: PASS`).
> 계약 *문구*는 프론트 반론이 오면 1회 갱신한다 — 합의 전에 구현한 이유는 반론이 와도 바뀌는 것이
> 이름 수준이고, 기다리는 동안 엔진이 놀면 증분 전체가 직렬화되기 때문이다.

### 3.1 `EditorNavigationRequest` — 편집기 → 앱 (REQ-015)

```swift
/// 사용자가 편집기 안에서 요청한 내비게이션 (REQ-015).
public enum EditorNavigationRequest: String, Sendable, Hashable, Codable {
    case goToDefinition   // gd
    case findReferences   // gr
}
```

```swift
// EditorSession
/// `gd`·`gr` 이 눌릴 때마다 하나씩. 앱은 ⌘B·⇧⌘B 가 부르는 그 핸들러를 그대로 부른다.
func navigationRequests() async -> AsyncStream<EditorNavigationRequest>
```

**페이로드가 비어 있는 것이 계약의 요점이다.** 심볼 이름을 실으면 앱에 ⌘B 경로와 `gd` 경로가
따로 생기고, AC-3(⌘B 그대로)·AC-4(후보 목록 재사용)·AC-5(심볼 아니면 이유 설명)가 "두 경로가
같은가"라는 **매번의 규율**에 걸리게 된다. 빈 신호는 그것을 호출 그래프로 만든다.

### 3.2 `EditorSyntaxPalette` — 앱 → 세션 (REQ-016 AC-3 · AC-6)

```swift
/// 편집기 강조에 쓸 색. 앱의 테마가 단일 소스다 (REQ-016 AC-3·AC-6).
public struct EditorSyntaxPalette: Sendable, Hashable, Codable {
    public let keyword: EditorColor
    public let type: EditorColor
    public let function: EditorColor
    public let string: EditorColor
    public let number: EditorColor
    public let comment: EditorColor
    public let sameSymbolBackground: EditorColor   // AC-2
    public let selectionBackground: EditorColor    // REQ-017 AC-3
}
```

```swift
// EditorSession
/// 팔레트를 편집기의 표준 강조 그룹에 바른다. 세션 시작 직후 1회 + 테마가 바뀔 때마다.
/// 부르지 않으면 편집기 기본색이 남는다 — 강조는 파생물이므로 실패가 편집을 막지 않는다(INV-8).
func applySyntaxPalette(_ palette: EditorSyntaxPalette) async throws
```

**색의 소유자를 앱으로 둔 이유**: 테마(라이트/다크)를 아는 쪽이 앱이다. 백엔드가
`02_design.md`의 값을 복제하면 같은 시맨틱이 두 곳에 살고 한쪽만 고쳐진다. 이 방향이면
"앱 테마가 이긴다"(AC-6)가 판단이 아니라 **데이터 흐름**이 된다.

**세션이 바르는 대상 그룹** (Vim 표준 강조 그룹 — 실측으로 3언어 모두 여기로 링크됨을 확인):

| 팔레트 필드 | 강조 그룹 |
|---|---|
| `keyword` | `Statement` · `Keyword` · `Conditional` · `Repeat` · `StorageClass` |
| `type` | `Type` · `Structure` |
| `function` | `Function` · `Identifier` |
| `string` | `String` |
| `number` | `Number` · `Boolean` |
| `comment` | `Comment` |
| `sameSymbolBackground` | `CodeNavigatorSameSymbol` (우리가 만드는 그룹) |
| `selectionBackground` | `Visual` |

⚠ **미결**: `sameSymbolBackground` 에 해당하는 디자인 토큰이 `02_design.md`에 없다. PD 결정 필요.
`selectionBackground`는 `accent`(`#007AFF`/`#0A84FF`)가 "선택 배경"으로 등재돼 있다.
⚠ **`02_design.md:289` 갱신 필요**: 구문 토큰에 "실제로는 Neovim/사용자 테마 소유"라는 단서가
붙어 있는데, AC-3·AC-6이 그 소유권을 뒤집었다.

### 3.3 `EditorKeyMappingOutcome` — 세션 → 앱 (REQ-015 AC-6 검증)

```swift
/// 내비게이션 키 하나에 대해 세션이 내린 판정 (REQ-015 AC-6).
public struct EditorKeyMappingOutcome: Sendable, Hashable {
    /// 셋은 서로 다른 사실이다. 하나의 불리언으로 뭉개지 않는다.
    public enum Resolution: String, Sendable, Hashable, Codable {
        case installed              // 비어 있어서 우리가 심었다
        case replacedEditorDefault  // Neovim 자신의 기본을 대체했다
        case deferredToUserMapping  // 사용자 설정이 있어 심지 않았다
    }

    public let keys: String
    public let request: EditorNavigationRequest
    public let resolution: Resolution
    /// `deferredToUserMapping` 일 때만 — 어느 파일의 매핑이 이겼는지.
    public let userScriptPath: String?
}
```

```swift
// EditorSession
/// 이 세션이 내비게이션 키에 대해 내린 판정. UI 요구는 아니고, AC-6 을 nvim 내부 조회 없이
/// 검증할 수 있게 하려는 것이다.
func navigationKeyMappingOutcomes() async -> [EditorKeyMappingOutcome]
```

### 3.4 계약 하드닝

- **모든 색은 `EditorColor`(24bit RGB)다.** 문자열 hex를 계약에 넣지 않는다 — 파싱 실패라는
  실패 모드를 만들지 않기 위해서다.
- **좌표는 그리드 셀이다.** 마우스는 기존 `EditorMouseEvent` 그대로(버퍼 줄도 픽셀도 아니다).
- **`navigationRequests()`는 `AsyncStream`이고 replay 하지 않는다.** 늦게 붙은 구독자가
  과거의 `gd`를 다시 받아 엉뚱한 위치로 점프하면 안 된다. (강조·상태와 달리 이것은 상태가
  아니라 **사건**이다.)
- **팔레트 적용 실패는 세션을 되돌리지 않는다** (INV-8).
- **미지원 언어는 색이 *없다*. 잘못된 색이 붙는 것이 아니다** (AC-4) — `syntax=OFF`는 버퍼 단위.

---

## 4. 작업 분해

| # | 작업 | REQ | 복잡도 | 담당 | 완료 기준 (통과해야 할 테스트) |
|---|---|---|---|---|---|
| B-1 | 계약 3종 + `EditorSession` 메서드 3개 | 015·016 | 중 | **senior** | 계약 표면 테스트가 새 타입·메서드를 열거하고, 양 타깃이 컴파일된다 |
| B-2 | 매핑 판정기 `NeovimKeyMappingClassifier` (순수) | 015 AC-6 | 중 | **senior** | `absent`/`editorDefault`/`user` 세 상태가 각각 단언된다. **심링크된 설정 경로에서도 `user`로 읽힌다** |
| B-3 | 매핑 설치 + `gr*` 기본 삭제 + `navigationRequests` 스트림 | 015 AC-1·2·6 | 높음 | **senior** | `gd`·`gr` 이 스트림에 값을 낸다. 사용자 매핑이 있으면 안 심고 `deferredToUserMapping`이 남는다. `gr` 발화가 `timeoutlen` 미만 |
| B-4 | 팔레트 적용 (`nvim_set_hl` + `ColorScheme` 재적용) | 016 AC-1·3·6 | 중 | **senior** | 팔레트를 바른 뒤 그리드 런의 색이 팔레트 값과 같다. 사용자 colorscheme 이 있어도 같다 |
| B-5 | 파일타입 허용목록 → `syntax=OFF` | 016 AC-4 | 낮음 | senior (아래 사유) | `.py`·`.go` 버퍼의 런에 전경색이 없다. `.ts`·`.java`·`.kt` 는 색이 있다 |
| B-6 | 같은 심볼 강조 (`CursorMoved` + `matchadd`) | 016 AC-2 | 중 | senior (아래 사유) | 커서를 심볼에 두면 그 파일 안 같은 이름 전부에 배경이 붙고, **다른 이름으로 옮기면 이전 것이 사라진다** |
| B-7 | `mouse=a` 세션 적용 + 비대칭 회귀 테스트 | 017 AC-1·2 | 낮음 | senior (아래 사유) | `mouse=''` 로 만들어 둔 상태에서 드래그가 선택을 만든다. **클릭과 드래그를 각각 단언한다** |
| B-8 | 환경 가정 스위트 유지 | 전부 | — | **senior** | `Increment3EnvironmentAssumptionsTests` 8건 통과 (이미 작성·통과) |

**위임 판단 — 처음엔 B-5·B-6·B-7을 주니어 후보로 적었다가 철회했다.**

셋 다 결정이 ADR로 내려져 있고 완료 기준도 관측 가능하다. 그런데 **파일이 겹치지 않는다는 전제가
틀렸다** — 셋 다 `NeovimEditorSession`의 같은 기동 경로(`start()` 이후의 설치 단계)를 편집한다.
나눠 주면 세 사람이 한 함수를 동시에 고친다.

**그래서 스폰을 요청하지 않고 시니어가 전부 했다.** 이번 증분은 세 요구가 한 타입으로 수렴해서
병렬 이득이 없다. 없는 병렬성을 만들어 내는 것보다 그렇게 보고하는 쪽이 맞다.

> 위임 가능성은 "결정이 내려졌는가"가 아니라 **"같은 파일을 만지는가"**로 먼저 갈린다.
> 앞의 것만 보고 후보로 적은 것이 이 표의 첫 판이었다.

### 이 증분이 **하지 않는** 것 (범위 밖 — 요구사항 명시)

스크롤 휠 · 더블클릭 단어 선택 · 우클릭 메뉴 · 에러 밑줄/진단 · 3언어 외 강조 ·
프로젝트 간 같은 심볼 강조.

---

## 5. 선행 실측 (spike) — 결정을 만든 측정

전문은 세 ADR에. 여기에는 결론만 둔다. 측정 트리 `c7a6bf7`, Neovim 0.12.5.
**측정은 `Tests/CodeNavigatorCoreTests/Increment3EnvironmentAssumptionsTests.swift` 8건으로 고정돼
회귀 시 깨진다** — 환경 사실이 조용히 바뀌면 결정의 근거가 사라지는데, 기능 테스트는 그때도
초록일 수 있기 때문이다.

| 잰 것 | 결과 | 무엇을 결정했나 |
|---|---|---|
| nvim 기본 강조 | `g:syntax_on=1`, java·kotlin·typescript 구문 파일 전부 존재 | ADR-0010 ① 채택 |
| 번들 treesitter 파서 | 지원 3언어 **없음** (`c,lua,markdown,…`만) | ①-treesitter 기각 |
| 색이 계약까지 오는가 | 온다 (`EditorTextStyle.foreground`, 6종) | 계약 변경 0 |
| **앱이 색을 덮으면** | **이긴다** (`#9B9EA4`→`#FF00FF`) | AC-3·AC-6이 구조로 성립 |
| nvim 기본색의 키워드 | **기본 전경색과 같다** (`#E0E2EA`) | 팔레트가 AC-1의 *전제* |
| `syntax=OFF` | 전경색이 사라진다 | AC-4 달성 방법 |
| `gd` → 앱 | 21ms | 콜백 경로 확정 |
| **`gr` → 앱** | **1032ms** (`timeoutlen`) — `gr*` 기본군의 접두 충돌 | 기본군 삭제 결정 |
| 기본군 삭제 후 `gr` | **0ms**, LSP 클라이언트 **0개** | 삭제가 무해함의 근거 |
| 매핑 세 상태 | 사용자 `sid=3`+스크립트 / 기본 `sid=-8` / 없음 | AC-6 판정 가능 |
| **설정 경로 접두 비교** | **심링크에 걸려 실패** (`/var` vs `/private/var`) | 판정은 `$VIMRUNTIME` 밖인가로 |
| `&mouse` 기본값 | `nvi` — 비어 있지 않다 | 리더 가설의 절반 기각 |
| **`mouse=''` 일 때** | **클릭은 살고 드래그만 죽는다** | `mouse=a` 강제 + 각각 단언 |
| 드래그 선택 | 배경 셀 60→115 로 그리드 도착 | REQ-017 AC-3 계약 변경 0 |

### 측정 방법에서 배운 것 (재발 금지)

**1차 측정은 두 항목에서 정반대 결론을 냈다** — "앱이 색을 덮어도 안 이긴다", "syntax=OFF 해도
파이썬이 여전히 칠해진다". 원인은 `gridUpdates()`가 구독 즉시 마지막 프레임을 replay 하는데
(`EventBroadcaster`), 프로브가 **행동 이전의 프레임**을 읽고 "안 변했다"고 판정한 것이다.

> **낡은 프레임은 정확히 "변하지 않음"처럼 보인다.**
> 그리드를 근거로 판정하는 모든 테스트는 `revision` 기준선을 잡는다.

---

## 6. 미해결 · 리스크

| | 내용 | 누구 |
|---|---|---|
| ⚠ 승인 대기 | `gr` 접두 충돌 해소안(Neovim 기본 `gr*` 6개를 세션에서 삭제) | 리더 → PM |
| ⚠ 토큰 부재 | `sameSymbolBackground` 디자인 토큰 없음 | PD |
| ⚠ 문서 정정 | `02_design.md:289` 의 "실제로는 Neovim/사용자 테마 소유" 단서가 AC-3·AC-6과 모순 | PD |
| ⚠ 미측정 | REQ-017 이 **실제 앱**에서 도는가. 엔진 경계까지만 쟀다 | frontend-senior · QA |
| 열린 질문 | ⌘B 핸들러가 "심볼 아님"을 이미 말하는가 (AC-5가 공짜인지) | frontend-senior |
| 인증 후 처리 | `BUILD_COMPLETE` 의 1·2번(`bufferLines` 세 개의 0, `invalidPath` 분류)은 이 증분과 별개로 남아 있다 | backend-senior |

**REQ-017 에 대한 내 주장의 범위**: 엔진은 쟀고 돈다. **실제 앱에서 도는지는 아무도 안 봤다.**
사용자가 요구했다는 것은 어딘가에서 안 된다는 뜻이고, 그 어딘가는 내가 잰 구간 밖이다.
