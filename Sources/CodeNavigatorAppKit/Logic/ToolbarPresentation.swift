import CodeNavigatorContract

/// One toolbar button (design §3 W-1 title bar).
public struct ToolbarButton: Sendable, Hashable, Identifiable {
    public let command: MenuCommand
    public let title: String
    public let shortcutLabel: String
    public let systemImage: String
    public let isEnabled: Bool

    public var id: MenuCommand { command }
}

/// What the 48px title bar shows (design §3 W-1).
public struct ToolbarPresentation: Sendable, Hashable {
    public let projectButtonTitle: String
    public let windowTitle: String
    public let showsDirtyIndicator: Bool
    public let buttons: [ToolbarButton]
    public let showsModeSegment: Bool
    public let showsButtonTitles: Bool
    public let showsShortcutLabels: Bool
}

extension ToolbarPresentation {
    public static let noProjectTitle = "프로젝트 없음"

    public static func make(
        projectName: String?,
        editorStatus: EditorStatus?,
        availability: MenuAvailability,
        layout: ShellLayout
    ) -> ToolbarPresentation {
        ToolbarPresentation(
            projectButtonTitle: projectName ?? noProjectTitle,
            windowTitle: windowTitle(projectName: projectName, editorStatus: editorStatus),
            showsDirtyIndicator: editorStatus?.isDirty ?? false,
            buttons: buttons(availability: availability),
            // §11 ruling 5: the mode segment is built, not optional, and it is never
            // dropped — REQ-010 AC-3 asks for the current mode to be always visible.
            showsModeSegment: true,
            showsButtonTitles: layout.showsToolbarButtonTitles,
            showsShortcutLabels: layout.showsToolbarShortcutLabels
        )
    }

    /// The file being edited, or the project when no file is open yet.
    private static func windowTitle(projectName: String?, editorStatus: EditorStatus?) -> String {
        guard let path = editorStatus?.filePath else {
            return projectName ?? AppMenuBuilder.applicationName
        }
        return PathDisplay.fileName(path)
    }

    /// The three toolbar actions from design §3 W-1.
    ///
    /// Their enabled state is read from `MenuAvailability` rather than decided here, so the
    /// toolbar and the menu cannot end up disagreeing about whether search is usable —
    /// which of the two is right would be impossible for a user to work out.
    private static func buttons(availability: MenuAvailability) -> [ToolbarButton] {
        [
            ToolbarButton(
                command: .symbolSearch,
                title: "심볼",
                shortcutLabel: "⌘P",
                systemImage: "magnifyingglass",
                isEnabled: availability.isEnabled(.symbolSearch)
            ),
            ToolbarButton(
                command: .textSearch,
                title: "전문 검색",
                shortcutLabel: "⇧⌘F",
                systemImage: "text.magnifyingglass",
                isEnabled: availability.isEnabled(.textSearch)
            ),
            ToolbarButton(
                command: .togglePanel,
                title: "패널",
                shortcutLabel: "⌥⌘0",
                systemImage: "sidebar.right",
                isEnabled: availability.isEnabled(.togglePanel)
            ),
        ]
    }
}
