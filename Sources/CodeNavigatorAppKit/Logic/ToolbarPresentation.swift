import CodeNavigatorContract

/// One toolbar button (design §3 W-1 title bar).
public struct ToolbarButton: Sendable, Hashable, Identifiable {
    public let command: MenuCommand
    public let title: String
    public let shortcutLabel: String
    public let systemImage: String
    public let isEnabled: Bool

    /// 토글 버튼이 눌려 있는가. 토글이 아닌 버튼은 `false` 로 남는다.
    ///
    /// 버튼이 스스로 판단하지 않고 받는다 — 02b F-14 1 은 같은 사실을 세 곳에 그리고,
    /// 셋이 각자 계산하면 어긋난 화면을 만든다.
    public var isOn: Bool = false

    public var id: MenuCommand { command }
}

/// What the 48px title bar shows (design §3 W-1).
public struct ToolbarPresentation: Sendable, Hashable {
    public let windowTitle: String
    public let showsDirtyIndicator: Bool
    public let buttons: [ToolbarButton]
    public let showsModeSegment: Bool
    public let showsButtonTitles: Bool
    public let showsShortcutLabels: Bool
}

extension ToolbarPresentation {

    public static func make(
        projectName: String?,
        editorStatus: EditorStatus?,
        availability: MenuAvailability,
        layout: ShellLayout,
        renderView: RenderViewState = .noDocument
    ) -> ToolbarPresentation {
        ToolbarPresentation(
            windowTitle: windowTitle(projectName: projectName, editorStatus: editorStatus),
            showsDirtyIndicator: editorStatus?.isDirty ?? false,
            buttons: buttons(availability: availability, renderView: renderView),
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
    private static func buttons(
        availability: MenuAvailability,
        renderView: RenderViewState
    ) -> [ToolbarButton] {
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
            ToolbarButton(
                command: .toggleRenderView,
                title: "렌더",
                shortcutLabel: "⇧⌘V",
                systemImage: "doc.richtext",
                // 렌더할 수 없는 파일에서는 애초에 못 누른다(02b F-14 4) — 누르게 두고
                // 에러를 띄우는 것보다 누르기 전에 말해 주는 쪽이 낫다.
                isEnabled: availability.isEnabled(.togglePanel) && renderView.isRenderable,
                isOn: renderView.isShowingRender
            ),
        ]
    }
}
