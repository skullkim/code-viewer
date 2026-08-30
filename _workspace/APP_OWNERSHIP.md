# 실행 중인 앱을 누가 모는가

오늘 이것으로 **세 번** 부딪혔다. 세 번 다 형태가 달랐고, 세 번째가 가장 조용했다.

| # | 무슨 일이 있었나 | 왜 안 보였나 |
|---|---|---|
| 1 | 리더의 `pkill -f "CodeNavigator"` 가 **`CodeNavigatorPackageTests` 까지** 죽였다 | 팀원들에게는 몇 시간 동안 "유령 게이트 실패"로 보였다 |
| 2 | 리더의 `pkill -f "nvim --embed"` 가 프론트 시니어의 **라이브 세션**을 죽였다 | 세션이 그냥 끊긴 것처럼 보인다 |
| 3 | 프론트가 조작한 인스턴스와 **캡처한 인스턴스가 달랐다**(21:10:48 에 PID 33697 이 새로 뜸) | **아무 에러도 안 난다.** 키 입력이 남의 창으로 가고 스크린샷은 멀쩡해 보인다 |

3번이 위험한 이유: **틀린 측정이 성공한 측정처럼 보인다.** 1·2번은 무언가 죽어서 티가 났지만,
3번은 조용히 **다른 앱을 재고 그 결과를 보고**하게 만든다. 남의 세션에 키를 흘리기도 한다.

---

## 규칙 1 — 앱을 몰기 전에 잡는다 (조율)

```bash
LOCK=_workspace/APP_LOCK
cat "$LOCK" 2>/dev/null                 # 비어 있지 않으면 그 사람에게 물어본다
printf '%s · %s · %s\n' "$(whoami)-<역할>" "$(date '+%H:%M:%S')" "<무엇을 하는지>" > "$LOCK"
# … 작업 …
rm -f "$LOCK"                           # 끝나면 반드시 놓는다
```

**잠금이 20분 넘게 묵어 있으면 죽은 것으로 보고 가져가되, 가져간다고 알려라.**
조율은 예의이지 보증이 아니다 — 그래서 규칙 2가 있다.

## 규칙 2 — 내가 띄운 PID 만 조작한다 (정확성)

**이게 진짜 방어선이다.** 잠금은 잊을 수 있지만 이건 기계적으로 확인된다.

```bash
open .build/CodeNavigator.app
MY_PID=$(pgrep -n -f 'CodeNavigator.app/Contents/MacOS/CodeNavigator')   # -n = 가장 최근
```

그 뒤 **모든** 조작·캡처에서:
- 창 ID 를 **`MY_PID` 로 필터**해서 얻는다. 앱 이름으로 찾지 마라 — 이름은 인스턴스를 구분 못 한다
- 캡처 직전에 **그 창이 아직 `MY_PID` 의 것인지 다시 확인**한다(측정 도중 새 인스턴스가 뜰 수 있다 — 3번이 정확히 그랬다)
- 조작 전후로 `MY_PID` 가 **살아 있는지** 확인한다. 죽었으면 그 시행은 버린다

## 규칙 3 — 종료는 PID 로, 확인될 때까지 (안전)

```bash
osascript -e 'quit app "CodeNavigator"' ; sleep 1
kill    "$MY_PID" 2>/dev/null ; sleep 1
kill -9 "$MY_PID" 2>/dev/null
pgrep -f 'CodeNavigator.app/Contents/MacOS' | wc -l    # 0 을 눈으로 확인
```

**❌ 패턴으로 죽이지 마라.** `pkill -f "CodeNavigator"` 는 `CodeNavigatorPackageTests` 를 잡는다.
**❌ `pkill -f "nvim --embed"` 금지.** 남의 라이브 세션을 죽인다. 내 앱을 죽이면 그 자식은 따라 죽는다.

**⚠ `quit` 은 실패할 수 있다.** 기동에 실패한 인스턴스는 `quit` 이 안 먹는 것이 실측됐다
(pid 75939 유지). **초기화는 성공을 확인할 때까지 escalate 하고, 그 확인 자체를 시행 데이터로
기록한다** — 확인 없는 초기화는 초기화가 아니다.

## 규칙 4 — 합성 입력은 창 ID 로만

**전역 좌표로 클릭하지 마라.** 한 번은 합성 클릭이 사용자의 터미널에 떨어져 그 세션에
글자가 들어갔다. 좌표는 창이 어디 있는지에 의존하고, 창은 움직인다.

## 규칙 5 — 번들이 최신인지 먼저 확인한다

라이브 측정은 **`.app` 을 통해서만** 코드에 닿는다. 워킹 트리가 최신인 것과 번들이 최신인 것은
다르다 — QA 의 8/8 이 **수정 10분 전 번들**에서 났다.

```bash
BUNDLE=.build/CodeNavigator.app/Contents/MacOS/CodeNavigator
find Sources -name '*.swift' -newer "$BUNDLE"     # 비어야 한다. 아니면 ./scripts/bundle.sh
nm "$BUNDLE" | grep -c '<찾는심볼>'                # 양성 대조와 함께
```

**`strings` 로 Swift 심볼을 찾지 마라** — 맹글돼 있어 못 찾고 **거짓 음성**을 준다.
