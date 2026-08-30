import SwiftUI

/// The bar shown when a search stopped at its cap (design §3 W-6, `.cap-bar`).
///
/// It exists so a truncated result set is never read as a complete one. 03 §3.1: `total` on
/// a truncated search is what was observed before stopping, not what the repository holds —
/// so the wording the presentation supplies says "표시" rather than claiming a repository count.
struct PanelLimitBar: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: DesignTokens.Typography.secondarySize))
            .foregroundStyle(DesignTokens.warning.dynamicColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, Metrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelTint.warning.dynamicColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.vertical, DesignTokens.Spacing.small)
    }

    private enum Metrics {
        static let verticalPadding: CGFloat = 6
    }
}
