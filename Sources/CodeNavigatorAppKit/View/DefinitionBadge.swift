import SwiftUI

/// The `[정의]` marker on a reference row (design §3 W-5, REQ-006 AC-2).
///
/// A definition appears in the reference list alongside the usages, and AC-2 asks for it to
/// be told apart. Outlined rather than filled: it marks one row in a list the user is
/// scanning, and a filled badge would out-shout the preview text that row exists to show.
struct DefinitionBadge: View {

    var body: some View {
        Text("정의")
            .font(.system(size: Metrics.fontSize, weight: .bold))
            .foregroundStyle(DesignTokens.accentText.dynamicColor)
            .padding(.horizontal, Metrics.horizontalPadding)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(DesignTokens.accentText.dynamicColor, lineWidth: 1)
            }
            .fixedSize()
            // The row's accessibility label already says "정의"; announcing it twice makes
            // the row read as though there were two of them.
            .accessibilityHidden(true)
    }

    private enum Metrics {
        static let fontSize: CGFloat = 10
        static let horizontalPadding: CGFloat = 4
        static let radius: CGFloat = 3
    }
}
