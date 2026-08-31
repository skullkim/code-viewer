import SwiftUI

/// The sheet that stands between a dirty tab and closing it (02b W-13).
///
/// Every choice the user can make is here and none is hidden behind a default they cannot
/// see: the safe action is the one Enter triggers, the destructive one is spelled out, and
/// a failed save leaves the sheet up rather than closing over the files it could not write.
struct TabCloseConfirmationView: View {

    let confirmation: TabCloseConfirmation
    let onAction: (TabCloseConfirmation.Action) -> Void

    private enum Metrics {
        static let width: CGFloat = 420
        static let rowSpacing: CGFloat = 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            Text(confirmation.title)
                .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)

            Text(confirmation.body)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)

            fileList

            if let failureNote = confirmation.failureNote {
                Text(failureNote)
                    .font(.system(size: DesignTokens.Typography.secondarySize))
                    .foregroundStyle(DesignTokens.danger.dynamicColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(DesignTokens.Spacing.large)
        .frame(width: Metrics.width)
        .background(DesignTokens.backgroundWindow.dynamicColor)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            ForEach(Array(confirmation.fileRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DesignTokens.Spacing.small) {
                    // Marked rather than merely listed: when a save half succeeds, the rows
                    // that failed are the only ones the user still has to act on.
                    if confirmation.failedRows.contains(row) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignTokens.danger.dynamicColor)
                            .accessibilityLabel("저장 실패")
                    }
                    Text(row)
                        .font(.system(size: DesignTokens.Typography.bodySize, design: .monospaced))
                        .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    if let reason = confirmation.failureReasons[row] {
                        // Each file keeps its own reason: read-only and "folder is gone" are
                        // different problems with different fixes.
                        Text(reason)
                            .font(.system(size: DesignTokens.Typography.secondarySize))
                            .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                    }
                }
            }
            if let overflow = confirmation.overflowNote {
                Text(overflow)
                    .font(.system(size: DesignTokens.Typography.secondarySize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            if confirmation.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("저장 중")
            }
            Spacer()
            ForEach(confirmation.buttons, id: \.action) { button in
                Button(button.label) { onAction(button.action) }
                    .disabled(!button.isEnabled)
                    // Enter triggers the safe action, never the one that discards work.
                    .keyboardShortcut(shortcut(for: button.action))
            }
        }
    }

    private func shortcut(for action: TabCloseConfirmation.Action) -> KeyboardShortcut? {
        if action == confirmation.defaultAction { return .defaultAction }
        if action == confirmation.cancelAction { return .cancelAction }
        return nil
    }
}
