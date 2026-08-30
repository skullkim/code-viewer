import SwiftUI

/// The line number on a result row (design §3 W-5 · W-6, `.pitem .loc`).
///
/// Fixed minimum width so the previews beside it line up into a column; a ragged left edge
/// makes a list of code lines much harder to scan than the numbers are worth.
struct PanelLineNumberLabel: View {

    let line: Int

    var body: some View {
        Text("\(line)")
            .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
            .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            .frame(minWidth: Metrics.minimumWidth, alignment: .trailing)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private enum Metrics {
        static let minimumWidth: CGFloat = 26
    }
}
