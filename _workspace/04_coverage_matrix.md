# 요구사항-테스트 추적 매트릭스 — code-navigator-mac

각 개발자가 **자기 기여분만 추가**한다(행 추가·자기 행 수정). 게이트 상태는 `_workspace/gate.sh`를
실제로 돌린 사람(backend-senior)만 갱신한다.

| REQ-ID | 영역 | 커버하는 테스트 | 담당 | 테스트 상태 |
|--------|------|---------------|------|-----------|
| REQ-001 AC-1 · AC-4 | backend | `ProjectIndexerTests` — 열기 시 전체 인덱싱·제외/gitignore 반영 · `ProjectScannerTests` (12) | backend-senior | PASS |
| REQ-001 AC-2 | backend | `ProjectSwitchingTests` (3) — 인덱스·검색·트리 교체 · **편집기도 새 루트를 따라감** · 실패 시 이전 프로젝트 유지 | backend-senior | PASS |
| REQ-001 AC-3 | backend | `ProjectIndexerTests` "존재하지 않는 경로는 에러이고 이전 프로젝트가 유지된다" · `ProjectScannerTests` 누락/파일루트 에러 | backend-senior | PASS |
| REQ-002 AC-1 · AC-2 | backend | `SymbolExtractorTests` (Kotlin 5 / Java 2 / TS·JS 5) — 7종 심볼 전량, 4언어 | backend-senior | PASS |
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

