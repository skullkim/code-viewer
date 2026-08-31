import SwiftUI
import CodeNavigatorContract

/// The project file tree (design §3 W-1 left column, REQ-003).
///
/// The view draws rows and turns key presses into `FileTreeAction`s; it decides nothing.
/// Every rule about what is visible, what a key means and which row is the current file
/// lives in `FileTreePresentation`, where a test can reach it.
///
/// It takes whatever width the shell gives it — `ShellLayout` owns the split (§4.4), and a
/// view that also had an opinion about its width would be a second source of truth.
public struct FileTreeView: View {

    private let tree: FileTreePresentation
    private let onAction: (FileTreeAction) -> Void

    /// 트리가 지금 키보드를 갖고 있는가. **뷰가 스스로 판단하지 않고 받는다** — 누가
    /// 키보드를 갖는지는 창 전체의 사실이고, 표면마다 자기 답을 가지면 둘이 동시에
    /// "내가 갖고 있다"고 그린다.
    private let ownsKeyboard: Bool

    /// 사용자가 트리를 눌렀다. 코디네이터가 에디터에서 키보드를 거둬 온다.
    private let onClaimKeyboard: () -> Void

    @State private var hoveredPath: String?
    @FocusState private var isFocused: Bool

    public init(
        tree: FileTreePresentation,
        ownsKeyboard: Bool = false,
        onClaimKeyboard: @escaping () -> Void = {},
        onAction: @escaping (FileTreeAction) -> Void
    ) {
        self.tree = tree
        self.ownsKeyboard = ownsKeyboard
        self.onClaimKeyboard = onClaimKeyboard
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = tree.title {
                titleLabel(title)
            }

            if tree.showsSkeleton {
                skeleton
            } else {
                rowList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundSidebar.dynamicColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.border.dynamicColor)
                .frame(width: 1)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        // 창의 소유권이 단일 소스다. SwiftUI 의 `@FocusState` 는 그것을 따라가는
        // 사본이지 판정자가 아니다 — 둘이 각자 판단하면 어긋난다.
        .onChange(of: ownsKeyboard) { _, owns in isFocused = owns }
        .onAppear { isFocused = ownsKeyboard }
        .onKeyPress(.upArrow) { send(.up) }
        .onKeyPress(.downArrow) { send(.down) }
        .onKeyPress(.leftArrow) { send(.left) }
        .onKeyPress(.rightArrow) { send(.right) }
        .onKeyPress(.return) { send(.enter) }
        .accessibilityLabel("파일 트리")
    }

    // MARK: 조각

