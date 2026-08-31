/// Builds the menu bar (design §3 W-9).
///
/// Every command in this application has a menu path, because a shortcut with no menu row
/// is a shortcut nobody discovers (design §4.5). The menu is also where the key-routing
/// contract is enforced: the application claims **Command combinations only**, so every
/// Control chord Vim needs — ⌃O, ⌃R, ⌃V, ⌃W — reaches Neovim untouched (REQ-011 AC-2).
/// `AppMenuBuilderTests` walks the built menu and fails on any row that would break that.
public enum AppMenuBuilder {

    public static let applicationName = "CodeNavigator"

    public static func menus() -> [MenuDescriptor] {
        [
            applicationMenu,
            fileMenu,
            editMenu,
            navigateMenu,
            viewMenu,
            windowMenu,
            helpMenu,
        ]
    }

    // MARK: 메뉴

    private static var applicationMenu: MenuDescriptor {
        MenuDescriptor(title: applicationName, items: [
            MenuItemDescriptor(title: "\(applicationName) 정보", systemAction: .about),
            .separator,
            MenuItemDescriptor(title: "서비스", systemAction: .services, submenu: []),
            .separator,
            MenuItemDescriptor(title: "\(applicationName) 가리기", systemAction: .hide, keyEquivalent: "h", modifiers: [.command]),
            MenuItemDescriptor(title: "다른 항목 가리기", systemAction: .hideOthers, keyEquivalent: "h", modifiers: [.command, .option]),
            MenuItemDescriptor(title: "모두 보기", systemAction: .showAll),
            .separator,
            MenuItemDescriptor(title: "\(applicationName) 종료", systemAction: .quit, keyEquivalent: "q", modifiers: [.command]),
        ])
    }

    private static var fileMenu: MenuDescriptor {
        MenuDescriptor(title: "파일", items: [
            MenuItemDescriptor(title: "프로젝트 열기…", command: .openProject, keyEquivalent: "o", modifiers: [.command]),
            // A container: the recent projects themselves are filled in at display time,
            // because they change while the application runs.
            MenuItemDescriptor(title: "최근 프로젝트 열기", command: .openRecentProject, submenu: []),
            MenuItemDescriptor(title: "프로젝트 닫기", command: .closeProject, keyEquivalent: "w", modifiers: [.command, .shift]),
            .separator,
            MenuItemDescriptor(title: "저장", command: .save, keyEquivalent: "s", modifiers: [.command]),
            .separator,
            MenuItemDescriptor(title: "창 닫기", command: .closeWindow, keyEquivalent: "w", modifiers: [.command]),
        ])
    }

    private static var editMenu: MenuDescriptor {
        MenuDescriptor(title: "편집", items: [
            MenuItemDescriptor(title: "실행 취소", command: .undo, keyEquivalent: "z", modifiers: [.command]),
            MenuItemDescriptor(title: "다시 실행", command: .redo, keyEquivalent: "z", modifiers: [.command, .shift]),
            .separator,
            MenuItemDescriptor(title: "오려두기", command: .cut, keyEquivalent: "x", modifiers: [.command]),
            MenuItemDescriptor(title: "복사", command: .copy, keyEquivalent: "c", modifiers: [.command]),
            MenuItemDescriptor(title: "붙여넣기", command: .paste, keyEquivalent: "v", modifiers: [.command]),
            MenuItemDescriptor(title: "전체 선택", command: .selectAll, keyEquivalent: "a", modifiers: [.command]),
            .separator,
            MenuItemDescriptor(title: "입력 모드 전환", command: .toggleInputMode, keyEquivalent: "v", modifiers: [.command, .control]),
            MenuItemDescriptor(title: "Vim 모드", command: .selectVimMode),
            MenuItemDescriptor(title: "표준 모드", command: .selectStandardMode),
            .separator,
            MenuItemDescriptor(title: "편집 세션 재기동", command: .restartEditSession, keyEquivalent: "r", modifiers: [.command, .control]),
        ])
    }

    private static var navigateMenu: MenuDescriptor {
        MenuDescriptor(title: "이동", items: [
            MenuItemDescriptor(title: "심볼 검색…", command: .symbolSearch, keyEquivalent: "p", modifiers: [.command]),
            MenuItemDescriptor(title: "전문 검색…", command: .textSearch, keyEquivalent: "f", modifiers: [.command, .shift]),
            .separator,
            MenuItemDescriptor(title: "정의로 이동", command: .goToDefinition, keyEquivalent: "b", modifiers: [.command]),
            MenuItemDescriptor(title: "참조 보기", command: .showReferences, keyEquivalent: "b", modifiers: [.command, .shift]),
            .separator,
            MenuItemDescriptor(title: "뒤로", command: .navigateBack, keyEquivalent: "[", modifiers: [.command]),
            MenuItemDescriptor(title: "앞으로", command: .navigateForward, keyEquivalent: "]", modifiers: [.command]),
        ])
    }

    private static var viewMenu: MenuDescriptor {
        MenuDescriptor(title: "보기", items: [
            MenuItemDescriptor(title: "파일 트리 표시", command: .toggleFileTree, keyEquivalent: "1", modifiers: [.command, .option]),
            MenuItemDescriptor(title: "참조·검색 패널 표시", command: .togglePanel, keyEquivalent: "0", modifiers: [.command, .option]),
            // 툴바 버튼과 달리 렌더 불가 파일에서도 살아 있다 — 02b F-14 4 는 이 경우를
            // 비활성이 아니라 "왜 안 되는지 말해 주기"로 처리한다. 비활성 메뉴 항목은
            // 이유를 말할 자리가 없다.
            MenuItemDescriptor(title: "렌더 보기 전환", command: .toggleRenderView, keyEquivalent: "v", modifiers: [.command, .shift]),
            .separator,
            MenuItemDescriptor(title: "전체 화면 시작", command: .toggleFullScreen, keyEquivalent: "f", modifiers: [.command, .control]),
        ])
    }

    private static var windowMenu: MenuDescriptor {
        MenuDescriptor(title: "창", items: [
            MenuItemDescriptor(title: "최소화", systemAction: .minimize, keyEquivalent: "m", modifiers: [.command]),
            MenuItemDescriptor(title: "확대", systemAction: .zoom),
        ])
    }

    private static var helpMenu: MenuDescriptor {
        MenuDescriptor(title: "도움말", items: [
            MenuItemDescriptor(title: "\(applicationName) 도움말", systemAction: .help),
        ])
    }
}
