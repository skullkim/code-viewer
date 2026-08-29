import Foundation

/// How long a status-bar message stays up (design §3 W-7).
///
/// An error is given longer than a success because it is the one the user has to read and
/// act on; a success only confirms what they just did. The persistent case — a lost edit
/// session — is not here at all: it is derived from the session state and clears when the
/// session comes back, not on a clock.
public enum StatusMessageDuration {
    public static let success: TimeInterval = 2
    public static let error: TimeInterval = 3

    public static func seconds(for kind: StatusMessage.Kind) -> TimeInterval {
        switch kind {
        case .success:
            return success
        case .error:
            return error
        }
    }
}
