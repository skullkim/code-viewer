import SwiftUI

/// The file a run of results belongs to (design §3 W-5 · W-6, `.pgroup`).
///
/// Grouping is the panel's job, not the engine's: results arrive already sorted by path and
/// then line, and `FileGrouping` preserves that order rather than imposing one of its own.
struct PanelGroupHeader: View {

    let path: String

    var body: some View {
        Text(path)
            .font(.system(size: DesignTokens.Typography.secondarySize, weight: .semibold))
            .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            .lineLimit(1)
            // The file name is what identifies the group; leading directories are the part
            // that can be dropped when the panel is narrow.
            .truncationMode(.head)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.top, DesignTokens.Spacing.small)
            .padding(.bottom, Metrics.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.backgroundPanel.dynamicColor)
            .accessibilityAddTraits(.isHeader)
    }

    private enum Metrics {
        static let bottomPadding: CGFloat = 2
    }
}
