import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The menu bar is where two acceptance criteria meet: every command is reachable without
/// a shortcut (REQ-011 AC-1), and the shortcuts the application claims never collide with
/// the ones Vim needs (REQ-011 AC-2).
@Suite("AppMenuBuilder — 메뉴 막대 (REQ-010 AC-3·AC-5, REQ-011 AC-1·AC-2)")
struct AppMenuBuilderTests {

    private var menus: [MenuDescriptor] {
        AppMenuBuilder.menus()
    }

    private func allItems(in menus: [MenuDescriptor]) -> [MenuItemDescriptor] {
        func flatten(_ items: [MenuItemDescriptor]) -> [MenuItemDescriptor] {
            items.flatMap { [$0] + flatten($0.submenu) }
        }
        return menus.flatMap { flatten($0.items) }
    }

    // MARK: 구조

    @Test("02 §3 W-9 의 메뉴가 애플 관례 순서대로 있다")
    func theDesignedMenusExist() {
        #expect(menus.map(\.title) == ["CodeNavigator", "파일", "편집", "이동", "보기", "창", "도움말"])
    }

    @Test("모든 명령에 메뉴 경로가 있다 — 단축키만 있는 기능은 없다")
    func everyCommandIsReachableFromTheMenu() {
        let reachable = Set(allItems(in: menus).compactMap(\.command))
        let missing = Set(MenuCommand.allCases).subtracting(reachable)
        #expect(missing.isEmpty, "메뉴에서 닿을 수 없는 명령: \(missing)")
    }

    // MARK: 키 라우팅 계약 (REQ-011 AC-2)

    @Test("단축키를 가진 모든 메뉴 항목은 ⌘를 포함한다 — ⌃ 단독 조합은 Neovim 것이다")
    func theApplicationClaimsCommandCombinationsOnly() {
        let shortcutItems = allItems(in: menus).filter(\.hasKeyEquivalent)
        // Without this the loop passes on an empty menu, which is the failure it exists to
        // catch: a menu that builds nothing looks exactly like a menu that is well behaved.
        #expect(shortcutItems.count >= 15)

        for item in shortcutItems {
            #expect(
                item.modifiers.contains(.command),
                "\(item.title) 이 ⌘ 없이 키를 가로챈다 — Vim 의 ⌃ 조합을 빼앗는다"
            )
        }
    }

    @Test("Vim 이 쓰는 ⌃ 조합은 어떤 항목도 가로채지 않는다")
    func vimControlChordsAreNotClaimed() {
        let vimChords = ["o", "r", "v", "w", "f", "b", "d", "u"]
        let controlOnly = allItems(in: menus).filter {
            $0.modifiers.contains(.control) && !$0.modifiers.contains(.command)
        }
        #expect(controlOnly.isEmpty)

        for chord in vimChords {
            let claimed = allItems(in: menus).contains {
                $0.keyEquivalent == chord && $0.modifiers == [.control]
            }
            #expect(!claimed, "⌃\(chord.uppercased()) 를 앱이 가로챈다")
        }
    }

    @Test("설계가 지정한 단축키가 그대로 붙어 있다")
    func theDesignedShortcutsAreBound() {
        let expected: [MenuCommand: (String, KeyModifiers)] = [
            .openProject: ("o", [.command]),
            .closeProject: ("w", [.command, .shift]),
            .save: ("s", [.command]),
            .closeWindow: ("w", [.command]),
            .undo: ("z", [.command]),
            .redo: ("z", [.command, .shift]),
            .cut: ("x", [.command]),
            .copy: ("c", [.command]),
            .paste: ("v", [.command]),
            .selectAll: ("a", [.command]),
            .toggleInputMode: ("v", [.command, .control]),
            .restartEditSession: ("r", [.command, .control]),
            .symbolSearch: ("p", [.command]),
            .textSearch: ("f", [.command, .shift]),
            .goToDefinition: ("b", [.command]),
            .showReferences: ("b", [.command, .shift]),
            .navigateBack: ("[", [.command]),
            .navigateForward: ("]", [.command]),
            .toggleFileTree: ("1", [.command, .option]),
            .togglePanel: ("0", [.command, .option]),
            .toggleFullScreen: ("f", [.command, .control]),
        ]

        for (command, binding) in expected {
            let item = allItems(in: menus).first { $0.command == command }
            #expect(item?.keyEquivalent == binding.0, "\(command) 의 키")
            #expect(item?.modifiers == binding.1, "\(command) 의 조합키")
        }
    }

    @Test("같은 단축키를 두 항목이 나눠 갖지 않는다")
    func noShortcutIsBoundTwice() {
        let bindings = allItems(in: menus)
            .filter(\.hasKeyEquivalent)
            .map { "\($0.modifiers.rawValue):\($0.keyEquivalent)" }
        #expect(bindings.count == Set(bindings).count, "중복 단축키: \(bindings)")
    }

    // MARK: 모드별 활성 (REQ-010 AC-5)

    @Test("Vim 모드에서 표준 편집 명령이 비활성이다")
    func standardEditingIsOffInVimMode() {
        let availability = MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true)
        for command in [MenuCommand.undo, .redo, .cut, .copy, .paste, .selectAll] {
            #expect(!availability.isEnabled(command), "\(command) 이 Vim 모드에서 활성이다")
        }
        // ⌘S is the exception: writing is delegated to `:w` in both modes (INV-3).
        #expect(availability.isEnabled(.save))
    }

    @Test("표준 모드에서는 같은 명령이 활성이다")
    func standardEditingIsOnInStandardMode() {
        let availability = MenuAvailability(inputMode: .standard, sessionState: .connected, hasOpenProject: true)
        for command in [MenuCommand.undo, .redo, .cut, .copy, .paste, .selectAll] {
            #expect(availability.isEnabled(command))
        }
    }

    @Test("모드 항목은 현재 모드에 체크가 붙는다")
    func theCurrentModeIsTicked() {
        let vim = MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true)
        #expect(vim.isChecked(.selectVimMode))
        #expect(!vim.isChecked(.selectStandardMode))

        let standard = MenuAvailability(inputMode: .standard, sessionState: .connected, hasOpenProject: true)
        #expect(standard.isChecked(.selectStandardMode))
        #expect(!standard.isChecked(.selectVimMode))
    }
}