    private func titleLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: Metrics.titleFontSize, weight: .semibold))
            .kerning(Metrics.titleKerning)
            .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.top, DesignTokens.Spacing.extraSmall)
            .padding(.bottom, DesignTokens.Spacing.small)
            .accessibilityAddTraits(.isHeader)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Metrics.skeletonSpacing) {
            ForEach(0..<tree.skeletonRowCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Metrics.skeletonRadius)
                    .fill(DesignTokens.backgroundHover.dynamicColor)
                    .frame(height: Metrics.skeletonHeight)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.top, Metrics.skeletonSpacing)
        .accessibilityLabel("파일 트리를 읽는 중")
    }

    private var rowList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tree.rows) { row in
                        rowView(row)
                            .id(row.path)
                    }
                }
            }
            .onChange(of: selectedPath) { _, path in
                // Arrow keys can walk the selection past the visible area; without this the
                // selection is somewhere off screen and the tree looks unresponsive.
                guard let path else {
                    return
                }
                scroll.scrollTo(path, anchor: .center)
            }
        }
    }

    private func rowView(_ row: FileTreeRow) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            disclosureIndicator(row)

            Image(systemName: row.isDirectory ? "folder" : "doc.text")
                .font(.system(size: Metrics.iconFontSize))
                .frame(width: Metrics.iconWidth)
                .opacity(Metrics.iconOpacity)

            Text(row.name)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if row.isLoadingChildren {
                MotionSafeSpinner(tone: foreground(for: row))
            }
            if row.isDirty {
                dirtyIndicator(row)
            }
        }
        .foregroundStyle(foreground(for: row))
        .padding(.vertical, Metrics.rowVerticalPadding)
        .padding(.trailing, DesignTokens.Spacing.large)
        .padding(.leading, DesignTokens.Spacing.large + Metrics.indentPerDepth * CGFloat(row.depth))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: row))
        .overlay(selectionRing(for: row))
        .contentShape(Rectangle())
        .onHover { isInside in
            hoveredPath = isInside ? row.path : (hoveredPath == row.path ? nil : hoveredPath)
        }
        .onTapGesture {
            // 링을 그리기 전에 키보드를 실제로 가져온다. 이 순서가 D-8 의 전부다 —
            // 예전엔 선택만 하고 키보드는 에디터에 남아, 링은 떴는데 ↓ 가 nvim 커서를
            // 움직였다.
            onClaimKeyboard()
            onAction(.select(path: row.path))
            guard !row.isDirectory else {
                return
            }
            onAction(.openFile(path: row.path))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    private func disclosureIndicator(_ row: FileTreeRow) -> some View {
        Group {
            if row.isDirectory {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: Metrics.disclosureFontSize, weight: .semibold))
                    .opacity(row.isCurrentFile ? Metrics.disclosureOnFillOpacity : 1)
                    .foregroundStyle(row.isCurrentFile ? .white : DesignTokens.textTertiary.dynamicColor)
            }
        }
        .frame(width: Metrics.disclosureWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            // The twisty toggles without moving the selection, the way a Finder outline does.
            onAction(row.isExpanded ? .collapse(path: row.path) : .expand(path: row.path))
        }
    }

    private func dirtyIndicator(_ row: FileTreeRow) -> some View {
        Circle()
            .fill(row.isCurrentFile ? Color.white : DesignTokens.warningSolid.dynamicColor)
            .frame(width: Metrics.dirtyDotSize, height: Metrics.dirtyDotSize)
            .help("더티 버퍼 — 저장하지 않은 변경")
    }

    // MARK: 색

    /// The file being edited is filled, the way the prototype draws it (REQ-003 AC-3).
    private func background(for row: FileTreeRow) -> Color {
        if row.isCurrentFile {
            return DesignTokens.accent.dynamicColor
        }
        if hoveredPath == row.path {
            return DesignTokens.backgroundHover.dynamicColor
        }
        return .clear
    }

    private func foreground(for row: FileTreeRow) -> Color {
        row.isCurrentFile ? .white : DesignTokens.textSecondary.dynamicColor
    }

    /// Keyboard selection and "the file that is open" are different facts, so they get
    /// different marks: the open file is filled, the keyboard cursor wears the focus ring
    /// design §4.5 already defines. One style for both would make it impossible to see
    /// where the arrow keys are.
    @ViewBuilder
    private func selectionRing(for row: FileTreeRow) -> some View {
        if FileTreeFocusMark.showsKeyboardCursor(isSelected: row.isSelected, treeOwnsKeyboard: ownsKeyboard) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(DesignTokens.accent.dynamicColor, lineWidth: Metrics.focusRingWidth)
                .padding(Metrics.focusRingInset)
        }
    }

    // MARK: 입력

    private var selectedPath: String? {
        tree.rows.first { $0.isSelected }?.path
    }

    private func send(_ key: FileTreeKey) -> KeyPress.Result {
        let action = FileTreePresentation.action(for: key, rows: tree.rows, selectedPath: selectedPath)
        guard action != .none else {
            // Handing the key back lets the window act on it — swallowing every arrow key
            // at the edge of the tree would trap the user inside the sidebar.
            return .ignored
        }
        onAction(action)
        return .handled
    }

    private func accessibilityLabel(for row: FileTreeRow) -> String {
        var parts = [row.isDirectory ? "폴더" : "파일", row.name]
        if row.isCurrentFile {
            parts.append("편집 중")
        }
        if row.isDirty {
            parts.append("저장하지 않은 변경")
        }
        return parts.joined(separator: ", ")
    }

    /// Dimensions taken from the prototype stylesheet's `.tree` rules and design §4.3.
    private enum Metrics {
        static let titleFontSize: CGFloat = 11
        static let titleKerning: CGFloat = 0.55

        static let rowSpacing: CGFloat = 6
        static let rowVerticalPadding: CGFloat = 3
        static let indentPerDepth: CGFloat = 14

        static let disclosureWidth: CGFloat = 10
        static let disclosureFontSize: CGFloat = 9
        static let disclosureOnFillOpacity: Double = 0.75

        static let iconWidth: CGFloat = 13
        static let iconFontSize: CGFloat = 11
        static let iconOpacity: Double = 0.75

        static let dirtyDotSize: CGFloat = 6

        static let focusRingWidth: CGFloat = 2
        static let focusRingInset: CGFloat = 1

        static let skeletonHeight: CGFloat = 11
        static let skeletonRadius: CGFloat = 3
        static let skeletonSpacing: CGFloat = 9
    }
}
