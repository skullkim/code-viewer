# 작업 목록 — code-navigator-mac

> TaskCreate 도구가 없는 빌드이므로 이 파일이 작업 목록이다.
> **소유권 규칙**: owner 아닌 사람은 그 파일을 편집하지 않는다. 흡수가 필요하면 리더가 소유권을 재배정한 뒤 진행한다.

## 프론트엔드 (owner: frontend-senior)

상세 스펙·완료 기준은 `03_frontend_architecture.md §4`. 아래는 상태 추적용.

| # | 작업 | REQ | 담당 | 상태 |
|---|------|-----|------|------|
| F-01 | 디자인 토큰 | REQ-011 AC-4 | frontend-senior | 진행 |
| F-02 | ShellLayout 치수 계산 | REQ-011 AC-3 | frontend-senior | 진행 |
| F-03 | KeyNotation + 단축키 판별 | REQ-010·011 | frontend-senior | 진행 |
| F-04 | 그리드 렌더러 | REQ-004 | frontend-senior | 대기(계약 #1) |
| F-05 | EditorGridView + 키 배선 | REQ-004·010 | frontend-senior | 대기(계약 #1) |
| F-06 | AppModel + 스트림 소비 | REQ-004·009·010 | frontend-senior | 대기(타깃 분리) |
| F-07 | 메인 창 셸 | REQ-011 | frontend-senior | 대기 |
| F-08 | 상태바 W-7 | REQ-004·009·010·011 | frontend-senior | 대기 |
| F-09 | 메뉴 막대 W-9 | REQ-010·011 | frontend-senior | 대기 |
| F-10 | 입력 모드 토글 | REQ-010 | frontend-senior | 대기 |
| F-11 | 편집 세션 오버레이 W-8 | REQ-004 | frontend-senior | 대기(계약 #2) |
| F-17 | 정의 후보 팝오버 W-4 | REQ-005 | frontend-senior | 대기 |
| F-19 | .app 조립 + 실행 검증 | REQ-011 AC-1 | frontend-senior | 대기 |

### 주니어 위임 후보 (선행 조건: F-01·F-02·F-06 완료)
기반이 서기 전에 넘기면 주니어가 기반을 추측하게 되고 그게 재작업이 된다.
스폰은 리더가 판단한다 — 나는 스폰·생존을 가정하지 않는다.

| # | 작업 | REQ | 담당 | 상태 |
|---|------|-----|------|------|
| F-12 | 파일 트리 W-1 좌측 | REQ-003 | frontend-junior | 미착수 |
| F-13 | 프로젝트 열기 W-2 | REQ-001 | frontend-junior | 미착수 |
| F-14 | 심볼 퍼지 검색 모달 W-3 | REQ-007 | frontend-junior | 미착수 |
| F-15 | 참조 패널 W-5 | REQ-006 | frontend-junior | 미착수 |
| F-16 | 전문 검색 패널 W-6 | REQ-008 | frontend-junior | 미착수 |
| F-18 | 인덱스 상태 칩·팝오버 W-10 | REQ-009·002 AC-4 | frontend-junior | 미착수 |
