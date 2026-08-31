import SwiftUI
import CodeNavigatorContract

/// What the full-text panel asks the application to do.
public enum TextSearchAction: Sendable, Hashable {
    case queryChanged(String)
    case modeChanged(TextSearchMode)
    case submit
    case select(itemID: String)
}

/// The full-text search panel (design §3 W-6, REQ-008).
///
/// SC-6 is the rule the layout is built around: an invalid regular expression is an error,
/// never an empty result set. So the error text appears *and* the previous results stay,
/// dimmed, with a notice saying no new search ran. Clearing the list instead would show the
/// user "결과 없음" for a search that never happened.
public struct TextSearchPanelView: View {

    private let panel: TextSearchPresentation
    private let query: String
    private let mode: TextSearchMode
    private let selectedItemID: String?
    /// Whether the window's focus coordinator has given this panel the keyboard.
    private let hasKeyboard: Bool
    private let onAction: (TextSearchAction) -> Void
    private let onClaimKeyboard: () -> Void

    @State private var hoveredID: String?
    @FocusState private var isQueryFocused: Bool

    public init(
        panel: TextSearchPresentation,
        query: String,
        mode: TextSearchMode,
        selectedItemID: String? = nil,
        hasKeyboard: Bool = false,
        onAction: @escaping (TextSearchAction) -> Void,
        onClaimKeyboard: @escaping () -> Void = {}
    ) {
        self.panel = panel
        self.query = query
        self.mode = mode
        self.selectedItemID = selectedItemID
        self.hasKeyboard = hasKeyboard
        self.onAction = onAction
        self.onClaimKeyboard = onClaimKeyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchRow

            if let errorText = panel.errorText {
                errorLabel(errorText)
            }

            if let metaText = panel.metaText {
                metaLabel(metaText)
            }

            // Says the list below is the previous answer, not this one.
            if let staleResultNotice = panel.staleResultNotice {
                metaLabel(staleResultNotice)
            }

            if let limitWarningText = panel.limitWarningText {
                PanelLimitBar(text: limitWarningText)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundPanel.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("전문 검색 패널")
    }

    // MARK: 입력

    private var searchRow: some View {
        HStack(spacing: Metrics.searchRowSpacing) {
            TextField("검색어", text: Binding(
                get: { query },
                set: { onAction(.queryChanged($0)) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: DesignTokens.Typography.bodySize))
            .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .frame(height: Metrics.controlHeight)
            .background(DesignTokens.backgroundContent.dynamicColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    // The field itself turns red, so the error is attached to the thing
                    // that caused it rather than only to a line of text below.
                    .strokeBorder(inputBorderColor, lineWidth: 1)
            }
            .focused($isQueryFocused)
            // The field bound `.focused` and nothing ever set it, so it never took the
            // keyboard: typing into the panel went nowhere and REQ-008 had no route from
            // the UI at all, while every engine and presentation test passed. The binding
            // now follows the window's one answer to "who has the keyboard".
            .onChange(of: hasKeyboard, initial: true) { _, hasIt in
                isQueryFocused = hasIt
            }
            .onChange(of: isQueryFocused) { _, focused in
                // Clicking the field is the user claiming it — tell the rest of the window
                // so the editor stops holding on.
                if focused { onClaimKeyboard() }
            }
            .onSubmit { onAction(.submit) }
            .accessibilityLabel("검색어")

            regularExpressionToggle
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.top, DesignTokens.Spacing.medium)
    }

    private var regularExpressionToggle: some View {
        let isOn = mode == .regularExpression

        return Button {
            onAction(.modeChanged(isOn ? .literal : .regularExpression))
        } label: {
            Text(".*")
                .font(.system(size: DesignTokens.Typography.shortcutSize, weight: isOn ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isOn ? Color.white : DesignTokens.textTertiary.dynamicColor)
                .padding(.horizontal, DesignTokens.Spacing.small)
                .frame(height: Metrics.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .fill(isOn ? DesignTokens.accent.dynamicColor : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .strokeBorder(
                            isOn ? DesignTokens.accent.dynamicColor : DesignTokens.border.dynamicColor,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("정규식 모드")
        // Colour alone never carries state (§4.5); the toggle reports its own.
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .help("정규식 모드")
    }

    private var inputBorderColor: Color {
        panel.errorText == nil
            ? DesignTokens.borderStrong.dynamicColor
            : DesignTokens.danger.dynamicColor
    }

    // MARK: 메타·에러

    private func errorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Typography.secondarySize))
            .foregroundStyle(DesignTokens.danger.dynamicColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.top, Metrics.metaTopPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // An error the user has to read, announced rather than left to be noticed.
            .accessibilityAddTraits(.isStaticText)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Typography.secondarySize))
            .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.top, Metrics.metaTopPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 결과

    @ViewBuilder
    private var content: some View {
        if panel.isLoading && panel.items.isEmpty {
            PanelMessage(text: "검색 중…", tone: .busy)
        } else if let emptyText = panel.emptyText {
            PanelMessage(text: emptyText)
        } else {
            resultList
                // Design §3 W-6: results kept after a failed search are dimmed to 40%, so
                // they read as history rather than as the answer to what was just typed.
                .opacity(panel.resultsAreDimmed ? Metrics.dimmedOpacity : 1)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(panel.groups, id: \.path) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        PanelGroupHeader(path: group.path)
                    }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.medium)
        }
    }

    private func row(_ item: TextSearchItem) -> some View {
        Button {
            onAction(.select(itemID: item.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.rowSpacing) {
                PanelLineNumberLabel(line: item.line)

                HighlightedText(
                    segments: MatchHighlighter.segments(
                        text: item.previewText,
                        ranges: item.matchRanges
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
            .background(rowBackground(for: item))
            .overlay(alignment: .leading) {
                if item.id == selectedItemID {
                    Rectangle()
                        .fill(DesignTokens.accent.dynamicColor)
                        .frame(width: Metrics.selectionBarWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            hoveredID = isInside ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .accessibilityLabel("\(PathDisplay.fileName(item.path)), \(item.line)번째 줄, \(item.previewText)")
        .accessibilityAddTraits(item.id == selectedItemID ? .isSelected : [])
    }

    private func rowBackground(for item: TextSearchItem) -> Color {
        if item.id == selectedItemID {
            return DesignTokens.accentDim.dynamicColor
        }
        if hoveredID == item.id {
            return DesignTokens.backgroundHover.dynamicColor
        }
        return .clear
    }

    private enum Metrics {
        static let controlHeight: CGFloat = 26
        static let searchRowSpacing: CGFloat = 6
        static let metaTopPadding: CGFloat = 6

        static let rowSpacing: CGFloat = 6
        static let rowVerticalPadding: CGFloat = 3
        static let rowLeadingPadding = DesignTokens.Spacing.large + 10
        static let selectionBarWidth: CGFloat = 2

        static let dimmedOpacity: Double = 0.4
    }
}
