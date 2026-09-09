import AppKit
import SwiftUI
import CodeNavigatorContract

/// 터미널 패널 (REQ-018).
///
/// 그리드는 편집기와 같은 렌더러를 쓴다 — nvim 의 `:terminal` 이 libvterm 으로 그린 화면이
/// 같은 UI 프로토콜로 오기 때문이다. 우리가 새로 쓸 것은 머리줄과 배선뿐이다.
public struct TerminalPanelView: View {

    private let state: TerminalModel.State
    private let grid: GridFrame?
    private let configurations: [RunConfiguration]
    private let selectedConfigurationID: String?
    /// 이 설정이 소스에서 알아낸 것인지. 저장된 것과 구별해 보여 준다 — 사용자가 만든 적
    /// 없는 항목이 목록에 있으면 어디서 왔는지 알 수 있어야 한다.
    private let isDetected: (RunConfiguration) -> Bool
    private let ownsKeyboard: Bool
    private let onSelectConfiguration: (RunConfiguration) -> Void
    private let onRun: (RunConfiguration) -> Void
    private let onDebug: (RunConfiguration) -> Void
    private let onStop: () -> Void
    private let onOpenShell: () -> Void
    private let onEditConfigurations: () -> Void
    private let onKey: (String) -> Void
    private let onGridSizeChange: (Int, Int) -> Void
    private let onClaimKeyboard: () -> Void
    /// 지금 명령을 찾는 데 쓰는 PATH. 실행이 실패했을 때 보여 준다 —
    /// "command not found" 만으로는 무엇이 빠졌는지 사용자도 우리도 알 수 없다.
    private let searchPath: String

    public init(
        state: TerminalModel.State,
        grid: GridFrame?,
        configurations: [RunConfiguration],
        selectedConfigurationID: String?,
        isDetected: @escaping (RunConfiguration) -> Bool,
        ownsKeyboard: Bool,
        onSelectConfiguration: @escaping (RunConfiguration) -> Void,
        onRun: @escaping (RunConfiguration) -> Void,
        onDebug: @escaping (RunConfiguration) -> Void,
        onStop: @escaping () -> Void,
        onOpenShell: @escaping () -> Void,
        onEditConfigurations: @escaping () -> Void,
        onKey: @escaping (String) -> Void,
        onGridSizeChange: @escaping (Int, Int) -> Void,
        onClaimKeyboard: @escaping () -> Void,
        searchPath: String = ""
    ) {
        self.state = state
        self.grid = grid
        self.configurations = configurations
        self.selectedConfigurationID = selectedConfigurationID
        self.isDetected = isDetected
        self.ownsKeyboard = ownsKeyboard
        self.onSelectConfiguration = onSelectConfiguration
        self.onRun = onRun
        self.onDebug = onDebug
        self.onStop = onStop
        self.onOpenShell = onOpenShell
        self.onEditConfigurations = onEditConfigurations
        self.onKey = onKey
        self.onGridSizeChange = onGridSizeChange
        self.onClaimKeyboard = onClaimKeyboard
        self.searchPath = searchPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundPanel.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("터미널 패널")
    }

    private var selected: RunConfiguration? {
        configurations.first { $0.id == selectedConfigurationID } ?? configurations.first
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            if configurations.isEmpty {
                Text("실행 설정이 없습니다")
                    .font(.system(size: DesignTokens.Typography.panelTitleSize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            } else {
                Picker("실행 설정", selection: Binding(
                    get: { selected?.id ?? "" },
                    set: { identifier in
                        if let configuration = configurations.first(where: { $0.id == identifier }) {
                            onSelectConfiguration(configuration)
                        }
                    }
                )) {
                    ForEach(configurations) { configuration in
                        // 감지된 것에 표를 붙인다. 저장한 것과 섞여 있으면 어느 것이 내가
                        // 만든 것인지 알 수 없다.
                        Text(isDetected(configuration) ? "\(configuration.name) · 감지됨" : configuration.name)
                            .tag(configuration.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: Metrics.pickerWidth)
            }

            Text(statusText)
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(statusColour)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DesignTokens.Spacing.medium)

            if case .running = state {
                Button("정지", action: onStop)
            } else if let configuration = selected {
                // 실행과 디버그 실행을 나란히 둔다 — IntelliJ 의 ▶ 와 🐞 자리다.
                Button("실행") { onRun(configuration) }
                Button("디버그 실행") { onDebug(configuration) }
                    // JDWP 는 JVM 전용이다. 켜 두면 사용자는 눌러서 30초를 기다린 뒤
                    // "붙지 못했습니다" 만 보고, 이유는 화면 어디에도 없다.
                    .disabled(!configuration.canDebug)
                    .help(configuration.canDebug
                        ? "JDWP 인자를 붙여 띄우고 자동으로 붙습니다"
                        : "이 명령에는 붙을 수 없습니다 — 자바 디버거는 JVM 만 다룹니다")
            }
            Button("셸", action: onOpenShell)
            Button("설정…", action: onEditConfigurations)
            // 명령을 못 찾는 일이 잦고, 그때 사용자가 볼 수 있는 것은 셸의 한 줄뿐이다.
            // 어떤 PATH 로 찾았는지를 여기서 보여 준다.
            if !searchPath.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(searchPath, forType: .string)
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("명령을 찾는 경로 (눌러서 복사)\n\n" + searchPath.replacingOccurrences(of: ":", with: "\n"))
                .accessibilityLabel("명령 검색 경로")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.small)
    }

    private var statusText: String {
        switch state {
        case .idle: return "대기"
        case .running(let name): return "실행 중 — \(name)"
        case .failed(let reason): return reason
        }
    }

    private var statusColour: Color {
        switch state {
        case .failed: return DesignTokens.danger.dynamicColor
        case .running: return DesignTokens.textPrimary.dynamicColor
        case .idle: return DesignTokens.textSecondary.dynamicColor
        }
    }

    @ViewBuilder
    private func body(for state: TerminalModel.State) -> some View {
        if let grid {
            // 편집기와 같은 렌더러. 마우스는 넘기지 않는다 — 터미널에서 드래그는 선택인데,
            // 그 의미가 셸마다 달라서 지금은 키보드만 다룬다.
            EditorGridView(
                frame: grid,
                isInputBlocked: false,
                editorMode: .insert,
                inputMode: .standard,
                ownsKeyboard: ownsKeyboard,
                onKey: onKey,
                onMouse: { _ in },
                onGridSizeChange: onGridSizeChange,
                onClaimKeyboard: onClaimKeyboard,
                onAppearanceChange: { _ in }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 글자가 창 모서리에 붙지 않게 한 칸 띄운다. 편집기는 줄 번호가 그 일을 하지만
            // 터미널에는 그게 없어서 첫 글자가 테두리에 닿는다.
            .padding(.leading, DesignTokens.Spacing.small)
        } else {
            PanelMessage(text: emptyText)
        }
    }

    private var emptyText: String {
        switch state {
        case .failed(let reason):
            return reason
        case .running:
            // 띄우긴 했는데 아직 첫 화면이 안 왔다. "빈 터미널" 과 구별해서 말한다.
            return "시작하는 중…"
        case .idle:
            return configurations.isEmpty
                ? "이 프로젝트에서 띄울 것을 찾지 못했습니다. 설정…을 눌러 명령을 직접 추가하세요."
                : "실행을 누르면 여기에서 돕니다. 셸을 눌러 직접 명령을 칠 수도 있습니다."
        }
    }

    private enum Metrics {
        static let pickerWidth: CGFloat = 180
    }
}
