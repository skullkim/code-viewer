# 요구사항-테스트 추적 매트릭스 — code-navigator-mac

각 개발자가 **자기 기여분만 추가**한다(행 추가·자기 행 수정). 게이트 상태는 `_workspace/gate.sh`를
실제로 돌린 사람(backend-senior)만 갱신한다.

| REQ-ID | 영역 | 커버하는 테스트 | 담당 | 테스트 상태 |
|--------|------|---------------|------|-----------|
| REQ-007 AC-1 | backend | `FuzzyMatcherTests` (10) — 부분수열 매칭·대소문자 무시·불일치·강조 구간·점수 순위 | backend-junior | PASS |
| REQ-006 AC-1 · REQ-008 AC-1 | backend | `PreviewTextBuilderTests` (8) — UTF-8→UTF-16 환산(한글)·선행 공백 보정·200 절단·서로게이트 페어 보호 | backend-junior | PASS |
| REQ-004 (ADR-0006 RPC 코덱) | backend | `MessagePackCodecTests` (23) — 전 타입 왕복·폭 경계·중첩·부분 프레임 판정·다중 프레임 소비 위치 | backend-junior | PASS |
| REQ-010 AC-2 · AC-5 | backend | `StandardInputTranslatorTests` (14) — 화살표/⌘·⌥ 조합·클립보드·undo/redo·저장·전체선택·문자 리터럴·`<` 이스케이프 | backend-junior | PASS |
| REQ-003 AC-1 · AC-2 | backend | `DirectoryTreeListerTests` (13) — 한 레벨 지연 로드·디렉토리 우선 정렬·제외/gitignore·`..` 세그먼트 거부·읽기 실패 | backend-junior | PASS |
| REQ-006 AC-1 · AC-2 · AC-4 | backend | `ReferenceSearcherTests` (11) — 단어 경계(부분 단어 불일치)·정의 플래그·정렬·상한 1000 경계 | backend-junior | PASS |
| REQ-008 AC-1~AC-4 | backend | `TextSearcherTests` (15) — 리터럴/정규식·잘못된 정규식 에러·제외 미노출·이진 파일 스킵·상한 500 경계 | backend-junior | PASS |

## 게이트 상태
- 풀 게이트(`_workspace/gate.sh`)는 backend-senior가 1회 실행한다. 아래 값은 그 실행 결과로만 갱신된다.
- 마지막 실행: (미실행)

## 기여 범위 메모 (backend-junior)
위 네 행은 **단위 수준** 커버리지다. 해당 REQ가 끝단까지 충족됐다는 뜻이 아니다:
- REQ-006·008의 검색기는 완료됐고 `PreviewTextBuilder`를 실제로 쓴다. 남은 것은 `CodeNavigatorEngine`(BE-18)이
  이들을 `ProjectSession` 계약에 배선하는 것과, 프론트엔드 화면(F-12·15·16)이다.
- REQ-004·010은 `NeovimEditorSession`(BE-16)이 코덱·번역기를 배선한 테스트가 있어야 닫힌다.
