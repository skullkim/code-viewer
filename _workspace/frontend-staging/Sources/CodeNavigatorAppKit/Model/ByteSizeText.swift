/// Formats a byte count for the status bar's save confirmation.
///
/// Deliberately not `ByteCountFormatter`: that one is locale-dependent and uses decimal
/// units, and the status bar has a fixed narrow slot where "8.1KB" fits and
/// "8,294 bytes" does not.
public enum ByteSizeText {
    private static let kilobyte = 1024.0
    private static let megabyte = kilobyte * 1024

    public static func string(fromByteCount byteCount: Int) -> String {
        let bytes = Double(byteCount)
        if bytes < kilobyte {
            return "\(byteCount)B"
        }
        if bytes < megabyte {
            return String(format: "%.1fKB", bytes / kilobyte)
        }
        return String(format: "%.1fMB", bytes / megabyte)
    }
}
