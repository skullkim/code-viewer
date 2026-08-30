# REQ-012 계약 초안 — 다중 프로젝트

- 작성: backend-senior · 2026-08-30 · **초안 (프론트 합의 대기, 구현 착수 전)**
- 근거: `02b_design.md §7.1`(PD 데이터 요구) · `§12`(리더 판정 8건) · `ADR-0008`(모델 B) · `03b`(후보 비교)

## 0. 형태 요약
**워크스페이스가 탭을 소유하고, 탭마다 `ProjectSession`이 하나씩 있다.**

- `ProjectSession`은 **조회 9개 시그니처가 그대로**다. `openProject`만 빠져 워크스페이스로 옮긴다.
- 탭 간 격리(INV-5)가 **구조로** 성립한다 — 인스턴스가 다르면 서로의 상태에 닿을 수 없다.
- `EditorSession`은 **하나**다(ADR-0008). 탭 조작만 는다.

```
ProjectWorkspace ──┬─ tab A ── ProjectSession A (인덱스 A)
                   ├─ tab B ── ProjectSession B (인덱스 B)   ← 인스턴스 분리 = 격리
                   └─ EditorSession (하나, 탭페이지 N개)      ← 보이는 표면은 하나
```

## 1. 새 값 타입

```swift
/// 탭 하나를 가리키는 불투명 식별자. 경로가 아니라 식별자인 이유: 같은 경로가 다시 열릴 수
/// 있고(닫았다 열기), 그때 이전 탭의 참조가 새 탭을 가리키면 안 된다.
public struct ProjectTabIdentifier: Sendable, Hashable, Codable { ... }

public struct ProjectTab: Sendable, Hashable, Identifiable {
    public let id: ProjectTabIdentifier
    public let displayName: String        // 루트 디렉토리 이름
    public let rootPath: URL              // **정규화된** 루트 (realpath 기준, §4)
    public let indexState: IndexState     // 기존 5상태 그대로, 탭별
    public let dirtyFileCount: Int        // 이 탭의 저장 안 된 버퍼 수
    public let disambiguator: String?     // 이름 충돌 시에만 (예: 상위 디렉토리명)
}

/// 여는 시도의 **성공** 두 갈래. 실패는 기존대로 throw 한다.
///
/// 반환형으로 가른 이유는 AC-5 때문이다 — "새 탭을 열었다"와 "이미 있던 탭을 활성화했다"는
/// 사용자에게 다른 일이고 문구가 갈린다. 불린이나 무시되는 반환값이면 앱이 추측하게 된다.
public enum ProjectOpenOutcome: Sendable, Hashable {
    case opened(ProjectTab)
    case activatedExisting(ProjectTab)
}

public struct TabRestoreOutcome: Sendable {
    public let restored: [ProjectTab]
    public let activeIndex: Int?
    public let missing: [MissingTab]      // 조용히 버리지 않는다 (AC-6)
}

public struct MissingTab: Sendable, Hashable {
    public let displayName: String
    public let rootPath: URL
    public let reason: TabRestoreFailureReason
}

/// 사유를 뭉개지 않는다. 사용자가 할 수 있는 일이 다르기 때문이다 —
/// 없어진 폴더는 목록에서 지우면 되고, 권한 문제는 다시 허용하면 복구된다.
public enum TabRestoreFailureReason: Sendable, Hashable {
    case notFound
    case noPermission
}

/// 폴링 금지 규칙(02 §6)의 계승. 탭별 인덱스 진행·더티 변화·활성 탭 변경이 여기로 온다.
public enum WorkspaceEvent: Sendable {
    case tabsChanged([ProjectTab])                    // 추가·삭제·순서·표시명
    case tabIndexStateChanged(ProjectTabIdentifier, IndexState)
    case tabDirtyCountChanged(ProjectTabIdentifier, Int)
    case activeTabChanged(ProjectTabIdentifier)       // **Neovim 발 변경 포함** (§3)
}
```

## 2. `ProjectWorkspace` 프로토콜

```swift
public protocol ProjectWorkspace: Sendable {
    /// 엶. 이미 열린 루트면 새 탭을 만들지 않고 기존 탭을 활성화한다(AC-5).
    /// 판정 기준은 **정규화된 루트**이며 그 정규화는 엔진이 소유한다(§4).
    func openProject(at rootPath: URL) async throws -> ProjectOpenOutcome

    func tabs() async -> [ProjectTab]                 // 순서 있음 (사용자 재정렬 반영)
    func activeTab() async -> ProjectTab?

    /// 활성화. **I/O 대기가 없다** — 인덱스가 메모리에 상주하므로(AC-2).
    /// 활성화된 탭의 인덱싱 우선순위가 올라간다(§5).
    func activate(_ id: ProjectTabIdentifier) async throws

    /// 이 탭의 저장 안 된 파일들. 닫기 확인 시트(W-13)가 이걸로 목록을 그린다.
    func dirtyFiles(in id: ProjectTabIdentifier) async throws -> [String]
    /// 저장은 Neovim 이 한다(INV-3). 앱이 파일을 쓰지 않는다.
    func saveAll(in id: ProjectTabIdentifier) async throws

    /// 닫기. 인덱스·감시자·편집 버퍼가 함께 해제된다(AC-3, §6).
    func closeTab(_ id: ProjectTabIdentifier) async throws

    /// 복원. 사유를 마스킹하지 않는다(AC-6·AC-9).
    /// **전제**: 넘어오는 URL 은 이미 접근 가능해야 한다 — security-scoped 북마크의
    /// 해제·유지는 앱 소유이고, 스코프는 **탭이 열려 있는 내내** 유지되어야 한다(§7).
    func restoreTabs(from saved: [URL]) async -> TabRestoreOutcome

    func reorderTabs(_ order: [ProjectTabIdentifier]) async

    /// 그 탭의 인덱스·검색·트리. 시그니처는 지금과 같다.
    func session(for id: ProjectTabIdentifier) async -> (any ProjectSession)?

    func workspaceEvents() async -> AsyncStream<WorkspaceEvent>

    /// REQ-NF-002 재정의를 위한 계측 훅. UI 표시는 없다(PD §7.1).
    func memoryFootprint() async -> WorkspaceMemoryFootprint
}
```

