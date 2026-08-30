import Foundation

/// The text a render view draws, and where it came from.
///
/// Rendering reads; it never writes (REQ-013 AC-4, INV-3). Every read of project text for the
/// render view goes through this one door so the sandbox rule — local file access stays inside
/// the open project root (INV-6) — is enforced at a boundary rather than remembered at each
/// call site. Two places reading files their own way is how the two rules drift apart.
public struct RenderSource: Sendable, Hashable {

    /// Which copy of the document this is.
    ///
    /// The user has to be told, because the two can disagree. Preview is usually opened to see
    /// how the thing just typed looks, so the buffer is what they mean by "the document"; but a
    /// dead edit session leaves only the file on disk, and drawing that silently shows a document
    /// missing the paragraph they just wrote. That is not "slightly stale", it is wrong, and they
    /// will go looking for the mistake in their own writing.
    public enum Origin: Sendable, Hashable {
        /// The live Neovim buffer — what the user is looking at, saved or not.
        case editorBuffer
        /// The file on disk. The editor is not holding this file, so this is the whole truth.
        case savedFile
    }

    /// Past this, rendering is refused rather than truncated.
    ///
    /// Truncating reads as "the document ends here", which is a silent lie about someone's
    /// content. Refusing says what happened and offers the source view instead
    /// (design §7.2, §12 judgement 6).
    ///
    /// 🔴 This is **not** `SourceFileReader.maximumFileSizeInBytes`, which is half as large and
    /// belongs to indexing. Reusing that one would turn every file between the two limits into a
    /// silent empty result — exactly the blank screen REQ-013 AC-6 forbids.
    public static let maximumByteSize = 2 * 1_048_576

    /// The project-relative path this text belongs to.
    ///
    /// Echoed back because rendering is asynchronous and the user can move on before it lands:
    /// without it a view has no way to tell a late answer for the previous file from the answer
    /// it is waiting for, and would draw one document under another document's name.
    public let path: String

    /// The document text. Empty is a legitimate answer — an empty file is not a failure, and the
    /// view says so in its own words rather than the engine inventing an error for it.
    public let text: String

    public let origin: Origin

    public init(path: String, text: String, origin: Origin) {
        self.path = path
        self.text = text
        self.origin = origin
    }
}
