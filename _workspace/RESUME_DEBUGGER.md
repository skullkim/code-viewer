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

## 이미 실측으로 확인한 것 (다시 재지 마라)

스파이크: `/private/tmp/claude-501/.../scratchpad/jdwp-spike/` (세션 스크래치라 사라질 수 있음)

```
핸드셰이크            ✅  "JDWP-Handshake" 14바이트 교환
IDSizes               ✅  이 JVM 은 referenceTypeID=8 methodID=8
ClassesBySignature    ✅  "LProbe;" → 1건
ReferenceType.Methods ✅  메서드 id 조회
Method.LineTable      ✅  4줄 · 소스 8행 → codeIndex 0
CapabilitiesNew       ✅  watchpoint·핫스왑·강제반환·인스턴스조회 허용
                      ❌  drop frame · 클래스 언로드 추적 (이 JVM 이 거절)
```

## 스파이크가 잡은 함정 셋 — 설계에 반영할 것

| 함정 | 왜 위험한가 |
|---|---|
| `suspend=y` 면 우리 클래스가 **아직 로드 전**이라 `ClassesBySignature` 가 0건 | 브레이크포인트는 `ClassPrepare` 이벤트로 클래스 로드를 기다려야 한다. 0건을 "클래스 없음"으로 읽으면 조용히 아무 데도 안 걸린다 |
| ID 크기가 프로토콜상 **가변** | `IDSizes` 를 먼저 읽고 그 값으로 파싱한다. 8 로 박으면 다른 JVM 에서 전부 어긋난다 |
| `Methods`(cmd 5)는 문자열 **2개**, `MethodsWithGeneric`(cmd 15)은 3개 | 하나 틀리면 다음 메서드의 ID 를 길이로 해석한다. 실제로 그렇게 크래시했다 |

**그리고 진단 도구가 진단 대상을 바꿨다**: 포트 확인용 `nc -z` 가 JDWP 연결을 가져가 버렸다.
JDWP `server=y` 는 연결을 **하나만** 받는다. 살아 있는지 보려고 붙으면 그게 디버거 자리다.

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
