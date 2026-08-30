import SwiftUI
import CodeNavigatorContract

/// What the symbol search modal asks the application to do.
public enum SymbolSearchAction: Sendable, Hashable {
    case queryChanged(String)
    case moveSelection(SelectionDirection)
    case select(index: Int)
    case activate(index: Int)
    case dismiss
}

/// The fuzzy symbol search modal (design §3 W-3, REQ-007).
///
/// REQ-007 AC-3 requires the whole thing to be usable from the keyboard, so every action
/// here has a key: ↑↓ move, ⏎ goes to the definition, esc closes. The selection arithmetic
/// is not done in this view — `SymbolSearchPresentation` owns it, including the clamp that
/// keeps a selection valid when typing shrinks the list under it.
public struct SymbolSearchModalView: View {

    private let presentation: SymbolSearchPresentation
    private let query: String
    private let onAction: (SymbolSearchAction) -> Void

    @State private var hoveredIndex: Int?
    @FocusState private var isQueryFocused: Bool

    public init(
        presentation: SymbolSearchPresentation,
        query: String,
        onAction: @escaping (SymbolSearchAction) -> Void
    ) {
        self.presentation = presentation
        self.query = query
        self.onAction = onAction
    }

    public var body: some View {
        ZStack {
            scrim
            modal
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("심볼 검색")
    }

    /// The dim behind the modal. Tapping it closes, the way every other macOS overlay does.
    private var scrim: some View {
        Color.black
            .opacity(Metrics.scrimOpacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onAction(.dismiss) }
            .accessibilityHidden(true)
    }

    private var modal: some View {
        VStack(spacing: 0) {
            queryField
            Divider()

            if let notice = presentation.partialResultsNotice {
                partialResultsBanner(notice)
                Divider()
            }

            content

            Divider()
            footer
        }
        .frame(width: Metrics.width)
        .background(DesignTokens.backgroundElevated.dynamicColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.modal))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.modal)
                .strokeBorder(DesignTokens.border.dynamicColor)
        )
        .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowOffsetY)
        // esc must work from anywhere inside the modal, not only the text field.
        .onExitCommand { onAction(.dismiss) }
    }

    // MARK: 입력

    private var queryField: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)

            TextField(SymbolSearchPresentation.queryHint, text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: Metrics.queryFontSize))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .focused($isQueryFocused)
                .onSubmit { activateSelection() }
                .onKeyPress(.upArrow) { move(.up) }
                .onKeyPress(.downArrow) { move(.down) }
                .accessibilityLabel("심볼 이름")

            if presentation.showsSpinner {
                MotionSafeSpinner(tone: DesignTokens.textTertiary.dynamicColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.medium)
        .onAppear { isQueryFocused = true }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { query },
            set: { onAction(.queryChanged($0)) }
        )
    }

    private func partialResultsBanner(_ notice: String) -> some View {
        // Without this, "결과 없음" reads as "이 심볼은 없다" when the truth may be
        // "아직 인덱싱되지 않았다".
        Text(notice)
            .font(.system(size: DesignTokens.Typography.secondarySize))
            .foregroundStyle(DesignTokens.warning.dynamicColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.vertical, DesignTokens.Spacing.small)
            .background(DesignTokens.accentDim.dynamicColor)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: 결과

    @ViewBuilder
    private var content: some View {
        if let hint = presentation.hintText {
            message(hint)
        } else if let empty = presentation.emptyText {
            message(empty)
        } else {
            resultList
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Typography.bodySize))
            .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignTokens.Spacing.extraLarge)
    }

    private var resultList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(presentation.results.enumerated()), id: \.element.id) { index, result in
                        row(result, at: index)
                            .id(index)
                    }
                }
            }
            .frame(maxHeight: Metrics.listMaximumHeight)
            .onChange(of: presentation.selectedIndex) { _, index in
                scroll.scrollTo(index, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ result: SymbolSearchResult, at index: Int) -> some View {
        let isSelected = index == presentation.selectedIndex

        return HStack(spacing: DesignTokens.Spacing.small) {
            SymbolKindBadgeView(kind: result.definition.kind)

            // The match ranges are UTF-16 offsets into the name; MatchHighlighter is what
            // turns them into runs without breaking Korean or emoji.
            HighlightedText(
                segments: MatchHighlighter.segments(
                    text: result.definition.name,
                    ranges: result.matchRanges
                ),
                font: .system(size: DesignTokens.Typography.bodySize, weight: .medium),
                baseColor: DesignTokens.textPrimary
            )
            .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.small)

            Text("\(result.definition.path):\(result.definition.line)")
                .font(.system(size: DesignTokens.Typography.previewSize, design: .monospaced))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .lineLimit(1)
                // The file name identifies the hit; the directories in front of it are the
                // part worth losing when the row is narrow.
                .truncationMode(.head)
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: isSelected, index: index))
        .contentShape(Rectangle())
        .onHover { isInside in
            hoveredIndex = isInside ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
        .onTapGesture {
            onAction(.select(index: index))
            onAction(.activate(index: index))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(SymbolKindBadge.badge(for: result.definition.kind).accessibilityLabel) "
            + "\(result.definition.name), \(result.definition.path) \(result.definition.line)번째 줄"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowBackground(isSelected: Bool, index: Int) -> Color {
        if isSelected {
            return DesignTokens.accentDim.dynamicColor
        }
        if hoveredIndex == index {
            return DesignTokens.backgroundHover.dynamicColor
        }
        return .clear
    }

    // MARK: 푸터

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            keyHint("↑↓", "이동")
            keyHint("⏎", "정의로 이동")
            keyHint("esc", "닫기")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityHidden(true)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Text(key)
                .font(.shortcutLabel())
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            Text(label)
                .font(.system(size: DesignTokens.Typography.shortcutSize))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
        }
    }

    // MARK: 키

    private func move(_ direction: SelectionDirection) -> KeyPress.Result {
        guard !presentation.results.isEmpty else {
            return .ignored
        }
        onAction(.moveSelection(direction))
        return .handled
    }

    private func activateSelection() {
        guard presentation.selectedResult != nil else {
            return
        }
        onAction(.activate(index: presentation.selectedIndex))
    }

    private enum Metrics {
        static let width: CGFloat = 560
        static let listMaximumHeight: CGFloat = 360
        static let queryFontSize: CGFloat = 15
        static let rowVerticalPadding: CGFloat = 6

        static let scrimOpacity: Double = 0.28
        static let shadowOpacity: Double = 0.30
        static let shadowRadius: CGFloat = 32
        static let shadowOffsetY: CGFloat = 12
    }
}
