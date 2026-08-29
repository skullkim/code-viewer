/// Extracts the lowercased extension of a path, or `nil` when the last component has none.
///
/// A leading dot does not count as an extension separator, so `.gitignore` has no extension.
enum FileExtension {
    static func of(filePath: String) -> String? {
        guard let lastSlash = filePath.lastIndex(of: "/") else {
            return extensionOfComponent(filePath)
        }
        let component = String(filePath[filePath.index(after: lastSlash)...])
        return extensionOfComponent(component)
    }

    private static func extensionOfComponent(_ component: String) -> String? {
        guard let lastDot = component.lastIndex(of: "."), lastDot != component.startIndex else {
            return nil
        }
        let text = component[component.index(after: lastDot)...]
        guard !text.isEmpty else { return nil }
        return text.lowercased()
    }
}
