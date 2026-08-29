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

## 새 세션에서 이어받는 절차
1. 이 파일 + `01_requirements.md` 읽기
2. `BUILD_COMPLETE.md` 없으면 미완 — 상태 문서를 믿지 말고 실행으로 검증(`swift build && swift test`, gate.sh 있으면 그것)
3. 팀 죽었으면: 산출물 실재 확인 후 리더 직접 마무리 또는 단계별 재스폰

## 환경 메모
- 실행: `swift build` / `swift test` (프로젝트 루트에서). `.app` 번들 구성은 시니어 ADR 대상
- Neovim: 시스템 설치본 사용(`/opt/homebrew/bin/nvim`), 앱이 번들하지 않음. 사용자 `~/.config/nvim` 설정 그대로 적용(INV-4)
- 이 빌드에서 TaskCreate/TaskList 도구 사용 불가 — 작업 분해는 `_workspace/tasks.md` 파일 + SendMessage
