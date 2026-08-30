import SwiftUI
import CodeNavigatorContract

/// The index status chip and its details popover (design §3 W-10, REQ-009 · REQ-002 AC-4).
///
/// A drop-in replacement for the status bar's generic chip, for the index chip only. The
/// index is the one chip that answers "are these results current" (INV-1) and the one that
/// opens — the skip count behind it is the sole place REQ-002 AC-4 surfaces.
///
/// Everything it says comes from `StatusBarPresentation` and `IndexDetailsPresentation`;
/// this view chooses no wording of its own.
struct IndexStatusChipView: View {

    let chip: StatusChip
    let indexState: IndexState
    let details: IndexDetailsPresentation

    @State private var isShowingDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            chipContent
        }
        .buttonStyle(.plain)
        .help(chip.tooltip ?? "")
        .accessibilityLabel("인덱스 상태: \(chip.label)")
        .accessibilityHint("자세히 보려면 누르세요")
        .accessibilityAddTraits(.updatesFrequently)
        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
            IndexDetailsPopover(details: details)
        }
    }

    private var chipContent: some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            indicator

            Text(chip.label)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .lineLimit(1)

            if let progress = chip.progress, IndexChipIndicator.showsProgressBar(for: indexState) {
                progressBar(progress)
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var indicator: some View {
        switch IndexChipIndicator.indicator(for: indexState) {
        case .dot:
            dot

        case .pulsingDot:
            dot
                .opacity(isPulsing ? Metrics.pulseMinimumOpacity : 1)
                .animation(pulseAnimation, value: isPulsing)
                .onAppear { isPulsing = !reduceMotion }
                .onDisappear { isPulsing = false }

        case .spinner:
            MotionSafeSpinner(tone: tone, size: Metrics.indicatorSize)
        }
    }

    private var dot: some View {
        Circle()
            .fill(tone)
            .frame(width: Metrics.dotSize, height: Metrics.dotSize)
    }

    /// Nil when motion is reduced, so the dot settles at full opacity instead of freezing
    /// mid-fade (§4.5).
    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Metrics.pulseDuration).repeatForever(autoreverses: true)
    }

    private func progressBar(_ progress: IndexProgress) -> some View {
        // `total` is 0 while the file list is still being built; a bar driven by that would
        // sit at zero and look stuck rather than starting.
        ProgressView(value: progress.fractionCompleted)
            .progressViewStyle(.linear)
            .frame(width: Metrics.progressBarWidth)
            .tint(tone)
            .accessibilityLabel("진행률")
            .accessibilityValue("\(progress.completed) / \(progress.total)")
    }

    private var tone: Color {
        switch chip.tone {
        case .success: return DesignTokens.success.dynamicColor
        case .accent: return DesignTokens.accentText.dynamicColor
        case .purple: return DesignTokens.purple.dynamicColor
        case .warning: return DesignTokens.warning.dynamicColor
        case .danger: return DesignTokens.danger.dynamicColor
        case .neutral: return DesignTokens.textSecondary.dynamicColor
        }
    }

    fileprivate enum Metrics {
        static let dotSize: CGFloat = 6
        static let indicatorSize: CGFloat = 10
        static let progressBarWidth: CGFloat = 48
        static let pulseDuration: Double = 0.9
        static let pulseMinimumOpacity: Double = 0.35
        static let popoverWidth: CGFloat = 260
    }
}

/// The popover behind the chip: what the index holds, and what it left out.
private struct IndexDetailsPopover: View {

    let details: IndexDetailsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(details.title)
                .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)

            if let progress = details.progress {
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(.linear)
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                ForEach(details.rows) { row in
                    detailRow(row)
                }
            }

            if let notice = details.skippedNotice {
                Text(notice)
                    .font(.system(size: DesignTokens.Typography.shortcutSize))
                    .foregroundStyle(DesignTokens.warning.dynamicColor)
            }

            if let stale = details.staleNotice {
                Text(stale)
                    .font(.system(size: DesignTokens.Typography.shortcutSize))
                    .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(width: IndexStatusChipView.Metrics.popoverWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("인덱스 상세")
    }

    private func detailRow(_ row: IndexDetailRow) -> some View {
        HStack {
            Text(row.label)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)

            Spacer(minLength: DesignTokens.Spacing.medium)

            Text(row.value)
                .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                // The skip count is the one figure that changes meaning above zero, so it
                // is the one figure that changes colour.
                .foregroundStyle(
                    row.isWarning
                        ? DesignTokens.warning.dynamicColor
                        : DesignTokens.textPrimary.dynamicColor
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label) \(row.value)")
    }
}
