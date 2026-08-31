import SwiftUI

/// What the render surface asks the application to do.
public enum RenderDocumentAction: Sendable, Hashable {
    case showSource
    case retry
}

/// The render surface (design 02b §3 W-14, REQ-013).
///
/// Laid over the editor rather than beside it. The Neovim grid keeps its size and is merely
/// covered — resizing it would force a full redraw of a surface the app does not own
/// (ADR-0109, INV-4).
///
/// Read-only is stated three ways, because the render view swallows keys bound for the
/// editor and a mode segment still reading `NORMAL Vim` would be a lie: the header badge,
/// the status bar's mode segment, and the toolbar toggle. This view owns the first.
public struct RenderDocumentView<Document: View>: View {

    private let screen: RenderDocumentPresentation
    private let blocked: BlockedResourcePresentation
    private let document: Document
    private let onAction: (RenderDocumentAction) -> Void

    public init(
        screen: RenderDocumentPresentation,
        blocked: BlockedResourcePresentation,
        onAction: @escaping (RenderDocumentAction) -> Void,
        @ViewBuilder document: () -> Document
    ) {
        self.screen = screen
        self.blocked = blocked
        self.onAction = onAction
        self.document = document()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(DesignTokens.backgroundContent.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("렌더 보기")
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Text(screen.fileName)
                .font(.system(size: DesignTokens.Typography.secondarySize, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.middle)

            badge(screen.readOnlyBadge)

            // Only present when the render fell back to disk. A badge that is always there
            // is a badge nobody reads — and this one has to be noticed when it appears.
            if let sourceBadge = screen.sourceBadge {
                badge(sourceBadge)
                    .help(screen.sourceTooltip ?? "")
            }

            BlockedResourceChipView(panel: blocked)

            if screen.showsHeaderSpinner {
                // A re-render after a save keeps the document on screen and spins here
                // instead (AC-5) — blanking what someone is reading is worse than waiting.
                MotionSafeSpinner(tone: DesignTokens.textTertiary.dynamicColor)
            }

            Spacer(minLength: DesignTokens.Spacing.small)

            Button(screen.toggleTitle) { onAction(.showSource) }
                .buttonStyle(.plain)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.accentText.dynamicColor)
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .frame(height: Metrics.headerHeight)
        .background(DesignTokens.backgroundWindow.dynamicColor)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Typography.shortcutSize))
            .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            .padding(.horizontal, DesignTokens.Spacing.extraSmall)
            .padding(.vertical, Metrics.badgeVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(DesignTokens.backgroundSidebar.dynamicColor)
            )
    }

    // MARK: 본문

    @ViewBuilder
    private var content: some View {
        ZStack {
            if screen.keepsPreviousDocument || screen.notice == nil {
                documentBody
            }

            if let notice = screen.notice {
                noticeCard(notice)
            } else if let progressText = screen.progressText {
                // Only past the flicker threshold. Most renders finish in milliseconds, and
                // a spinner for those reads as a glitch rather than as progress.
                VStack(spacing: DesignTokens.Spacing.small) {
                    MotionSafeSpinner(tone: DesignTokens.textTertiary.dynamicColor, size: 16)
                    Text(progressText)
                        .font(.system(size: DesignTokens.Typography.secondarySize))
                        .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentBody: some View {
        ScrollView {
            document
                // Prose, not code: 14pt at a wider leading, plainly different from the
                // 13pt monospaced grid underneath (W-14).
                .font(.system(size: Metrics.bodyTextSize))
                .frame(maxWidth: Metrics.maximumBodyWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.extraLarge)
                .padding(.horizontal, DesignTokens.Spacing.large)
        }
        // No caret, no cursor — but selection and copy stay, because reading includes them.
        .textSelection(.enabled)
    }

    private func noticeCard(_ notice: RenderNoticeCard) -> some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            Text(notice.glyph)
                .font(.system(size: Metrics.noticeGlyphSize))
            Text(notice.title)
                .font(.system(size: DesignTokens.Typography.welcomeTitleSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
            Text(notice.detail)
                .font(.system(size: DesignTokens.Typography.bodySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignTokens.Spacing.small) {
                // Every dead end offers a way out — AC-6 forbids leaving a blank screen
                // with nothing to press.
                ForEach(notice.actions, id: \.self) { action in
                    Button(action.title) {
                        onAction(action == .retry ? .retry : .showSource)
                    }
                }
            }
            .padding(.top, DesignTokens.Spacing.extraSmall)
        }
        .padding(DesignTokens.Spacing.extraLarge)
        .frame(maxWidth: Metrics.noticeCardWidth)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .fill(DesignTokens.backgroundElevated.dynamicColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .strokeBorder(DesignTokens.border.dynamicColor)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title). \(notice.detail)")
    }
}

/// Dimensions from 02b §3 W-14.
///
/// At file scope rather than nested: a generic type cannot hold static stored properties.
private enum Metrics {
    static let headerHeight: CGFloat = 28
    static let badgeVerticalPadding: CGFloat = 1
        /// 14pt prose — the designer measured 11pt-class text smudging on non-Retina, and
        /// the body has to read as clearly different from the code grid.
    static let bodyTextSize: CGFloat = 14
    static let maximumBodyWidth: CGFloat = 720
    static let noticeCardWidth: CGFloat = 420
    static let noticeGlyphSize: CGFloat = 28
    }
