import SwiftUI

/// The main window (design §3 W-1).
///
/// The order of the stack is the point. The status bar is placed with a fixed height and
/// the content takes what remains, so the editor is never in a position to push the status
/// bar off screen — the failure the designer hit in the prototype at 820x620 (ADR-0104).
/// The status bar is the only permanent surface for the input mode (REQ-010 AC-3) and the
/// index state (REQ-009), so losing it breaks two acceptance criteria at once.
public struct MainWindowView: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let layout = ShellLayout.resolve(windowSize: proxy.size)

            VStack(spacing: 0) {
                contentAreas(layout: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                StatusBarView(layout: layout)
                    .frame(height: layout.statusBarHeight)
            }
        }
    }

    @ViewBuilder
    private func contentAreas(layout: ShellLayout) -> some View {
        HStack(spacing: 0) {
            if layout.treePlacement == .column {
                PlaceholderPane(title: "파일 트리", token: DesignTokens.backgroundSidebar)
                    .frame(width: layout.treeWidth)
                Divider()
            }

            PlaceholderPane(title: "Neovim 그리드", token: DesignTokens.backgroundContent)
                .frame(maxWidth: .infinity)

            if layout.panelPlacement == .column {
                Divider()
                PlaceholderPane(title: "참조 · 검색", token: DesignTokens.backgroundPanel)
                    .frame(width: layout.panelWidth)
            }
        }
    }
}

/// A stand-in until the real panes land, so the shell's layout can be seen and compared
/// against the prototype screenshots before the panes exist.
struct PlaceholderPane: View {
    let title: String
    let token: ColorToken

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            token.color(for: colorScheme)
            Text(title)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textTertiary.color(for: colorScheme))
        }
    }
}

extension ColorToken {
    /// Resolves the token for SwiftUI's current appearance (REQ-011 AC-4).
    func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? swiftUIDark : swiftUILight
    }
}
