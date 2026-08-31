# 요구사항-테스트 추적 매트릭스 — code-navigator-mac

각 개발자가 **자기 기여분만 추가**한다(행 추가·자기 행 수정). 게이트 상태는 `_workspace/gate.sh`를
실제로 돌린 사람(backend-senior)만 갱신한다.

> ## 이 표가 증명하지 않는 것 — 화면 (2026-08-29 22:5x, 리더)
>
> `테스트 상태` 열은 **"나열된 테스트가 통과한다"** 만 뜻한다. **"그 요구사항이 화면에서
> 성립한다"는 뜻이 아니다.** 화면 동작을 요구하는 AC(파일을 선택하면 에디터에 열린다 ·
> 트리에서 강조된다 · 화면에 반영된다 …)가 지금 순수 함수 테스트만을 근거로 PASS 로 적혀
> 있는데, 정작 그 뷰들은 **어디에도 마운트돼 있지 않다**. 값이 틀린 게 아니라 스키마에
> 렌더링이 드러날 자리가 없다.
>
> **완료 인증에서 이 표의 PASS 를 화면 근거로 쓰지 않는다.** 화면 판정은 둘로만 한다:
>
> 1. **마운트 카운트**(기계적) — 정의부를 뺀 참조 수:
>    `grep -rn "ViewName(" Sources/ --include="*.swift" | grep -v "struct ViewName"`
>    합격선 = `PlaceholderPane` 이 **0** 이고, 화면 뷰(`FileTreeView` · `EditorGridView` ·
>    `ProjectOpenView` · `StatusBarView` · `MainWindowView` 등)가 각각 **1 이상**.
> 2. **리더 인증** — 실제 `.app` 라이브 E2E + 프로토타입 스크린샷 대조(화면 잠금 해제 필요).
>
> 22:56 실측: `PlaceholderPane` **3** · `FileTreeView`·`EditorGridView`·`ProjectOpenView` 각 **0**.
> 이 시점의 화면 관련 PASS 는 전부 **리더 인증 대기**다.
>
> ### 추가 (2026-08-30 21:2x, 리더) — REQ-012·013 을 PASS 로 읽지 마라
>
> 사용자가 직접 요청한 기능 둘이다. **실측**:
> ```
> ProjectTabSet · ProjectTab · ProjectTabBarPresentation
> ProjectTabCommand · TabRestorePlan     소스 참조 전부 0   ← 뷰만이 아니라 모든 층
> ProjectTabBarView                      마운트     0
> AppModel(413줄)  indexState·editorStatus·projectRootPath·fileTree 를 직접 보유
> 렌더 뷰              존재하지 않음 · WKWebView 참조 0
> RenderSandboxPolicy  소스 0 · 테스트 33       ← 완전히 테스트된 고아
> ```
> **배선은 "뷰 하나 꽂기"가 아니다** — ADR-0107 이 "상태는 탭 단위"로 결정했는데 `AppModel` 이
> 아직 단일 프로젝트 상태를 직접 들고 있다. **모델 소유 구조를 바꾸는 통합 작업**이다
> (리더가 "한 곳"이라는 추정을 실측 없이 받아 세 번 재촉했던 것을 정정한다).
> REQ-012 는 AC-1~AC-6 이 **71건의 테스트로 PASS** 인데 **사용자는 탭을 하나도 볼 수 없다.**
> 이게 정확히 위 배너가 경고하는 상태이고, **이번 빌드에서 가장 비싼 오판의 형태**다 —
> 매트릭스가 PASS 로 가득한데 화면에 그 기능이 없는 것.
>
> **판정: REQ-012·REQ-013 은 "로직 PASS · UI 미배선"이다.** 1차 인증 범위 밖이고,
> **마운트되기 전까지 어떤 문서도 이 둘을 "구현됨"으로 적지 않는다.**

