# ADR-0105: `.app` 번들 조립과 앱 타깃 분리

- 상태: 채택
- 영역: 프론트엔드 (frontend-senior)
- 날짜: 2026-08-29

## 맥락

REQ-011 AC-1은 **`.app`으로 실행**되고 표준 맥 창과 메뉴 막대를 가질 것을 요구한다.
빌드 시스템은 SPM이고(Xcode 프로젝트 파일 없음), 배포·서명은 범위 밖이다(가정 B).
그리고 TDD가 강제인데 executable 타깃에는 테스트 타깃을 붙일 수 없다.

## 결정

1. **타깃을 쪼갠다.** `CodeNavigatorAppKit`(라이브러리 — 뷰·모델·순수 로직 전부) +
   `CodeNavigatorApp`(executable — 조립 루트만). 테스트는 `CodeNavigatorAppKitTests`.
2. **번들은 스크립트로 조립한다.** `swift build --show-bin-path`의 산출물에 `Info.plist`를 씌워
   `CodeNavigator.app`을 만든다. `scripts/bundle.sh`.
3. **게이트는 존재가 아니라 실행을 확인한다** — 조립 후 앱을 띄워 **번들 식별자가 실제로 읽히는지**
   확인하는 스텝을 넣는다. `.app` 디렉토리가 생겼다는 것은 동작의 증거가 아니다.

## 고려한 대안

- **A. Xcode 프로젝트로 전환** — 번들·서명·리소스를 도구가 해 준다.
- **B. SPM executable 그대로 실행** — 조립 없이 바이너리를 실행.
- **C. SPM + 조립 스크립트 + 타깃 분리 (채택)**

## 트레이드오프

- **A**는 번들링이 공짜지만 백엔드가 이미 SPM 기반으로 4개 타깃과 tree-sitter 의존성을 세웠고,
  `swift build`/`swift test`가 게이트다. 빌드 시스템을 둘로 만들면 게이트가 둘이 된다.
- **B**는 **실측으로 탈락**했다. 맨 실행 파일은 `Bundle.main.bundleIdentifier`가 nil이고
  창이 key window가 되지 않았다. `Info.plist`를 얹어 `.app`으로 만드니 식별자가 붙고
  메뉴 막대가 정상 채택됐다. REQ-011 AC-1도 `.app`을 직접 요구한다.
- **C**의 비용은 스크립트 하나와 `Info.plist` 하나다.

- **테스트 용이성**: 타깃 분리가 **전제 조건**이다. 이게 없으면 프론트 영역에 테스트가 0이 된다.
- **단순성**: 빌드 시스템이 하나로 유지된다.
- **되돌림**: 나중에 서명·배포가 필요해지면 A로 옮길 수 있고, 그때도 `CodeNavigatorAppKit`은 그대로 쓴다.

## 채택 이유

번들링은 요구사항이고(AC-1), 타깃 분리는 TDD 게이트의 전제다. 둘 다 SPM 안에서 작은 비용으로
해결되므로 빌드 시스템을 늘릴 이유가 없다.

## 파생 결과

- Package.swift는 backend-senior 소유이므로 타깃 분리를 요청했다(내가 동시 편집하지 않는다).
- `main.swift` 톱레벨 코드를 쓰지 않는다 — spike에서 확인했듯 톱레벨 변수에는 글로벌 액터를
  붙일 수 없어 Swift 6 동시성과 충돌한다. `@main` 타입을 쓴다.
