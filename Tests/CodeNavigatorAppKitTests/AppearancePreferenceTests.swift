import Testing
import AppKit
@testable import CodeNavigatorAppKit

/// The application used to take whatever appearance macOS was in, with no way to say otherwise.
/// A reader who wants a light editor on a dark desktop had to change the whole system.
@Suite("외관 설정 — 시스템 따름·밝게·어둡게")
@MainActor
struct AppearancePreferenceTests {

    @Test("저장하고 다시 읽으면 같은 값이다")
    func roundTripsThroughStorage() {
        for preference in AppearancePreference.allCases {
            let storage = InMemoryKeyValueStore()
            let writing = ShellPreferences(storage: storage)
            writing.appearance = preference

            let reading = ShellPreferences(storage: storage)
            #expect(reading.appearance == preference)
        }
    }

    @Test("처음 실행하면 시스템을 따른다 — 우리가 임의로 고르지 않는다")
    func defaultsToFollowingTheSystem() {
        #expect(ShellPreferences(storage: InMemoryKeyValueStore()).appearance == .system)
    }

    @Test("손상된 값은 시스템 따름으로 읽는다 — 설정 하나 때문에 창이 안 열리지 않는다")
    func treatsUnreadableValuesAsSystem() {
        let storage = InMemoryKeyValueStore()
        storage.setData(Data("보라색".utf8), forKey: ShellPreferences.appearanceKey)
        #expect(ShellPreferences(storage: storage).appearance == .system)
    }

    @Test("밝게·어둡게는 NSAppearance 를 지정하고, 시스템 따름은 지정하지 않는다")
    func mapsToTheAppKitAppearance() {
        #expect(AppearancePreference.light.appearanceName == .aqua)
        #expect(AppearancePreference.dark.appearanceName == .darkAqua)
        // nil 이어야 한다. 시스템을 따른다는 것은 우리가 아무 값도 안 박는다는 뜻이고,
        // 여기에 현재 시스템 값을 넣어 두면 실행 중 시스템이 바뀌어도 안 따라간다.
        #expect(AppearancePreference.system.appearanceName == nil)
    }

    @Test("적용하면 NSApplication 의 외관이 바뀐다")
    func appliesToTheApplication() {
        let application = NSApplication.shared
        let original = application.appearance
        defer { application.appearance = original }

        AppearanceApplier.apply(.dark, to: application)
        #expect(application.appearance?.name == .darkAqua)

        AppearanceApplier.apply(.light, to: application)
        #expect(application.appearance?.name == .aqua)

        AppearanceApplier.apply(.system, to: application)
        #expect(application.appearance == nil)
    }

    @Test("메뉴에서 고른 항목에만 체크가 붙는다")
    func ticksTheChosenRow() {
        for chosen in AppearancePreference.allCases {
            let availability = MenuAvailability(
                inputMode: .vim,
                sessionState: .connected,
                hasOpenProject: true,
                appearance: chosen
            )
            #expect(availability.isChecked(.selectAppearanceSystem) == (chosen == .system))
            #expect(availability.isChecked(.selectAppearanceLight) == (chosen == .light))
            #expect(availability.isChecked(.selectAppearanceDark) == (chosen == .dark))
        }
    }

    /// 프로젝트가 없어도, 편집 세션이 죽어 있어도 고를 수 있어야 한다. 화면을 못 읽겠다는
    /// 것은 편집기 상태와 무관한 문제다.
    @Test("외관 항목은 언제나 선택 가능하다")
    func staysEnabledWithoutAProject() {
        let availability = MenuAvailability(
            inputMode: .vim,
            sessionState: .notStarted,
            hasOpenProject: false
        )
        for command in [MenuCommand.selectAppearanceSystem, .selectAppearanceLight, .selectAppearanceDark] {
            #expect(availability.isEnabled(command))
        }
    }

    @Test("보기 메뉴에 세 항목이 다 있다")
    func appearsInTheViewMenu() throws {
        let viewMenu = try #require(AppMenuBuilder.menus().first { $0.title == "보기" })
        let commands: [MenuCommand] = viewMenu.items.compactMap(\.command)
        #expect(commands.contains(.selectAppearanceSystem))
        #expect(commands.contains(.selectAppearanceLight))
        #expect(commands.contains(.selectAppearanceDark))
    }
}
