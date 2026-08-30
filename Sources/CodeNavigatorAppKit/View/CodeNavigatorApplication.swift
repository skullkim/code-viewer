import AppKit
import SwiftUI
import CodeNavigatorCore
import CodeNavigatorContract

/// Starts the windowed application.
///
/// The activation policy is set explicitly because a Swift Package executable does not get
/// one from a bundle automatically; without it the window never becomes key (measured
/// 2026-08-29, ADR-0105).
@MainActor
public enum CodeNavigatorApplication {
    public static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let delegate = ApplicationDelegate()
        application.delegate = delegate
        // Held for the process's lifetime; NSApplication keeps only a weak delegate.
        retainedDelegate = delegate

        application.run()
    }

    /// Builds the window, lays it out once, and reports what happened — then exits.
    ///
    /// Used by `scripts/verify-bundle.sh`, and deliberately more than a bundle-identity
    /// probe. An earlier version returned before `run()` was ever reached, so the gate
    /// proved the binary started and nothing else; the window could have been three grey
    /// placeholders, or could have trapped on first layout, and the gate would still have
    /// been green. This drives the real object graph through a real layout pass.
    ///
    /// It never enters the run loop, so it terminates on its own.
    public static func reportSelfCheck() {
        let identifier = Bundle.main.bundleIdentifier ?? "(none)"
        let executable = Bundle.main.executableURL?.lastPathComponent ?? "(none)"

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let hosting = ApplicationDelegate.makeRootView()
        hosting.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        hosting.layoutSubtreeIfNeeded()

        // The menu bar is installed here too, because it is what claims Command
        // combinations (ADR-0102). A build that shipped without it would give ⌘O and ⌘P to
        // Neovim, and the gate would not have noticed.
        ApplicationDelegate.makeMenuBar().install(into: application)
        let menuCount = application.mainMenu?.items.count ?? 0

        print("bundleIdentifier=\(identifier) executable=\(executable) rootView=laidOut subviews=\(hosting.subviews.count) menus=\(menuCount)")
    }
}

@MainActor private var retainedDelegate: ApplicationDelegate?

/// Builds the object graph and puts the window on screen.
///
/// This is the only place the engine is constructed. Everything below it takes the two
/// contract protocols, so the whole shell can be driven by fakes in tests.
@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var menuBar: MenuBarController?
    private static var sharedModel: AppModel?
    private static var sharedSearch: SearchModel?
    private static var sharedEngine: CodeNavigatorEngine?

    /// Builds the object graph and the root view.
    ///
    /// Shared with the self-check so the gate exercises the same assembly the user gets,
    /// rather than a simplified stand-in that could diverge from it.
    static func makeRootView() -> NSHostingView<MainWindowView> {
        let engine = CodeNavigatorEngine()
        let model = AppModel(
            projectSession: engine.project,
            editorSession: engine.editor,
            workspace: engine,
            storage: UserDefaults.standard,
            now: { Date() }
        )
        let search = SearchModel(projectSession: engine.project)
        model.start()

        sharedEngine = engine
        sharedModel = model
        sharedSearch = search
        return NSHostingView(rootView: MainWindowView(model: model, search: search))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = Self.makeRootView()

        // Installed before the window is shown. The menu bar is not decoration here: it is
        // the mechanism that claims Command combinations, so that every Control chord Vim
        // needs falls through to the editor untouched (ADR-0102, REQ-011 AC-2). Without it
        // ⌘O and ⌘P reach Neovim as <D-o> and <D-p>.
        let menuBar = Self.makeMenuBar()
        menuBar.install()
        self.menuBar = menuBar

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeNavigator"
        // Design §4.4: the window may not be shrunk below what the three-area layout needs.
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the menu bar against whatever models exist.
    ///
    /// Shared with the self-check so the gate installs the same menu the user gets.
    static func makeMenuBar() -> MenuBarController {
        MenuBarController(
            availability: {
                sharedModel?.menuAvailability
                    ?? MenuAvailability(inputMode: .vim, sessionState: .notStarted, hasOpenProject: false)
            },
            perform: { command in
                guard let model = sharedModel, let search = sharedSearch else { return }
                Task { await MenuCommandRouter.perform(command, model: model, search: search) }
            },
            recentProjects: { sharedModel?.recentProjects.projects() ?? [] },
            openRecentProject: { path in
                guard let model = sharedModel else { return }
                Task { await model.openProject(at: URL(fileURLWithPath: path)) }
            }
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Shuts the embedded Neovim down before the application exits.
    ///
    /// `applicationWillTerminate` cannot do this: it is synchronous, and a `Task` started
    /// there does not get to run before the process goes away — which leaves the child
    /// reparented to launchd. Measured: those orphans survive for hours, ignore `SIGTERM`,
    /// and accumulate every time the app is opened and closed. So termination is deferred
    /// until the shutdown actually completes, which takes about 20ms.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine = Self.sharedEngine else {
            return .terminateNow
        }
        Task {
            await engine.shutDown()
            await MainActor.run { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}
