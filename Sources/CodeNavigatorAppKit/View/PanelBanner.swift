import SwiftUI

/// Which meaning a panel banner carries.
enum PanelBannerTone {
    /// A standing caveat about the results — the approximation notice (REQ-006 AC-3).
    case information
    /// The results are incomplete right now, and will change (index still working).
    case warning
}

/// A tinted notice above a panel's results (design §3 W-5, `.banner`).
///
/// It sits above the list rather than inside it so it survives the empty state. That is the
/// whole point for REQ-006 AC-3: the caveat matters most when there are no results, because
/// "참조 없음" from a name-based search is not the same claim as "이 심볼은 쓰이지 않는다".
struct PanelBanner: View {

    let text: String
    var tone: PanelBannerTone = .information

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.iconSpacing) {
            Image(systemName: tone == .information ? "info.circle" : "exclamationmark.triangle")
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, Metrics.verticalPadding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private var backgroundColor: Color {
        switch tone {
        case .information:
            return DesignTokens.accentDim.dynamicColor
        case .warning:
            return PanelTint.warning.dynamicColor
        }
    }

    private var iconColor: Color {
        switch tone {
        case .information:
            return DesignTokens.accentText.dynamicColor
        case .warning:
            return DesignTokens.warning.dynamicColor
        }
    }

    private enum Metrics {
        static let iconSpacing: CGFloat = 6
        static let verticalPadding: CGFloat = 6
    }
}
