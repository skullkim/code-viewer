# 작업 목록 — 프론트엔드 (owner: frontend-senior)

상세 스펙·완료 기준은 `03_frontend_architecture.md §4`. 아래는 상태 추적용.

> **현황 (2026-08-29 17:33 실측)**: 순수 로직 18개 스위트 **187 테스트 전부 통과**.
> **단, 이 테스트는 아직 레포의 `swift test`로 돌지 않는다.** `Package.swift`의 프론트 타깃 분리가
> 미반영이라(16:33 이후 미변경) 코드가 `_workspace/frontend-staging/`의 미러 패키지에서 돈다.
> 계약은 실제 소스를 심볼릭 링크로 물려 쓴다(복사본 드리프트 방지). SPM이 `_workspace/`를 보지
> 않으므로 레포 빌드에는 영향이 없다(`swift package describe`로 확인).
> **타깃이 생기기 전까지 "게이트 통과"로 간주하지 마라** — 리더 인증 대기 상태다.

## 시니어 직접

| # | 작업 | REQ | 상태 | 테스트 |
|---|------|-----|------|-------|
| F-01 | 디자인 토큰 | REQ-011 AC-4 | **로직 완료** | `DesignTokenTests`(6) · `ColorContrastTests`(5) |
| F-02 | ShellLayout 치수 계산 | REQ-011 AC-3 | **로직 완료** | `ShellLayoutTests`(13) |
| F-03 | KeyNotation + 단축키 판별 | REQ-010·011 | **로직 완료** | `KeyNotationTests`(12) |
| F-04 | 그리드 렌더러 | REQ-004 | **로직 완료** (계약 #1 반영됨) | `GridGeometryTests`(9) · `GlyphBatcherTests`(9) · `GridFrameBuilderTests`(18) · `DisplayWidthTests`(8) |
| F-05 | EditorGridView + 키 배선 | REQ-004·010 | 대기(타깃) — 로직은 전부 준비됨 | — |
| F-06 | AppModel + 스트림 소비 | REQ-004·009·010 | 대기(타깃) | — |
| F-07 | 메인 창 셸 | REQ-011 | 대기(타깃) | — |
| F-08 | 상태바 W-7 | REQ-004·009·010·011 | **로직 완료**, 뷰 대기 | `StatusBarPresentationTests`(15) |
| F-09 | 메뉴 막대 W-9 | REQ-010·011 | **로직 완료**, 뷰 대기 | `MenuAvailabilityTests`(12) |
| F-10 | 입력 모드 토글 | REQ-010 | 로직은 F-03·F-09에 포함, 뷰·복원 대기 | — |
| F-11 | 편집 세션 오버레이 W-8 | REQ-004 | 대기(계약 #2 — 기동 실패/끊김 구분) | — |
| F-17 | 정의 후보 팝오버 W-4 | REQ-005 | **로직 완료**, 뷰 대기 | `DefinitionRoutingTests`(5) |
| F-19 | .app 조립 + 실행 검증 | REQ-011 AC-1 | **스크립트 완료·검증됨** (`scripts/bundle.sh` · `scripts/verify-bundle.sh` + `--self-test`). 대상 앱 생기면 이름만 기본값으로 동작 | spike 번들로 4방향 실측 |

## 공통 기반 (주니어가 소비)

| 모듈 | 쓰이는 곳 | 테스트 |
|------|----------|-------|
| `MatchHighlighter` | W-3·W-5·W-6 강조 | `MatchHighlighterTests`(13) |
| `FileGrouping` | W-5·W-6 파일별 그룹 | `FileGroupingTests`(4) |
| `PathDisplay` | W-7 경로·트리 강조 | `PathDisplayTests`(12) |
| `RecentProjectStore` | W-2 최근 목록 | `RecentProjectStoreTests`(9) |
| `SymbolSearchPresentation` | W-3 | `SymbolSearchPresentationTests`(15) |
| `ReferencePresentation` | W-5 | `ReferencePresentationTests`(9) |
| `TextSearchPresentation` | W-6 | `TextSearchPresentationTests`(12) |
| `GridFrameBuilder` · `DisplayWidth` | 에디터 그리드 | `GridFrameBuilderTests`(18) · `DisplayWidthTests`(8) |

## 주니어 위임 후보

선행 조건: **타깃 분리 + F-06(AppModel)**. 기반이 서기 전에 넘기면 주니어가 기반을 추측하게 되고
그게 재작업이 된다. 스폰은 리더가 판단한다 — 나는 스폰·생존을 가정하지 않는다.

**각 화면의 판단 로직은 이미 순수 함수 + 테스트로 준비돼 있다.** 주니어는 그것을 소비해 SwiftUI
뷰만 그리면 되고, 02의 상태 정의를 다시 해석할 필요가 없다.

| # | 작업 | REQ | 소비할 모듈 | 상태 |
|---|------|-----|-----------|------|
| F-12 | 파일 트리 W-1 좌측 | REQ-003 | `PathDisplay` · `DesignTokens` | 미착수 |
| F-13 | 프로젝트 열기 W-2 | REQ-001 | `RecentProjectStore` | 미착수 |
| F-14 | 심볼 퍼지 검색 모달 W-3 | REQ-007 | `SymbolSearchPresentation` · `MatchHighlighter` | 미착수 |
| F-15 | 참조 패널 W-5 | REQ-006 | `ReferencePresentation` · `MatchHighlighter` | 미착수 |
| F-16 | 전문 검색 패널 W-6 | REQ-008 | `TextSearchPresentation` · `MatchHighlighter` | 미착수 |
| F-18 | 인덱스 상태 칩·팝오버 W-10 | REQ-009·002 AC-4 | `StatusBarPresentation`(칩) | 미착수(계약 #3 — 통계) |

## 블로커

| # | 내용 | 소유자 | 요청 시각 |
|---|------|--------|----------|
| 1 | `Package.swift` 프론트 타깃 분리 (테스트를 레포에서 못 돌림) | backend-senior / 리더 판정 요청함 | 17:00 · 17:14 · 17:17 |
| ~~2~~ | ~~`EditorTextRun.startColumn`·`cellWidth`~~ | **해결됨 17:30** | — |
| 3 | `EditorSessionState` 기동 실패 분리 (F-11 선행) | backend-senior | 17:00 |
| 4 | 인덱스 통계 조회 (F-18 — REQ-002 AC-4의 유일한 UI 표면) | backend-senior | 17:00 |
| 5 | 전문 검색 `filesSearched` (선택) — 없으면 "일치한 파일 수"로 대체 구현 완료 | backend-senior | 17:33 |

## 발견 사항 (다른 사람에게도 영향)

- **디자인 토큰 `text-3`이 WCAG 4.5:1 미달** — 라이트 3.81:1 / 다크 3.63:1 (실제로 놓이는 툴바·상태바
  배경 기준). `#6A6A73` / `#9898A1` 제안, 리더 판정 대기. 확정 시 `prototype/styles.css`도 같이
  고쳐야 QA 디자인 충실도 대조가 어긋나지 않는다(프로토타입은 PD 소유).
- **Swift Testing 함정**: `#expect(someCGFloat == 820 - 240)`은 값이 같아도 실패한다(거짓 Red).
  기대값을 `CGFloat(...)`로 감싸라. Double·Int는 정상.
- **`swift test --filter`가 아무것도 매칭 못 하면 "0 tests passed" 초록불**이 뜬다. 게이트에서 필터를
  쓸 거면 실행된 테스트 수를 함께 확인해야 한다.
