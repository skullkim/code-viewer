import SwiftUI

/// The sandbox chip and its popover (design 02b §3 W-15, INV-6).
///
/// The chip is present with nothing blocked, which is the design's point rather than an
/// oversight: a block the user cannot see becomes "why is this image missing", and the
/// conclusion is that the app is broken. Standing notice costs one chip.
///
/// Tone is neutral, never `danger` — blocking is protection, not failure, and `danger` is
/// reserved for things that actually went wrong.
struct BlockedResourceChipView: View {

    let panel: BlockedResourcePresentation

    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            Text(panel.chipLabel)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .padding(.horizontal, DesignTokens.Spacing.small)
                .padding(.vertical, Metrics.chipVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                        .fill(DesignTokens.backgroundSidebar.dynamicColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.chipLabel)
        .accessibilityHint("차단된 항목을 자세히 보려면 누르세요")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("이 문서에서 차단된 항목")
                .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)

            if let emptyText = panel.emptyText {
                Text(emptyText)
                    .font(.system(size: DesignTokens.Typography.secondarySize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                    ForEach(panel.rows) { row in
                        rowView(row)
                    }
                }
            }

            Divider()

            // The policy text says the blocking cannot be lifted. Without it people hunt for
            // a toggle that does not exist (W-15: there is deliberately no such control).
            Text(panel.policyText)
                .font(.system(size: DesignTokens.Typography.shortcutSize))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(width: Metrics.popoverWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("차단된 항목")
    }

    private func rowView(_ row: BlockedResourceRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            Text(row.label)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .frame(width: Metrics.labelColumnWidth, alignment: .leading)

            Text(GroupedNumberText.string(row.count))
                .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .frame(width: Metrics.countColumnWidth, alignment: .trailing)

            Text(row.detail)
                .font(.system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .lineLimit(1)
                // The host or path identifies what went missing; its front is the part
                // worth losing when the row is narrow.
                .truncationMode(.head)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label) \(row.count)건, \(row.detail)")
    }

    private enum Metrics {
        static let chipVerticalPadding: CGFloat = 2
        static let popoverWidth: CGFloat = 340
        static let labelColumnWidth: CGFloat = 108
        static let countColumnWidth: CGFloat = 28
    }
}
