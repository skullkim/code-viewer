import SwiftUI

/// The card shown over the editor when there is no usable edit session (design §3 W-8).
///
/// It covers the editor and nothing else. The index does not depend on Neovim, so the tree
/// and the panels keep working at full brightness — and the card says so, because a user
/// who reads a dead editor as a dead application quits instead of carrying on.
///
/// What it says is `EditSessionOverlay`'s decision; this view only arranges it.
struct EditSessionOverlayView: View {

    let overlay: EditSessionOverlay
    let onAction: (EditSessionOverlayAction) -> Void

    var body: some View {
        ZStack {
            // Only the editor is dimmed. The scrim is inside the editor's frame, so the
            // tree and the panel beside it are untouched.
            DesignTokens.backgroundContent.dynamicColor
                .opacity(Metrics.scrimOpacity)

            card
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(overlay.title)
    }

    private var card: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            icon

            Text(overlay.title)
                .font(.system(size: DesignTokens.Typography.welcomeTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .multilineTextAlignment(.center)

            Text(overlay.detail)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .multilineTextAlignment(.center)

            details

            if let title = overlay.primaryActionTitle, let action = overlay.primaryAction {
                Button(title) { onAction(action) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, DesignTokens.Spacing.extraSmall)
            }
        }
        .padding(DesignTokens.Spacing.extraLarge)
        .frame(maxWidth: Metrics.cardWidth)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .fill(DesignTokens.backgroundElevated.dynamicColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .strokeBorder(DesignTokens.border.dynamicColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowOffsetY)
    }

    /// A spinner while there is something to wait for, a static symbol when there is not.
    @ViewBuilder
    private var icon: some View {
        if overlay.primaryAction == nil {
            MotionSafeSpinner(tone: DesignTokens.accent.dynamicColor, size: Metrics.iconSize)
        } else {
            Image(systemName: overlay.primaryAction == .recheck ? "xmark.octagon" : "exclamationmark.triangle")
                .font(.system(size: Metrics.iconSize))
                .foregroundStyle(iconTone)
        }
    }

    private var iconTone: Color {
        overlay.primaryAction == .recheck
            ? DesignTokens.danger.dynamicColor
            : DesignTokens.warning.dynamicColor
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            if let reason = overlay.reasonText, reason != overlay.title {
                detailRow(label: "사유", value: reason)
            }
            if let version = overlay.requiredVersionText {
                detailRow(label: "버전", value: version)
            }
            if let command = overlay.installCommand {
                detailRow(label: "설치", value: command, isCode: true)
            }
            if !overlay.searchedPaths.isEmpty {
                // Said out loud so a user with Neovim somewhere unusual can see that the
                // application looked, and where.
                detailRow(label: "탐색 경로", value: overlay.searchedPaths.joined(separator: "\n"), isCode: true)
            }
            if let notice = overlay.recoveryNotice {
                Text(notice)
                    .font(.system(size: DesignTokens.Typography.secondarySize))
                    .foregroundStyle(DesignTokens.warning.dynamicColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(label: String, value: String, isCode: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .frame(width: Metrics.detailLabelWidth, alignment: .leading)

            Text(value)
                .font(.system(
                    size: DesignTokens.Typography.secondarySize,
                    design: isCode ? .monospaced : .default
                ))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum Metrics {
        static let scrimOpacity: Double = 0.4
        static let cardWidth: CGFloat = 420
        static let iconSize: CGFloat = 28
        static let detailLabelWidth: CGFloat = 56
        static let shadowOpacity: Double = 0.18
        static let shadowRadius: CGFloat = 28
        static let shadowOffsetY: CGFloat = 8
    }
}
