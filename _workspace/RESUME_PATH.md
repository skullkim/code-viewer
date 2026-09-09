# RESUME — 실행 PATH · 저장 전 변경 표시

**상태: 진행 중**

> 사용자 지시: "command not found: gradle. 실행이 안되는데 뭐가 된다는거야!!! 그리고
> 변경된 코드 왼쪽에 노란줄 안나오자낭"
>
> 완료 판정은 리더가 `_workspace/PATH_COMPLETE.md` 를 쓰는 시점이다.

| # | 항목 | 상태 |
|---|---|---|
| 1 | 로그인 셸 PATH 를 받아 실행에 쓴다 | ⬜ |
| 2 | 저장 전 편집도 변경 막대에 반영 | ⬜ |
| 3 | 라이브 검증 (진짜 프로젝트) | ⬜ |
| 4 | v0.8 릴리스 | ⬜ |

## 1번 원인 (실측)

```
$ launchctl getenv PATH        → (비어 있음 = 기본값)
$ PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v npm   → 없음
$ PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v node  → 없음
```

Finder(`open`)로 띄운 GUI 앱은 로그인 셸의 PATH 를 물려받지 않는다. 우리는 터미널에
`ProcessInfo.processInfo.environment` 를 그대로 넘기므로, homebrew 에 깐 도구가 전부
"command not found" 가 된다. 터미널에서 앱을 띄우면 셸의 PATH 를 물려받아 되는데,
그래서 개발 중에는 안 드러났다.

## 2번 원인 (실측)

사용자 저장소 3곳 모두 `git status --porcelain` 이 0건 — **커밋 기준으로 깨끗하다.**
앱에서 고친 내용은 **저장하기 전에는 디스크에 없어서** `git diff` 가 못 본다. 우리는
디스크만 보고, 갱신도 저장 시점에만 한다.

IntelliJ 는 타이핑하는 즉시 막대를 그린다 — 메모리의 문서를 저장소 내용과 견주기 때문이다.
같은 것을 하려면 버퍼 내용을 `HEAD` 의 내용과 견줘야 한다.

## 규율

TDD · 조용한 실패 의심 · 판정에 `2>/dev/null` 금지 · 0건은 positive control 뒤에 ·
**관측 도구를 먼저 의심하라** · `open` 은 도는 인스턴스를 재사용한다.
