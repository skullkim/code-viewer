# 0002. tree-sitter 통합 방식과 문법 확보

- 상태: 채택
- 날짜: 2026-08-29
- 결정자: backend-senior

## 맥락
심볼 추출은 이 앱의 핵심 기능(REQ-002)이고, 웹앱판은 `web-tree-sitter`(WASM) + 문법별 npm 패키지로
해결했다. Swift에는 WASM 런타임을 끌어올 이유가 없다 — tree-sitter는 C 라이브러리이므로 직접 링크할 수 있다.
문제는 **4개 언어 문법(Kotlin·Java·TypeScript·JavaScript)을 어떻게 확보하고 빌드하느냐**였고,
이것이 틀리면 설계가 통째로 바뀌므로 착수 전 spike로 실측했다(§3.6).

## 결정
**SPM 패키지 의존으로 문법을 가져오고, `swift-tree-sitter`로 파싱한다.**

```
tree-sitter/swift-tree-sitter        0.9.0+  (→ tree-sitter C 런타임 0.25.x 를 끌어옴)
tree-sitter-grammars/tree-sitter-kotlin  1.1.0+
tree-sitter/tree-sitter-java             0.23.5+
tree-sitter/tree-sitter-typescript       0.23.2+   (TypeScript + TSX 두 문법 포함)
```

- **JavaScript는 별도 문법 패키지를 쓰지 않고 TSX 문법으로 파싱한다.** `.js/.jsx/.mjs/.cjs` → TSX.
- Kotlin 문법은 `tree-sitter-grammars` 조직 판 v1.1.0 — **웹앱판이 검증한 것과 같은 문법·같은 버전**이라
  노드 타입 이름이 그대로 재사용된다.

## 고려한 대안과 실측 결과
1. **문법 4종을 각각 SPM 의존으로** (가장 자연스러운 선택) — `tree-sitter-javascript`에서 링크 실패.
   원인은 그 패키지의 매니페스트가
   `FileManager.default.fileExists(atPath: "src/scanner.c")`로 소스 포함 여부를 판단하는데,
   이 **상대 경로가 소비자(루트 패키지)의 작업 디렉토리 기준으로 평가**되어 항상 거짓이 된다는 것이다.
   결과적으로 `scanner.c`가 조용히 빠지고 `tree_sitter_javascript_external_scanner_*` 심볼이
   링크 단계에서 미정의로 남는다. 소비자가 고칠 수 없는 상류 매니페스트 결함이다.
2. **JS 문법 C 소스를 레포에 벤더링** — 결정적이고 오프라인 빌드가 되지만, 생성된 `parser.c`
   수 MB를 레포에 커밋해야 하고 갱신이 수작업이 된다. 한 언어 때문에 치르기엔 비싸다.
3. **채택: TSX 문법으로 JS 처리** — TSX 문법은 JavaScript의 상위집합(JS + 타입 + JSX)이라
   JS 파일을 정상 파싱한다. spike에서 실측했다: 클래스·메서드·클래스 필드·화살표 함수 상수·
   제너레이터·`constructor` 제외까지 웹앱판 분류 결과와 **완전히 일치**했고 파싱 에러는 0이었다.
   의존성이 하나 줄고 상류 결함도 우회된다.

## 실측 (spike, 2026-08-29)
4개 언어 현실적 소스에 웹앱판 분류 규칙을 그대로 이식해 실행한 결과 — 전부 `hasError=false`, 
분류 결과가 웹앱판과 일치:
- Kotlin: class/interface/enum/object/function/property/typeAlias 전 종류 추출.
  주 생성자 프로퍼티(`class Foo(val x: Int)`의 `x`)는 추출되지 않음 — 웹앱판과 동일한 동작.
- Java: 생성자가 클래스명과 같은 이름의 `function`으로 추출됨 — 웹앱판과 동일.
- TypeScript: `abstract class`, `declare function`(`function_signature`), 제너레이터 메서드 인식.
  블록 스코프 `const`는 모듈 레벨 게이트에서 제외됨 — 웹앱판과 동일.
- JavaScript(TSX 문법): `constructor` 제외, `render = () => …` → function, `count = 0` → property.

## 트레이드오프
- 얻는 것: 네이티브 빌드가 SPM 안에서 끝난다. WASM 런타임·수동 바이너리 없음. 문법 버전이
  매니페스트에 명시적으로 핀되어 노드 타입 이름의 재현성이 확보된다.
- 잃는 것: 문법 패키지의 상류 매니페스트 품질에 의존한다(위 1번 사례처럼). 새 언어를 추가할 때마다
  그 패키지가 SPM을 제대로 지원하는지 확인이 필요하다.
- 되돌리기: 특정 문법만 벤더링으로 전환하는 것은 국소 변경이다(매니페스트 + C 타깃 추가).

## 결과
- `.ts/.mts/.cts` → TypeScript 문법, `.tsx` → TSX 문법, `.js/.jsx/.mjs/.cjs` → TSX 문법,
  `.kt/.kts` → Kotlin 문법, `.java` → Java 문법.
- 문법 버전을 올릴 때는 노드 타입 이름이 바뀔 수 있으므로 추출기 테스트 전량 재실행이 게이트다.
