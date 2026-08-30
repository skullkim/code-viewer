import SwiftUI
import CodeNavigatorContract

/// The reference panel (design §3 W-5, REQ-006).
///
/// The banner is the part that carries a requirement rather than a decoration. Reference
/// search has no type resolution, so REQ-006 AC-3 asks for that caveat to be permanent —
/// and `ReferencePresentation` keeps it on the empty state too, where a bare "참조 없음"
/// would otherwise sound like a certainty the search cannot offer. Drawing it outside the
/// branch that swaps list for message is what makes that hold.
public struct ReferencePanelView: View {

    private let panel: ReferencePresentation
    private let selectedReferenceID: String?
    private let onSelect: (Reference) -> Void

    @State private var hoveredID: String?

    public init(
        panel: ReferencePresentation,
        selectedReferenceID: String? = nil,
        onSelect: @escaping (Reference) -> Void
    ) {
        self.panel = panel
        self.selectedReferenceID = selectedReferenceID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headerText = panel.headerText {
                Text(headerText)
                    .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, DesignTokens.Spacing.large)
                    .padding(.top, DesignTokens.Spacing.medium)
                    .accessibilityAddTraits(.isHeader)
            }

            // Outside every branch below: REQ-006 AC-3 says "상시".
            PanelBanner(text: panel.approximationNotice ?? ReferencePresentation.approximationNoticeText)

            if let partialResultsNotice = panel.partialResultsNotice {
                PanelBanner(text: partialResultsNotice, tone: .warning)
            }

            if let limitWarningText = panel.limitWarningText {
                PanelLimitBar(text: limitWarningText)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundPanel.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("참조 패널")
    }

    @ViewBuilder
    private var content: some View {
        if let errorText = panel.errorText {
            PanelMessage(text: errorText, tone: .failure)
        } else if panel.isLoading {
            PanelMessage(text: "참조를 찾는 중…", tone: .busy)
        } else if let placeholderText = panel.placeholderText {
            PanelMessage(text: placeholderText)
        } else if let emptyText = panel.emptyText {
            PanelMessage(text: emptyText)
        } else {
            referenceList
        }
    }

    private var referenceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(panel.groups, id: \.path) { group in
                    Section {
                        ForEach(group.items) { reference in
                            row(reference)
                        }
                    } header: {
                        PanelGroupHeader(path: group.path)
                    }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.medium)
        }
    }

    private func row(_ reference: Reference) -> some View {
        Button {
            onSelect(reference)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.rowSpacing) {
                PanelLineNumberLabel(line: reference.line)

                if reference.isDefinition {
                    DefinitionBadge()
                }

                HighlightedText(
                    segments: MatchHighlighter.segments(
                        text: reference.previewText,
                        ranges: reference.matchRanges
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.leading, Metrics.rowLeadingPadding)
            .padding(.trailing, DesignTokens.Spacing.large)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(for: reference))
            .overlay(alignment: .leading) {
                if reference.id == selectedReferenceID {
                    Rectangle()
                        .fill(DesignTokens.accent.dynamicColor)
                        .frame(width: Metrics.selectionBarWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            hoveredID = isInside ? reference.id : (hoveredID == reference.id ? nil : hoveredID)
        }
        .accessibilityLabel(accessibilityLabel(for: reference))
        .accessibilityAddTraits(reference.id == selectedReferenceID ? .isSelected : [])
    }

    private func rowBackground(for reference: Reference) -> Color {
        if reference.id == selectedReferenceID {
            return DesignTokens.accentDim.dynamicColor
        }
        if hoveredID == reference.id {
            return DesignTokens.backgroundHover.dynamicColor
        }
        return .clear
    }

    private func accessibilityLabel(for reference: Reference) -> String {
        var parts = [PathDisplay.fileName(reference.path), "\(reference.line)번째 줄"]
        if reference.isDefinition {
            parts.append("정의")
        }
        parts.append(reference.previewText)
        return parts.joined(separator: ", ")
    }

    private enum Metrics {
        static let rowSpacing: CGFloat = 6
        static let rowVerticalPadding: CGFloat = 3
        static let rowLeadingPadding = DesignTokens.Spacing.large + 10
        static let selectionBarWidth: CGFloat = 2
    }
}
