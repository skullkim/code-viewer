import Testing
import AppKit
@testable import CodeNavigatorAppKit

/// **모든 메뉴 행은 무언가를 한다** (D-20).
///
/// 기존 메뉴 테스트 21건은 전부 `MenuCommand` 에서 출발해 "이 명령이 메뉴에 있나"를 물었다.
/// 그래서 **command 가 없는 행은 테스트가 훑는 세계 밖**이었고, 종료·가리기·최소화 등 9행이
/// 이름만 가진 채 영구 비활성으로 남았다 — `autoenablesItems = true` 에서 action 이 nil 인
/// 행은 절대 활성화되지 않는다.
///
/// 빠져 있던 건 **역방향**이다: 명령에서 메뉴로가 아니라, **메뉴의 모든 행에서 출발해**
/// 각자가 무엇을 하는지 묻는다.
@MainActor
@Suite("메뉴 불변식 — 모든 행은 무언가를 한다 (D-20)")
struct MenuRowInvariantTests {

    /// ⚠ 서술자만 검사하면 **부족하다.** 서술자에 `systemAction` 을 채운 시점에 이 파일의
    /// 서술자 테스트는 전부 초록이었는데, 컨트롤러가 여전히 `command` 만 읽고 있어서
    /// **메뉴는 그대로 죽어 있었다.** 실제로 만들어진 `NSMenuItem` 에 물어야 한다 —
    /// 오늘 반복해서 만난 "존재 ≠ 연결"의 메뉴판이다.
    private func builtItems() -> [NSMenuItem] {
        let controller = MenuBarController(
            availability: { MenuAvailability(inputMode: .standard, sessionState: .connected, hasOpenProject: true) },
            perform: { _ in }
        )
        return AppMenuBuilder.menus().flatMap { descriptor -> [NSMenuItem] in
            flatten(controller.menu(from: descriptor))
        }
    }

