import AppKit
import SwiftUI
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

    /// 어느 JVM 에 붙을지. 폴더 선택과 같은 이유로 주입한다 — 대화상자를 띄우는 코드가
    /// 라우터 안에 박혀 있으면 라우팅을 테스트할 때마다 창이 뜬다.
    public typealias DebugTargetChooser = @MainActor () -> (host: String, port: UInt16)?

    /// 브레이크포인트 조건을 묻는다. 현재 조건을 받아 새 조건을 준다.
    public typealias ConditionEditor = @MainActor (String) -> String?

    /// 실행 설정을 고치는 화면. 취소하면 nil.
    public typealias RunConfigurationEditor = @MainActor ([RunConfiguration]) -> [RunConfiguration]?

    /// 사용자에게 무언가를 묻는 모든 자리를 한 곳에 모은 것.
    ///
    /// 훅마다 인자를 하나씩 늘리다가 실제로 당했다. 명령 전체를 도는 테스트가 폴더 대화상자만
    /// 막아 두었는데, 나중에 붙인 디버그 대상 대화상자는 그 방어 밖이라 **테스트 실행이 영원히
    /// 끝나지 않았다**. 모달의 기본값은 조용히 위험하다 — 인자를 안 넘긴 호출부는 컴파일도
    /// 통과하고 평소엔 잘 돌다가, 사용자가 없는 곳에서만 멈춘다.
    ///
    /// 묶어 두면 훅을 새로 추가해도 `.headless` 가 자동으로 덮는다. 방어를 훅마다 갱신해야
    /// 하는 구조를 없애는 것이 요점이다.
    public struct Environment: Sendable {
        public var chooseFolder: FolderChooser
        public var askDebugTarget: DebugTargetChooser
        public var askBreakpointCondition: ConditionEditor
        public var editRunConfigurations: RunConfigurationEditor

        public init(
            chooseFolder: @escaping FolderChooser,
            askDebugTarget: @escaping DebugTargetChooser,
            askBreakpointCondition: @escaping ConditionEditor,
            editRunConfigurations: @escaping RunConfigurationEditor
        ) {
            self.chooseFolder = chooseFolder
            self.askDebugTarget = askDebugTarget
            self.askBreakpointCondition = askBreakpointCondition
            self.editRunConfigurations = editRunConfigurations
        }

        /// 사람이 앉아 있는 실행.
        public static var interactive: Environment {
            Environment(
                chooseFolder: presentFolderPanel,
                askDebugTarget: presentDebugTargetPrompt,
                askBreakpointCondition: presentConditionPrompt,
                editRunConfigurations: presentRunConfigurationEditor
            )
        }

        /// 사람이 없는 실행(테스트·자동화). 모든 물음이 "취소" 로 답한다.
        public static var headless: Environment {
            Environment(
                chooseFolder: { nil }, askDebugTarget: { nil },
                askBreakpointCondition: { _ in nil }, editRunConfigurations: { _ in nil }
            )
        }
    }

    /// Runs a `gd`/`gr` request's commands in order (REQ-015).
    ///
    /// Sequential rather than concurrent: `gd` lists usages for the word under the cursor and
    /// then moves the cursor, and overlapping those two would read a word that is already gone.
    ///
    /// Both commands report a missing symbol with the same sentence, and `show` replaces rather
    /// than stacks — so a cursor on punctuation still produces one message, not two.
    public static func perform(
        _ request: EditorNavigationRequest,
        model: AppModel,
        search: SearchModel,
        environment: Environment = .interactive
    ) async {
        for command in request.menuCommands {
            await perform(command, model: model, search: search, environment: environment)
        }
    }

    public static func perform(
        _ command: MenuCommand,
        model: AppModel,
        search: SearchModel,
        environment: Environment = .interactive
    ) async {
        switch command {
        case .openProject, .openRecentProject:
            guard let url = environment.chooseFolder() else { return }
            await model.openProject(at: url)

        case .goToDefinition:
            await model.goToDefinition()

        case .showReferences:
            guard let name = await model.wordUnderCursor() else {
                model.show(StatusMessage(kind: .error, text: "✕ 커서 위치에 심볼이 없습니다"))
                return
            }
            await search.showReferences(to: name, from: model.referenceQueryOrigin)

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

        case .runSelected, .debugSelected:
            guard let configuration = model.selectedRunConfiguration else {
                model.show(StatusMessage(kind: .error, text: "✕ 실행 설정이 없습니다 — ⌘, 로 추가하세요"))
                return
            }
            await model.run(
                configuration, debugPort: command == .debugSelected ? AppModel.defaultDebugPort : nil
            )

        case .stopRun:
            await model.stopRun()

        case .openTerminal:
            await model.openShell()

        case .editRunConfigurations:
            // 감지된 것도 함께 연다. 고치려면 목록에 있어야 하고, 저장하는 순간 그것은
            // 사용자의 설정이 된다 — 그때부터 다음 스캔이 건드리지 않는다.
            let edited = environment.editRunConfigurations(model.availableRunConfigurations)
            guard let edited else { return }
            model.replaceRunConfigurations(edited)

        case .attachDebugger:
            guard let target = environment.askDebugTarget() else { return }
            await model.attachDebugger(host: target.host, port: target.port)
        case .detachDebugger:
            await model.detachDebugger()
        case .toggleBreakpoint:
            await model.toggleBreakpointAtCursor()
        case .resumeDebuggee:
            await model.debug.resume()
        case .stepOver:
            await model.debug.step(.over)
        case .stepInto:
            await model.debug.step(.into)
        case .stepOut:
            await model.debug.step(.out)
        case .editBreakpointCondition:
            guard let breakpoint = model.breakpointAtCursor() else {
                model.show(StatusMessage(kind: .error, text: "✕ 이 줄에 브레이크포인트가 없습니다"))
                return
            }
            guard let text = environment.askBreakpointCondition(breakpoint.condition?.text ?? "") else { return }
            model.debug.setCondition(text, forBreakpointWithID: breakpoint.id)
            if let error = model.debug.lastError {
                model.show(StatusMessage(kind: .error, text: "✕ \(error)"))
            }

        case .addWatch:
            guard let text = environment.askBreakpointCondition("") else { return }
            await model.debug.toggleWatch(text)
            if let error = model.debug.lastError {
                model.show(StatusMessage(kind: .error, text: "✕ \(error)"))
            }

        case .hotSwapCurrentFile:
            await model.hotSwapCurrentFile()

        case .toggleFieldWatch:
            await model.toggleFieldWatchAtCursor()

        case .evaluateExpression:
            guard let text = environment.askBreakpointCondition(model.debug.lastExpression ?? "") else { return }
            await model.debug.evaluate(text)

        case .toggleBreakOnUncaughtException:
            await model.debug.setExceptionRule(ExceptionBreakpointRule(
                breakOnCaught: model.debug.exceptionRule.breakOnCaught,
                breakOnUncaught: !model.debug.exceptionRule.breakOnUncaught
            ))
        case .toggleBreakOnCaughtException:
            await model.debug.setExceptionRule(ExceptionBreakpointRule(
                breakOnCaught: !model.debug.exceptionRule.breakOnCaught,
                breakOnUncaught: model.debug.exceptionRule.breakOnUncaught
            ))
        case .toggleDebugPanel:
            model.shell.isDebugPanelVisible.toggle()

        case .selectAppearanceSystem:
            model.setAppearancePreference(.system)
        case .selectAppearanceLight:
            model.setAppearancePreference(.light)
        case .selectAppearanceDark:
            model.setAppearancePreference(.dark)

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

        case .toggleRenderView:
            model.toggleRenderView()

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
    /// Asks which JVM to attach to.
    ///
    /// 기본값이 `127.0.0.1:5005` 인 것은 `-agentlib:jdwp` 예제가 거의 다 5005 를 쓰기 때문이다.
    /// 대부분은 그대로 엔터만 치면 된다.
    @MainActor
    public static func presentDebugTargetPrompt() -> (host: String, port: UInt16)? {
        let alert = NSAlert()
        alert.messageText = "디버거 연결"
        alert.informativeText = "JVM 이 -agentlib:jdwp=transport=dt_socket,server=y 로 떠 있어야 합니다."
        alert.addButton(withTitle: "연결")
        alert.addButton(withTitle: "취소")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "127.0.0.1:5005"
        alert.accessoryView = field
        // 대화상자가 뜨자마자 입력란에 커서가 가야 엔터 한 번으로 끝난다.
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let parts = field.stringValue.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]) else { return nil }
        return (host: String(parts[0]), port: port)
    }

    /// 조건을 묻는다. 비우면 조건을 뗀다.
    @MainActor
    public static func presentConditionPrompt(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "브레이크포인트 조건"
        alert.informativeText = "`변수 == 값` 형태만 됩니다 (예: i == 500, name == \"probe\").\n비우면 조건을 뗍니다."
        alert.addButton(withTitle: "적용")
        alert.addButton(withTitle: "취소")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// 실행 설정 편집 창.
    ///
    /// SwiftUI 화면을 모달 창에 올린다 — NSAlert 로는 표를 못 만들고, 시트로 띄우면 어느
    /// 창에 붙일지가 애매하다(패널에서도 메뉴에서도 연다).
    public static func presentRunConfigurationEditor(
        _ configurations: [RunConfiguration]
    ) -> [RunConfiguration]? {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "실행 설정"

        var result: [RunConfiguration]?
        let view = RunConfigurationEditorView(
            configurations: configurations,
            onSave: { edited in
                result = edited
                NSApp.stopModal()
            },
            onCancel: { NSApp.stopModal() }
        )
        window.contentView = NSHostingView(rootView: view)
        window.center()

        NSApp.runModal(for: window)
        // 모달이 끝나면 창을 반드시 닫는다. 안 닫으면 화면 밖에 살아 남아 다음 열기에서
        // 두 개가 뜬다.
        window.orderOut(nil)
        return result
    }

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
