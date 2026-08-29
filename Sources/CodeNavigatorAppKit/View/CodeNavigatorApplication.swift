import AppKit
import SwiftUI

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
}

@MainActor private var retainedDelegate: ApplicationDelegate?

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeNavigator"
        // Design §4.4: the window may not be shrunk below what the three-area layout needs.
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = NSHostingView(rootView: MainWindowView())
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
