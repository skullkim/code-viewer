import SwiftUI
import CodeNavigatorContract

/// The popover shown when a name has more than one definition (design §3 W-4, REQ-005 AC-2).
///
/// Rows are a fixed height and every line truncates rather than wraps: a long signature
/// that grew its row would push the candidates below it out of the card, which the designer
/// measured happening in the prototype.
struct DefinitionCandidatesView: View {

    let presentation: DefinitionCandidatePresentation
    /// The cursor's cell, in the coordinate space this view is laid out in.
    ///
    /// Optional so the popover still draws for a caller that has no cursor to point at; it
    /// then centres, which is what it did before it could anchor at all.
    var anchor: CGRect?
    let onSelect: (SymbolDefinition) -> Void
    let onShowReferences: () -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = fittedHeight(in: proxy.size)
            card(height: height)
                .offset(offset(in: proxy.size, cardHeight: height))
        }
    }

    /// Where the card sits, so it never covers the line it is about (design §3 W-4).
    private func offset(in area: CGSize, cardHeight: CGFloat) -> CGSize {
        guard let anchor else {
            return CGSize(
                width: max(0, (area.width - Metrics.width) / 2),
                height: max(0, (area.height - cardHeight) / 2)
            )
        }

        let placement = PopoverPlacement.place(
            anchor: anchor,
            contentSize: CGSize(width: Metrics.width, height: cardHeight),
            in: area
        )
        return CGSize(width: placement.origin.x, height: placement.origin.y)
    }

    private func fittedHeight(in area: CGSize) -> CGFloat {
        guard let anchor else {
            return naturalHeight
        }
        return Self.fittedHeight(natural: naturalHeight, anchor: anchor, area: area)
    }

    private var naturalHeight: CGFloat {
        Self.cardHeight(rowCount: presentation.rows.count)
    }

    /// The card height that still leaves the cursor's line uncovered.
    ///
    /// When neither side has room for the whole card, `PopoverPlacement` keeps it inside the
    /// area — which in a short window means putting it on top of the cursor. Reading a
    /// candidate list while the line it refers to is hidden is the one thing this popover
    /// must not do, so the card gives up height instead of position. The list already
    /// scrolls, so the candidates are all still reachable.
    static func fittedHeight(natural: CGFloat, anchor: CGRect, area: CGSize) -> CGFloat {
        let margins = PopoverPlacement.anchorGap + PopoverPlacement.edgeMargin
        let roomBelow = area.height - anchor.maxY - margins
        let roomAbove = anchor.minY - margins
        let room = max(roomBelow, roomAbove)

        guard natural > room else {
            return natural
        }
        // Below the floor the card stops being readable, and an unreadable popover that
        // avoids the cursor is no better than a readable one that covers it.
        return max(Self.cardHeight(rowCount: 1), room)
    }

    /// The card's height, computed rather than measured.
    ///
    /// The flip decision depends on this number: an estimate that runs short reports room
    /// below that does not exist, and the popover lands on the cursor it was supposed to
    /// stay clear of. Every band of the card has a fixed height so this can be exact.
    static func cardHeight(rowCount: Int) -> CGFloat {
        let listHeight = min(CGFloat(rowCount) * Metrics.rowHeight, Metrics.listMaximumHeight)
        return Metrics.headerHeight
            + Metrics.dividerHeight
            + listHeight
            + Metrics.dividerHeight
            + Metrics.footerHeight
    }

    private func card(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            rows(listHeight: Self.listHeight(inCardHeight: height))
            Divider()
            footer
        }
        .frame(width: Metrics.width, height: height)
        .background(DesignTokens.backgroundElevated.dynamicColor)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.return) { confirm() }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.symbolName) \(presentation.headerDetail)")
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Text(presentation.symbolName)
                .font(.system(size: DesignTokens.Typography.bodySize, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
            Text(presentation.headerDetail)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
        }
        .lineLimit(1)
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .frame(height: Metrics.headerHeight, alignment: .leading)
    }

    /// The list's share of the card, once the fixed bands have taken theirs.
    static func listHeight(inCardHeight cardHeight: CGFloat) -> CGFloat {
        max(0, cardHeight - Metrics.headerHeight - Metrics.footerHeight - 2 * Metrics.dividerHeight)
    }

    private func rows(listHeight: CGFloat) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isSelected: index == selectedIndex)
                            .id(row.id)
                            .onTapGesture { onSelect(row.definition) }
                    }
                }
            }
            .frame(height: listHeight)
            .onChange(of: selectedIndex) { _, index in
                guard presentation.rows.indices.contains(index) else {
                    return
                }
                scroll.scrollTo(presentation.rows[index].id)
            }
        }
    }

    private func rowView(_ row: DefinitionCandidateRow, isSelected: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            SymbolKindBadgeView(kind: row.definition.kind)

            Text(row.signature)
                .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                .foregroundStyle(isSelected ? .white : DesignTokens.textPrimary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DesignTokens.Spacing.small)

            Text(row.location)
                .font(.system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(Metrics.selectedSecondaryOpacity) : DesignTokens.textTertiary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(-1)
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .frame(height: Metrics.rowHeight)
        .background(isSelected ? DesignTokens.accent.dynamicColor : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            Button(presentation.footerText, action: onShowReferences)
                .buttonStyle(.link)
                .font(.system(size: DesignTokens.Typography.secondarySize))

            Spacer()

            Text(presentation.keyHintText)
                .font(.system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .frame(height: Metrics.footerHeight)
    }

    // MARK: 키보드

    private func move(by offset: Int) -> KeyPress.Result {
        guard !presentation.rows.isEmpty else {
            return .ignored
        }
        // Wrapping keeps ↑ from the first row useful; a list this short has no far end.
        let count = presentation.rows.count
        selectedIndex = (selectedIndex + offset + count) % count
        return .handled
    }

    private func confirm() -> KeyPress.Result {
        guard presentation.rows.indices.contains(selectedIndex) else {
            return .ignored
        }
        onSelect(presentation.rows[selectedIndex].definition)
        return .handled
    }

    private enum Metrics {
        static let width: CGFloat = 460
        static let rowHeight: CGFloat = 30
        static let listMaximumHeight: CGFloat = 240
        /// Fixed so `cardHeight` can be exact rather than estimated.
        static let headerHeight: CGFloat = 34
        static let footerHeight: CGFloat = 32
        static let dividerHeight: CGFloat = 1
        static let selectedSecondaryOpacity: Double = 0.75
    }
}
