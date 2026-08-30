import Testing
import AppKit
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The menu bar, built and inspected as a real `NSMenu`.
///
/// This is not decoration. ADR-0102 makes the menu the mechanism by which the application
/// claims Command combinations, so that every Control chord Vim needs falls through to the
/// editor (REQ-011 AC-2). A menu that is never installed, or that binds a key equivalent in
/// a way AppKit will not match, silently hands ⌘O and ⌘P to Neovim.
@MainActor
@Suite("MenuBarController — 실제로 설치되는 메뉴 막대 (REQ-010 AC-5, REQ-011 AC-1·AC-2)")
struct MenuBarControllerTests {

    private func makeController(
        inputMode: InputMode = .vim,
        session: EditorSessionState = .connected,
        hasProject: Bool = true,
        recents: [RecentProject] = [],
        onCommand: @escaping (MenuCommand) -> Void = { _ in },
        onOpenRecent: @escaping (String) -> Void = { _ in }
    ) -> MenuBarController {
        MenuBarController(
            availability: {
                MenuAvailability(inputMode: inputMode, sessionState: session, hasOpenProject: hasProject)
            },
            perform: onCommand,
            recentProjects: { recents },
            openRecentProject: onOpenRecent
        )
    }

    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            guard let submenu = item.submenu else { return [item] }
            return [item] + allItems(in: submenu)
        }
    }

    private func installedItems(_ controller: MenuBarController) -> [NSMenuItem] {
        AppMenuBuilder.menus().flatMap { allItems(in: controller.menu(from: $0)) }
    }

    // MARK: Installation

    @Test("메뉴 막대가 실제로 설치된다")
    func theMenuBarIsInstalled() {
        // The descriptors existed for a while with nothing building them, so the menu bar
        // was absent and every Command shortcut fell through to Neovim.
        let application = NSApplication.shared
        let previous = application.mainMenu
        defer { application.mainMenu = previous }

        makeController().install(into: application)
        #expect(application.mainMenu != nil)
        #expect((application.mainMenu?.items.count ?? 0) >= 6, "§3 W-9는 최상위 메뉴 6개 이상을 요구한다")
    }

    // MARK: The recent-projects submenu (REQ-001 AC-2)

    private func recentSubmenu(_ controller: MenuBarController) -> NSMenu? {
        let items = AppMenuBuilder.menus().flatMap { allItems(in: controller.menu(from: $0)) }
        return items.first { controller.command(for: $0) == .openRecentProject }?.submenu
    }

    private func sampleRecents() -> [RecentProject] {
        [
            RecentProject(name: "code-navigator", rootPath: "/tmp/a", lastOpenedAt: Date(timeIntervalSince1970: 200)),
            RecentProject(name: "shop", rootPath: "/tmp/b", lastOpenedAt: Date(timeIntervalSince1970: 100)),
        ]
    }

    @Test("최근 프로젝트가 서브메뉴 항목으로 나온다 (REQ-001 AC-2)")
    func recentProjectsAppearInTheSubmenu() {
        // The descriptor hardcoded an empty submenu, so the row existed and opened onto
        // nothing — the one route REQ-001 AC-2 names for switching projects.
        let controller = makeController(recents: sampleRecents())
        guard let submenu = recentSubmenu(controller) else {
            Issue.record("최근 프로젝트 열기 항목에 서브메뉴가 없다")
            return
        }
        controller.menuNeedsUpdate(submenu)
        #expect(submenu.items.map(\.title) == ["code-navigator", "shop"], "저장 순서(최근 우선)를 그대로 따라야 한다")
    }

    @Test("최근 항목을 고르면 그 경로가 열린다 (REQ-001 AC-2)")
    func choosingARecentProjectOpensThatPath() {
        var opened: [String] = []
        let controller = makeController(recents: sampleRecents(), onOpenRecent: { opened.append($0) })
        guard let submenu = recentSubmenu(controller) else {
            Issue.record("최근 프로젝트 열기 항목에 서브메뉴가 없다")
            return
        }
        controller.menuNeedsUpdate(submenu)
        guard let second = submenu.items.dropFirst().first else {
            Issue.record("서브메뉴 항목이 2개가 아니다")
            return
        }
        _ = second.target?.perform(second.action, with: second)
        #expect(opened == ["/tmp/b"], "고른 행의 경로가 열려야 한다 — 이름이 같은 다른 경로가 있을 수 있다")
    }

    @Test("최근 프로젝트가 없으면 비활성 안내 한 줄만 둔다")
    func anEmptyRecentListShowsADisabledPlaceholder() {
        let controller = makeController(recents: [])
        guard let submenu = recentSubmenu(controller) else {
            Issue.record("최근 프로젝트 열기 항목에 서브메뉴가 없다")
            return
        }
        controller.menuNeedsUpdate(submenu)
        #expect(submenu.items.count == 1)
        #expect(submenu.items.first?.isEnabled == false, "빈 메뉴는 고를 수 없어야 한다")
    }

    @Test("서브메뉴를 다시 열어도 항목이 누적되지 않는다")
    func reopeningTheSubmenuDoesNotAccumulateItems() {
        // menuNeedsUpdate fires on every open. Appending instead of rebuilding grows the
        // list without bound.
        let controller = makeController(recents: sampleRecents())
        guard let submenu = recentSubmenu(controller) else {
            Issue.record("최근 프로젝트 열기 항목에 서브메뉴가 없다")
            return
        }
        controller.menuNeedsUpdate(submenu)
        controller.menuNeedsUpdate(submenu)
        #expect(submenu.items.count == 2)
    }

    // MARK: The wiring that lets AppKit validate at all

    /// Every built menu must auto-enable its items.
    ///
    /// This one line is what makes AppKit call `validateMenuItem` on each item's target,
    /// which is where this controller decides — from `MenuAvailability` — whether an edit
    /// command is live (REQ-010 AC-5) and which input mode carries the tick (REQ-010 AC-3).
    /// With it off, AppKit asks no one and reads `isEnabled`, which nothing here sets: in
    /// the built application every edit command stayed live in Vim mode and no mode ever
    /// carried a tick. The suite stayed green because every other test called
    /// `validateMenuItem` directly, which is not the path AppKit takes.
    ///
    /// The assertion is on the wiring rather than on a validated menu because a test
    /// process has no running application, and `NSMenu.update()` there validates nothing —
    /// measured: zero validator calls. The policy itself is asserted separately, above, by
    /// calling the validator directly; this test covers the join between the two.
    @Test("모든 메뉴가 자동 활성화를 켠 채 만들어진다 (REQ-010 AC-3·AC-5)")
    func everyBuiltMenuLetsAppKitValidate() {
        let controller = makeController()
        var checked = 0
        for descriptor in AppMenuBuilder.menus() {
            let menu = controller.menu(from: descriptor)
            #expect(menu.autoenablesItems, "\(menu.title) 메뉴가 검증을 건너뛴다")
            checked += 1
            for item in menu.items {
                guard let submenu = item.submenu else { continue }
                #expect(submenu.autoenablesItems, "\(item.title) 하위 메뉴가 검증을 건너뛴다")
                checked += 1
            }
        }
        #expect(checked >= 6, "검사한 메뉴가 \(checked)개뿐이면 방어선이 헐겁다")
    }

    // MARK: The key-routing contract (REQ-011 AC-2)

    @Test("단축키가 붙은 모든 항목이 ⌘를 포함한다")
    func everyShortcutIncludesCommand() {
        // ADR-0102: the application claims Command combinations and nothing else. A menu
        // row bound to a bare Control chord would swallow one of Vim's own keys.
        for item in installedItems(makeController()) where !item.keyEquivalent.isEmpty {
            #expect(
                item.keyEquivalentModifierMask.contains(.command),
                "\(item.title)의 단축키에 ⌘가 없다 — Vim 키를 가로챈다"
            )
        }
    }

    @Test("키 이퀴벌런트가 소문자다 — 대문자는 Shift를 이중 계산해 매칭이 실패한다")
    func keyEquivalentsAreLowercase() {
        // Measured in the spike: `keyEquivalent: "F"` with `[.shift, .command]` never
        // matched, and ⇧⌘F leaked through to Neovim.
        for item in installedItems(makeController()) where !item.keyEquivalent.isEmpty {
            #expect(
                item.keyEquivalent == item.keyEquivalent.lowercased(),
                "\(item.title)의 키 이퀴벌런트가 대문자다"
            )
        }
    }

    @Test("Vim이 쓰는 ⌃ 조합이 메뉴에 없다")
    func vimsControlChordsAreNotClaimed() {
        let vimChords = ["o", "r", "v", "w", "i", "d", "u", "f", "b"]
        for item in installedItems(makeController()) where !item.keyEquivalent.isEmpty {
            let mask = item.keyEquivalentModifierMask
            let isBareControl = mask.contains(.control) && !mask.contains(.command)
            #expect(!(isBareControl && vimChords.contains(item.keyEquivalent)), "\(item.title)")
        }
    }

    // MARK: Enablement (REQ-010 AC-5)

    @Test("Vim 모드에서 편집 명령이 비활성이다")
    func editingIsDisabledInVimMode() {
        let controller = makeController(inputMode: .vim)
        let items = installedItems(controller)
        let editing: [MenuCommand] = [.undo, .redo, .cut, .copy, .paste, .selectAll]

        var checked = 0
        for item in items {
            guard let command = controller.command(for: item), editing.contains(command) else { continue }
            checked += 1
            #expect(!controller.validateMenuItem(item), "\(item.title)가 Vim 모드에서 활성이다")
        }
        #expect(checked == editing.count, "편집 명령 \(editing.count)개가 메뉴에 다 있어야 한다 (찾은 것 \(checked))")
    }

    @Test("표준 모드에서 편집 명령이 활성이다")
    func editingIsEnabledInStandardMode() {
        let controller = makeController(inputMode: .standard)
        let editing: [MenuCommand] = [.undo, .redo, .cut, .copy, .paste, .selectAll]
        for item in installedItems(controller) {
            guard let command = controller.command(for: item), editing.contains(command) else { continue }
            #expect(controller.validateMenuItem(item), "\(item.title)가 표준 모드에서 비활성이다")
        }
    }

    @Test("현재 입력 모드에 체크가 붙는다")
    func theCurrentInputModeIsTicked() {
        let controller = makeController(inputMode: .standard)
        for item in installedItems(controller) {
            guard let command = controller.command(for: item) else { continue }
            guard command == .selectVimMode || command == .selectStandardMode else { continue }
            _ = controller.validateMenuItem(item)
            #expect((item.state == .on) == (command == .selectStandardMode), "\(item.title)")
        }
    }

    @Test("세션이 끊겨도 검색 항목은 활성이다")
    func searchStaysEnabledWithoutASession() {
        let controller = makeController(session: .disconnected(reason: "종료"))
        for item in installedItems(controller) {
            guard let command = controller.command(for: item), command == .symbolSearch || command == .textSearch else {
                continue
            }
            #expect(controller.validateMenuItem(item), "\(item.title)가 비활성이다 — 인덱스는 편집 세션과 무관하다")
        }
    }

    // MARK: Dispatch

    @Test("항목을 고르면 그 명령이 실행된다")
    func choosingAnItemRunsItsCommand() {
        var fired: [MenuCommand] = []
        let controller = makeController(onCommand: { fired.append($0) })
        let items = installedItems(controller)

        guard let openItem = items.first(where: { controller.command(for: $0) == .openProject }) else {
            Issue.record("프로젝트 열기 항목이 없다")
            return
        }
        _ = openItem.target?.perform(openItem.action, with: openItem)
        #expect(fired == [.openProject])
    }
}
