import SwiftUI
import CodeNavigatorContract

/// 실행 설정 편집 화면 (REQ-018).
///
/// 왼쪽에 설정 목록, 오른쪽에 그 설정의 명령·작업 폴더·환경변수 표. IntelliJ 의
/// "Run/Debug Configurations" 와 같은 배치다 — 설정이 여러 개일 때 무엇을 고치는 중인지가
/// 한눈에 보여야 한다.
public struct RunConfigurationEditorView: View {

    @State private var drafts: [RunConfigurationDraft]
    @State private var selection: UUID?
    private let onSave: ([RunConfiguration]) -> Void
    private let onCancel: () -> Void

    public init(
        configurations: [RunConfiguration],
        onSave: @escaping ([RunConfiguration]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let drafts = configurations.map(RunConfigurationDraft.init)
        _drafts = State(initialValue: drafts)
        _selection = State(initialValue: drafts.first?.id)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                configurationList
                Divider()
                detail
            }
            Divider()
            footer
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .background(DesignTokens.backgroundWindow.dynamicColor)
    }

    private var selectedIndex: Int? {
        drafts.firstIndex { $0.id == selection }
    }

    private var configurationList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(drafts) { draft in
                    Text(draft.name.isEmpty ? "이름 없는 설정" : draft.name)
                        .lineLimit(1)
                        .tag(draft.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: DesignTokens.Spacing.small) {
                Button {
                    let draft = RunConfigurationDraft.newDraft(existing: drafts)
                    drafts.append(draft)
                    selection = draft.id
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("설정 추가")

                Button {
                    guard let index = selectedIndex else { return }
                    drafts.remove(at: index)
                    // 지운 자리 근처를 다시 고른다. 아무것도 안 고른 채로 두면 오른쪽이
                    // 통째로 비어서 사용자는 화면이 깨진 것으로 읽는다.
                    selection = drafts[safe: index]?.id ?? drafts.last?.id
                } label: {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("설정 삭제")
                .disabled(selection == nil)

                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .padding(DesignTokens.Spacing.small)
        }
        .frame(width: Metrics.listWidth)
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    field("이름", text: $drafts[index].name, prompt: "서버")
                    field(
                        "명령", text: $drafts[index].command,
                        prompt: "./gradlew bootRun"
                    )
                    field(
                        "작업 폴더", text: $drafts[index].workingDirectory,
                        prompt: "비우면 프로젝트 최상위"
                    )
                    environmentTable(index: index)
                }
                .padding(DesignTokens.Spacing.large)
            }
        } else {
            PanelMessage(text: "+ 를 눌러 실행 설정을 추가하세요.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.system(size: DesignTokens.Typography.secondarySize, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func environmentTable(index: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                Text("환경변수")
                    .font(.system(size: DesignTokens.Typography.secondarySize, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
                Spacer(minLength: 0)
                Button("추가") { drafts[index].addEnvironmentRow() }
                    .controlSize(.small)
            }

            if drafts[index].environmentRows.isEmpty {
                Text("없음. 추가를 눌러 `이름`과 `값`을 적으면 실행하는 프로세스가 물려받습니다.")
                    .font(.system(size: DesignTokens.Typography.secondarySize))
                    .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            } else {
                ForEach(drafts[index].environmentRows) { row in
                    if let rowIndex = drafts[index].environmentRows.firstIndex(where: { $0.id == row.id }) {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            TextField("이름", text: $drafts[index].environmentRows[rowIndex].key)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: Metrics.keyWidth)
                            TextField("값", text: $drafts[index].environmentRows[rowIndex].value)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                drafts[index].removeEnvironmentRow(id: row.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("환경변수 삭제")
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text("디버그 실행은 JDWP 인자를 자동으로 붙입니다 — 명령에 직접 적지 마세요.")
                .font(.system(size: DesignTokens.Typography.secondarySize))
                .foregroundStyle(DesignTokens.textSecondary.dynamicColor)
            Spacer(minLength: DesignTokens.Spacing.medium)
            Button("취소", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("저장") { onSave(RunConfigurationDraft.configurations(from: drafts)) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(DesignTokens.Spacing.large)
    }

    private enum Metrics {
        static let width: CGFloat = 640
        static let height: CGFloat = 420
        static let listWidth: CGFloat = 180
        static let keyWidth: CGFloat = 160
    }
}

private extension Array {
    /// 지운 자리를 다시 고를 때 쓴다. 범위를 벗어나면 nil — 마지막 줄을 지운 경우다.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
