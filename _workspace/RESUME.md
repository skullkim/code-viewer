# RESUME — code-navigator-mac 빌드 런북

## 현재 단계
- Phase 1 완료 (2026-08-29): `01_requirements.md` 승인 — REQ-001~011, INV-1~4, SC-1~9
- Phase 2·3 병렬 진행 중: product-designer(네이티브 UI 설계) + backend-senior(코어 엔진·Neovim RPC) 스폰됨

## 프로젝트 컨텍스트
- 위치: `/Users/skull/Documents/repo/code-navigator-mac` (git init, 커밋 0)
- 목적: 맥 네이티브 코드 에디터 겸 내비게이터. 인덱싱은 자체(웹앱판 엔진 이식), **편집은 Neovim 임베드**(모든 Vim 기능), Vim↔표준 모드 토글
- **웹앱판 대체**: `/Users/skull/Documents/repo/code-navigator` (312 테스트 통과, 엔진 재사용 대상 — `server/src/core/`, `docs/adr/`)

## 프리플라이트 실측 (2026-08-29, 소비 주체 방식)
- Swift 6.2.3 + SPM 빌드 정상 (`swift build` 실행 확인)
- SwiftUI 컴파일·실행 정상 (spike: ProbeView 인스턴스화 확인 — Xcode 없이도 가능했음)
- **Swift Testing 정상** — Xcode 설치 + `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 완료 후 `swift test` 통과 실측
  - ⚠ Command Line Tools만으로는 XCTest·Testing 모듈이 **없다**. Xcode 필수.
- **Neovim 0.12.5 + `--embed` RPC 왕복 실증**: msgpack `nvim_eval("1+1")` → `[1, msgid, nil, 2]` 수신
- macOS 26.2 / arm64

## 핵심 설계 결정 (요구사항 단계에서 확정)
- **INV-3 편집 단일 경로**: 앱 코드는 대상 레포 파일을 직접 쓰지 않는다. 수정은 오직 Neovim 경유(인덱서·트리·검색은 읽기 전용)
- **Vim 모드 토글**(REQ-010): 두 에디터를 병존시키지 않는다 — Neovim이 버퍼·undo·파일을 단독 소유하고 **키 입력 해석 계층만** 전환. 모드 전환 시 내용·커서·undo·더티 상태 보존
- **계약 = Swift 프로토콜/값 타입**(HTTP 아님). 단일 소스 = `03_backend_architecture.md §3`, 소유자 = backend-senior

## 2026-08-29 17:2x 진행 상황 (리더 실측)
- **백엔드**: `swift test` = **235 tests / 26 suites 통과**(리더 직접 실행). 실제 Neovim 통합 테스트 포함("설정은 UI attach 뒤 로드", "프로세스 사망 시 즉시 실패"), 성능 테스트 포함("단일 파일 증분 갱신 500ms"). 주니어 위임 7건(BE-04·05·13·17·08·09·10) 완료.
- **프론트**: 순수 로직 11스위트 **103 테스트 통과** — 단, **타깃 부재로 `/tmp/cn-fe` 미러 패키지에 고립돼 있었다**(세션 종료 시 소실 위험). 리더가 Package.swift 프론트 타깃 소유권을 프론트에 이양(17:4x) → 반영 대기 중.
- **QA**: 점진 검증 라운드1 진행 중(계약 표면 전수 대조 최우선).

## 이 빌드에서 발생한 사고·조치 (재개자 필독)
1. **tasks.md 백엔드 표 24행 소실** — 두 시니어가 한 파일에 각자 표를 쓰다 프론트가 덮어씀. git `82483c3`에서 복구 후 **소유자별 파일로 분리**: `tasks-backend.md`(BE 소유) / `tasks-frontend.md`(FE 소유) / `tasks.md`는 인덱스 전용. **작업 표를 tasks.md에 쓰지 말 것.**
2. **Package.swift 타깃 분리 블로커** — 앱이 executable 단일 타깃이라 프론트가 테스트를 붙일 수 없었다. 리더가 구조를 동결(AppKit 라이브러리 + 진입점 executable + AppKit 테스트 타깃)하고, 45분 미반영 후 **소유권을 프론트에 이양**. 백엔드는 이 파일 편집 금지(동시 편집 방지).
3. **`swift test --filter` 초록불 함정** — 패턴이 매칭 0건이면 "0 tests passed" + **종료 코드 0**(주니어가 자기 툴체인에서 재현). 게이트가 필터를 쓰면 **실행 테스트 수를 함께 확인**해야 한다.
4. **Swift Testing CGFloat 함정** — `#expect(someCGFloat == 820 - 240)`은 값이 같아도 실패(매크로가 정수 리터럴 산술을 따로 캡처). 기대값을 `CGFloat(...)`로 감싸거나 소수 리터럴로.
5. **디자인 토큰 접근성 미달** — `text-3`이 실제 놓이는 4개 표면 최악 기준 3.81/3.63으로 WCAG 4.5:1 미달. 확정값 라이트 `#6A6A73`·다크 `#9898A1`. **대비는 배경 하나가 아니라 실제 사용 표면 전부의 최악값으로 잰다**(테스트로 고정됨).

## 미해결 블로커 (2026-08-29 17:2x 기준)
- **`EditorTextRun.startColumn`·`cellWidth`** — 계약(백엔드 소유). 프론트 F-04(그리드 렌더러)·F-05가 여기서 막혀 있다. 근거: nvim `grid_line`은 더블폭 뒤 빈 셀·런렝스 반복·결합문자를 실어 **뷰가 런 텍스트에서 컬럼을 유도할 수 없다**.
- **BE-17 ⌘ 매핑 판정** + 주니어 경계 의미 4건(`total` 값·줄당 항목 수·비ASCII 단어 경계·이진 파일 스킵) — 기본값으로 구현·테스트 고정돼 있어 확답만 오면 한 줄씩 바뀐다.
- `tasks-backend.md` 상태 열이 낡음(복구본이 `82483c3` 시점) — 백엔드 시니어가 갱신 예정.

## 새 세션에서 이어받는 절차
1. 이 파일 + `01_requirements.md` 읽기
2. `BUILD_COMPLETE.md` 없으면 미완 — 상태 문서를 믿지 말고 실행으로 검증(`swift build && swift test`, gate.sh 있으면 그것)
3. 팀 죽었으면: 산출물 실재 확인 후 리더 직접 마무리 또는 단계별 재스폰

## 환경 메모
- 실행: `swift build` / `swift test` (프로젝트 루트에서). `.app` 번들 구성은 시니어 ADR 대상
- Neovim: 시스템 설치본 사용(`/opt/homebrew/bin/nvim`), 앱이 번들하지 않음. 사용자 `~/.config/nvim` 설정 그대로 적용(INV-4)
- 이 빌드에서 TaskCreate/TaskList 도구 사용 불가 — 작업 분해는 `_workspace/tasks.md` 파일 + SendMessage
