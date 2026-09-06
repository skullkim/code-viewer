# RESUME — JDWP 디버거 (증분 4)

**상태: 진행 중**

> 이 줄이 `상태: 완료` 로 바뀌면 SessionStart 훅이 더 이상 이 문서를 주입하지 않는다.
> 완료 판정은 리더가 `_workspace/DEBUGGER_COMPLETE.md` 를 쓰는 시점이다 — 이 줄만 고치고
> 인증 문서를 안 쓰면 다음 세션이 "끝났다"고 믿고 아무도 검증하지 않는다.

## 무엇을 만드는가

IntelliJ 급 Java 디버깅. JDWP(JVM 표준 프로토콜)에 Swift 로 직접 붙는다. 어댑터도
언어 서버도 번들하지 않는다 — `java-debug` 경로는 Eclipse JDT(수백 MB)를 끌고 오는데,
그러면 "작고 네이티브"라는 이 앱의 유일한 정당성이 사라진다.

## 1차 범위 (여기까지가 이번 증분)

```
연결   attach(host:port) · 핸드셰이크 · IDSizes · ClassPrepare 대기
중단   파일:줄 → 브레이크포인트 · 멈춘 줄 강조
관찰   호출 스택 · 지역변수 값
해제   resume · 브레이크포인트 제거
```

2차 이후: 스텝(over/into/out) · 예외 브레이크포인트 → 객체 그래프·필드 watchpoint·핫스왑
→ 식 평가 부분집합 → 조건부 브레이크포인트·Watch.

## 엔진은 끝났다 (2026-09-06, `eab2825`)

**1차 범위의 엔진 부분은 트리에 있고 실제 JVM 으로 검증됐다.** 스파이크는 더 볼 것 없다.

```
Sources/CodeNavigatorCore/Debugging/
  JDWPPacket.swift          프레이밍 (헤더 11바이트, 오류 코드는 헤더에)
  JDWPReader.swift          빅엔디언 읽기 · 가변 폭 ID · 범위 넘으면 던진다
  JDWPTransport.swift       전송 추상 + ID 폭 + 이벤트 타입
  JDWPSocketTransport.swift 실제 소켓 (정확히 N바이트, 부분 버퍼 금지)
  JDWPConnection.swift      핸드셰이크 · id 로 응답/이벤트 가르기
  JDWPLineTable.swift       줄 ↔ 코드 인덱스
  JDWPMethod.swift          Methods 응답 (문자열 둘)
  JDWPValue.swift           태그 붙은 값 (C·S 는 2바이트)
  JavaDebugSession.swift    attach · 브레이크포인트 · 스택 · 지역변수 · resume
```

라이브 실측 결과 (OpenJDK 21, `Probe.step:6`):
```
breakpoint request=2 · stopped thread=1 codeIndex=4 · suspendCount=1
top frame Probe.step:6
var this: LProbe; = Object@3 · var input: I = 182 · var doubled: I = 364
resumed
```

**라이브 테스트 돌리는 법** (게이트에서는 자동으로 건너뛴다):
```bash
cd <scratch>/jdwp-live && javac -g Probe.java   # -g 없으면 변수 이름이 안 나온다
java "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:5005" Probe &
cd /Users/skull/Documents/repo/code-navigator-mac
JDWP_LIVE=1 swift test --no-parallel --filter JDWPLive
```

## 남은 일 — UI

엔진은 되지만 **사용자는 아직 못 쓴다.** 화면이 없다. 붙일 것:
- 디버그 대상 지정(호스트·포트) 과 붙기/떼기
- 편집기 거터 클릭으로 브레이크포인트 · 멈춘 줄 강조
- 호출 스택 패널 · 변수 패널
- resume / 브레이크포인트 제거 버튼

2차 이후: 스텝(over/into/out) · 예외 브레이크포인트 · 객체 그래프 · 조건부 브레이크포인트.

## 스파이크가 잡은 함정 셋 — 이미 코드와 테스트에 반영됨

| 함정 | 왜 위험한가 |
|---|---|
| `suspend=y` 면 우리 클래스가 **아직 로드 전**이라 `ClassesBySignature` 가 0건 | 브레이크포인트는 `ClassPrepare` 이벤트로 클래스 로드를 기다려야 한다. 0건을 "클래스 없음"으로 읽으면 조용히 아무 데도 안 걸린다 |
| ID 크기가 프로토콜상 **가변** | `IDSizes` 를 먼저 읽고 그 값으로 파싱한다. 8 로 박으면 다른 JVM 에서 전부 어긋난다 |
| `Methods`(cmd 5)는 문자열 **2개**, `MethodsWithGeneric`(cmd 15)은 3개 | 하나 틀리면 다음 메서드의 ID 를 길이로 해석한다. 실제로 그렇게 크래시했다 |

**그리고 진단 도구가 진단 대상을 바꿨다**: 포트 확인용 `nc -z` 가 JDWP 연결을 가져가 버렸다.
JDWP `server=y` 는 연결을 **하나만** 받는다. 살아 있는지 보려고 붙으면 그게 디버거 자리다.

**구현하면서 넷째를 배웠다**: `ThreadReference.Frames` 의 length 는 `-1`("남은 전부")이어야
한다. 넉넉한 수를 주면 되겠거니 하고 64 를 넘겼더니 504 로 거절당했다 — 실제 프레임 수보다
큰 값은 상한이 아니라 오류다. 504 를 THREAD_NOT_SUSPENDED 로 잘못 읽고 한참 헤맬 뻔했는데,
`SuspendCount` 를 물어 1 이 나온 것이 그 가설을 깼다. **가설을 세웠으면 그 가설을 깨는 값을
먼저 재라.**

**다섯째**: `javac -g` 없이 컴파일된 클래스는 `VariableTable` 이 101(ABSENT_INFORMATION)로
거절한다. 흔한 일이고, 빈 목록으로 넘기면 사용자는 "이 자리에 지역 변수가 없다" 로 읽는다.

## 이어받는 절차

```bash
cd /Users/skull/Documents/repo/code-navigator-mac
git log --oneline -5                  # 어디까지 갔나
swift test --no-parallel 2>&1 | tail -3   # 실제 상태는 실행으로 확인한다
./_workspace/gate.sh                  # 게이트가 판정의 단일 소스
```

**문서보다 실행을 믿어라.** 이 파일은 쓰인 시점의 사실이고, 그 뒤로 트리가 움직였을 수 있다.

## 규율 (이 빌드에서 비싸게 배운 것)

- **TDD** — 실패 테스트 먼저. 프로토콜 계층은 특히: 스파이크에서 이미 두 번 틀렸다
- **조용한 실패를 의심하라** — `runLua` 가 Lua 오류를 삼켜 `runtimepath` 미설정을 한참 못 봤다
- **판정에 `2>/dev/null` 금지**, 0건은 positive control 뒤에 믿는다
- **게이트는 조용한 창에서** — 실행 정지 + **트리 동결**. 커밋도 막아야 한다
- 새 검사기에는 `--self-test` 를 붙이고, **자기검사와 실데이터 시운전을 둘 다** 돌린다
