import Foundation
import CoreGraphics
import Observation

/// What the shell remembers about its own arrangement between runs (REQ-011 AC-3).
///
/// REQ-011 AC-3 names four things that come back: the window's size and position, the split
/// ratio, which side areas are showing, and the recent projects. All but the last are kept
/// here, so they restore through one mechanism a test can drive.
///
/// The window frame is deliberately not left to AppKit's frame autosave. Autosave works,
/// but it would put one of those four values in an opaque side channel under its own key,
/// unreachable from a test — and the case that actually breaks is the one most worth
/// testing: a frame saved on a monitor that is no longer attached. `WindowFrameFit` owns
/// that rule, and this class only stores and returns what it decides.
///
/// Every value is clamped on the way in as well as on the way out. Stored preferences
/// outlive the code that wrote them: a width saved on a wider monitor, or a file edited by
/// hand, must not be able to produce a shell with no editor in it.
@MainActor
@Observable
public final class ShellPreferences {

    public var treeWidth: CGFloat {
        didSet { write(treeWidth, forKey: Self.treeWidthKey) }
    }

    public var panelWidth: CGFloat {
        didSet { write(panelWidth, forKey: Self.panelWidthKey) }
    }

    public var isTreeVisible: Bool {
        didSet { write(isTreeVisible, forKey: Self.treeVisibleKey) }
    }

    public var isPanelVisible: Bool {
        didSet { write(isPanelVisible, forKey: Self.panelVisibleKey) }
    }

    private let storage: KeyValueStore

    static let treeWidthKey = "shell.treeWidth"
    static let panelWidthKey = "shell.panelWidth"
    static let treeVisibleKey = "shell.treeVisible"
    static let panelVisibleKey = "shell.panelVisible"
    static let windowFrameKey = "shell.windowFrame"
    static let openTabsKey = "shell.openTabs"
    static let activeTabKey = "shell.activeTab"

    public init(storage: KeyValueStore) {
        self.storage = storage
        self.treeWidth = ShellLayout.clampTreeWidth(
            Self.readWidth(storage, forKey: Self.treeWidthKey) ?? ShellLayout.Metrics.treeDefaultWidth
        )
        self.panelWidth = ShellLayout.clampPanelWidth(
            Self.readWidth(storage, forKey: Self.panelWidthKey) ?? ShellLayout.Metrics.panelDefaultWidth
        )
        // Both areas show by default: a first run should look like design §7's wireframe,
        // not like a window somebody had already tidied away.
        self.isTreeVisible = Self.readFlag(storage, forKey: Self.treeVisibleKey) ?? true
        self.isPanelVisible = Self.readFlag(storage, forKey: Self.panelVisibleKey) ?? true
    }

    /// Applies a splitter drag, clamped to what the design allows.
    public func setTreeWidth(_ width: CGFloat) {
        treeWidth = ShellLayout.clampTreeWidth(width)
    }

    public func setPanelWidth(_ width: CGFloat) {
        panelWidth = ShellLayout.clampPanelWidth(width)
    }

    // MARK: 열린 탭 (REQ-012 AC-4)

    /// The projects that were open, in the user's order, and which one was in front.
    ///
    /// Stored as paths rather than the engine's tab identifiers: identifiers are per-run
    /// (a UUID minted when a project opens), so a stored one would name nothing after a
    /// relaunch. The path is what survives a restart.
    public func setOpenTabs(rootPaths: [String], activeRootPath: String?) {
        storage.setData(try? JSONEncoder().encode(rootPaths), forKey: Self.openTabsKey)
        storage.setData(activeRootPath.flatMap { $0.data(using: .utf8) }, forKey: Self.activeTabKey)
    }

    public var openTabRootPaths: [String] {
        guard let data = storage.data(forKey: Self.openTabsKey),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return paths
    }

    public var activeTabRootPath: String? {
        storage.data(forKey: Self.activeTabKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: 창 프레임 (REQ-011 AC-3)

    /// Records where the window ended up, to reopen there next time.
    public func setWindowFrame(_ frame: CGRect) {
        // Stored unfitted, on purpose. Which screens exist is a fact about launch time, not
        // about save time: a frame that is off-screen today may be exactly right once the
        // external display is plugged back in.
        storage.setData(Self.encode(frame), forKey: Self.windowFrameKey)
    }

    /// Where to open the window, or nil on a first run.
    ///
    /// - Parameter visibleFrames: the visible frame of every screen attached *now*.
    public func windowFrame(forVisibleFrames visibleFrames: [CGRect]) -> CGRect? {
        guard let frame = Self.readFrame(storage, forKey: Self.windowFrameKey) else {
            return nil
        }
        return WindowFrameFit.fit(frame, intoVisibleFrames: visibleFrames)
    }

    private static func encode(_ frame: CGRect) -> Data? {
        "\(Double(frame.origin.x)),\(Double(frame.origin.y)),\(Double(frame.width)),\(Double(frame.height))"
            .data(using: .utf8)
    }

    private static func readFrame(_ storage: KeyValueStore, forKey key: String) -> CGRect? {
        guard let data = storage.data(forKey: key),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let parts = text.split(separator: ",").map(String.init)
        guard parts.count == 4 else {
            return nil
        }

        let values = parts.compactMap(Double.init)
        // Damaged or hand-edited preferences read as "no saved frame" rather than as a
        // window at NaN, which would open nowhere at all (REQ-NF-004).
        guard values.count == 4, values.allSatisfy(\.isFinite) else {
            return nil
        }

        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    // MARK: 저장

    private func write(_ width: CGFloat, forKey key: String) {
        storage.setData(String(Double(width)).data(using: .utf8), forKey: key)
    }

    private func write(_ flag: Bool, forKey key: String) {
        storage.setData((flag ? "1" : "0").data(using: .utf8), forKey: key)
    }

    private static func readWidth(_ storage: KeyValueStore, forKey key: String) -> CGFloat? {
        guard let data = storage.data(forKey: key),
              let text = String(data: data, encoding: .utf8),
              let value = Double(text),
              value.isFinite
        else {
            // Unreadable or nonsense: fall back to the default rather than refuse to draw.
            return nil
        }
        return CGFloat(value)
    }

    private static func readFlag(_ storage: KeyValueStore, forKey key: String) -> Bool? {
        guard let data = storage.data(forKey: key),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text == "1"
    }
}
