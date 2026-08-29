import Foundation

/// Every failure the engine reports to the UI.
///
/// Each case carries enough detail for a specific message. Silence and empty results are never
/// used to signal failure — an invalid regular expression is an error, not zero matches.
public enum NavigatorError: Error, Sendable, Equatable {
    case projectNotFound(path: String)
    case projectNotReadable(path: String, reason: String)
    case noProjectOpen
    case invalidPath(String)
    case fileNotFound(path: String)
    case invalidRegularExpression(pattern: String, reason: String)
    case editorNotInstalled
    case editorUnavailable(reason: String)
    case editorNotRunning
    case editorRequestFailed(method: String, reason: String)
}

extension NavigatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "프로젝트 경로를 찾을 수 없습니다: \(path)"
        case .projectNotReadable(let path, let reason):
            return "프로젝트를 읽을 수 없습니다: \(path) (\(reason))"
        case .noProjectOpen:
            return "열려 있는 프로젝트가 없습니다."
        case .invalidPath(let path):
            return "잘못된 경로입니다: \(path)"
        case .fileNotFound(let path):
            return "파일을 찾을 수 없습니다: \(path)"
        case .invalidRegularExpression(let pattern, let reason):
            return "잘못된 정규식: \(pattern) — \(reason)"
        case .editorNotInstalled:
            return "Neovim을 찾을 수 없습니다. 설치 후 다시 시도하세요."
        case .editorUnavailable(let reason):
            return "편집 세션을 시작할 수 없습니다: \(reason)"
        case .editorNotRunning:
            return "편집 세션이 끊겼습니다. 재기동이 필요합니다."
        case .editorRequestFailed(let method, let reason):
            return "편집기 요청이 실패했습니다 (\(method)): \(reason)"
        }
    }
}
