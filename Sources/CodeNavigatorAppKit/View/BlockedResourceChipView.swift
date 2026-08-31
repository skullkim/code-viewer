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

/// The box left where a blocked image was (design 02b §3 W-15).
///
/// The space is not left empty. An image that vanishes takes the layout with it and gives
/// no reason; a box that says what it was and where it came from does both.
struct BlockedResourcePlaceholder: View {

    let kind: BlockedResourceKind
    /// The host for a remote resource, or the original path for a local one.
    let detail: String
    let alternativeText: String?
    /// The original dimensions, when the document gave them. Height falls back to 88.
    var aspectRatio: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.lineSpacing) {
            Text("🛡 \(title)")
                .font(.system(size: DesignTokens.Typography.panelTitleSize))
            Text(detail)
                .font(.system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            if let alternativeText, !alternativeText.isEmpty {
                Text("alt: \(alternativeText)")
                    .font(.system(size: DesignTokens.Typography.shortcutSize))
                    .lineLimit(2)
            }
        }
        // Neutral, not danger — blocking is protection, not an error (W-15).
        .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: aspectRatio == nil ? Metrics.fallbackHeight : nil)
        .background(DesignTokens.backgroundSidebar.dynamicColor)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(
                    DesignTokens.borderStrong.dynamicColor,
                    style: StrokeStyle(lineWidth: 1, dash: Metrics.dash)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("차단된 \(kind.label): \(alternativeText ?? detail)")
    }

    private var title: String {
        kind == .outsideProjectRoot
            ? "프로젝트 폴더 밖의 파일은 표시하지 않습니다"
            : "\(kind.label)가 차단되었습니다"
    }

    private enum Metrics {
        static let lineSpacing: CGFloat = 2
        static let fallbackHeight: CGFloat = 88
        static let dash: [CGFloat] = [4, 3]
    }
}
