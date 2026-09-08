# RESUME — 실행 설정 자동 감지 · 명령별 디버그 전략

**상태: 진행 중**

> 사용자 지시: "실행과 디버깅에 필요한 세팅이 소스를 분석해서 자동으로 등록되게 할 수 없나?"
>
> 완료 판정은 리더가 `_workspace/AUTODETECT_COMPLETE.md` 를 쓰는 시점이다.

## 착수 전 실측으로 드러난 결함 (v0.5.0)

`JAVA_TOOL_OPTIONS` 는 **모든 자식 JVM 이 물려받는다.** `./gradlew bootRun` 에 걸면
Gradle **런처** JVM 이 먼저 그것을 집어 포트를 잡고 `suspend=y` 로 멈춘다 — 앱은 뜨지도
않는다. 실측(2026-09-08, `~/Documents/repo/2022-thankoo/backend`):

```
$ JAVA_TOOL_OPTIONS="-agentlib:jdwp=...suspend=y,address=127.0.0.1:5099" ./gradlew --version
Picked up JAVA_TOOL_OPTIONS: -agentlib:jdwp=...
Listening for transport dt_socket at address: 5099      ← 런처가 멈췄다
$ lsof -nP -iTCP:5099
java  72972  ... 127.0.0.1:5099 (LISTEN)                ← 런처가 포트를 잡았다
```

즉 v0.5.0 의 디버그 실행은 Gradle/Maven 프로젝트에서 **엉뚱한 JVM 에 붙는다.**
자동 감지는 이 전략 선택까지 같이 정해야 의미가 있다.

| # | 항목 | 상태 |
|---|---|---|
| 1 | 명령별 디버그 부착 전략 (`DebugLaunchStrategy`) | ⬜ |
| 2 | 감지기 — 빌드 파일·main 클래스에서 설정을 만든다 (순수 함수) | ⬜ |
| 3 | 프로젝트를 열 때 훑어 감지 결과를 목록에 올린다 | ⬜ |
| 4 | 화면 — 감지된 것 표시 · 디버그 못 하는 명령은 막는다 | ⬜ |
| 5 | 진짜 Gradle 프로젝트로 라이브 검증 | ⬜ |
| 6 | v0.6 릴리스 | ⬜ |

## 설계 결정

**전략은 설정에 저장한다.** 명령 문자열을 매번 다시 분석해 추측하면, 사용자가 명령을 조금
고칠 때마다 붙는 방식이 소리 없이 바뀐다.

| 전략 | 어떻게 붙나 | 언제 |
|---|---|---|
| `javaToolOptions` | `JAVA_TOOL_OPTIONS` 환경변수 | `java` 를 직접 부르는 명령 |
| `gradleDebugJvm` | 명령에 `--debug-jvm` 을 붙인다 | `gradlew`/`gradle` |
| `mavenJvmArguments` | `-Dspring-boot.run.jvmArguments=...` | `mvnw`/`mvn` spring-boot |
| `unsupported` | 붙지 않는다 — 디버그 실행 버튼을 막는다 | Node·Python·Go 등 |

**환경변수는 자동으로 채우지 않는다.** `.env` 를 읽어 넣으면 비밀값이 앱 설정 파일로
복사된다. 게다가 대부분의 프레임워크(dotenv·Spring)가 이미 그 파일을 스스로 읽는다.
자동으로 정하는 것은 **명령·작업 폴더·디버그 전략** 셋뿐이다.

**감지된 설정은 저장하지 않는다.** 목록에 바로 보이되 사용자가 고쳐 저장할 때 비로소
설정이 된다. 그래야 "사용자가 고친 것을 다음 스캔이 덮어썼다" 가 원천적으로 없다.

## 규율

TDD · 조용한 실패 의심 · 판정에 `2>/dev/null` 금지 · 0건은 positive control 뒤에 ·
**관측 도구를 먼저 의심하라** · `open` 은 도는 인스턴스를 재사용한다(시작 시각과 바이너리
mtime 을 대조하고 판정하라).

## 이어받는 절차

```bash
cd /Users/skull/Documents/repo/code-navigator-mac
git log --oneline -5
swift test --no-parallel > /tmp/t.log 2>&1; grep -E "✘|Test run with" /tmp/t.log
./_workspace/gate.sh
```

실측용 진짜 프로젝트: `~/Documents/repo/2022-thankoo/backend` (Gradle + Spring Boot 2.6.8),
`~/Documents/repo/store-management/backend` (NestJS · package.json).