| REQ-011 AC-3 (창 크기 적응) | frontend | `ShellLayoutTests` (13) — 02 §4.4 창 폭 표 전수 · **좁은 창에서 상태바 26pt 생존**(PD 프로토타입 결함 재발 방지) · 에디터 최소 420 우선 | frontend-senior | PASS* |
| REQ-011 AC-4 (다크/라이트) | frontend | `DesignTokenTests` (6) — 19토큰 2테마 · **텍스트 8토큰 × 실제 사용 배경 6종 대비 4.5:1 검사** · `ColorContrastTests` (5) WCAG 공식 | frontend-senior | PASS* |
| REQ-011 AC-2 (단축키 비충돌) | frontend | `KeyNotationTests` (12) — ⌘ 조합만 앱이 claim · ⌃O·⌃R·⌃V·⌃W·`:`·Esc·화살표 전부 Neovim 도달. spike가 `.app`에서 실제 이벤트 디스패치로 실증 | frontend-senior | PASS* |
| REQ-010 AC-3 (모드 상시 표시) | frontend | `StatusBarPresentationTests` (15) — Vim 4모드 칩·표준 칩·끊김 시 편집 불가 · **모든 창 폭에서 모드 세그먼트·인덱스 칩 생존** | frontend-senior | PASS* |
| REQ-010 AC-5 (모드별 편집 메뉴) | frontend | `MenuAvailabilityTests` (12) — Vim에서 ⌘Z·⌘C·⌘V·⌘A 비활성, ⌘S만 공통 활성 · 세션 끊겨도 검색은 동작 · 24명령 전수 | frontend-senior | PASS* |
| REQ-009 (인덱스 상태 UI) | frontend | `StatusBarPresentationTests` — 인덱스 5상태 칩 §6과 1:1 · 비-최신 상태 툴팁("직전 인덱스로 응답 중") | frontend-senior | PASS* |
| REQ-004 AC-2 (그리드 렌더) | frontend | `GridGeometryTests` (9) 뷰 크기→행·열 역산·셀 원점 산술 · `GlyphBatcherTests` (9) 폰트·색 배치·결정적 순서 · `GridFrameBuilderTests` (18) **startColumn 기반 배치·더블폭 2셀 전진·반전 표시·커서 폭** · `DisplayWidthTests` (8) 한글/한자/전각/이모지 2셀·결합문자 0셀 | frontend-senior | PASS* |
| REQ-004 AC-5 · AC-1 · REQ-NF-005 | frontend | `EditSessionOverlayTests` (11) — 연결 중·**기동 실패(미설치 vs 버전 미달 문구 분리)**·끊김 3카드 · 재기동 시 디스크 재로드 고지 · 에디터만 흐림 · `StatusBarPresentationTests` 세션 5상태 칩 | frontend-senior | PASS* |
| REQ-010 AC-4 · AC-6 (모드 보존·복원) | frontend | `AppModelTests` (15) — 전환이 `:w`를 보내지 않고 저장 피드백도 없음(AC-4) · 재시작 후 모드 복원(AC-6) | frontend-senior | PASS* |
| REQ-004 AC-4 (저장 피드백) | frontend | `AppModelTests` 저장 이벤트 → `✓ 저장됨 · {파일명} ({줄 수}, {크기})` · `ByteSizeText` 바이트/KB 분기 | frontend-senior | PASS* |
| REQ-005 (정의 이동 분기) | frontend | `DefinitionRoutingTests` (5) — 1건 즉시 이동 / N건 후보 / **0건 상태바 에러(무반응 금지, AC-3)** / 커서에 심볼 없음 | frontend-senior | PASS* |
| REQ-006 AC-3 · AC-4 (참조 패널) | frontend | `ReferencePresentationTests` (9) — **근사 안내 배너 전 상태 상시**(0건 포함) · 정의 배지 · 파일별 그룹 · 인덱싱 중 고지 | frontend-senior | PASS* |
| REQ-007 AC-3 · AC-4 (심볼 모달) | frontend | `SymbolSearchPresentationTests` (15) — ↑↓ 순환·**결과 축소 시 선택 클램프**·상위 50·0건 문구·인덱싱 중 부분 결과 고지 | frontend-senior | PASS* |
| REQ-008 AC-2 · AC-4 · SC-6 | frontend | `TextSearchPresentationTests` (12) — **정규식 에러 시 이전 결과를 흐림으로 유지**(빈 결과 위장 금지) · 상한 경고 · 메타 문구 | frontend-senior | PASS* |
| REQ-007·008 (강조 구간) | frontend | `MatchHighlighterTests` (13) — **UTF-16 오프셋**을 한글·이모지·서로게이트 쌍에서 정확히 분할 · 범위 밖·역전 구간 방어 | frontend-senior | PASS* |
| REQ-003 AC-3 (현재 파일 강조) | frontend | `PathDisplayTests` (12) — 절대↔프로젝트 상대 정합 · **`/private` 접두사 차이 흡수**(조용한 매칭 실패 방지) · 앞쪽 축약 | frontend-senior | PASS* |
| REQ-001 AC-2 · REQ-011 AC-3 (최근 프로젝트) | frontend | `RecentProjectStoreTests` (9) — 최신순·중복 없음·최대 5·경로 정규화·재시작 복원·**손상 데이터 생존** | frontend-senior | PASS* |
| REQ-006 · 008 (파일별 그룹) | frontend | `FileGroupingTests` (4) — 첫 등장 순서 보존(엔진 정렬과 불일치 방지) | frontend-senior | PASS* |

> **\* 프론트 행의 PASS는 아직 레포의 `swift test` 결과가 아니다.** `Package.swift` 프론트 타깃 분리
> 미반영으로 `_workspace/frontend-staging/`의 미러 패키지에서 실행한 결과다(계약은 실제 소스를
> 심볼릭 링크로 사용). **타깃 반영 후 레포에서 재실행하기 전까지 리더 인증 대상이 아니다.**
> 실측 시각 2026-08-29 17:39 — 20개 스위트 **215 테스트** 전부 통과.
>
> 프론트 각 규칙은 **일부러 깨뜨려 Red를 확인**했다(방어선 실측): REQ-010 AC-5 편집 명령 활성화 ·
> §2 F-9 세션 끊김 시 검색 비활성화 · §3 W-7 끊김 안내가 메시지에 밀림 · §4.3 상태바 높이 0 ·
> REQ-006 AC-3 0건에서 배너 제거 · REQ-007 AC-3 선택 클램프 제거 · SC-6 정규식 에러 시 이전 결과 삭제 ·
> spike 키 버그 2건 재주입 · text-3 원안 복원(17건 Red) · **ADR-0101이 막은 버그 재주입(컬럼을 문자 수로 계산)** ·
> 반전 표시 무시(선택 영역 안 보임). 전부 Red 확인 후 복구해 Green 재확인.

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
