import CodeNavigatorContract

/// Why a resource did not make it into a rendered document (W-14 · W-15).
///
/// This is a table, not a branch inside a view model, and the difference is the whole reason the
/// type exists. As a `switch` with a `default` inside `RenderDocumentModel` it was unreachable
/// from tests without standing up the model, so nothing walked it — and when `pathOutsideProject`
/// was added to `NavigatorError`, the `default` quietly swallowed it into `.notReadable`, which
/// `blockedKind()` maps to `nil`, which removes the block **from the list of blocks entirely**.
/// A real INV-6 rejection would have vanished from the screen. backend-senior caught it by
/// reverting the fix and measuring: three tests broke, all engine-level, and **zero** covered
/// this mapping.
///
/// Two properties keep that from recurring, and both are structural rather than diligent:
///
/// 1. **It is a pure function on a value**, so a test walks it without a view, a window, or a
///    session. `DefinitionRouting` has this shape, and that is exactly why `gd` was covered
///    while `gr` — whose identical decision sat inside a router function — was not.
/// 2. **There is no `default`.** Every case is named. Adding one to `NavigatorError` now fails
///    to compile here, which makes the compiler ask the question a reviewer would otherwise
///    have to remember to ask. Writing `default` is switching that help off; `route()` leaked
///    three defects through exactly that line.
enum RenderResourceFailureMapping {

    static func failure(for error: NavigatorError) -> RenderResourceFailure {
        switch error {
        case .fileNotFound:
            return .notFound

        case .fileTooLarge(_, let byteSize, let limit):
            return .tooLarge(byteSize: byteSize, limit: limit)

        // 둘 다 W-15 에게는 같은 사건이다 — 루트 제한 때문에 안 실었다. 엔진이 둘을 가르는 것은
        // 로그와 문장을 위해서고(계약 오용 vs INV-6 거절), 샌드박스 칩이 말할 것은 하나다.
        case .invalidPath, .pathOutsideProject:
            return .invalidPath

        // 나머지는 전부 "우리가 막은 게 아니라 못 읽었다"이다. 그래서 차단 칩에 올라가지 않고
        // (`blockedKind()` 가 nil), 문서에는 이유가 적힌 박스로 남는다 — 리더 판정에 따라
        // "차단"과 "실패"는 문패가 다르다. 이유 문자열을 싣는 것이 그 문패의 내용이다.
        case .projectNotFound, .projectNotReadable, .noProjectOpen,
             .fileNotReadable, .fileNotDecodable,
             .invalidRegularExpression,
             .editorNotInstalled, .editorUnavailable, .editorNotRunning, .editorRequestFailed:
            return .notReadable(error.errorDescription ?? "\(error)")
        }
    }
}
