import SwiftUI
import CodeNavigatorContract

/// Draws a symbol-kind badge (design §4.1: 18×18 rounded square on a 12% tint).
///
/// Shared by the search modal, the definition popover and the reference panel so the same
/// kind never appears as two different marks.
public struct SymbolKindBadgeView: View {

    private let badge: SymbolKindBadge

    public init(kind: SymbolKind) {
        self.badge = SymbolKindBadge.badge(for: kind)
    }

    public var body: some View {
        Text(badge.letter)
            .font(.system(size: Metrics.letterSize, weight: .bold, design: .rounded))
            .foregroundStyle(badge.token.dynamicColor)
            .frame(width: Metrics.side, height: Metrics.side)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(badge.token.dynamicColor.opacity(Metrics.tintOpacity))
            )
            .accessibilityLabel(badge.accessibilityLabel)
    }

    private enum Metrics {
        static let side: CGFloat = 18
        static let letterSize: CGFloat = 10
        static let tintOpacity: Double = 0.12
    }
}
