import SwiftUI
import CodeNavigatorContract

/// The status bar (design §3 W-7) — this app's single surface for state.
///
/// What it says is decided by `StatusBarPresentation`, which is covered by tests; this
/// view only arranges it. The input mode segment and the index chip are never dropped at
/// any window width, because they answer "which keys am I typing" (REQ-010 AC-3) and "are
/// these results current" (REQ-009).
struct StatusBarView: View {
    let layout: ShellLayout
    var presentation: StatusBarPresentation?
    /// The index chip is interactive — it opens the details popover that carries
    /// `skippedCount`, the only place REQ-002 AC-4 becomes visible — so it needs the state
    /// behind the chip, not just the chip's label.
    var indexState: IndexState = .notIndexed
    var indexDetails: IndexDetailsPresentation?

    init(
        layout: ShellLayout,
        presentation: StatusBarPresentation? = nil,
        indexState: IndexState = .notIndexed,
        indexDetails: IndexDetailsPresentation? = nil
    ) {
        self.layout = layout
        self.presentation = presentation
        self.indexState = indexState
        self.indexDetails = indexDetails
    }

    var body: some View {
        let bar = presentation ?? StatusBarPresentation.make(
            sessionState: .notStarted,
            editorStatus: nil,
            indexState: .notIndexed,
            inputMode: .vim,
            message: nil,
            projectRoot: nil,
            layout: layout
        )

        HStack(spacing: DesignTokens.Spacing.small) {
            modeSegment(bar.modeSegment)

            if let path = bar.path {
                pathLabel(path, isDirty: bar.showsDirtyIndicator)
            }

            Spacer(minLength: DesignTokens.Spacing.small)

            Text(bar.centerText)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(centerColor(for: bar.centerRole))
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: DesignTokens.Spacing.small)

            if let cursorText = bar.cursorText {
                Text(cursorText)
                    .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                    .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            }

            indexChip(bar.indexChip)
            chip(bar.sessionChip)
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .frame(height: layout.statusBarHeight)
        .background(DesignTokens.backgroundStatus.dynamicColor)
        .accessibilityElement(children: .contain)
    }

    private func modeSegment(_ segment: InputModeSegment) -> some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Text(segment.primaryLabel)
                .font(.system(size: DesignTokens.Typography.secondarySize, weight: .semibold))
                .foregroundStyle(color(for: segment.tone))
            Text(segment.secondaryLabel)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
        }
        .fixedSize()
        .accessibilityLabel("입력 모드: \(segment.primaryLabel) \(segment.secondaryLabel)")
    }

    private func pathLabel(_ path: String, isDirty: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Text(path)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.head)
            if isDirty {
                // The dirty marker appears in three places at once (title, tree, status
                // bar); no single dot is load-bearing on its own.
                Circle()
                    .fill(DesignTokens.warningSolid.dynamicColor)
                    .frame(width: 6, height: 6)
                    .help("더티 버퍼 — 저장하지 않은 변경")
            }
        }
    }

    /// The index chip, with its spinner, pulse and progress bar (design §3 W-10).
    ///
    /// Falls back to the plain chip only when no details have been supplied, which happens
    /// in previews and in the status bar's own tests.
    @ViewBuilder
    private func indexChip(_ statusChip: StatusChip) -> some View {
        if let indexDetails {
            IndexStatusChipView(chip: statusChip, indexState: indexState, details: indexDetails)
        } else {
            chip(statusChip)
        }
    }

    private func chip(_ chip: StatusChip) -> some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Circle()
                .fill(color(for: chip.tone))
                .frame(width: 6, height: 6)
            Text(chip.label)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .lineLimit(1)
        }
        .fixedSize()
        .help(chip.tooltip ?? "")
    }

    private func color(for tone: StatusTone) -> Color {
        switch tone {
        case .success: return DesignTokens.success.dynamicColor
        case .accent: return DesignTokens.accentText.dynamicColor
        case .purple: return DesignTokens.purple.dynamicColor
        case .warning: return DesignTokens.warning.dynamicColor
        case .danger: return DesignTokens.danger.dynamicColor
        case .neutral: return DesignTokens.textSecondary.dynamicColor
        }
    }

    private func centerColor(for role: StatusCenterRole) -> Color {
        switch role {
        case .hint: return DesignTokens.textTertiary.dynamicColor
        case .success: return DesignTokens.success.dynamicColor
        case .error, .persistentError: return DesignTokens.danger.dynamicColor
        }
    }
}
