# REQ-012 계약 준비 — 다중 프로젝트 표면 후보

- 작성: backend-senior · 2026-08-30 · **준비 문서 (구현 착수 전, PD 설계·프론트 합의 대기)**
- 전제: ADR-0008 채택 — **Neovim 프로세스는 하나**, 프로젝트당 탭페이지 + `tcd`

## 1. 지금 계약이 "프로젝트 하나"를 전제하는 지점 (전수)

| 위치 | 전제 | 다중화하면 |
|---|---|---|
| `openProject(at:)` | **교체** 의미론 — 새로 열면 이전 것이 사라진다 | "추가"가 되어야 한다. 교체는 별개 개념이 된다 |
| `currentProject()` | 열린 프로젝트가 **0 또는 1** | 여럿 중 **어느 것**인지 물어야 한다 |
| `indexState()` / `indexStateUpdates()` | 인덱스가 하나 | 탭마다 다른 상태(한 탭은 인덱싱 중, 다른 탭은 최신) |
| `indexStatistics()` | 통계가 하나 | 탭별 + 합계 둘 다 필요할 수 있다 |
| `definitions` · `searchSymbols` · `references` · `searchText` · `directoryEntries` | **암묵적으로 "그 하나의 프로젝트"** 대상 | 어느 프로젝트에 묻는지가 명시돼야 한다 |
| `EditorSession.start(projectRoot:)` | 세션 = 프로젝트 하나 | 세션은 하나, 프로젝트는 여럿 |
| `EditorSession.openFile(atRelativePath:)` | 상대 경로가 **그 하나의 루트** 기준 | 어느 탭의 루트인지 결정돼야 한다 |
| `ProjectWorkspace`(앱, ADR-0106) | 인덱스와 편집기가 **한** 프로젝트를 함께 따라간다 | 탭 단위로 좁힌다 (리더 관측대로 폐기가 아니라 축소) |

**앱 쪽 파급**: `AppModel` · `FileTreeModel` · `SearchModel`이 각각 `ProjectSession`을 하나씩 들고 있다.
이 셋은 **이미 "세션을 주입받는" 모양**이라, 세션이 프로젝트당 하나가 되면 **그대로 탭당 하나**가 된다.

## 2. 후보 셋

### 후보 A — `ProjectSession` 인스턴스를 프로젝트당 하나 (권고)
열기는 세션을 **만드는** 일이 되고, 조회 메서드는 전부 그대로다.
```
protocol ProjectSessionFactory { func openProject(at: URL) async throws -> any ProjectSession }
// ProjectSession 에서 openProject 는 빠지고, 나머지 9개는 시그니처 불변
```
- **INV-5(탭 간 격리)가 구조로 성립한다** — 인스턴스가 다르면 서로의 상태에 닿을 방법이 없다.
- 조회 메서드 **시그니처가 하나도 안 바뀐다.** 프론트의 `FileTreeModel`·`SearchModel`은 주입만 탭별로 바뀐다.
- 탭 닫기 = 그 세션을 놓아주는 것. 소유권이 명확하다.
- 비용: 앱이 `[탭: 세션]`을 관리해야 한다. 다만 **지금도 세션을 주입받는 구조라 자연스럽다.**

### 후보 B — 모든 메서드에 프로젝트 식별자를 더한다
```
func definitions(named: String, in project: ProjectIdentifier) async -> [SymbolDefinition]
```
- 세션은 계속 하나. 계약 표면의 **모든 조회 메서드가 바뀐다**(9개).
- **격리가 구조가 아니라 규율이 된다** — 식별자를 잘못 넘기면 다른 탭 결과가 나온다. 컴파일러가 안 막는다.
- 이 빌드에서 반복해 배운 것과 반대 방향이다(규율보다 구조).

### 후보 C — 세션 하나 + "활성 프로젝트" 포인터
```
func activateProject(_ id: ProjectIdentifier) async ; 이후 조회는 활성 대상에 적용
```
- 계약 변경이 가장 작다. 그러나 **조회가 상태 의존이 되어 경합이 생긴다** — 탭 A의 검색이 진행 중에
  사용자가 탭 B로 옮기면 A의 결과가 B의 것으로 표시될 수 있다. **INV-5 위반 경로가 열린다.**
- 기각 권고.

## 3. 편집기 쪽은 비대칭이다 — 그리고 그게 맞다
**`ProjectSession`은 N개, `EditorSession`은 1개**를 권고한다. 근거:

- **격리가 필요한 곳은 동시에 질의되는 곳**이다. 인덱스·검색은 탭이 보이지 않아도 배경에서 돌고,
  사용자가 탭을 옮겨도 이전 탭의 검색이 끝나서는 안 된다 → 인스턴스 분리가 답이다.
- **편집기는 보이는 표면이 하나뿐이다.** Neovim의 활성 탭페이지가 곧 화면이고, 그리드도 하나다.
  여기에 인스턴스를 N개 두면 **없는 동시성을 모델링**하는 것이고, ADR-0008이 얻은 45MB를 도로 잃는다.

따라서 `EditorSession`에 필요한 것은 인스턴스가 아니라 **탭 조작**이다:
```
func openProjectTab(root: URL) async throws -> EditorTabIdentifier
func activateProjectTab(_ id: EditorTabIdentifier) async throws
func closeProjectTab(_ id: EditorTabIdentifier) async throws
func openFile(atRelativePath:line:recordJump:)   // 활성 탭의 루트 기준 — 지금과 같다
```
`openFile`이 활성 탭 기준인 것은 경합이 아니다 — **활성 탭이 곧 사용자가 보고 있는 화면**이기 때문이다.

## 4. 탭 닫기 정리 계약 (REQ-012 AC-3)
"메모리 잔존 없음"을 **RSS 감소로 판정하면 안 된다**(ADR-0008 실측: 닫아도 RSS는 안 줄지만 재사용된다).
계약이 보장해야 할 것은 셋이고, 그대로 테스트 가능하다:

1. **고아 프로세스 없음** — 탭페이지 모델이라 프로세스는 애초에 하나다. 앱 종료 시 `shutDown()` 하나로 끝난다.
2. **인덱스 해제** — 그 프로젝트의 `ProjectSession`을 놓으면 인덱스도 함께 해제된다.
   후보 A에서는 **인스턴스 수명이 곧 인덱스 수명**이라 별도 정리 호출이 필요 없다.
3. **여닫기를 반복해도 증가하지 않는다** ← 진짜 회귀 신호. 이것만 테스트로 못 박으면 된다.

→ 계약 표면에 `closeProject()`류를 두기보다 **세션을 놓는 것으로 정리가 성립**하는 편이 낫다.
   "정리하는 것을 잊었다"가 불가능해진다.

## 5. 아직 정하지 않은 것 (PD 설계·프론트 합의 필요)
- 탭별 인덱스 상태를 **탭 바에 어떻게 드러낼지**(각 탭에 진행 표시 vs 활성 탭만)
- **전역 검색**(모든 열린 프로젝트를 가로질러)이 필요한가 — 요구사항에 없다. 없으면 후보 A가 더 단순하다.
- 탭 전환 시 **이전 프로젝트 화면이 한 프레임 보이는지**(프론트에 확인 요청해 둠). 문제면 엔진이
  전환 완료 후에만 스냅샷을 내보내면 된다.
