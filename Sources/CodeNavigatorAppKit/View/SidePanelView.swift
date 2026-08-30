import SwiftUI
import CodeNavigatorContract

/// Which tab of the right panel is showing (design §3 W-1).
public enum SidePanelTab: String, Sendable, Hashable, CaseIterable, Identifiable {
    case references
    case textSearch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .references:
            return "참조"
        case .textSearch:
            return "검색"
        }
    }
}

/// The right-hand panel: a tab header over one of the two search surfaces.
///
/// The header belongs here rather than in either panel, so the two cannot drift into
/// drawing their own differently.
struct SidePanelView<ReferenceContent: View, SearchContent: View>: View {

    @Binding var selectedTab: SidePanelTab
    @ViewBuilder let referenceContent: () -> ReferenceContent
    @ViewBuilder let searchContent: () -> SearchContent

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
            Divider()

            switch selectedTab {
            case .references:
                referenceContent()
            case .textSearch:
                searchContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundPanel.dynamicColor)
    }

    private var tabHeader: some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            ForEach(SidePanelTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.small)
        .padding(.vertical, DesignTokens.Spacing.small)
    }

    private func tabButton(_ tab: SidePanelTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            selectedTab = tab
        } label: {
            Text(tab.title)
                .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                .foregroundStyle(isSelected ? DesignTokens.accentText.dynamicColor : DesignTokens.textSecondary.dynamicColor)
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, DesignTokens.Spacing.extraSmall)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .fill(isSelected ? DesignTokens.backgroundHover.dynamicColor : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