    private func flatten(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            guard !item.isSeparatorItem else { return [] }
            return [item] + (item.submenu.map(flatten) ?? [])
        }
    }

    @Test("만들어진 메뉴 행에 실제로 동작이 붙어 있다")
    func everyBuiltItemHasAnAction() {
        // `autoenablesItems = true` 에서 **action 이 nil 인 행은 영구 비활성**이다. 화면에는
        // 이름이 보이고 눌리지 않으므로, 사용자는 "지금은 못 쓰는 상태"로 읽는다 —
        // 영원히 그렇다는 것은 알 방법이 없다.
        let dead = builtItems().filter { $0.action == nil && $0.submenu == nil }

        #expect(dead.isEmpty, "동작 없는 행: \(dead.map(\.title))")
    }

    @Test("종료 행이 terminate: 를 부른다")
    func quitCallsTerminate() {
        let quit = builtItems().first { $0.title.contains("종료") }

        #expect(quit?.action == #selector(NSApplication.terminate(_:)))
        // 대상을 비워 두는 것이 요점이다 — 응답자 사슬이 `NSApplication` 까지 올려 준다.
        #expect(quit?.target == nil, "대상을 박으면 그 객체가 사라질 때 행이 죽는다")
    }

    /// 구분선을 제외한 모든 행을 재귀로 편다.
    private func allRows(_ items: [MenuItemDescriptor]) -> [MenuItemDescriptor] {
        items.flatMap { item -> [MenuItemDescriptor] in
            guard !item.isSeparator else { return [] }
            return [item] + allRows(item.submenu)
        }
    }

    private var rows: [MenuItemDescriptor] {
        allRows(AppMenuBuilder.menus().flatMap(\.items))
    }

    @Test("행동이 없는 행이 하나도 없다")
    func everyRowDoesSomething() {
        // 행이 할 수 있는 일은 셋뿐이다: 우리 명령을 실행하거나, AppKit 표준 동작을
        // 부르거나, 하위 메뉴를 여는 그릇이거나.
        let inert = rows.filter { row in
            row.command == nil && row.systemAction == nil && row.submenu.isEmpty
        }

        #expect(inert.isEmpty, "이름만 있고 아무것도 안 하는 행: \(inert.map(\.title))")
    }

    @Test("종료가 실제로 무언가에 연결돼 있다")
    func quitIsWiredToSomething() {
        // 이 한 줄이 인증 경로 위에 있다 — 정상 종료가 안 되면 고아 프로세스를
        // 정상 경로로 잴 수가 없다.
        let quit = rows.first { $0.title.contains("종료") }

        #expect(quit != nil, "종료 항목이 없다")
        #expect(quit?.systemAction == .quit)
        #expect(quit?.keyEquivalent == "q")
    }

    @Test("표준 동작을 받기로 한 쪽이 실제로 그것을 받는다")
    func everySystemActionIsAnsweredByItsIntendedResponder() {
        // **오늘 델리게이트에서 배운 것의 같은 형태다.** 셀렉터 이름은 문자열이라 오타가
        // 조용하다 — 없는 셀렉터를 걸면 컴파일은 통과하고 그 행은 비활성으로 남는다.
        // 타입이 아니라 **런타임이 그 셀렉터를 아는지** 물어야 잡힌다.
        //
        // "앱 **또는** 창이 응답한다"로 느슨하게 물으면, 창 셀렉터를 앱 동작으로 잘못
        // 분류해도 통과한다 — 그러면 그 행은 **키 윈도우가 없을 때만** 죽는다. 가끔만
        // 나타나는 결함이 늘 나타나는 것보다 나쁘다. 그래서 받기로 한 쪽에만 묻는다.
        for action in MenuSystemAction.allCases {
            guard let selector = action.selector else {
                #expect(action.responder == .none, "\(action) 이 셀렉터 없이 응답자를 지정했다")
                continue
            }
            switch action.responder {
            case .application:
                #expect(NSApplication.shared.responds(to: selector), "\(action): 앱이 응답하지 않는다")
            case .window:
                #expect(NSWindow.instancesRespond(to: selector), "\(action): 창이 응답하지 않는다")
            case .none:
                #expect(Bool(false), "\(action) 이 셀렉터를 가졌는데 받을 사람이 없다")
            }
        }
    }

    @Test("종료는 살아 있는 앱 인스턴스가 실제로 받는다")
    func terminateIsAnsweredByTheRunningApplication() {
        // 리더 요구: **선언과 발화는 다르다.** 행에 셀렉터를 붙이면 "action 이 있다"는
        // 만족하지만, 응답자 사슬이 그걸 실제로 받는지는 **다른 주장**이다.
        // 클래스가 아니라 **지금 살아 있는 `NSApp` 인스턴스**에 묻는다.
        #expect(NSApplication.shared.responds(to: #selector(NSApplication.terminate(_:))))

        // 그리고 이 물음이 아무것에나 참을 주는 게 아닌지 같이 본다.
        #expect(!NSApplication.shared.responds(to: Selector("terminateNothing:")))
    }

    @Test("우리 명령과 표준 동작을 동시에 갖지 않는다")
    func aRowHasOneKindOfActionNotTwo() {
        // 둘 다 있으면 어느 쪽이 실행되는지가 컨트롤러의 순서에 달리고, 그건 읽는 사람이
        // 알 수 없는 규칙이다.
        let both = rows.filter { $0.command != nil && $0.systemAction != nil }

        #expect(both.isEmpty, "행동이 둘인 행: \(both.map(\.title))")
    }

    @Test("편집 메뉴의 Vim 비활성은 결함이 아니다 — 명세다")
    func theEditMenuItemsAreDeliberatelyCommandBacked() {
        // QA 보고의 절반이 이것이었다. `실행취소`·`복사`·`붙여넣기`·`전체선택` 은
        // **명령이 있고**, Vim 모드에서 비활성인 것은 REQ-010 AC-5 의 요구다.
        // 이 구분 없이 "메뉴가 비활성이다"를 고치면 명세를 깨뜨린다.
        let editRows = allRows(
            AppMenuBuilder.menus().first { $0.title == "편집" }?.items ?? []
        )

        #expect(!editRows.isEmpty)
        #expect(editRows.allSatisfy { $0.command != nil }, "편집 행은 우리 명령이 맡는다")
    }
}

