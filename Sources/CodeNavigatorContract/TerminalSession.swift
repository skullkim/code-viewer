import Foundation

/// 앱이 터미널에게 바라는 것. 실제 구현은 Core 가, 테스트는 가짜가 준다.
public protocol TerminalSession: Sendable {
    func start(
        command: String, workingDirectory: String, environment: [String: String],
        columns: Int, rows: Int
    ) async throws
    func send(keys: String) async
    func resize(columns: Int, rows: Int) async
    func stop() async
    func gridUpdates() async -> AsyncStream<EditorGridSnapshot>
}

/// 편집기 아래 패널의 탭.
public enum BottomPanelTab: String, Sendable, Hashable, CaseIterable, Identifiable {
    case debug
    case terminal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .debug: return "디버그"
        case .terminal: return "터미널"
        }
    }
}
