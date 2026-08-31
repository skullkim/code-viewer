import SwiftUI

/// Reports the projects that did not come back (02b W-12, REQ-012 AC-6).
///
/// One sheet for all of them. Five sheets would teach the reader to hit 확인 five times
/// without looking, and the one that mattered would go past unread.
struct MissingTabsSheetView: View {

    let presentation: MissingTabsPresentation
    let onConfirm: () -> Void

    private enum Metrics {
        static let width: CGFloat = 440
        static let rowSpacing: CGFloat = 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            HStack(spacing: DesignTokens.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.warning.dynamicColor)
                Text(presentation.title)
                    .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
            }

            Text(presentation.body)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                ForEach(presentation.rows) { row in
                    Text(row.text)
                        .font(.system(size: DesignTokens.Typography.secondarySize))
                        .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("복원하지 못한 프로젝트")

            HStack {
                Spacer()
                Button(presentation.confirmLabel, action: onConfirm)
                    // Both the default and the cancel action: there is only one way out, so
                    // Escape has to work as well as Return (02b W-12 accessibility).
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.large)
        .frame(width: Metrics.width)
        .background(DesignTokens.backgroundWindow.dynamicColor)
    }
}
