# RESUME — 디버거 2~4차 전체

**상태: 진행 중**

> 사용자 지시: "1, 2, 3, 4차 싹다 하라니까." — **묻지 말고 끝까지 간다.**
> 중간에 멈췄으면 아래 표에서 ⬜ 인 것부터 이어간다.
> 완료 판정은 리더가 `_workspace/DEBUGGER2_COMPLETE.md` 를 쓰는 시점이다.

| # | 항목 | 상태 |
|---|---|---|
| 0 | ClassPrepare 배선 (1차 미완 — 함수만 있고 호출부 0건) | ✅ |
| 1 | 객체 그래프 펼치기 (변수 안의 필드 보기) | ✅ |
| 2 | 거터 클릭으로 브레이크포인트 토글 | ✅ |
| 3 | 예외 브레이크포인트 | ✅ |
| 4 | 조건부 브레이크포인트 | ✅ |
| 5 | 식 평가 (부분집합) | ✅ |
| 6 | 필드 watchpoint | ✅ |
| 7 | 핫스왑 | ✅ |
| 8 | Watch 패널 | ✅ |
| 9 | v0.4 릴리스 | ⬜ |

## 각 항목의 JDWP 근거

- **ClassPrepare**: `EventRequest.Set` kind 8 + ClassMatch(5). 로드되면 이벤트가 오고, 그때
  브레이크포인트를 실제로 건다. 지금은 `classNotLoaded` 로 그냥 실패한다.
- **객체 그래프**: `ReferenceType.Fields`(2,4) 로 필드 목록 → `ObjectReference.GetValues`(9,2)
  로 값. 배열은 `ArrayReference.Length`(13,1) + `GetValues`(13,2).
- **거터 클릭**: nvim `sign` 열 클릭 좌표를 줄로. `nvim_input_mouse` 의 좌표계를 이미 쓴다.
- **예외**: kind 4(EXCEPTION) + modifier 8(ExceptionOnly). caught/uncaught 를 고를 수 있다.
- **조건부**: JDWP 에 식 조건이 없다. 멈춘 뒤 값을 읽어 우리가 판정하고 아니면 다시 resume.
- **식 평가**: `ObjectReference.InvokeMethod`(9,6) / `ClassType.InvokeMethod`(3,3). 부분집합만 —
  필드 읽기와 인자 없는 메서드 호출.
- **watchpoint**: kind 20(FIELD_ACCESS) / 21(FIELD_MODIFICATION) + modifier 9(FieldOnly).
- **핫스왑**: `VirtualMachine.RedefineClasses`(1,18). `CapabilitiesNew` 로 가능 여부 확인.

## 도구에서 배운 것 (반복하지 마라)

- **모달 대화상자에는 `postToPid` 가 안 닿는다.** 모달 런루프의 필드 에디터가 그 경로로는
  이벤트를 못 받는다 — 입력란이 빈 채로 남아 "조건이 안 걸린다" 고 제품을 의심할 뻔했다.
  접근성으로 값을 넣어라: `set value of text field 1 of window 1 to "..."`.
- **모달이 떠 있을 때만 창 열거가 된다.** 평소 `count of windows` 는 0 을 준다.
- **GUI 조작에 `2>/dev/null` 을 쓰지 마라.** 엉뚱한 창을 짚어 실패한 것을 못 보고 두 시간을
  제품 의심에 썼다. 판정 명령에 금지한 것과 같은 이유다.

## 규율

TDD · 조용한 실패 의심 · 판정에 `2>/dev/null` 금지 · 0건은 positive control 뒤에 · 게이트는
조용한 창에서 · 관측 도구를 먼저 의심하라(strings 는 한글을 못 뽑고, 바이트 검색도 거짓 0을
낸다 — 앱을 띄워 확인해라).

## 라이브 검증

```bash
cd <scratch>/debug-project && javac -g Probe.java
java "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:5005" Probe &
JDWP_LIVE=1 swift test --no-parallel --filter JDWPLive
```
앱이 그 JVM 에 붙어 있으면 테스트는 못 붙는다 — `server=y` 는 연결을 하나만 받는다.