`ProjectSession`에서는 **`openProject`만 제거**한다. 나머지 9개는 그대로다.

## 3. `EditorSession` 추가분 (하나의 세션, 탭페이지 N개)

```swift
func openProjectTab(root: URL) async throws -> EditorTabIdentifier
func activateProjectTab(_ id: EditorTabIdentifier) async throws
func closeProjectTab(_ id: EditorTabIdentifier) async throws
```

**기동 시 `showtabline=0`을 설정한다.** 앱이 탭 바를 그리므로 Neovim 이 자기 탭줄을 그리면
탭 줄이 둘이 되고 그리드 행 계산이 한 줄 밀린다(실측: 기본값 1, 탭 2개 이상일 때 나타남 —
**탭 1개로 테스트하면 안 걸린다**). INV-4 와의 관계: 이것은 UI 렌더 계약이지 사용자 편집
설정이 아니다.

**활성 탭의 단일 소스는 Neovim 이다.** 사용자가 Vim 모드에서 `gt`·`:tabnext` 를 치면 탭이
바뀌는데, 앱 탭 바가 그걸 모르면 화면과 탭 바가 어긋난다. `TabEnter` autocmd → `rpcnotify`
로 받아 `activeTabChanged` 로 흘린다(실측 확인).

## 4. 경로 정규화 — 엔진이 단일 소스
`realpath(3)` 기준이다(파일 감시자가 이미 그것을 쓴다 — FSEvents 가 `/tmp` 를 `/private/tmp` 로
주기 때문에 그러지 않으면 경로 비교가 조용히 전부 빗나간다). 심볼릭 링크·`..`·`.` 가 해소된다.

`ProjectTab.rootPath` 는 **항상 정규화된 값**이다. 앱은 그것을 키로 AC-5 를 판정한다 —
**판정 주체는 앱, 기준값은 엔진.** 앱이 자기 규칙으로 정규화하면 같은 프로젝트가 두 탭이 된다.

## 5. 인덱싱 스케줄 — 활성 탭 우선
복원 직후 탭 다섯을 동시에 인덱싱하면 **사용자가 보는 탭이 가장 늦게 준비될 수 있다**(PD F-13-3).
- 활성 탭을 먼저 끝내고, 나머지는 배경에서 **순차**로.
- `activate(_:)` 는 그 탭의 우선순위를 올린다 — 사용자가 옮겨간 곳이 곧 급한 곳이다.
- 병렬 파싱은 **탭 안에서** 유지한다(기존 `TaskGroup`). 탭 **사이**를 순차로 둔다.

## 6. 탭 닫기 정리 계약 (AC-3)
계약이 보장하는 것 셋. **RSS 감소는 판정 기준이 아니다**(ADR-0008 실측: 닫아도 RSS 는 안 줄지만
재사용된다 — 다시 열어도 +0.4MB).
1. **고아 프로세스 없음** — 프로세스가 하나뿐이라 탭 단위로는 발생 여지가 없다.
2. **인덱스 해제** — 세션 인스턴스 수명 = 인덱스 수명. **별도 정리 호출이 없으므로 잊을 수 없다.**
3. **여닫기를 반복해도 증가하지 않는다** ← 진짜 회귀 신호. 이것만 테스트로 못 박는다.

## 7. security-scoped 제약 (AC-7·8·9)
저장·복원은 앱 소유다. 다만 **엔진이 그 URL 로 계속 스캔하고 감시하기 때문에** 제약이 생긴다:

> **스코프는 탭이 열려 있는 내내 유지되어야 한다.** 여는 순간만 열고 닫으면 이후 재스캔과
> 파일 감시가 **조용히** 실패한다 — 에러가 아니라 "변경이 반영되지 않음"으로 나타나서
> 원인 추적이 어렵다.

부분 방어: `indexStatistics().fileCount == 0` 이면 앱이 **"열렸는데 파일이 하나도 없다"** 를
알 수 있다. 진짜 빈 레포와 구분은 못 하지만 **조용히 정상인 척하는 것보다 낫다.**

## 8. 미정 — 프론트 합의가 필요한 것
1. **마지막 탭 닫기**: `tabclose` 는 마지막 탭페이지에서 실패한다(실측: `E784`, 프로세스 생존).
   **제안 — 세션을 죽이지 말고 빈 탭페이지로 남긴다.** 재개방이 즉시다(기동 440ms 절약).
   메모리를 더 아끼려면 죽이는 선택도 있다(15MB).
2. **전역 검색**(열린 프로젝트 전체를 가로지르는)이 필요한가 — 요구사항에 없다. 없으면 이 형태가 그대로 맞다.
3. `WorkspaceMemoryFootprint` 의 모양 — 탭별 증가분만인지, 기준선도 포함인지.