| REQ-ID | 영역 | 커버하는 테스트 | 담당 | 테스트 상태 |
|--------|------|---------------|------|-----------|
| REQ-001 AC-1 · AC-4 | backend | `ProjectIndexerTests` — 열기 시 전체 인덱싱·제외/gitignore 반영 · `ProjectScannerTests` (12) | backend-senior | PASS |
| REQ-001 AC-2 | backend | `ProjectSwitchingTests` (3) — 인덱스·검색·트리 교체 · **편집기도 새 루트를 따라감** · 실패 시 이전 프로젝트 유지 | backend-senior | PASS |
| REQ-001 AC-3 | backend | `ProjectIndexerTests` "존재하지 않는 경로는 에러이고 이전 프로젝트가 유지된다" · `ProjectScannerTests` 누락/파일루트 에러 | backend-senior | PASS |
| REQ-002 AC-1 · AC-2 | backend | `SymbolExtractorTests` (Kotlin 5 / Java 2 / TS·JS 5) — 7종 심볼 전량, 4언어 | backend-senior | PASS |
| REQ-010 AC-2 (마우스) | backend | `NeovimMouseInputTests` (5) — 드래그 선택·휠 스크롤·수식키 전달·그리드 셀 좌표계(스크롤 상태)·기동 전 무시 | backend-junior | PASS (합성 마우스 이벤트에 80ms 간격 필요 — 붙여 보내면 nvim이 드래그로 안 읽는다) |
| REQ-004 AC-4 (저장 통지 값) | backend | `EditorSavedFileTests` (2) — 줄 수·바이트 수를 픽스처·디스크와 등호 대조(한글 픽스처로 바이트≠글자 확인) | backend-junior | PASS |
| REQ-002 AC-4 (인덱스 통계) | backend | `ProjectEngineStatisticsTests` (2) — 읽지 못한 파일만 건너뜀으로 집계·열기 전 빈 통계 | backend-junior | PASS |
| REQ-NF-001 (전문 검색 ≤2초) | backend | `SearchPerformanceTests` (5) — 리터럴·정규식 전체 스캔, 상한 도달, 측정기 자체 검사 | backend-junior | PASS (리터럴 305ms · 정규식 250ms · 상한 77ms) |
| SC-1 · SC-2 (인증 픽스처) | backend | `CertificationFixtureTests` (6) — 정의 1곳/3곳, 유사 이름 미오염, node_modules 제외, 한글 오프셋·경계 | backend-junior | PASS |
| REQ-NF-003 (기동 ≤2초) | backend | `_workspace/measure-app-runtime.sh` | backend-junior | **측정 불가** — 화면 잠금으로 창이 CGWindowList에 안 오름. 해제 후 재실행 필요 |
| SC-8 (.app 유휴 메모리) | backend | `measure-app-runtime.sh --idle-only` | backend-junior | **미판정** — 프로젝트 미개방 기준선만 84.8MB 실측. 인덱싱 후 값은 수동 단계 필요 |
| REQ-NF-002 · SC-8 (유휴 메모리) | backend | `SearchPerformanceTests` + `gate.sh` 격리 측정 스텝 | backend-junior | PASS (격리 실행 27.4MB / 인덱스 비용 19.1MB) |
| **W-8 약속 (편집기 없이도 인덱스)** · REQ-004 AC-5 | backend | `EditorFailureKeepsIndexTests` (2) — 편집기 실패해도 프로젝트 열림·심볼 검색됨·상태에 실패 남음 · **실패 후 다시 열기가 편집기를 다시 띄운다**(흡수 상태 회귀 방어) | backend-senior | PASS |
| **REQ-001 AC-2 (전환 시 편집기 동행)** · REQ-004 AC-5 | backend | `EditorFailureKeepsIndexTests` — 크래시 뒤 다른 프로젝트로 전환하면 **전환도 되고 편집기도 돌아온다**(예전 동작으로 변이 시 Red 확인) | backend-senior | PASS |
| **REQ-012 AC-5 (대소문자 접힘)** | backend | `ProjectWorkspaceEngineTests` — 대소문자만 다른 경로가 한 탭. **볼륨에 직접 물어** 비구분이면 1탭·구분이면 2탭. 정규화를 `realpath`→문자열로 변이 시 Red 확인(빌드 에러 0) | backend-senior | PASS |
| **REQ-012 AC-1·AC-2·AC-5 · INV-5** | backend | `ProjectWorkspaceEngineTests` (8) — 두 프로젝트 동시 개방·양쪽 검색 · **탭 A 검색이 탭 B 심볼을 못 본다(INV-5)** · 재개방은 `.activatedExisting` · 심링크 다른 표기도 한 프로젝트 · 순서 바꾸기는 순열만 | backend-senior | PASS |
| **REQ-012 AC-3 (닫으면 해제)** | backend | 위 스위트 — 세션 nil·이웃 탭 무사 · `WorkspaceMemoryReuseTests` (2) — **총 증가 688KB < 인덱스 하나 5936KB**. 회차 10·20·40·80 을 각각 새 프로세스에서 재어 **총 증가가 회차와 무관**함을 확인(누수 아님). 판정은 `gate.sh` 격리 스텝(동시 실행 0 확인 후) | backend-senior | PASS |
| **REQ-012 AC-4·AC-6 (복원)** | backend | 위 스위트 — 못 연 것을 사유(`notFound`)와 함께 돌려준다 · **활성 탭 복원**(가운데 탭이 활성이던 경우) · **활성이던 프로젝트가 사라지면 남은 첫 번째로 폴백**. 경로 비교는 정규화 기준 | backend-senior | PASS (앱 저장·전달 배선은 프론트) |
| **ADR-0008/0009 (탭페이지 격리)** | backend | `EditorProjectTabTests` (5) — 탭별 `tcd` · 첫 탭 재사용 · 닫기 · **마지막 탭은 세션 유지** · `showtabline=0`(변이 2건 Red) · `TabPageIsolationSpikeTests` — 격리되는 둘과 **격리 안 되는 둘 모두 단언** | backend-senior | PASS |
| **D-16 (편집기 cwd)** | backend | `EditorWorkingDirectoryTests` — `lsof` 로 OS 에 묻는다(`:cd` 가 답을 바꿀 수 있으므로). 변이 시 관측값이 `~/Documents/...` — **D-14 TCC 후보 뒷받침** | backend-senior | PASS |
| **공유 머신 안전 (pid 0)** | backend | `ProcessIdentifierSafetyTests` (2) — 기동 안 한 프로세스의 pid 가 nil. `kill(0,…)` 은 프로세스 그룹을 겨눈다 | backend-senior | PASS |
| **D-2 (버려진 세션이 편집기를 남기지 않음)** | backend | `AbandonedSessionReclaimProbeTests` (2) — 세션 4·8개를 **동시에** 띄워 한꺼번에 버려도 전부 회수. 수정 전 100% 재현(넷 중 셋 생존), 수정 후 0.54초 전량 회수 | backend-senior | PASS |
| **기동 중 소유권 (D-7 가설 배제)** | backend | `StartupOwnershipTests` (3) — 세션만·엔진만 붙들어도 프로세스 생존 + **양성 대조: 전부 놓으면 0.07초에 죽는다**(앞 둘이 실제로 재고 있다는 증거) | backend-senior | PASS |
| **INV-6 (엔진 파일 읽기 루트 제한)** | backend | `ProjectRelativePathTests` (7) — 절대경로 3종·상위 탈출 4종·**루트 밖 심링크**(세그먼트 검사로는 못 잡음)·루트 안 심링크 허용·`docs..old` 정상 통과·없는 파일은 경로위반 아닌 `fileNotFound` | backend-senior | PASS |
| 계약 §3.2 표면 | backend | `ContractSurfaceTests` (3) — `any ProjectSession`으로 전 메서드 호출 + 오프셋 불변식 | backend-junior | PASS |
| REQ-013 AC-1·AC-5·AC-6 · INV-6 | backend | `RenderSourceTests` (9) — 버퍼 우선·출처 구분·1MiB~2MB 구간 성공·2MB 초과 tooLarge·경로 이탈 거부·디코드 실패 | backend-junior | PASS |
| REQ-001 AC-3 (열기 실패) | backend | `ProjectOpenFailureTests` (6) — 경로 없음·파일을 루트로·권한 없음 구분, 한국어 안내 문구, 실패 후 이전 프로젝트 유지 | backend-junior | PASS |
| REQ-010 AC-2 (편집 명령 실패 경로) | backend | `EditorCommandFailurePathTests` (8) — 선택 없는 복사/잘라내기, 예전 선택 되살리기 회귀, 이름없음·읽기전용 저장 에러, undo/redo 경계, 전체선택→잘라내기 후 타이핑 | backend-junior | PASS |
| REQ-002 AC-3 | backend | `SourceLanguageTests` (4) 미지원 확장자 nil · `SymbolExtractorTests` 미지원 확장자 빈 결과 · `ProjectScannerTests` 미지원 파일도 검색 대상 유지 | backend-senior | PASS |
| REQ-004 AC-2 (셀 좌표) | backend | `NeovimGridStateWideCharacterTests` (5) — 한글 줄 문자7/셀10 · 한글 뒤 startColumn · run 타일링 · 커서 좌표계 일치 · ASCII 동치 | backend-senior | PASS |
| REQ-NF-005 (버전) | backend | `NeovimVersionTests` (6) 파싱·나이틀리 접미사·숫자 비교 · `NeovimEditorSessionTests` 기동 실패 구조화·실설치 버전 판독 | backend-senior | PASS |
| REQ-010 AC-2 (마우스) | backend | `NeovimEditorSessionTests` "마우스 클릭을 그리드 셀 좌표로 전달한다" | backend-senior | PASS |
| REQ-008 (검색 범위 문구) | backend | `TextSearchFilesSearchedTests` (3) — 훑은 파일 수 보고 · 빈 질의 0 · 상한 중단 시 전체보다 작음 | backend-senior | PASS |
| REQ-002 AC-4 (UI 표면) | backend | `IndexStatisticsTests` (5) — 스킵 집계·복구·삭제와 구분·전환 시 초기화 | backend-senior | PASS |
| REQ-005 AC-1 (강조) | backend | `QaIdentifiedGapTests` 정의 이동 시 임시 강조 후 자동 소멸 · 라인 미지정 시 미강조 | backend-senior | PASS |
| REQ-009 AC-5 (재기동 후) | backend | `QaIdentifiedGapTests` "편집기 재기동 후에도 저장이 인덱스에 반영된다" | backend-senior | PASS |
| REQ-003 AC-3 (경로 정합) | backend | `QaIdentifiedGapTests` 편집기 절대경로 → 트리 상대경로 상대화 일치 | backend-senior | PASS |
| REQ-002 AC-4 | backend | `SymbolExtractorTests` 깨진 소스·부분 깨짐·빈 소스 · `ProjectIndexerTests` "파싱이 깨지는 파일이 있어도 나머지는 인덱싱된다" | backend-senior | PASS |
| REQ-004 AC-1 | backend | `NeovimChannelTests` 기동·요청/응답·에러 표면화 · 미설치 시 명확한 에러 · `NeovimEditorSessionTests` 끊김 상태 | backend-senior | PASS |
| REQ-004 AC-2 | backend | `NeovimChannelTests` ui_attach 후 redraw 수신·키 입력→버퍼·모드 전이 · `NeovimGridStateTests` (16) 그리드 전 이벤트 | backend-senior | PASS |
| REQ-004 AC-3 · INV-4 | backend | `NeovimChannelTests` "사용자 설정이 그대로 적용된다 — 단, UI를 붙인 뒤에 로드된다" (XDG 픽스처) | backend-senior | PASS |
| REQ-004 AC-4 | backend | `NeovimEditorSessionTests` 더티→저장→경로 통지·디스크 반영 · `AcceptanceScenarioTests` SC-3 | backend-senior | PASS |
| REQ-004 AC-5 · SC-7 | backend | `NeovimChannelTests` SIGKILL 감지·요청 즉시 실패 · `NeovimEditorSessionTests` 끊김 통지 후 재기동 | backend-senior | PASS |
| REQ-005 AC-1 · SC-1 | backend | `AcceptanceScenarioTests` SC-1 · `NeovimEditorSessionTests` 파일 열기+라인 이동 | backend-senior | PASS |
| REQ-005 AC-2 · SC-2 | backend | `AcceptanceScenarioTests` SC-2 동명 정의 3건 · `SymbolIndexTests` 동명 정의 전량·정렬 | backend-senior | PASS |
| REQ-005 AC-3 | backend | `SymbolIndexTests` "없는 이름은 빈 배열이다 — nil이 아니다" (호출자가 "찾을 수 없음"을 구분 가능) | backend-senior | PASS |
| REQ-005 AC-4 | backend | `NeovimEditorSessionTests` `recordJump` 경로 · `NeovimChannelTests` 점프 목록 | backend-senior | PASS |
| REQ-006 AC-1 (강조) | backend | `ReferenceHighlightTests` (7) — 구간이 미리보기 심볼을 가리킴 · 한 줄 2회 · 부분 단어 미강조 · **한글 접두 식별자 미강조**(경계 규칙 한 벌) · UTF-16 환산 · 선행 공백 보정 · 정의도 구간 보유 | backend-senior | PASS |
| REQ-006 AC-2 | backend | `AcceptanceScenarioTests` "참조 목록에 정의가 포함되고 플래그로 구분된다" | backend-senior | PASS |
| REQ-007 AC-1 · AC-2 · AC-4 | backend | `SymbolSearcherTests` (7) 관련도 순위·동점 규칙·상한 50·강조 구간·빈 결과 · `AcceptanceScenarioTests` 퍼지 검색 | backend-senior | PASS |
| REQ-008 AC-2 · SC-6 | backend | `AcceptanceScenarioTests` SC-6 잘못된 정규식은 에러(같은 문자열의 리터럴 검색은 정상 빈 결과) | backend-senior | PASS |
| REQ-009 AC-1 | backend | `ProjectIndexerTests` 변경 파일만 재인덱싱 · `FileSystemWatcherTests` 실제 FSEvents 감지 · `FileChangeBatchTests` 디바운스 합침 | backend-senior | PASS |
| REQ-009 AC-2 · INV-1 | backend | `ProjectIndexerTests` 삭제 시 심볼 제거 · `SymbolIndexTests` 양방향 맵 정리·빈 키 제거 | backend-senior | PASS |
| REQ-009 AC-3 | backend | `ProjectIndexerTests` 이름 변경 후 옛 경로 잔재 없음 · gitignore 신규 적용 시 삭제 취급 | backend-senior | PASS |
| REQ-009 AC-4 · SC-5 | backend | `ProjectIndexerTests` 대량 변경 전체 재스캔 폴백(경계 50)·드롭 신호 재스캔 · `FileChangeBatchTests` (7) · `FileSystemWatcherTests` 대량 변경 생존 | backend-senior | PASS |
| REQ-009 AC-5 · SC-3 | backend | `AcceptanceScenarioTests` SC-3(2초 내 검색) · "저장 통지 경로만으로도 재인덱싱된다" · 프로젝트 밖 경로 무시 | backend-senior | PASS |
| REQ-010 AC-4 | backend | `NeovimEditorSessionTests` "입력 모드를 바꿔도 편집 내용과 더티 상태가 보존된다"(전환만으로 저장되지 않음 포함) | backend-senior | PASS |
| INV-2 (파생물) | backend | `ProjectIndexerTests` 열기 시 전량 재생성 · 디스크 영속 코드 부재(ADR-0003) | backend-senior | PASS |
| INV-3 (편집 단일 경로) | backend | `NeovimChannelTests` "버퍼를 고쳐도 디스크는 그대로고 :w 시점에만 쓰인다" · `ProjectSession`에 쓰기 API 부재(타입 수준 강제) | backend-senior | PASS |
| REQ-NF-003 | backend | `StartupAndBulkChangeTests` — 3,000파일 엔진 기동 **0.19초**(목표 2초) · 인덱싱·편집기 병렬성(합보다 짧음) | backend-senior | PASS |
| SC-5 (실 git) | backend | `StartupAndBulkChangeTests` — 실제 `git init`+`commit`+`checkout -- .` 300파일 되돌림 후 유령 0 · 추적 안 된 파일 보존 · 검색이 디스크와 일치 | backend-senior | PASS |
| REQ-NF-001 | backend | `IndexingPerformanceTests` (3) — 5,000파일 인덱싱 0.28초 / 정의 조회 0.0ms / 증분 갱신 0.4ms | backend-senior | PASS |
| REQ-NF-004 | backend | `SymbolExtractorTests` 깨진 소스 · `ProjectScannerTests` 심링크 루프·읽기 실패 · `ProjectIndexerTests` 바이너리/초대형 파일 스킵 · `NeovimGridStateTests` 미지 이벤트·범위 밖 좌표 | backend-senior | PASS |
| REQ-NF-005 | backend | `NeovimChannelTests` 미설치 시 `editorNotInstalled` · 실행 불가 경로 에러 | backend-senior | PASS |
| REQ-007 AC-1 | backend | `FuzzyMatcherTests` (10) — 부분수열 매칭·대소문자 무시·불일치·강조 구간·점수 순위 | backend-junior | PASS |
| REQ-006 AC-1 · REQ-008 AC-1 | backend | `PreviewTextBuilderTests` (8) — UTF-8→UTF-16 환산(한글)·선행 공백 보정·200 절단·서로게이트 페어 보호 | backend-junior | PASS |
| REQ-004 (ADR-0006 RPC 코덱) | backend | `MessagePackCodecTests` (23) — 전 타입 왕복·폭 경계·중첩·부분 프레임 판정·다중 프레임 소비 위치 | backend-junior | PASS |
| REQ-002 AC-3 | backend | `ProjectEngineSearchScopeTests` (3) — 미지원 확장자도 전문·참조 검색 대상, 인덱싱 대상은 아님 (변이 주입으로 검증) | backend-junior | PASS |
| REQ-003 AC-1 · AC-2 | backend | `DirectoryTreeListerTests` (13) — 한 레벨 지연 로드·디렉토리 우선 정렬·제외/gitignore·`..` 세그먼트 거부·읽기 실패 | backend-junior | PASS |
| REQ-006 AC-1 · AC-2 · AC-4 | backend | `ReferenceSearcherTests` (11) — 단어 경계(부분 단어 불일치)·정의 플래그·정렬·상한 1000 경계 | backend-junior | PASS |
| REQ-008 AC-1~AC-4 | backend | `TextSearcherTests` (15) — 리터럴/정규식·잘못된 정규식 에러·제외 미노출·이진 파일 스킵·상한 500 경계 | backend-junior | PASS |

