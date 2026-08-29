/// A file Neovim has just written.
///
/// The line count and size come from Neovim, which already knows them at the moment it saves.
/// Having the application re-read the file to count would both duplicate the work and put
/// application code back in the business of reading the repository after a write.
public struct SavedFile: Sendable, Hashable {
    /// Absolute path, as Neovim reports it.
    public let path: String
    public let lineCount: Int
    public let byteSize: Int

    public init(path: String, lineCount: Int, byteSize: Int) {
        self.path = path
        self.lineCount = lineCount
        self.byteSize = byteSize
    }
}
