import AppKit
import CodeNavigatorContract

/// Runs a menu command.
///
/// Shared by the menu bar and the toolbar so the same command cannot mean two things
/// depending on where it was pressed. Every case is listed rather than defaulted: a command
/// added to `MenuCommand` then fails to compile here instead of silently doing nothing.
@MainActor
public enum MenuCommandRouter {

    /// Asks the user for a project folder, or returns nil if they cancelled.
    ///
    /// Injectable because the real one runs a modal panel: a test that walked every command
    /// with the panel wired in blocked for ever on the first one, which is a fair warning
    /// that a modal in a router is a modal in everything downstream of it.
    public typealias FolderChooser = @MainActor () -> URL?

    public static func perform(
        _ command: MenuCommand,
        model: AppModel,
        search: SearchModel,
        chooseFolder: FolderChooser = presentFolderPanel
    ) async {
        switch command {
        case .openProject, .openRecentProject:
            guard let url = chooseFolder() else { return }
            await model.openProject(at: url)

        case .goToDefinition:
            await model.goToDefinition()

        case .showReferences:
            guard let name = await model.wordUnderCursor() else {
                model.show(StatusMessage(kind: .error, text: "✕ 커서 위치에 심볼이 없습니다"))
                return
            }
            await search.showReferences(to: name)

        case .symbolSearch:
            search.isShowingSymbolSearch = true

        case .textSearch:
            search.selectedTab = .textSearch

        case .toggleInputMode:
            await model.toggleInputMode()
        case .selectVimMode:
            await model.setInputMode(.vim)
        case .selectStandardMode:
            await model.setInputMode(.standard)
        case .restartEditSession:
            await model.restartEditSession()

        // Every editing command goes through the engine, never as a raw key string. A
        // normal-mode key means something else in standard mode, where Neovim is held in
        // insert: `u` would type the letter u and `:w<CR>` would not save. The engine wraps
        // each of these so the same menu row does the same thing in both modes, and the
        // application never has to know which mode it is in — that branch would be the
        // state tracking REQ-010 exists to avoid.
        case .save:
            await model.save()
        case .navigateBack:
            await model.jumpBack()
        case .navigateForward:
            await model.jumpForward()
        case .undo:
            await model.undo()
        case .redo:
            await model.redo()
        case .cut:
            await model.cutSelection()
        case .copy:
            await model.copySelection()
        case .paste:
            await model.paste()
        case .selectAll:
            await model.selectAll()

        case .toggleFileTree:
            model.shell.isTreeVisible.toggle()
        case .togglePanel:
            model.shell.isPanelVisible.toggle()

        // `NSApplication.shared` rather than `NSApp`: the latter is an implicitly unwrapped
        // optional that is nil until an application exists, so it traps in a test process.
        // A router that cannot be exercised without a running application cannot be tested.
        case .toggleFullScreen:
            NSApplication.shared.keyWindow?.toggleFullScreen(nil)
        case .closeWindow:
            NSApplication.shared.keyWindow?.performClose(nil)

        case .closeProject:
            await model.closeProject()
        }
    }

    /// The standard macOS folder chooser (REQ-001 AC-1).
    public static func presentFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "프로젝트 열기"

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }
}
