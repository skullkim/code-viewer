# 계약 표면 ↔ 구현 전수 대조

- 시점: `CodeNavigatorEngine` 폐기 직후 · `@ ab7dfc1`
- 작성: backend-senior · 방법: **명령 출력**(눈으로 세지 않는다)

```bash
# 프로토콜 요구
grep -oE '^    func [a-zA-Z]+' Sources/CodeNavigatorContract/<Protocol>.swift
# 구현 공개 표면
grep -oE '^    public func [a-zA-Z]+' Sources/CodeNavigatorCore/<Impl>.swift
# 양방향 차집합
comm -3 <(…요구…) <(…구현…)
```

## 1. 방향 A — 계약이 요구하는데 구현에 없는 것

| 프로토콜 | 요구 | 미구현 |
|---|---|---|
| `ProjectSession` → `ProjectEngine` | 10 | **0** |
| `EditorSession` → `NeovimEditorSession` | 26 | **0** |
| `ProjectWorkspace` → `ProjectWorkspaceEngine` | 10 | **0** |

**구멍 없음.** 폐기가 계약에 빈자리를 만들지 않았다.

## 2. 방향 B — 구현에 있는데 계약에 없는 것

이 방향을 같이 보지 않으면 *"구현이 있다"* 와 *"앱이 부를 수 있다"* 를 구별하지 못한다.
오늘 이 구별을 세 번 놓쳤다(`renderSource`·`renderResource`·아래 2건).

| 타입 | 멤버 | 분류 | 근거 |
|---|---|---|---|
| `ProjectEngine` | `closeProject` | **내부 생명주기** | 워크스페이스가 탭을 닫을 때 부른다. 앱은 탭을 닫지 세션을 닫지 않는다 |
| `ProjectEngine` | `reindexSavedFile` | **검증 표면 + 내부** | 워크스페이스 라우팅이 부르고, `WorkspaceSaveRoutingTests` 가 **감시자를 우회해** 직접 부른다. 이게 없으면 라우팅을 잴 방법이 없다 |
| `NeovimEditorSession` | `startReusingAgreedGridSize` | **내부 생명주기** | 워크스페이스가 실패한 편집기를 되살릴 때. 앱은 재시도를 명령하지 크기를 정하지 않는다 |
| `NeovimEditorSession` | `dirtyStateChanges` | **내부 신호** | 워크스페이스가 탭별 더티 수로 집계할 원천. 앱은 집계된 값을 본다 |
| `ProjectWorkspaceEngine` | `memoryFootprint` | **검증 표면** | AC-3 판정용. `gate.sh` 격리 스텝이 읽는다. UI 표시 없음(PD §7.1) |
| `ProjectWorkspaceEngine` | `shutDown` | **조립 루트 전용** | 앱 종료 시 조립부가 부른다. 프로토콜에 올리면 뷰가 워크스페이스를 끌 수 있게 된다 |
| `ProjectWorkspaceEngine` | **`dirtyFiles(in:)`** | 🔴 **부채** | 아래 |
| `ProjectWorkspaceEngine` | **`saveAll(in:)`** | 🔴 **부채** | 아래 |

## 3. 부채 — 앱이 계약을 우회한다 (인증 후 처리, 리더 판정)

W-13(더티 탭 닫기)이 필요로 하는 탭 단위 문이 **구현에는 있고 프로토콜에는 없다.**
그래서 앱이 편집기로 직접 간다:

```swift
AppModel:503   let root = URL(fileURLWithPath: tab.rootPath)
AppModel:504   try? await editorSession.dirtyFiles(inProjectRoot: root)
```

**오늘 깨지는 것은 없다.** 리더가 실측했다 — `NeovimEditorSession:576-589` 이 양쪽을 `realpath`
로 정규화하고 구분자를 붙여 접두 비교하므로, **형제 접두 함정이 이쪽엔 처음부터 없다.**

**위험은 두 자리가 앞으로 갈라지는 것이다.** 루트 정규화가 앱과 워크스페이스 두 곳에 있고,
한쪽만 고치면 조용히 어긋난다.

**판정(리더): 인증 후 `tabs()` 단일 소스 ADR 과 함께 다룬다.** 둘은 *"앱이 워크스페이스를
건너뛴다"* 는 한 문제의 두 얼굴이다. 트리가 안정해야 하는 구간에 계약 표면을 넓히지 않는다.

## 4. 이 감사가 잡은 규칙

**계약에 문이 없으면 앱은 우회로를 만든다.** 그리고 우회로가 생긴 뒤에 문을 내면 **이미 두
경로다.** 오늘 세 번 나왔다:

| # | 구현 위치 | 계약 표면 | 결과 |
|---|---|---|---|
| 1 | `renderSource` (워크스페이스) | 없었음 | 주니어가 막힘 → 두 줄 추가로 해소 |
| 2 | `renderResource` (워크스페이스) | 없었음 | 어댑터 착수 불가 → 같이 해소 |
| 3 | `dirtyFiles`·`saveAll` (워크스페이스) | **없음** | 앱이 편집기로 우회 중 → 부채 |

→ **새 능력을 워크스페이스에 넣을 때 "앱이 이걸 어떻게 부르나"를 같은 커밋에서 답한다.**
