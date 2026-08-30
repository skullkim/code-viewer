import SwiftUI

/// What the welcome screen asks the application to do.
public enum ProjectOpenAction: Sendable, Hashable {
    case openProject
    case openRecentProject(path: String)
    /// The sheet was dismissed. The path, when present, is a recent entry that proved dead
    /// and should be dropped from the list.
    case dismissFailure(forgetRecentProjectPath: String?)
}

/// The screen shown when no project is open (design §3 W-2, REQ-001).
///
/// The view draws and reports; every decision — which failure sentence, whether the recent
/// block exists at all, whether a dead entry should be forgotten — is made by
/// `ProjectOpenPresentation`, where tests can reach it.
public struct ProjectOpenView: View {

    private let screen: ProjectOpenPresentation
    private let onAction: (ProjectOpenAction) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredPath: String?

    public init(screen: ProjectOpenPresentation, onAction: @escaping (ProjectOpenAction) -> Void) {
        self.screen = screen
        self.onAction = onAction
    }

    public var body: some View {
        ZStack {
            DesignTokens.backgroundContent.dynamicColor

            ScrollView {
                card
                    .frame(maxWidth: Metrics.cardWidth)
                    .padding(.horizontal, DesignTokens.Spacing.large)
                    .padding(.vertical, DesignTokens.Spacing.huge)
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: sheetBinding) { sheet in
            failureSheet(sheet)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            appMark

            Text(screen.title)
                .font(.system(size: DesignTokens.Typography.welcomeTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .padding(.bottom, Metrics.titleBottomSpacing)

            Text(screen.detailText)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .multilineTextAlignment(.center)
                .padding(.bottom, DesignTokens.Spacing.extraLarge)

            openButton
                .padding(.bottom, DesignTokens.Spacing.extraLarge)

            if let recentTitle = screen.recentSectionTitle {
                recentList(title: recentTitle)
            }

            Text(screen.exclusionNotice)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .multilineTextAlignment(.center)
                .padding(.top, DesignTokens.Spacing.large)
        }
    }

    // MARK: 마크와 버튼

    private var appMark: some View {
        RoundedRectangle(cornerRadius: Metrics.appMarkRadius)
            .fill(LinearGradient(
                colors: [
                    DesignTokens.accent.dynamicColor,
                    DesignTokens.purple.dynamicColor,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: Metrics.appMarkSize, height: Metrics.appMarkSize)
            .overlay {
                Text(screen.appMark)
                    .font(.system(size: Metrics.appMarkFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, DesignTokens.Spacing.large)
            .accessibilityHidden(true)
    }

    private var openButton: some View {
        Button {
            onAction(.openProject)
        } label: {
            HStack(spacing: DesignTokens.Spacing.small) {
                Text(screen.openButtonTitle)
                    .font(.system(size: DesignTokens.Typography.bodySize, weight: .semibold))
                Text(screen.openButtonShortcut)
                    .font(.system(size: DesignTokens.Typography.bodySize))
                    .opacity(Metrics.shortcutOpacity)
            }
            .foregroundStyle(accentForeground)
            .padding(.horizontal, DesignTokens.Spacing.large)
            .frame(height: Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(DesignTokens.accent.dynamicColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(!screen.isOpenButtonEnabled)
        // The label already carries the shortcut, so the accessible name says it once.
        .accessibilityLabel(screen.openButtonTitle)
        .opacity(screen.isOpenButtonEnabled ? 1 : Metrics.disabledOpacity)
    }

    // MARK: 최근 프로젝트

    private func recentList(title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: Metrics.sectionTitleFontSize, weight: .semibold))
                .kerning(Metrics.sectionTitleKerning)
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, Metrics.sectionTitleVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Divider()

            ForEach(Array(screen.recentProjects.enumerated()), id: \.element.id) { index, project in
                if index > 0 {
                    Divider()
                }
                recentRow(project)
            }
        }
        .background(DesignTokens.backgroundElevated.dynamicColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .strokeBorder(DesignTokens.border.dynamicColor, lineWidth: 1)
        }
    }

    private func recentRow(_ project: RecentProjectRow) -> some View {
        Button {
            onAction(.openRecentProject(path: project.rootPath))
        } label: {
            HStack(spacing: DesignTokens.Spacing.medium) {
                Text(project.name)
                    .font(.system(size: DesignTokens.Typography.bodySize, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                    .fixedSize()

                Text(project.displayPath)
                    .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                    .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                    .lineLimit(1)
                    // The tail is the project folder itself and identifies the entry; the
                    // leading directories are the part that can go.
                    .truncationMode(.head)

                Spacer(minLength: DesignTokens.Spacing.small)

                Text(project.relativeTime)
                    .font(.system(size: Metrics.timeFontSize))
                    .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                    .fixedSize()
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hoveredPath == project.rootPath
                ? DesignTokens.backgroundHover.dynamicColor
                : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            hoveredPath = isInside ? project.rootPath : (hoveredPath == project.rootPath ? nil : hoveredPath)
        }
        .accessibilityLabel("\(project.name), \(project.displayPath), \(project.relativeTime)")
    }

    // MARK: 실패 시트 (AC-3)

    /// SwiftUI presents by identity, and the sheet is derived state rather than something
    /// the view stores. Wrapping it keeps the presentation the single source of truth: the
    /// sheet is up exactly while the phase says the open failed.
    private var sheetBinding: Binding<IdentifiedFailureSheet?> {
        Binding(
            get: { screen.failureSheet.map(IdentifiedFailureSheet.init) },
            set: { newValue in
                guard newValue == nil, let sheet = screen.failureSheet else {
                    return
                }
                onAction(.dismissFailure(forgetRecentProjectPath: sheet.forgetRecentProjectPath))
            }
        )
    }

    private func failureSheet(_ sheet: IdentifiedFailureSheet) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: Metrics.sheetGlyphSize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .padding(.bottom, DesignTokens.Spacing.small)
                .accessibilityHidden(true)

            Text(sheet.value.title)
                .font(.system(size: Metrics.sheetTitleFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .padding(.bottom, DesignTokens.Spacing.extraSmall)

            Text(sheet.value.detail)
                .font(.system(size: Metrics.sheetDetailFontSize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .multilineTextAlignment(.center)
                // The path is the content of this sheet, so it wraps rather than truncates.
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button(sheet.value.confirmTitle) {
                    onAction(.dismissFailure(forgetRecentProjectPath: sheet.value.forgetRecentProjectPath))
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, DesignTokens.Spacing.large)
        }
        .padding(DesignTokens.Spacing.extraLarge)
        .frame(width: Metrics.sheetWidth)
        .background(DesignTokens.backgroundElevated.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sheet.value.title). \(sheet.value.detail)")
    }

    private var accentForeground: Color {
        // The prototype puts dark ink on the accent fill in dark mode rather than white
        // (`--accent-on`), because the dark accent is light enough that white on it falls
        // under the floor §4.5 sets. Not in the §4.1 table; reported to the lead.
        colorScheme == .dark ? Metrics.accentForegroundDark : .white
    }

    /// Dimensions from the prototype stylesheet's `.welcome`, `.recent` and `.sheet` rules.
    private enum Metrics {
        static let cardWidth: CGFloat = 520

        static let appMarkSize: CGFloat = 56
        static let appMarkRadius: CGFloat = 13
        static let appMarkFontSize: CGFloat = 24

        static let titleBottomSpacing: CGFloat = 6
        static let buttonHeight: CGFloat = 28
        static let shortcutOpacity: Double = 0.75
        static let disabledOpacity: Double = 0.5

        static let sectionTitleFontSize: CGFloat = 11
        static let sectionTitleKerning: CGFloat = 0.55
        static let sectionTitleVerticalPadding: CGFloat = 6

        static let rowVerticalPadding: CGFloat = 8
        static let timeFontSize: CGFloat = 11

        static let sheetWidth: CGFloat = 420
        static let sheetGlyphSize: CGFloat = 24
        static let sheetTitleFontSize: CGFloat = 14
        static let sheetDetailFontSize: CGFloat = 12

        static let accentForegroundDark = Color(red: 0x06 / 255, green: 0x12 / 255, blue: 0x1F / 255)
    }
}

/// `sheet(item:)` needs an identity, and a failure sheet is a value without one.
struct IdentifiedFailureSheet: Identifiable {
    let value: ProjectOpenFailureSheet

    var id: String { value.title + value.detail }

    init(_ value: ProjectOpenFailureSheet) {
        self.value = value
    }
}
