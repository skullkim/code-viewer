# 완료 인증 — 실행 설정 자동 감지 (v0.6.0)

사용자 지시: "실행과 디버깅에 필요한 세팅이 소스를 분석해서 자동으로 등록되게 할 수 없나?"

| # | 항목 | 상태 | 근거 |
|---|---|---|---|
| 1 | 명령별 디버그 부착 전략 | ✅ | `DebugLaunchStrategyTests` 8 · 실제 Gradle 에 붙는 것을 lsof 로 확인 |
| 2 | 감지기 (순수 함수) | ✅ | `RunConfigurationDetectorTests` 22 |
| 3 | 프로젝트를 열 때 훑는다 | ✅ | `ProjectRunScannerTests` 7 · 앱에서 `backend bootRun · 감지됨` 확인 |
| 4 | 화면 — 감지 표시 · 디버그 차단 | ✅ | 스크린샷: `frontend dev` 선택 시 디버그 실행 회색 |
| 5 | 진짜 Gradle 라이브 검증 | ✅ | 앱에서 디버그 실행 → `--debug-jvm` → 5005 부착 → 재개 → `PROBE-STARTED` |
| 6 | v0.6 릴리스 | ✅ | `CodeNavigator-0.6.0.dmg` 32MB · 마운트한 배포본으로 검증 |

## 게이트

- `swift test --no-parallel` — **1790 tests / 239 suites 통과**
- `./_workspace/gate.sh` — **PASS**
- 배포본 — `verify-bundle.sh` 통과(배선 `terminal/debugger/detector` 전부 wired),
  `codesign --verify --deep --strict` 통과, `lipo -archs` = x86_64 arm64

## 진짜 저장소에 대고 잰 감지 결과

| 저장소 | 감지 | 훑기 |
|---|---|---|
| `2022-thankoo` | `backend bootRun`(Gradle·gradleDebugJvm) · `frontend start` | 681파일 0.03초 |
| `store-management` | `backend start:dev` · `frontend dev` | 104파일 0.00초 |
| `coin-trading` | `main.py` | 721파일 0.02초 |
| `code-navigator-mac` | `swift run CodeNavigator` | 2747파일 0.05초 |

## 착수 전 실측이 잡은 v0.5.0 의 결함

`JAVA_TOOL_OPTIONS` 는 모든 자식 JVM 이 물려받는다. `./gradlew` 에 걸면 **런처**가 먼저
포트를 잡고 `suspend=y` 로 멈춘다 — 앱은 뜨지도 않는다. v0.5.0 의 디버그 실행은 Gradle·
Maven 프로젝트에서 엉뚱한 JVM 에 붙고 있었다. 자동 감지를 만들지 않았다면 안 드러났을 것이다.

## 라이브 검증이 잡은 결함 둘 (테스트는 전부 초록이었다)

1. **한 줄 `plugins { id 'application' }` 을 못 읽었다.** 줄 단위 정확 일치로 짰는데 한 줄
   블록은 아주 흔하다. 앱에서 감지가 안 되는 것을 보고 알았다.
2. **훑기가 심링크 루트에서 조용히 0건이었다.** 두 가지가 겹쳐 있었다 — 심링크 자체는
   열거기가 0건을 내주고, macOS 는 `/private/var` 와 `/var` 철자를 API 마다 다르게 내준다.
   한쪽만 고치면 계속 0건이라, 둘 다 고치고 양쪽을 테스트로 못 박았다.

또 하나: **Gradle 은 `--debug-jvm` 의 포트를 못 바꾼다.** `-Dorg.gradle.debug.port=6001` 을
줘도 앱 JVM 은 `address=5005` 로 떴다(실측). 요청한 포트로 붙으러 가면 영영 못 붙는다.

## 검사기가 틀린 적 (앱을 고치기 전에 갈랐다)

- python `replace` 가 매칭에 실패해도 **조용히 아무것도 안 했다.** 고쳤다고 믿고 테스트를
  두 번 더 돌렸다. 이후 모든 치환에 `assert` 를 붙였다.
- AppleScript `entire contents` 는 이 창에서 0건을 준다(전에도 겪음). 한 단계 얕은
  `UI elements of window 1` 은 5건을 준다.
- 접근성으로 SwiftUI 팝업 메뉴 항목을 못 읽었다. 편집 화면 목록으로 우회해 확인했다.

## 알려진 한계 (별개 사안 — 이번 범위 아님)

**`~/Documents` 아래 프로젝트가 조용히 안 열린다.** macOS 파일 접근 권한(TCC) 문제로 확정:
같은 씨앗으로 `/private/tmp` 는 열리고, 터미널에서 띄우면(권한 상속) `~/Documents` 도
열린다. 사용자 저장소가 대부분 거기 있으므로 실제로 걸린다.

- 우회: 시스템 설정 → 개인정보 보호 및 보안 → **파일 및 폴더**(또는 전체 디스크 접근)에서
  CodeNavigator 를 허용.
- 남은 결함: 앱이 그 사실을 화면에 말하지 않는다. 복원 경로에 `.noPermission` 처리가
  있는데도 안내가 안 떴다 — 왜인지는 아직 안 밝혔다.