| REQ-011 AC-3 (창 크기 적응) | frontend | `ShellLayoutTests` (13) — 02 §4.4 창 폭 표 전수 · **좁은 창에서 상태바 26pt 생존**(PD 프로토타입 결함 재발 방지) · 에디터 최소 420 우선 | frontend-senior | PASS |
| REQ-011 AC-4 (다크/라이트) | frontend | `DesignTokenTests` (6) — 19토큰 2테마 · **텍스트 8토큰 × 실제 사용 배경 6종 대비 4.5:1 검사** · `ColorContrastTests` (5) WCAG 공식 | frontend-senior | PASS |
| REQ-011 AC-2 (단축키 비충돌) | frontend | `KeyNotationTests` (12) — ⌘ 조합만 앱이 claim · ⌃O·⌃R·⌃V·⌃W·`:`·Esc·화살표 전부 Neovim 도달. spike가 `.app`에서 실제 이벤트 디스패치로 실증 | frontend-senior | PASS |
| REQ-010 AC-3 (모드 상시 표시) | frontend | `StatusBarPresentationTests` (15) — Vim 4모드 칩·표준 칩·끊김 시 편집 불가 · **모든 창 폭에서 모드 세그먼트·인덱스 칩 생존** | frontend-senior | PASS |
| REQ-010 AC-5 (모드별 편집 메뉴) | frontend | `MenuAvailabilityTests` (12) — Vim에서 ⌘Z·⌘C·⌘V·⌘A 비활성, ⌘S만 공통 활성 · 세션 끊겨도 검색은 동작 · 24명령 전수 | frontend-senior | PASS |
| REQ-009 (인덱스 상태 UI) | frontend | `StatusBarPresentationTests` — 인덱스 5상태 칩 §6과 1:1 · 비-최신 상태 툴팁("직전 인덱스로 응답 중") | frontend-senior | PASS |
| REQ-004 AC-2 (그리드 렌더 — **픽셀 검증**) | frontend | `GridRenderingTests` (9) — **오프스크린 비트맵에 실제로 그리고 픽셀을 읽어** 검증. 런 안에서 `한A`의 A가 셀 2 · `가나다라X`의 X가 셀 8 · `👍A`의 A가 셀 2 · 더블폭 문자 위 커서가 두 셀 · 공백은 잉크 없음. **ADR-0101의 핵심 주장을 산술이 아니라 그려진 결과로 확인** | frontend-senior | PASS |
| REQ-011 AC-4 (배지 색) | frontend | `DesignTokenTests` — 심볼 종류 배지 4색(accent·**teal**·purple·warning) × 실제 표면 4종이 §4.5의 3:1을 넘는지. teal은 프로토타입 `--syn-type`과 같은 값으로 고정 | frontend-senior | PASS |
| REQ-004 AC-2 (그리드 산술) | frontend | `GridGeometryTests` (9) 뷰 크기→행·열 역산·셀 원점 산술 · `GlyphBatcherTests` (9) 폰트·색 배치·결정적 순서 · `GridFrameBuilderTests` (18) **startColumn 기반 배치·더블폭 2셀 전진·반전 표시·커서 폭** · `DisplayWidthTests` (8) 한글/한자/전각/이모지 2셀·결합문자 0셀 | frontend-senior | PASS |
| REQ-004 AC-5 · AC-1 · REQ-NF-005 | frontend | `EditSessionOverlayTests` (11) — 연결 중·**기동 실패(미설치 vs 버전 미달 문구 분리)**·끊김 3카드 · 재기동 시 디스크 재로드 고지 · 에디터만 흐림 · `StatusBarPresentationTests` 세션 5상태 칩 | frontend-senior | PASS |
| REQ-010 AC-4 · AC-6 (모드 보존·복원) | frontend | `AppModelTests` (15) — 전환이 `:w`를 보내지 않고 저장 피드백도 없음(AC-4) · 재시작 후 모드 복원(AC-6) | frontend-senior | PASS |
| REQ-004 AC-4 (저장 피드백) | frontend | `AppModelTests` 저장 이벤트 → `✓ 저장됨 · {파일명} ({줄 수}, {크기})` · `ByteSizeText` 바이트/KB 분기 | frontend-senior | PASS |
| REQ-005 (정의 이동 분기) | frontend | `DefinitionRoutingTests` (5) — 1건 즉시 이동 / N건 후보 / **0건 상태바 에러(무반응 금지, AC-3)** / 커서에 심볼 없음 | frontend-senior | PASS |
| REQ-006 AC-3 · AC-4 (참조 패널) | frontend | `ReferencePresentationTests` (9) — **근사 안내 배너 전 상태 상시**(0건 포함) · 정의 배지 · 파일별 그룹 · 인덱싱 중 고지 | frontend-senior | PASS |
| REQ-007 AC-3 · AC-4 (심볼 모달) | frontend | `SymbolSearchPresentationTests` (15) — ↑↓ 순환·**결과 축소 시 선택 클램프**·상위 50·0건 문구·인덱싱 중 부분 결과 고지 | frontend-senior | PASS |
| REQ-008 AC-2 · AC-4 · SC-6 | frontend | `TextSearchPresentationTests` (12) — **정규식 에러 시 이전 결과를 흐림으로 유지**(빈 결과 위장 금지) · 상한 경고 · 메타 문구 | frontend-senior | PASS |
| REQ-007·008 (강조 구간) | frontend | `MatchHighlighterTests` (13) — **UTF-16 오프셋**을 한글·이모지·서로게이트 쌍에서 정확히 분할 · 범위 밖·역전 구간 방어 | frontend-senior | PASS |
| REQ-003 AC-3 (현재 파일 강조) | frontend | `PathDisplayTests` (12) — 절대↔프로젝트 상대 정합 · **`/private` 접두사 차이 흡수**(조용한 매칭 실패 방지) · 앞쪽 축약 | frontend-senior | PASS |
| REQ-001 AC-2 · REQ-011 AC-3 (최근 프로젝트) | frontend | `RecentProjectStoreTests` (9) — 최신순·중복 없음·최대 5·경로 정규화·재시작 복원·**손상 데이터 생존** | frontend-senior | PASS |
| REQ-001 AC-2 (**메뉴에서의 전환 경로**) | frontend | `MenuBarControllerTests` (4) — `파일 ▸ 최근 프로젝트 열기` 서브메뉴를 열 때마다 다시 채움 · 고른 행의 **경로**로 열기(이름 아님 — 같은 레포 두 체크아웃 구분) · 빈 목록은 비활성 안내 한 줄 · 재개방 시 누적 없음. 이전엔 `submenu: []` 하드코딩이라 항목이 눌려도 아무것도 없었다(D-5) | frontend-senior | PASS |
| REQ-006 · 008 (파일별 그룹) | frontend | `FileGroupingTests` (4) — 첫 등장 순서 보존(엔진 정렬과 불일치 방지) | frontend-senior | PASS |
| REQ-003 AC-1 · AC-3 (파일 트리) | frontend | `FileTreePresentationTests` (26) — 지연 로드·스켈레톤·펼침/접힘·↑↓←→/Enter 전수 · 현재 파일 강조(**/private 접두 흡수**) · 더티 표시 | frontend-junior (시니어 리뷰 완료) | PASS |
| REQ-003 AC-1 (지연 로드 실측) · REQ-001 AC-2 | frontend | `FileTreeModelTests` (12) — 펼칠 때만 그 디렉토리를 읽는지 **엔진 호출 횟수로** 확인(다시 펼쳐도 재호출 0) · 한 디렉토리 읽기 실패가 트리를 지우지 않음 · 트리에서 연 파일도 점프 목록 기록 · 프로젝트 전환 시 이전 트리 소멸 | frontend-junior | PASS |
| REQ-011 AC-4 (§4.1 rgba 토큰) | frontend | `TranslucentTokenTests` (6) — `accent-dim`·`match`의 밑색과 알파가 §4.1 문구와 일치(다크 `accent-dim`의 밑색은 `accent`가 아니라 `accent-text`다) | frontend-junior | PASS |
| **REQ-002 AC-4 (스킵 건수 — 유일한 UI 표면)** · REQ-009 | frontend | `IndexDetailsPresentationTests` (13) — 스킵 건수 표시·0건에도 행 유지(누락과 구별)·사유 문구는 >0에서만 · 마지막 갱신 오늘/어제/올해/연도 · **통계 부재 시 숫자를 지어내지 않음** · 5상태 제목 · 비-최신 전 상태 낡음 고지 | frontend-junior | PASS |
| REQ-009 (칩 표시) · §4.5 색만으로 구분 금지 | frontend | `IndexChipIndicatorTests` (4, **계약의 `allKnownCases`·`Kind.allCases` 순회 — 상태가 늘면 컴파일 실패**, 걸러낸 목록 비었을 때 조용히 통과하는 것 방지) — 5상태 → dot/펄스/스피너 매핑 · **같은 앰버인 `갱신 중`·`전체 재스캔 중`이 서로 다른 표시를 갖는지** · 스피너 상태는 항상 진행 바 동반 | frontend-junior | PASS |
| **REQ-011 AC-3 (영역 표시/숨김 복원)** | frontend | `ShellVisibilityLayoutTests` (12) — 둘 다 보이면 기존 `resolve`와 동일(위임 확인) · **숨기면 눌려 있던 이웃이 선호 폭을 되찾음** · 에디터 최소 유지 · 오버레이는 숨겨도 에디터 폭 불변 · 8창×4조합 음수 폭 없음 · **어떤 조합에서도 모드 세그먼트·인덱스 칩 생존** · 숨김 상태에서도 드래그 왕복 성립. positive control로 순진한 구현(base 폭 상속)이 잡히는 것 실측 | frontend-junior | PASS |
| **REQ-005 AC-2 (정의 후보 팝오버 배치)** | frontend | `DefinitionPopoverPlacementTests` (10) — 커서 셀 → 앵커 환산 · 아래 자리 있으면 아래, 없으면 **위로 플립** · **행 0~38 × 후보 2/5/12 전수에서 팝오버가 커서 줄을 덮지 않음** · 짧은 창에서는 위치가 아니라 **높이를 양보** · 목록 높이 음수 방지 · 한 줄 카드 하한. positive control로 축소 무력화 시 커서 가림 재현 실측 | frontend-junior | PASS |
| **REQ-013 AC-1 (마크다운 → HTML)** | frontend | `MarkdownDocumentTests` (36) — **만들어 내지 않기**: 산문 꺾쇠·앰퍼샌드 · 펜스/인라인 코드 내용 이스케이프 · **링크 URL·이미지 alt 의 따옴표가 속성을 끝내지 못함**(마크다운을 통한 속성 주입) · 이미지를 `<a>` 로 오독하지 않음(앵커 예외를 타고 검사를 비켜가는 경로) · 원시 HTML 은 **일부러 통과**(ADR-0109 단일 표면). **그리기**: 제목 1~6/샵 7은 아님 · 펜스 언어 class · **닫히지 않은 펜스도 닫음**(AC-6) · 목록 3기호·번호 · 인용 · 표(thead/tbody·정렬) · 강조/굵게 우선순위 · 백슬래시 이스케이프. **회귀 3종은 실제 문서 38개를 통과시켜 발견**: 문단·목록에서 `**` 가 줄을 넘으면 **강조가 뒤집히던** 결함(닫는 표시를 여는 것으로 읽음 — 서식 누락이 아니라 문서 내용 왜곡) · 표 셀의 GFM `\|` 미지원(우리 02b 문서가 코드 스팬 안에서 사용). 이스케이프 4종은 각각 깨뜨려 **해당 테스트만** 실패함을 확인 | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-013 AC-5·AC-6 (렌더 표면 상태)** | frontend | `RenderDocumentPresentationTests` (13) — **문서를 못 그리는 4상태가 전부 카드+빠져나갈 길**(AC-6 빈 화면 금지) · 재렌더는 읽던 문서를 지우지 않음(AC-5) · 200ms 깜빡임 방지 · **디스크 폴백을 화면이 말함**(조용한 폴백 금지) · 읽기 전용 배지 전 상태 상시 · **크기 초과는 자르지 않고 거부**(부분 렌더=조용한 거짓말) | frontend-junior | **로직 PASS · UI 미배선** |
| **INV-6 (전처리 재작성 — 2겹 중 1겹)** | frontend | `RenderDocumentSanitizerTests` (31) + `…LimitTests` (9, **한계를 실행 가능한 형태로**) — **따옴표 없는 값·속성값 속 `>`·`=` 주변 공백 우회 3종 회귀**(실측으로 발견) · **`xlink:href`(SVG 옛 철자, WebKit 지원)** · **`<base>` 제거**(경로 판정을 무의미하게 만드는 문) · `meta refresh` 제거 · `iframe srcdoc` 비움 · 문서 내 조각 참조 보존 · **CSP 가 첫 참조보다 앞** · **작성자 URI 가 페치 가능한 자리에 하나도 안 남음** · `<script>` 내용째 제거(닫히지 않으면 나머지 폐기) · 허용 로컬은 **우리가 만든 `data:`** 로 · **작성자 `data:image/svg+xml` 제거**(CSP·콘텐츠룰이 못 보는 유일한 자리) · `srcset` 통째 폐기 · CSS `url()` · **CSP 백스톱 주입**(head 없는 조각 포함) · `<a href>` 는 네비게이션이라 보존 · **`data-src` 미끼에 속아 진짜 `src` 를 남기던 결함 회귀** | frontend-junior | 로직 PASS · UI 미배선 |
| **INV-6 (렌더 샌드박스 판정)** | frontend | `RenderSandboxPolicyTests` (33) — **leaf 부재 심링크 탈출 차단(D-12 회귀, 실제 심링크)** · 해석된 경로를 결과에 실어 TOCTOU 차단 · 존재하지 않는 파일 차단 · 프로토콜 상대 참조 · 루트 자신 · **`data:` 래스터 이미지 허용 / SVG·그 외 차단**(리더 판정, 이미지 자리에서만) · 원격 이미지/스타일시트/폰트 종류별 차단 · 스크립트·프레임은 **로컬이어도** 차단 · 루트 안 로컬은 허용(반대 방향 실측) · `..` 탈출·형제 폴더 접두 · **실제 심링크 루트 탈출 차단** · 탭별 루트(INV-5) · `data:`/`javascript:` 차단 · **루트 미설정 시 CWD 로 열리는 fail-open 차단** | frontend-junior | **로직 PASS · UI 미배선** |
| **INV-6 (차단 고지 §3 W-15)** | frontend | `BlockedResourcePresentationTests` (11) — **0건에도 샌드박스 칩 상시** · 건수 천 단위 · 종류별 집계 6줄 상한 · 출처 여럿이면 `{첫 곳} 외 {n}곳` · 문서 순서 유지 · 정책 문구 상시 | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-012 AC-4 · AC-6 (탭 복원)** | frontend | `TabRestorePlanTests` (12) — 첫 실행/전부 성공/일부 실패/전부 실패 · **사라진 탭을 조용히 버리지 않고 사유와 함께 남김**(AC-6) · `notFound`/`noPermission` 문구 비마스킹 · 활성 탭이 사라지면 생존 탭으로 폴백 · **활성 인덱스가 항상 복원 목록 안** · 복원+누락 합 = 저장 수 · **첫 실행과 전부 실패를 구별**(둘 다 웰컴이지만 시트 유무가 다르다) | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-012 AC-2·AC-3·AC-5 · INV-5 (탭이 상태의 단위)** | frontend | `ProjectTabSetTests` (9) — 탭마다 별도 트리·인덱스(공유하면 한 탭에서 펼친 폴더가 다른 탭에도 펼쳐진다) · 닫아도 남은 탭 상태 보존 · 재개방 시 **기존 탭 유지**(새 인스턴스로 갈아치우면 트리·인덱스가 날아간다) · 전환은 활성 id 대입 · 없는 id 무시 · 승계/마지막/배경 닫기 · 서술자 정합. AC-5 가드·id 가드 각각 제거해 Red 실측 | frontend-senior | PASS |
| **REQ-012 AC-3 · REQ-004 AC-4 (W-13 더티 탭 닫기)** | frontend | `TabCloseConfirmationTests` (8) — 깨끗한 탭은 **시트 없음** · 1건/5건/5건 초과(**`외 n건` 의 n 은 나머지**) · 저장 중 전 버튼 비활성+스피너 · 저장 실패 시 **시트 유지** · 기본 버튼=`저장 후 닫기`. 기본 버튼 뒤집기·넘침 수를 전체로·깨끗한 탭에 시트 각각 Red 실측 | frontend-senior | **프레젠테이션 PASS · 배선 불가** — 아래 계약 3건 부재 |
| **W-13 배선 차단 (계약 3건)** | backend | — | backend-senior | 🔴 **미구현.** ① `setDirtyBufferCount` 호출부 **0곳** → 더티 점·시트가 발동 불가 ② `dirtyFiles(in:)` 없음 → 목록 못 그림 ③ **`save()` = `:w`(현재 버퍼만)** → `저장 후 닫기` 가 나머지를 버린다. ③이 가장 위험 — **시트가 손실을 승인해 주는** 형태라 안 뜨는 것보다 나쁘다 |
| **REQ-012 AC-1 (탭 바 마운트)** | frontend | `AppModelTabTests` (7) — 열면 탭 생성·활성 · **실패하면 탭 없음** · 재개방 시 하나 유지(AC-5) · 닫으면 웰컴(§12 판정 3) · 서술자가 인덱스 상태 반영 · **1개여도 바 표시**(§12 판정 1) · 프로젝트 없으면 바 없음. `CompositionRootTests` — **최소 창 720×480에서 상태바 생존**(탭 바가 세 번째 고정 행). 탭 생성/닫기 정리 각각 제거해 Red 실측 | frontend-senior | **부분** — 껍데기·1탭까지. AC-2·AC-4·INV-5 는 **엔진 단일 세션이라 성립 불가**(아래) |
| **ADR-0009 조건 (다른 프로젝트 파일이 드러난다)** | frontend | `StatusBarForeignPathTests` (3) — 루트 밖은 **절대 경로**로 표시(상대로 접히면 이 프로젝트 파일처럼 보인다) · 루트 안은 상대 경로(반대 방향 회귀 방지) · 프로젝트 없으면 절대. 폴백을 파일명만으로 바꾸면 Red 실측. 백엔드가 엔진 절반(`EditorStatus.filePath` 절대 유지)을 이미 닫았고 이것이 UI 절반 | frontend-senior | PASS |
| **REQ-012 AC-1·2·3·5 · INV-5 (다중 프로젝트 배선)** | frontend | `MultiProjectTabsTests` (8) — 두 프로젝트 동시 개방 · **탭마다 다른 트리**(INV-5) · 전환해도 다른 인덱스 생존(AC-2) · 재개방 시 기존 탭 활성(AC-5, 판정은 엔진) · 닫으면 **엔진에서도** 닫힘(AC-3) · 마지막 탭→웰컴 · 실패 시 탭 없음 · **전환을 엔진에게도 알림**. 방어선 실측에서 구멍 2개 발견: 엔진 `activate` 미호출이 안 잡혔고(단언 추가), AppModel 재활성화 분기는 **효율 가드**이고 정확성은 `ProjectTabSet.open` 이 든다(그쪽 가드 제거 시 Red 확인) | frontend-senior | PASS (QA 실물 확인 대기) |
| ~~REQ-012 (엔진 미구현)~~ | frontend+backend | — | backend-senior | ~~미구현~~ **해소됨 — `ProjectWorkspaceEngine` 구현됨.** 엔진이 `openProject(at:) async throws`(반환값 없음)뿐이고 `ProjectSessionFactory` 가 없다. 두 번째 프로젝트가 첫 번째를 **대체**하므로 동시 개방·즉시 전환·격리·복원이 불가능하다. `03c` 는 채택됐으나 미구현 |
| **REQ-008 (검색 패널 입력) — D-11** | frontend | `KeyboardFocusTests` (12) — **전 표면 전수**(열리면 주인이 된다 / 닫히면 돌려준다, `allCases` 비어있지 않음 선단언) + 패널 단독. **`scripts/check-focus-symmetry.sh`** — 소스에서 `surfaceDidOpen/Close` 짝을 기계 검사(게이트 스텝, 자체 검사 4종). **단위 테스트만으론 못 잡는다**: 패널 `.onAppear` 를 지워도 코디네이터 12건이 전부 그린임을 실측 → 그래서 배선 검사를 따로 뒀다. 실제 D-11 재현 시 검사기가 FAIL 하는 것 확인 | frontend-senior | PASS (QA 실물 재확인 대기) |
| **REQ-010 AC-1 · REQ-008 (키보드 소유권)** | frontend | `KeyboardFocusTests` (9) + `EditorFocusTests` (6) — 기본 소유자=에디터 · 모달이 가져갔다 **열기 전 주인에게** 돌려줌(검색 패널에서 열었으면 패널로) · 겹쳐 열려도 복귀 지점 유지 · 패널이 사라지면 에디터로 · **다른 곳이 잡고 있어도 에디터 차례면 되찾음**(D-6 잔여) · 차례가 아니면 안 가져감. 되찾기를 옛 조건부 규칙으로 되돌리면 **`NSTextView` 가 붙든 원래 결함이 재현**되며 Red | frontend-senior | PASS (QA 라이브 대기) |
| **REQ-014 (한글 자판 명령키) — B안 1단계** | frontend | `LatinKeyTranslationTests` (9) — 노멀에서 자모→명령키 번역 · **이미 라틴이면 물리 키가 달라도 받은 글자를 신뢰**(Dvorak 등 기존 자판 무회귀) · ⌃ 코드도 번역(`<C-h>`) · 번역 불가 키는 통과 · **삽입 모드 무번역**(한글 치는 자리) · 표준 모드 무번역 · 비주얼·명령행은 번역(`:w`). 실제 ASCII 레이아웃으로 5키 실측(i·k·h·g·;). 방어선 4종 Red 실측 | frontend-senior | PASS (2단계 미착수) |
| **REQ-014 2단계 · D-13 (삽입 모드 한글 조합)** | frontend | `EditorKeyRouteTests` (8) — 삽입·표준은 입력 컨텍스트, 노멀·비주얼은 키 번역 · **조합 중 Esc·⌃[·⌃C 는 커밋 후 이탈**(데이터 손실 방지) · 표준 모드는 커밋 안 함. `EditorCompositionTests` (6) — 커밋본만 전송 · 조합 중은 미전송 · 커밋 시 마크 해제 · 빈 커밋 무시 · markedRange 추적. 방어선 4종 Red 실측 | frontend-senior | **구현 완료 · 닫힘 미주장** — QA `hexdump` 로 `U+D55C U+AE00` 6바이트 확인 필요 |
| ~~REQ-014 2단계 (구)~~ | frontend | — | frontend-senior | ~~미착수~~ `NSTextInputClient` 10메서드 + `keyDown` 분기. **조합 중 표시가 미지수** — 커밋 전 글자는 Neovim 버퍼에 없어 그리드가 못 그린다. (a)커밋 시에만 전송 / (b)marked text 오버레이 중 리더 판정 대기 |
| **REQ-014 AC-4 (시스템 설정 비침범)** | frontend | **게이트 스텝** — `grep TISSelectInputSource Sources/` **0건**. AC-4 를 기계로 말한 것: B안이 "입력 소스를 바꾼 채로 끝나지 않는다"로 성립하는 근거는 **되돌리기를 잘해서가 아니라 되돌릴 것이 없어서**다. 철거 전 2건 → 후 0건 실측. 읽기 전용 `TISCopy` 1건은 남는다(번역 기제) | frontend-senior | PASS |
| ~~REQ-014 (한글 자동 전환) — A안~~ | frontend | `InputSourceSwitchingTests` (5) — 삽입 나감→영문 · 들어감→복원 · 삽입 미교차는 무반응 · **표준 모드 무전환**(AC-5) · **에디터 밖 무전환**(AC-3). `InputSourceRestorationTests` (6) — 원복 · **비활성화 시 원복**(AC-4) · 우리가 안 바꿨으면 무동작 · 원복 1회만 · 영문 소스 없는 시스템 무동작 · **두 번 전환해도 원본은 처음 것**(가드 제거해도 그린이던 구멍, 실측으로 발견). 가드 5종 제거해 각각 Red 확인 | frontend-senior | PASS (QA 라이브 대기) |
| **D-10 (실패 종류별 문구)** | frontend | `EditorFailureChipTests` (5) — `.notInstalled`만 "Neovim 없음" · **`.unresponsive`는 "응답 없음"** · 종류별 고유 문구 불변식 · 전 종류가 "편집 불가"·danger 유지. 하나를 되돌리면 Red | frontend-senior | PASS |
| **INV-6 (렌더 리소스 루트 제한)** | frontend | ~~`RenderResourcePolicyTests`~~ **폐기 — `RenderSandboxPolicy` 로 단일화**(W-15 요소 종류 축이 필요해 그쪽이 남았다). 내 케이스 전부 그쪽 29건이 덮는 것 확인 후 삭제. D-12(leaf 부재 심링크 미해석) 수정을 **양방향 실측**(탈출 3종 차단 + 정상·루트 안 심링크 허용) (구 11) — 원격 스킴 6종 · **프로토콜 상대 `//host`**(경로처럼 보이는 원격) · `..` 탈출 · 루트 밖 절대경로 · **이름만 루트로 시작하는 형제 폴더**(문자열 접두 비교 버그) · 루트 안 복귀 `..` 허용 · 루트 자신 거부 · `data:` 통과 · **실제 심링크로 안팎 2종**. 성분비교→접두비교 / 심링크해석 제거 각각 Red 실측 | frontend-senior | PASS |
| **REQ-013 · INV-6 (샌드박스 기제 실측)** | frontend | `scripts/spike-render-sandbox.swift` — 대조군(JS 켬·규칙 없음)=요청 다수 · **JS만 끔=9건 그대로 나감** · 규칙+JS끔=0건. `data:` 는 전면차단 아래 생존(픽셀 실측, 깨진 URI와 구별 확인). ADR-0109 근거 | frontend-senior | 스파이크 (회귀 승격은 REQ-013 착수 시) |
| **REQ-012 AC-5 (이미 열린 프로젝트)** | frontend | `ProjectIdentityTests` (10) — 표기 차이(끝 슬래시·`.`·`..`) · **실제 심링크를 만들어** 같은 폴더 판정 · `/tmp`↔`/private/tmp` · **대소문자는 볼륨이 정한다**(구분 볼륨에서는 다른 프로젝트) · 볼륨 질의 트랩 없음 | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-012 AC-1 (탭 목록 표시)** | frontend | `ProjectTabBarTests` (22) — **활성 탭은 어떤 탭 수·폭·위치에서도 보이는 쪽**(시니어 리뷰 지적, 전수 불변식) · 보이는 탭은 연속 구간 · 탭 0개=바 없음 / **1개도 바 표시**(§12 판정 1) · 동명 시 상위 폴더 보조 라벨(안 겹치면 미부착) · 더티·인덱싱 글리프와 툴팁 · 폭 균등 분배와 112/220 경계 · **넘침 버튼 폭을 불필요하게 예약하지 않음** · 아무리 좁아도 탭 1개 생존 · 보이는 수+넘친 수=전체 불변식 | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-012 AC-2 · AC-3 (탭 전환·닫기)** | frontend | `ProjectTabCommandTests` (18) — `⇧⌘]`/`⇧⌘[` 양끝 순환 · `⌘1~⌘8` 위치 / **`⌘9`=마지막 탭**(Safari 관례) · `⌘W`는 닫기 **요청**(W-13 시트 선행) · 활성 탭 닫으면 오른쪽→왼쪽 승계 · 배경 탭 닫아도 화면 불변 · **마지막 탭 닫기=웰컴 복귀**(§12 판정 3) · 어떤 조합에서도 활성 탭이 실재 | frontend-junior | **로직 PASS · UI 미배선** |
| **REQ-011 AC-4 · REQ-004 AC-2 · §4.4 (시각 회귀 게이트)** | frontend | `DesignRegressionGateTests` (8) — 빈 캔버스 아님 · 사이드바가 라이트/**다크** 토큰 색 · 좁은 창이 툴바 단축키 라벨 제거 · **에디터에 한글이 실제로 그려짐**(빈 화면과 잉크량 비교) · 한글 잉크가 영문의 40% 이상 · 수식키 3덩어리(**실제 툴바 폰트로** 측정) · 덩어리 세기 교정 / `DesignRegressionSelfTests` (8) — 빈 캔버스·틀린 토큰 색·붙은 글리프를 **합성 비트맵에 심어** 검출 확인, 반대 방향(떨어진 것은 제 수대로)까지. `Sources/` 무변형 | frontend-junior | PASS |
| **REQ-011 AC-3 (창 크기·위치 복원)** | frontend | `WindowFrameFitTests` (11) — **사라진 모니터 좌표 → 주 화면 중앙** · 타이틀바가 화면 위로 넘어가면 내려옴 · 걸쳐 둔 창은 유지 · 최소 720×480 · 화면보다 큰 창 캡 · 화면 목록 빈 경우 · 전 입력에서 「어느 화면에서든 잡을 수 있음」 불변식 / `ShellPreferencesWindowFrameTests` (6) — 첫 실행 nil · 재시작 왕복 · **저장은 화면에 안 맞춤**(모니터 재연결 시 복귀) · 손상 데이터 5종 → nil · 다른 복원 값 미훼손. positive control로 화면 맞춤 제거 시 검출 실측 | frontend-junior | PASS |
| **REQ-011 AC-3 (분할 비율 드래그)** | frontend | `ShellSplitDragTests` (10) — 창 폭을 아는 클램프: 좁은 창에서 에디터 최소 보호 · 오버레이는 폭을 안 먹음 · **왕복 불변식(끌어낸 폭 == 레이아웃이 되돌려준 폭)**을 창 5종 × 제안 6종으로 · 어떤 드래그에도 에디터 최소 유지. positive control로 창 무시 클램프가 잡히는 것 실측 | frontend-junior | PASS |
| REQ-007 (깜빡임 방지) | frontend | `SpinnerDelayTests` (7) — 199ms 침묵 / 200ms 표시 경계 · 검색 없음 · **시계 역행 시 오탐 없음** | frontend-junior | PASS |
| REQ-011 AC-1 (`.app` 실행) | frontend | `scripts/bundle.sh` + `scripts/verify-bundle.sh` — 조립 후 **실제 실행**해 번들 식별자 확인. `--self-test`로 검사기 자체를 양방향 실측. gate.sh 프론트 블록 3스텝 | frontend-senior | PASS |

> **프론트 행은 이제 레포에서 실행된 결과다.** `Package.swift` 프론트 타깃 분리가 반영돼
> `swift test --filter CodeNavigatorAppKitTests`로 **22개 스위트 254 테스트 전부 통과**를 확인했다
> (실측 2026-08-29 17:52). 스테이징 미러는 제거됐다.
> 필터가 매칭 0건이면 초록불이 뜨는 함정을 알고 있으므로 **실행된 테스트 수를 함께 확인**했다.
>
> 프론트 각 규칙은 **일부러 깨뜨려 Red를 확인**했다(방어선 실측): REQ-010 AC-5 편집 명령 활성화 ·
> §2 F-9 세션 끊김 시 검색 비활성화 · §3 W-7 끊김 안내가 메시지에 밀림 · §4.3 상태바 높이 0 ·
> REQ-006 AC-3 0건에서 배너 제거 · REQ-007 AC-3 선택 클램프 제거 · SC-6 정규식 에러 시 이전 결과 삭제 ·
> spike 키 버그 2건 재주입 · text-3 원안 복원(17건 Red) · **ADR-0101이 막은 버그 재주입(컬럼을 문자 수로 계산)** ·
> 반전 표시 무시(선택 영역 안 보임). 전부 Red 확인 후 복구해 Green 재확인.

| REQ-001·003·004·011 (창 조립) | frontend | `ShellCompositionTests` (5) 어떤 상태에 어떤 영역을 꽂는가 · `CompositionRootTests` (8) **`NSHostingView`로 실제 레이아웃**(빈 상태·프로젝트 열림·창 4크기·세션 끊김·기동 실패·정의 후보·그리드 프레임) · `scripts/check-view-mounts.sh` 게이트 스텝(뷰 11종 마운트 · 플레이스홀더 0) · `verify-bundle.sh`가 **실제 객체 그래프로 루트 뷰를 레이아웃**하고 확인 | frontend-senior | PASS |

| REQ-011 AC-1·AC-2 (메뉴 막대·단축키) | frontend | `MenuBarControllerTests` (9) — 실제 `NSMenu` 빌드·설치 · **단축키 전부 ⌘ 포함**(⌃ 단독을 claim하면 Vim 키를 뺏는다) · **키 이퀴벌런트 소문자**(대문자는 Shift 이중 계산으로 매칭 실패 — spike 실측 버그) · Vim ⌃ 조합 미claim · 명령 디스패치. 게이트가 `menus=7`을 요구 | frontend-senior | PASS |
| REQ-010 AC-5 (편집 메뉴 활성) | frontend | `MenuBarControllerTests` — Vim 모드에서 편집 6명령 비활성·표준 모드에서 활성·현재 모드 체크·세션 끊겨도 검색 활성. `MenuAvailability`(12)와 실제 `validateMenuItem` 양쪽 | frontend-senior | PASS |
| REQ-010 AC-3 · AC-5 (**검증이 실제로 불리는가**) | frontend | `MenuBarControllerTests` "모든 메뉴가 자동 활성화를 켠 채 만들어진다" — `autoenablesItems=false`면 AppKit이 `validateMenuItem`을 **아무에게도 안 묻는다.** 위 두 행은 검증기를 직접 호출해 그린이었고 실제 앱에선 Vim 모드 편집 명령이 전부 활성·체크 없음이었다. 끄면 8건 Red 실측 | frontend-senior | PASS |
| REQ-010 AC-1 (**타이핑이 Neovim에 닿는가**) | frontend | `EditorFocusTests` (5) — 실제 `NSWindow` + `window.sendEvent`. 클릭 시 포커스 획득(키보드를 먼저 다른 필드에 맡긴 상태에서) · 등장 시 미점유면 획득 · **점유 중이면 안 뺏음(검색창 캐럿 보호)** · 입력 차단 중에도 획득. `makeFirstResponder` 호출부가 0곳이라 `keyDown`이 한 번도 안 불렸다(D-6). 2방향 변이로 Red 실측 | frontend-senior | PASS (QA 라이브 확인 대기) |
| REQ-011 AC-3 (분할 비율 복원) | frontend | `ShellLayoutPreferredWidthTests` (5) — 드래그 폭 반영 · 각 영역 최소 폭 우선 · **에디터 최소 폭이 드래그보다 우선** · 오버레이는 고정 폭 · `ShellSplitter` 2곳 마운트 + `ShellPreferences` 영속 | frontend-senior | PASS |

| REQ-010 AC-2 (표준 모드 편집) | frontend | **해소됨.** `MenuCommandModeSafetyTests` (3) — 편집 9종이 전부 엔진 메서드(`save`·`undo`·`redo`·`cutSelection`·`copySelection`·`paste`·`selectAll`·`jumpBack`·`jumpForward`)로 나가고 **raw 키를 하나도 보내지 않는다.** 모드 의존 명령 집합이 8→0. 저장을 raw 키로 되돌리는 변이로 red 확인 | frontend-senior | PASS |
| REQ-005 AC-4 (뒤로 가기) | frontend | `MenuCommandModeSafetyTests` — `navigateBack`이 `jumpBack()`(모드 무관, `normal!` 래핑)을 쓰고 raw `<C-o>`를 보내지 않는다. 삽입 모드에서 `<C-o>`는 다음 타자를 먹는다 | frontend-senior | PASS |

## 게이트 상태
- 풀 게이트(`_workspace/gate.sh`)는 backend-senior가 1회 실행한다. 아래 값은 그 실행 결과로만 갱신된다.
- **마지막 실행: 2026-08-29 17:5x · `GATE: PASS` (exit 0)** — `swift build` OK · `swift test`
  **484 tests / 54 suites 전량 통과**(백엔드 266 + 프론트엔드 218) · 실행 건수 하한 검사 통과 · 민감정보 스캔 236파일 클린.

> ⚠ **이 줄은 기록이지 권위가 아니다.** 문서는 구조적으로 실행 시점보다 뒤처진다(실제로 이 줄은
> 한 번 252건에서 낡은 채로 남아 QA가 잡아냈다). **리더 인증은 이 기록값이 아니라 인증 시점에
> 직접 실행한 결과로 한다.** 이 줄이 최신인지 확인하려 애쓰지 말고 `bash _workspace/gate.sh`를
> 그 자리에서 돌려라 — 그게 유일하게 신뢰할 수 있는 값이다.
- 게이트 자체 검사(`gate.sh --self-test`): 리크 픽스처 3갈래(AWS 키·토큰·camelCase 자격증명) 전부 검출 + 제거 후 클린 = 양방향 통과.
- 게이트의 빌드 검사 실측: 일부러 컴파일 에러를 심어 `FAIL: swift build` / exit 1 확인(`set -o pipefail`이 파이프 뒤 종료코드를 보존함을 실증).

## 방어선 실측 (backend-senior)
핵심 규칙 25종을 일부러 깨뜨려 테스트가 red가 되는지 확인했다. 대표 항목:
gitignore 별표/앵커링/디렉토리전용/부정/중첩 · 스캐너 심링크·제외·중첩 gitignore · 인덱스 역방향 정리·정렬 ·
추출기 constructor 제외·모듈레벨 게이트 · 세션 저장 통지·flush 발행·경로 검증·끊김 통지 ·
심볼 검색 정렬/동점 규칙/상한 · 트리 디렉토리 우선 정렬 · 참조 상한.

이 과정에서 **가짜 초록 2건**을 발견해 보강했다:
1. "부착 전 키 큐잉" 테스트가 알림 도착만 단언해, 큐잉 코드를 지워도 통과했다 → 버퍼 내용 직접 확인으로 변경.
2. 심볼 검색 순위 테스트의 입력 순서가 기대 결과의 역순이라, 정렬을 `reverse()`로 바꿔도 통과했다 → 픽스처 재배치.

또한 **변이 하네스 자체가 침묵 실패**했다(변이가 컴파일 실패하면 실패 0건 = "방어선 있음"과 구분 불가).
빌드 실패와 테스트 실패를 분리 판정하도록 고친 뒤에야 위 2건이 드러났다.

## 백엔드 미충족/범위 밖 (정직한 상태)
- **REQ-003·REQ-011은 프론트엔드 영역**이다. 백엔드는 `directoryEntries` 데이터만 제공한다.
- **REQ-010 AC-1·2·3·5·6, SC-9**: 엔진은 `setInputMode`와 Neovim 옵션·매핑까지 구현했고 상태 보존(AC-4)은
  테스트로 닫혔다. 실제 키 해석 결과(AC-2 맥 관례 동작, AC-5 문자 리터럴 입력)와 토글 UI·재시작 복원(AC-3·AC-6)은
  **프론트엔드 조립 후 라이브 검증**이 필요하다 — 백엔드 단독으로 닫았다고 주장하지 않는다.
- **SC-4(사용자 실설정)**: 이 머신에 `~/.config/nvim`이 없어 XDG 픽스처로 *메커니즘*을 검증했다.
  실제 사용자 설정으로의 확인은 리더/QA 몫이다.
- **SC-8(유휴 메모리 150MB)**: 테스트 프로세스 피크 93.7MB를 실측했으나, **앱 유휴 실측은 조립 후 리더 인증 단계**의 몫이다.
- **REQ-NF-002 앱 번들 ≤200MB · REQ-NF-003 기동 ≤2초**: 앱 조립 후에만 측정 가능하다.

## 기여 범위 메모 (backend-junior)
위 네 행은 **단위 수준** 커버리지다. 해당 REQ가 끝단까지 충족됐다는 뜻이 아니다:
- REQ-006·008의 검색기는 완료됐고 `PreviewTextBuilder`를 실제로 쓴다. 남은 것은 `CodeNavigatorEngine`(BE-18)이
  이들을 `ProjectSession` 계약에 배선하는 것과, 프론트엔드 화면(F-12·15·16)이다.
- REQ-004는 `NeovimEditorSession`(BE-16)이 코덱을 배선한 테스트가 있어야 닫힌다. REQ-010은 표준 모드가
  앱 측 번역표에서 Neovim 옵션·매핑(`NeovimStandardMode`, 시니어 소유)으로 옮겨져 그쪽 테스트가 커버한다.
