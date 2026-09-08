import CodeNavigatorContract
import Foundation

/// 편집 중인 실행 설정 하나.
///
/// 저장 형식(`RunConfiguration`)과 따로 두는 이유는 **순서**다. 환경변수는 사전이라 순서가
/// 없는데, 표는 순서가 있어야 한다 — 사용자가 친 줄이 매 렌더마다 자리를 바꾸면 두 줄짜리
/// 표도 못 쓴다. 이름도 마찬가지다: 저장 형식은 이름이 곧 id 라 중간 상태로 이름이 비거나
/// 겹칠 수 있는 편집 중에는 쓸 수 없다.
public struct RunConfigurationDraft: Identifiable, Hashable {

    /// 표 한 줄. `id` 가 있어야 `ForEach` 가 줄을 헷갈리지 않는다 — 키로 잡으면 사용자가
    /// 키를 고치는 순간 줄이 새것으로 바뀌면서 입력 포커스가 튄다.
    public struct EnvironmentRow: Identifiable, Hashable {
        public let id: UUID
        public var key: String
        public var value: String

        public init(id: UUID = UUID(), key: String, value: String) {
            self.id = id
            self.key = key
            self.value = value
        }
    }

    public let id: UUID
    public var name: String
    public var command: String
    public var workingDirectory: String
    public var environmentRows: [EnvironmentRow]
    /// 디버그 실행일 때 에이전트를 어디에 붙일지.
    public var debugLaunch: DebugLaunchStrategy

    public init(_ configuration: RunConfiguration) {
        self.id = UUID()
        self.name = configuration.name
        self.command = configuration.command
        self.workingDirectory = configuration.workingDirectory
        self.debugLaunch = configuration.debugLaunch
        // 이름순으로 편다. 사전 순회 순서는 실행마다 달라서, 그대로 쓰면 열 때마다 표의
        // 줄 순서가 바뀐다.
        self.environmentRows = configuration.environment
            .sorted { $0.key < $1.key }
            .map { EnvironmentRow(key: $0.key, value: $0.value) }
    }

    public mutating func addEnvironmentRow() {
        environmentRows.append(EnvironmentRow(key: "", value: ""))
    }

    public mutating func removeEnvironmentRow(id rowID: UUID) {
        environmentRows.removeAll { $0.id == rowID }
    }

    /// 저장 형식으로 되돌린다. 이름은 손대지 않는다 — 겹침 해소는 목록 전체를 봐야 한다.
    public func configuration() -> RunConfiguration {
        var environment: [String: String] = [:]
        for row in environmentRows {
            // 키만 다듬는다. 붙여넣기로 딸려 온 공백 하나 때문에 `PORT` 가 안 먹는 일을
            // 막되, 값의 공백은 의미가 있을 수 있어 그대로 둔다.
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            environment[key] = row.value
        }
        return RunConfiguration(
            name: name, command: command, workingDirectory: workingDirectory,
            environment: environment, debugLaunch: debugLaunch
        )
    }

    /// 목록 전체를 저장 형식으로 옮긴다. 이름 겹침과 빈 값을 여기서 정리한다.
    public static func configurations(from drafts: [RunConfigurationDraft]) -> [RunConfiguration] {
        var used: Set<String> = []
        var result: [RunConfiguration] = []

        for draft in drafts {
            var configuration = draft.configuration()
            // 명령이 없으면 눌러도 아무 일이 안 일어난다. 목록에 남겨 두면 사용자는 고장으로
            // 읽는다.
            guard !configuration.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            var name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                name = Defaults.unnamed
            }
            // 이름이 곧 id 다. 겹치면 고르개가 한 줄만 보여 주고 나머지는 영영 못 고른다.
            name = uniqueName(startingFrom: name, avoiding: used)
            used.insert(name)

            configuration.name = name
            result.append(configuration)
        }
        return result
    }

    /// 새로 만드는 설정. 바로 돌아가는 명령을 넣어 둔다 — 빈 명령이면 저장 단계에서 버려져서,
    /// 사용자는 "추가가 안 된다" 로 겪는다.
    public static func newDraft(existing: [RunConfigurationDraft]) -> RunConfigurationDraft {
        let taken = Set(existing.map(\.name))
        return RunConfigurationDraft(
            RunConfiguration(
                name: uniqueName(startingFrom: Defaults.newName, avoiding: taken),
                command: Defaults.newCommand,
                workingDirectory: "",
                environment: [:]
            )
        )
    }

    private static func uniqueName(startingFrom name: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var suffix = 2
        while taken.contains("\(name) \(suffix)") {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }

    private enum Defaults {
        static let unnamed = "이름 없는 설정"
        static let newName = "새 설정"
        /// 무엇이든 도는 명령. 사용자가 지울 자리 표시다.
        static let newCommand = "echo 실행할 명령을 적으세요"
    }
}
