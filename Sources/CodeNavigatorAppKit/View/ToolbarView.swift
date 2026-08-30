import SwiftUI
import CodeNavigatorContract

/// The 48px title bar (design §3 W-1).
///
/// The mode segment is here as well as in the status bar, and deliberately so: §11 ruling 5
/// made it a required control rather than an optional one, because REQ-010 AC-3 asks the
/// current mode to be visible and switchable without going through a menu.
struct ToolbarView: View {

    let toolbar: ToolbarPresentation
    let inputMode: InputMode
    let isModeSwitchEnabled: Bool
    let onCommand: (MenuCommand) -> Void
    let onSelectInputMode: (InputMode) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            projectButton

            Spacer(minLength: DesignTokens.Spacing.small)

            windowTitle

            Spacer(minLength: DesignTokens.Spacing.small)

            if toolbar.showsModeSegment {
                modeSegment
            }

            ForEach(toolbar.buttons) { button in
                toolbarButton(button)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .frame(height: ShellLayout.Metrics.titleBarHeight)
        .background(DesignTokens.backgroundWindow.dynamicColor)
    }

    private var projectButton: some View {
        Button {
            onCommand(.openProject)
        } label: {
            HStack(spacing: DesignTokens.Spacing.extraSmall) {
                Image(systemName: "folder")
                Text(toolbar.projectButtonTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: Metrics.chevronSize))
            }
            .font(.system(size: DesignTokens.Typography.secondarySize))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
        .frame(maxWidth: Metrics.projectButtonMaximumWidth)
        .accessibilityLabel("프로젝트: \(toolbar.projectButtonTitle)")
    }

    private var windowTitle: some View {
        HStack(spacing: DesignTokens.Spacing.extraSmall) {
            Text(toolbar.windowTitle)
                .font(.system(size: DesignTokens.Typography.bodySize, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.middle)

            if toolbar.showsDirtyIndicator {
                // One of the three places the dirty state shows (§4.5): title, tree, status
                // bar. No single dot carries it alone.
                Circle()
                    .fill(DesignTokens.warningSolid.dynamicColor)
                    .frame(width: Metrics.dirtyDotSize, height: Metrics.dirtyDotSize)
                    .help("더티 버퍼 — 저장되지 않은 변경")
            }
        }
        .fixedSize()
    }

    private var modeSegment: some View {
        Picker("입력 모드", selection: Binding(
            get: { inputMode },
            set: { onSelectInputMode($0) }
        )) {
            Text("Vim").tag(InputMode.vim)
            Text("표준").tag(InputMode.standard)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(!isModeSwitchEnabled)
        .help("입력 모드 전환 ⌃⌘V")
    }

    private func toolbarButton(_ button: ToolbarButton) -> some View {
        Button {
            onCommand(button.command)
        } label: {
            HStack(spacing: DesignTokens.Spacing.extraSmall) {
                Image(systemName: button.systemImage)
                if toolbar.showsButtonTitles {
                    Text(button.title)
                        .font(.system(size: DesignTokens.Typography.secondarySize))
                }
                if toolbar.showsShortcutLabels {
                    Text(button.shortcutLabel)
                        .font(.system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
                        .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                }
            }
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
        .disabled(!button.isEnabled)
        // The label collapses to an icon on a narrow window, so the name has to survive
        // somewhere a screen reader and a tooltip can reach it.
        .help("\(button.title) \(button.shortcutLabel)")
        .accessibilityLabel(button.title)
    }

    private enum Metrics {
        static let chevronSize: CGFloat = 8
        static let dirtyDotSize: CGFloat = 6
        static let projectButtonMaximumWidth: CGFloat = 240
    }
}