/// 종료가 **살아나는 순간** 처음으로 도는 경로 (D-20 · D-2).
///
/// `⌘Q` 가 죽어 있던 동안 정상 종료 경로는 한 번도 실행되지 않았다. 그 경로를 되살리는 것이
/// D-20 의 절반이고, 나머지 절반은 **되살린 경로가 자식 프로세스를 실제로 정리하는가** 다.
/// 임베드된 Neovim 은 SIGTERM 으로 안 죽는다 — stdin EOF 로 죽는다(리더 라이브 재확인:
/// 2시간 살아남은 고아 2개가 `kill` 을 무시하고 `kill -9` 로만 죽었다).
@MainActor
@Suite("종료 경로 — 되살린 뒤에 자식이 남지 않는가 (D-20 · D-2)")
struct TerminationPathTests {

    @Test("종료 훅이 옵셔널 요구사항을 실제로 만족한다")
    func theTerminationHookActuallySatisfiesTheOptionalRequirement() {
        // **오늘 웹뷰 델리게이트에서 겪은 것과 같은 자리다.** `applicationShouldTerminate` 는
        // `NSApplicationDelegate` 의 **옵셔널** 요구사항이라, 시그니처가 어긋나면 컴파일은
        // 통과하고 AppKit 은 그냥 안 부른다 — 그러면 앱은 정리 없이 즉시 죽고 **자식 nvim 이
        // 그대로 고아가 된다.** 화면상으로는 "종료가 잘 된다"로 보인다.
        //
        // 타입으로는 안 잡힌다. 런타임에 물어야 한다.
        let delegate = ApplicationDelegate()

        #expect(
            delegate.responds(to: #selector(NSApplicationDelegate.applicationShouldTerminate(_:))),
            "종료 훅이 어긋나 있다 — 정리 없이 죽고 nvim 이 고아로 남는다"
        )

        // 이 검사가 아무것에나 참을 돌려주는 건 아닌지 같이 확인한다. `responds(to:)` 가
        // 무조건 true 라면 위 단언은 아무것도 안 지킨다 — 검사기를 검사한다.
        #expect(!delegate.responds(to: Selector("applicationShouldNeverExist:")))
    }

    @Test("셀렉터 이름을 바꾸는 어긋남은 컴파일러가 잡는다 — 시그니처 어긋남은 못 잡는다")
    func theCompilerCatchesOnlyOneOfTheTwoMismatchShapes() {
        // 이 테스트는 단언이 아니라 **기록**이다. 두 어긋남이 검출 가능성이 다르다:
        //
        //   `@objc(다른이름:)` 으로 셀렉터만 바꾸면  → **컴파일 에러**
        //     "provided by method ... does not match the requirement's selector"
        //   Swift 시그니처를 어긋나게 하면        → **경고**뿐. 증인이 아니게 되어
        //     `@objc` 로 노출조차 안 되고, AppKit 은 조용히 안 부른다
        //
        // 오늘 웹뷰에서 물린 것이 **후자**다(`@MainActor` 누락). 대조를 전자로 시도했더니
        // 컴파일러가 먼저 막아서 그 형태로는 재현되지 않았다 — 즉 **위험한 쪽은 컴파일러가
        // 안 막아 주는 쪽**이고, 그래서 런타임 질문이 필요하다.
        #expect(ApplicationDelegate().responds(to: #selector(NSApplicationDelegate.applicationShouldTerminate(_:))))
    }

    @Test("마지막 창을 닫으면 종료한다는 훅도 연결돼 있다")
    func theLastWindowHookIsWiredToo() {
        let delegate = ApplicationDelegate()

        #expect(delegate.responds(
            to: #selector(NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed(_:))
        ))
    }

    @Test("워크스페이스가 없으면 기다리지 않고 바로 종료한다")
    func withNothingToCleanUpTerminationIsImmediate() {
        // 정리할 게 없는데 `.terminateLater` 를 돌려주면 아무도 `reply(toApplicationShouldTerminate:)`
        // 를 부르지 않아 **앱이 종료 중인 채로 멈춘다.** 고아보다 눈에 띄지만 못지않게 나쁘다.
        let delegate = ApplicationDelegate()

        #expect(delegate.applicationShouldTerminate(.shared) == .terminateNow)
    }
}
