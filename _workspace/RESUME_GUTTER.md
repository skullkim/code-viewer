# RESUME — 시작 교착 수정 · Git 변경 표시

**상태: 완료**

> 사용자 지시: "응 그거 고쳐. 그리고 intellJ 보면 git에 unstage된 변경 부분은 열려 있는
> 파일의 라인 수 표시 왼쪽에 노란 줄로 변경된 라인 표시되거든. 그 기능도 넣어봐"
>
> 완료 판정은 리더가 `_workspace/GUTTER_COMPLETE.md` 를 쓰는 시점이다.

| # | 항목 | 상태 |
|---|---|---|
| 1 | 시작 교착 수정 — FSEvents 를 메인 스레드에서 만들지 않는다 | ✅ |
| 2 | Git 변경 계산 (순수 파서 + git 실행) | ✅ |
| 3 | 거터에 변경 표시 그리기 | ✅ |
| 4 | 편집·저장에 따라 갱신 | ✅ |
| 5 | 라이브 검증 (진짜 저장소) | ✅ |
| 6 | 검색창에서 ⌘A·⌘C·⌘V 가 먹게 | ✅ |
| 7 | 검색 결과에 정의가 안 나온다 | ✅ |
| 8 | v0.7 릴리스 | ✅ |

## 6·7번 (작업 중 추가된 사용자 지시)

> "검색에서 입력한 거 전체 선택 안되고, 복사 붙여넣기도 안돼, 그리고 검색 결과에 정의가 없어"

6번 가설: 메뉴가 ⌘ 조합을 전부 claim 하는데(REQ-011 AC-2), Vim 모드에서는 표준 편집 명령을
비활성으로 둔다. 그 판단이 **편집기 모드만** 보고 이뤄져서, 키보드를 텍스트 필드가 들고
있을 때도 ⌘A·⌘C·⌘V 가 꺼진다. 확인하고 고칠 것.

7번: 검색 결과가 정의를 안 보여 준다. 무엇이 빠졌는지 실측할 것.

## 1번의 진짜 원인 (실측)

앞선 세션에서 "`~/Documents` 프로젝트가 권한 때문에 안 열린다" 고 적었는데 **틀렸다.**
`/usr/bin/sample` 로 멈춘 프로세스를 뜬 결과:

```
DispatchQueue_1: com.apple.main-thread
  AppModel.restoreTabs → ProjectWorkspaceEngine.openProject
    → ProjectIndexer.openProject → FileSystemWatcher.start()   FileSystemWatcher.swift:79
      → FSEventStreamCreate → _FSEventStreamCreate
        → watch_all_parents → open → __open      ← 커널에서 블록 (2270/2270 샘플)
```

`kFSEventStreamCreateFlagWatchRoot` 를 주면 FSEvents 가 `watch_all_parents` 로 **모든 상위
폴더를 `open()`** 한다. `~/Documents` 를 여는 순간 TCC 동의 관문에 걸리는데, 그 대화상자는
메인 런루프가 돌아야 뜬다. 우리가 메인 스레드를 막고 있으니 영원히 안 뜬다 — **교착**이다.

권한이 관여하긴 하지만 원인은 우리 코드다: **I/O 를 메인 스레드에서 한다.** `/private/tmp`
는 TCC 대상이 아니라 통과했고, 터미널에서 띄우면 셸의 권한을 물려받아 통과했다. 그래서
"권한 문제" 로 보였다.

## 2·3번 설계 (예정)

- 변경 계산은 `git diff -U0` 출력 파싱(순수 함수) + 실행부 분리.
- HEAD 대비 추가/수정/삭제를 줄 범위로. 추적 안 되는 파일은 전부 추가.
- 거터는 줄 번호 **왼쪽**에 세로 막대. 사용자 표현대로 수정은 노란색.

## 규율

TDD · 조용한 실패 의심 · 판정에 `2>/dev/null` 금지 · 0건은 positive control 뒤에 ·
**관측 도구를 먼저 의심하라**(이번에도 `sample` 이 conda 것이었고, python `replace` 는
매칭 실패를 조용히 넘겼다 — 모든 치환에 assert 를 붙인다) · `open` 은 도는 인스턴스를
재사용한다(시작 시각과 바이너리 mtime 대조).

## 이어받는 절차

```bash
cd /Users/skull/Documents/repo/code-navigator-mac
git log --oneline -5
swift test --no-parallel > /tmp/t.log 2>&1; grep -E "✘|Test run with" /tmp/t.log
./_workspace/gate.sh
```
