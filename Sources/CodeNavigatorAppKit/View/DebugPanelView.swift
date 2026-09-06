import SwiftUI
import CodeNavigatorContract

/// The debug panel (REQ-016).
///
/// IntelliJ 처럼 편집기 **아래**에 눕는다. 호출 스택과 변수는 나란히 놓아야 둘 다 읽히고,
/// 오른쪽 세로 패널에 넣으면 프레임 한 줄이 잘려 어느 메서드인지 알 수 없게 된다.
///
/// 이 패널이 답해야 하는 것은 셋이다 — 붙어 있는가, 어디에 멈췄는가, 그 자리의 값은 무엇인가.
/// 셋 다 **모를 때 모른다고 말한다.** 빈 목록은 "없다" 로 읽히는데, 디버거에서 없는 것과
/// 알 수 없는 것은 사용자가 해야 할 일이 다르다.
public struct DebugPanelView: View {

    private let connection: DebugConnection
    private let breakpoints: [DebugBreakpoint]
    private let frames: [JavaStackFrame]
    private let variableRows: [DebugVariableRow]
    private let variableNotice: String?
    private let selectedFrameID: UInt64?
    private let onSelectFrame: (JavaStackFrame) -> Void
    private let onToggleVariable: (DebugVariableRow) -> Void
    private let onResume: () -> Void
    private let onAttach: () -> Void
    private let onDetach: () -> Void

    public init(
        connection: DebugConnection,
        breakpoints: [DebugBreakpoint],
        frames: [JavaStackFrame],
        variableRows: [DebugVariableRow],
        variableNotice: String?,
        selectedFrameID: UInt64?,
        onSelectFrame: @escaping (JavaStackFrame) -> Void,
        onToggleVariable: @escaping (DebugVariableRow) -> Void,
        onResume: @escaping () -> Void,
        onAttach: @escaping () -> Void,
        onDetach: @escaping () -> Void
    ) {
        self.connection = connection
        self.breakpoints = breakpoints
        self.frames = frames
        self.variableRows = variableRows
        self.variableNotice = variableNotice
        self.selectedFrameID = selectedFrameID
        self.onSelectFrame = onSelectFrame
        self.onToggleVariable = onToggleVariable
        self.onResume = onResume
        self.onAttach = onAttach
        self.onDetach = onDetach
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: connection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.backgroundPanel.dynamicColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("디버그 패널")
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text(statusText)
                .font(.system(size: DesignTokens.Typography.panelTitleSize, weight: .semibold))
                .foregroundStyle(statusColour)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DesignTokens.Spacing.medium)

            if connection.isStopped {
                Button("계속 실행", action: onResume)
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
            if connection.isAttached {
                Button("끊기", action: onDetach)
            } else {
                Button("연결…", action: onAttach)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.small)
    }

    private var statusText: String {
        switch connection {
        case .detached:
            return "연결 안 됨"
        case .attaching(let host, let port):
            return "연결 중… \(host):\(port)"
        case .attached(let host, let port):
            return "실행 중 — \(host):\(port) · 브레이크포인트 \(breakpoints.count)개"
        case .stopped(let host, let port):
            return "멈춤 — \(host):\(port)"
        case .failed(let reason):
            return reason
        }
    }

    private var statusColour: Color {
        switch connection {
        case .failed: return DesignTokens.danger.dynamicColor
        case .stopped: return DesignTokens.textPrimary.dynamicColor
        default: return DesignTokens.textSecondary.dynamicColor
        }
    }

    // MARK: 몸

