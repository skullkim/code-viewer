import Foundation

/// One line of a `.gitignore` file, compiled to a matcher.
///
/// Patterns are translated to regular expressions because gitignore globs have three behaviours
/// a simple `fnmatch` does not give us: `*` must not cross a slash, `**` must cross any number of
/// them, and a pattern containing a slash anchors to its own directory while one without matches
/// at any depth.
struct GitignorePattern {
    let isNegated: Bool
    let matchesDirectoriesOnly: Bool
    private let expression: NSRegularExpression

    /// Parses one line. Returns `nil` for blank lines, comments, and lines that cannot compile —
    /// an unparseable line is skipped rather than failing the whole scan.
    init?(line rawLine: String) {
        var line = Self.stripTrailingWhitespace(rawLine)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        if line.hasPrefix("!") {
            isNegated = true
            line = String(line.dropFirst())
        } else {
            isNegated = false
            // A leading '#' or '!' can be escaped to be taken literally.
            if line.hasPrefix("\\#") || line.hasPrefix("\\!") {
                line = String(line.dropFirst())
            }
        }
        guard !line.isEmpty else { return nil }

        if line.hasSuffix("/") {
            matchesDirectoriesOnly = true
            line = String(line.dropLast())
        } else {
            matchesDirectoriesOnly = false
        }
        guard !line.isEmpty else { return nil }

        // A slash anywhere but the (already removed) trailing position anchors the pattern to the
        // directory holding the .gitignore. Without one, the pattern matches at any depth.
        let isAnchored = line.dropLast().contains("/") || line.hasPrefix("/")
        if line.hasPrefix("/") {
            line = String(line.dropFirst())
        }

        guard let expression = Self.compile(glob: line, anchored: isAnchored) else { return nil }
        self.expression = expression
    }

    /// Matches a path expressed relative to the directory holding this pattern's `.gitignore`.
    func matches(relativePath: String, isDirectory: Bool) -> Bool {
        if matchesDirectoriesOnly, !isDirectory {
            return false
        }
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return expression.firstMatch(in: relativePath, options: [], range: range) != nil
    }

    // MARK: - Parsing helpers

    /// Removes trailing spaces, which git treats as insignificant unless backslash-escaped.
    private static func stripTrailingWhitespace(_ line: String) -> String {
        var characters = Array(line)
        while let last = characters.last, last == " " || last == "\t" {
            // A backslash immediately before the space escapes it, so the space is meaningful.
            let escapedByBackslash = characters.count >= 2 && characters[characters.count - 2] == "\\"
            if escapedByBackslash {
                characters.removeLast(2)
                characters.append(last)
                return String(characters)
            }
            characters.removeLast()
        }
        return String(characters)
    }

    private static func compile(glob: String, anchored: Bool) -> NSRegularExpression? {
        var pattern = anchored ? "^" : "^(?:.*/)?"
        pattern += translate(glob: glob)
        // A matched directory carries everything beneath it, so allow a trailing subpath.
        pattern += "(?:/.*)?$"
        return try? NSRegularExpression(pattern: pattern)
    }

    /// Translates gitignore glob syntax to a regular expression body.
    private static func translate(glob: String) -> String {
        var result = ""
        let characters = Array(glob)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                let isDoubleStar = index + 1 < characters.count && characters[index + 1] == "*"
                if isDoubleStar {
                    index += 2
                    // "a/**/b" must also match "a/b", so consume the following slash here and
                    // make the whole directory span optional.
                    if index < characters.count, characters[index] == "/" {
                        index += 1
                        result += "(?:.*/)?"
                    } else {
                        result += ".*"
                    }
                    continue
                }
                result += "[^/]*"

            case "?":
                result += "[^/]"

            case "[":
                if let (classPattern, nextIndex) = characterClass(from: characters, at: index) {
                    result += classPattern
                    index = nextIndex
                    continue
                }
                result += "\\["

            case "\\":
                index += 1
                if index < characters.count {
                    result += NSRegularExpression.escapedPattern(for: String(characters[index]))
                }

            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return result
    }

    /// Reads a bracket expression, translating git's `!` negation to the regex `^` form.
    private static func characterClass(
        from characters: [Character],
        at start: Int
    ) -> (pattern: String, nextIndex: Int)? {
        var index = start + 1
        var body = ""
        if index < characters.count, characters[index] == "!" || characters[index] == "^" {
            body += "^"
            index += 1
        }
        var sawContent = false
        while index < characters.count {
            let character = characters[index]
            if character == "]", sawContent {
                return ("[" + body + "]", index + 1)
            }
            sawContent = true
            if character == "\\" {
                body += "\\\\"
            } else {
                body.append(character)
            }
            index += 1
        }
        return nil
    }
}
