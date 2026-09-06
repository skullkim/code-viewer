# 디버거 1차 — 완료 인증

**인증 시각:** 2026-09-06 · **HEAD:** 472b6f5 이후 (아래 커밋 목록 참조)

리더가 직접 실행해 확인했다. 아래는 전부 **실측**이고, 문서에서 옮겨 적은 것이 아니다.

## 무엇이 되는가

`_workspace/RESUME_DEBUGGER.md` 의 1차 범위 네 가지가 화면에서 끝까지 돈다.

```
연결   디버그 → 디버거 연결…  → 127.0.0.1:5005  → "실행 중 — 127.0.0.1:5005"
중단   커서를 6행에 두고 브레이크포인트 토글    → "멈춤 — 127.0.0.1:5005"
관찰   호출 스택  Probe.step :6 · Probe.main :14
       변수      this Probe = Object@3 · input int = 3190 · doubled int = 6380
해제   계속 실행 → 다음 바퀴에서 다시 멈춤, input 3191 · doubled 6382
```

`doubled == input × 2` 가 두 번 다 성립했고 재개 후 값이 정확히 한 바퀴 움직였다 —
값이 우연히 맞은 것이 아니라 실제 그 프레임의 값이라는 뜻이다.

## 검증한 것과 방법

| 무엇 | 어떻게 |
|---|---|
| 프로토콜 프레이밍·ID 폭·Methods 파싱 | 단위 테스트 (JDWPWireFormatTests 12) |
| 응답/이벤트 가르기, 동시 입출력 | 단위 테스트 (JDWPConnectionTests 9 · JDWPConcurrentIOTests 3) |
| 줄 ↔ 코드 인덱스 | 단위 테스트 (JDWPLineTableTests 5) |
| 실제 JVM 접속·버전 왕복 | 라이브 (OpenJDK 21) |
| 브레이크포인트·스택·변수·재개 | 라이브 |
| **리스너가 도는 중에 건 브레이크포인트** | 라이브 — 이게 실제로 죽었던 조합이다 |
| 화면 상태 기계 | 단위 테스트 (DebugModelTests 8, 가짜 세션) |
| 화면 전체 사슬 | 실제 앱 조작 + 스크린샷 |

게이트 PASS (19 스텝, FAIL·WARNING 0건), 전체 테스트 1,621개 통과.

## 라이브 테스트 돌리는 법

게이트에서는 자동으로 건너뛴다(디버기가 없으면 실패가 아니라 SKIP).

```bash
cd <어딘가>/jdwp-live && javac -g Probe.java   # -g 없으면 변수 이름이 안 나온다
java "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:5005" Probe &
cd /Users/skull/Documents/repo/code-navigator-mac
JDWP_LIVE=1 swift test --no-parallel --filter JDWPLive
```

**앱이 그 JVM 에 붙어 있으면 테스트는 못 붙는다.** `server=y` 는 연결을 하나만 받는다.

## 1차에 없는 것 (2차 이후)

스텝(over/into/out) · 예외 브레이크포인트 · 조건부 브레이크포인트 · 객체 그래프 펼치기 ·
필드 watchpoint · 핫스왑 · 식 평가 · 편집기 거터 클릭으로 브레이크포인트 · 멈춘 줄 강조 ·
아직 로드되지 않은 클래스에 거는 `ClassPrepare` 대기(요청 API 는 있으나 화면에서 안 쓴다).