    @ViewBuilder
    private func body(for connection: DebugConnection) -> some View {
        switch connection {
        case .detached, .failed:
            PanelMessage(text: """
            디버거를 연결하면 브레이크포인트를 걸 수 있습니다.

            디버깅할 JVM 을 먼저 이렇게 띄우세요:
            java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:5005 …
            """)
        case .attaching:
            PanelMessage(text: "연결 중…")
        case .attached:
            // 붙었지만 아직 안 멈췄다. **빈 스택을 보여 주지 않는다** — 빈 스택은 "스택이
            // 없다" 로 읽히는데, 사실은 아직 멈추지 않은 것이다.
            PanelMessage(text: breakpoints.isEmpty
                ? "브레이크포인트를 걸어 두면(⌘⌥B) 그 줄에서 멈춥니다."
                : "실행 중입니다. 브레이크포인트에 닿으면 여기에 호출 스택이 표시됩니다.")
        case .stopped:
            stoppedBody
        }
    }

    private var stoppedBody: some View {
        HStack(spacing: 0) {
            framesColumn
            Divider()
            variablesColumn
        }
    }

    private var framesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelGroupHeader(path: "호출 스택")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(frames) { frame in
                        frameRow(frame)
                    }
                }
            }
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private func frameRow(_ frame: JavaStackFrame) -> some View {
        let isSelected = frame.frameID == selectedFrameID
        return Button {
            onSelectFrame(frame)
        } label: {
            HStack(spacing: DesignTokens.Spacing.small) {
                Text("\(frame.className).\(frame.methodName)")
                    .font(.system(size: DesignTokens.Typography.bodySize, design: .monospaced))
                    .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // 0 은 첫 줄이 아니라 "줄을 알 수 없다" 는 뜻이다. 그대로 0 을 찍으면
                // 사용자는 1행 근처라고 읽는다.
                Text(frame.line > 0 ? ":\(frame.line)" : " (줄 모름)")
                    .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                    .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.large)
            .padding(.vertical, DesignTokens.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DesignTokens.backgroundHover.dynamicColor : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(frame.className).\(frame.methodName)")
    }

    private var variablesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelGroupHeader(path: "변수")
            if let variableNotice {
                // 값이 없는 이유를 적는다. 빈 목록만 보여 주면 "이 자리에 변수가 없다" 로
                // 읽히는데, 대개는 `javac -g` 없이 컴파일된 것뿐이다.
                PanelMessage(text: variableNotice)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(variableRows) { row in
                            variableRow(row)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private func variableRow(_ row: DebugVariableRow) -> some View {
        let variable = row.variable
        return HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            // 들여쓰기로 부모-자식을 보인다. 선을 긋지 않는 것은 IntelliJ 와 같다 — 깊이가
            // 깊어져도 화면이 조용하다.
            if row.depth > 0 {
                Spacer().frame(width: CGFloat(row.depth) * Metrics.indentPerDepth)
            }
            // 삼각형은 **열 수 있는 것에만** 준다. 기본형에 그리면 사용자가 눌러 보고
            // 아무 일도 안 일어나는 것을 겪는다.
            if variable.isExpandable {
                Button {
                    onToggleVariable(row)
                } label: {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: Metrics.disclosureSize))
                        .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
                        .frame(width: Metrics.disclosureWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.isExpanded ? "\(variable.name) 접기" : "\(variable.name) 펼치기")
            } else {
                Spacer().frame(width: Metrics.disclosureWidth)
            }
            Text(variable.name)
                .font(.system(size: DesignTokens.Typography.bodySize, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.textPrimary.dynamicColor)
            Text(DebugTypeName.readable(variable.typeSignature))
                .font(.system(size: DesignTokens.Typography.secondarySize, design: .monospaced))
                .foregroundStyle(DesignTokens.textTertiary.dynamicColor)
            Spacer(minLength: DesignTokens.Spacing.medium)
            Text(variable.value)
                .font(.system(size: DesignTokens.Typography.bodySize, design: .monospaced))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // 줄 아무 데나 눌러도 열린다. 삼각형만 눌러야 하면 표적이 너무 작다.
        .onTapGesture { if variable.isExpandable { onToggleVariable(row) } }
    }

    private enum Metrics {
        static let indentPerDepth: CGFloat = 14
        static let disclosureWidth: CGFloat = 14
        static let disclosureSize: CGFloat = 9
    }
}
