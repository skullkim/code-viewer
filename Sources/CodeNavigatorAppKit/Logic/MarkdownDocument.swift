import Foundation

/// Turns markdown into the HTML fragment that the sandbox pass then rewrites (REQ-013 AC-1,
/// ADR-0109).
///
/// **This is not a security boundary and must never be mistaken for one.** Markdown may
/// contain raw HTML, and this converter passes it through deliberately — ADR-0109 put
/// markdown and HTML on *one* surface precisely so there would be one boundary to get right.
/// Filtering here would create a second, weaker one and invite the belief that the output is
/// already safe. Everything this emits still goes through `RenderDocumentSanitizer`.
///
/// What it *is* responsible for is not manufacturing markup that was never in the document.
/// Text, code, and URLs that came from the file are escaped, so a `<` in prose stays a `<`
/// and a quote inside a link target cannot end the attribute it sits in. That distinction is
/// the whole contract: **pass through what the author wrote as markup, escape what the author
/// wrote as text, and never turn the second into the first.**
///
/// A deliberate subset of CommonMark, chosen for what documentation in a source repository
/// actually uses. Known gaps, all of which degrade to visible text rather than broken markup:
/// nested lists flatten to one level, reference-style links are not resolved, and
/// footnotes are not supported.
public enum MarkdownDocument {

    /// A fragment, not a page — no `<html>` or `<head>`. The sanitizer prepends the CSP meta
    /// tag to a headless fragment, which is the shape markdown produces.
    public static func html(from markdown: String) -> String {
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        return blocks(from: normalised.components(separatedBy: "\n")).joined(separator: "\n")
    }

    // MARK: 블록

    private static func blocks(from lines: [String]) -> [String] {
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }
            if let fence = fenceMarker(trimmed) {
                output.append(fencedBlock(lines, from: &index, fence: fence))
                continue
            }
            if isThematicBreak(trimmed) {
                output.append("<hr>")
                index += 1
                continue
            }
            if let heading = atxHeading(trimmed) {
                output.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                output.append(blockquote(lines, from: &index))
                continue
            }
            if listMarker(trimmed) != nil {
                output.append(list(lines, from: &index))
                continue
            }
            if let table = table(lines, from: &index) {
                output.append(table)
                continue
            }
            if trimmed.hasPrefix("<") {
                output.append(rawHTMLBlock(lines, from: &index))
                continue
            }
            output.append(paragraph(lines, from: &index))
        }

        return output
    }

    /// A fenced block, closed at the fence or at the end of the document.
    ///
    /// An unclosed fence still closes. AC-6 forbids a blank screen on broken markup, and
    /// leaving `<pre><code>` open hands the rest of the document to the browser's error
    /// recovery — which is a different renderer's opinion, not ours.
    private static func fencedBlock(
        _ lines: [String],
        from index: inout Int,
        fence: (marker: Character, length: Int, info: String)
    ) -> String {
        index += 1
        var content: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if isClosingFence(trimmed, fence: fence) {
                index += 1
                break
            }
            content.append(lines[index])
            index += 1
        }

        let language = fence.info.split(separator: " ").first.map(String.init) ?? ""
        let opening = language.isEmpty
            ? "<pre><code>"
            : "<pre><code class=\"language-\(escapedAttribute(language))\">"
        return opening + escaped(content.joined(separator: "\n")) + "</code></pre>"
    }

    private static func blockquote(_ lines: [String], from index: inout Int) -> String {
        var inner: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else {
                break
            }
            var stripped = String(trimmed.dropFirst())
            if stripped.hasPrefix(" ") {
                stripped.removeFirst()
            }
            inner.append(stripped)
            index += 1
        }

        return "<blockquote>" + blocks(from: inner).joined(separator: "\n") + "</blockquote>"
    }

    private static func list(_ lines: [String], from index: inout Int) -> String {
        guard let first = listMarker(lines[index].trimmingCharacters(in: .whitespaces)) else {
            return ""
        }
        let ordered = first.isOrdered
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let marker = listMarker(trimmed), marker.isOrdered == ordered else {
                break
            }
            index += 1

            // An item runs until something else starts one. Treating a bare following line
            // as the end of the list drops it out of the item entirely — and takes any
            // emphasis opened on the first line with it, which inverts the rest exactly the
            // way per-line paragraphs did. One item, one inline call.
            var itemLines = [marker.content]
            while index < lines.count {
                let continuation = lines[index].trimmingCharacters(in: .whitespaces)
                guard !continuation.isEmpty, !startsANewBlock(continuation) else {
                    break
                }
                itemLines.append(continuation)
                index += 1
            }

            items.append("<li>\(inline(itemLines.joined(separator: "\n")))</li>")
        }

        let tag = ordered ? "ol" : "ul"
        return "<\(tag)>" + items.joined() + "</\(tag)>"
    }

    /// Raw HTML, handed on untouched — see the type comment. The run ends at a blank line.
    private static func rawHTMLBlock(_ lines: [String], from index: inout Int) -> String {
        var content: [String] = []

        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            content.append(lines[index])
            index += 1
        }

        return content.joined(separator: "\n")
    }

    private static func paragraph(_ lines: [String], from index: inout Int) -> String {
        var content: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                break
            }
            // A setext underline turns the paragraph so far into a heading. Checked before
            // the thematic break, because `text` over `---` is a heading and `---` alone is
            // a rule — the difference is only what precedes it.
            if !content.isEmpty, let level = setextLevel(trimmed) {
                index += 1
                return "<h\(level)>\(inline(content.joined(separator: " ")))</h\(level)>"
            }
            if !content.isEmpty, startsANewBlock(trimmed) {
                break
            }
            content.append(lines[index])
            index += 1
        }

        return "<p>" + inline(paragraphText(content)) + "</p>"
    }

    /// The lines of a paragraph joined into the single string that inline parsing runs over.
    ///
    /// **One call for the whole paragraph, not one per line.** Emphasis, code spans, and
    /// links may cross a line break, and per-line parsing does not merely miss them — it
    /// gets them backwards. A `**` that closes on the second line is read there as an
    /// opening one, so the span pairs with the *next* delimiter and the emphasis inverts:
    /// the phrase the author emphasised comes out plain, and the phrase between it and the
    /// next marker comes out bold. Measured on real documents, not imagined.
    ///
    /// Hard breaks are folded in here because they are the one thing that is genuinely
    /// per-line: two trailing spaces mean a line break, and trimming the lines first would
    /// erase the only evidence. `<br>` survives inline parsing as raw HTML, which is the
    /// same passthrough every other tag in the document gets.
    private static func paragraphText(_ lines: [String]) -> String {
        lines
            .map { line in
                let isHardBreak = line.hasSuffix("  ")
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return isHardBreak ? trimmed + "<br>" : trimmed
            }
            .joined(separator: "\n")
    }

    /// Whether a line interrupts an open paragraph.
    private static func startsANewBlock(_ trimmed: String) -> Bool {
        fenceMarker(trimmed) != nil
            || isThematicBreak(trimmed)
            || atxHeading(trimmed) != nil
            || trimmed.hasPrefix(">")
            || listMarker(trimmed) != nil
            || trimmed.hasPrefix("<")
    }

    // MARK: 블록 인식

    private static func fenceMarker(_ trimmed: String) -> (marker: Character, length: Int, info: String)? {
        for marker in ["`", "~"] {
            guard trimmed.hasPrefix(String(repeating: marker, count: 3)) else {
                continue
            }
            let character = Character(marker)
            let length = trimmed.prefix { $0 == character }.count
            let info = String(trimmed.dropFirst(length)).trimmingCharacters(in: .whitespaces)
            // An info string cannot contain the fence character — that would be a code span.
            guard !info.contains(character) else {
                continue
            }
            return (character, length, info)
        }
        return nil
    }

    private static func isClosingFence(
        _ trimmed: String,
        fence: (marker: Character, length: Int, info: String)
    ) -> Bool {
        let run = trimmed.prefix { $0 == fence.marker }.count
        return run >= fence.length && trimmed.dropFirst(run).allSatisfy { $0 == " " }
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let stripped = trimmed.filter { $0 != " " }
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else {
            return false
        }
        return stripped.allSatisfy { $0 == first }
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        guard let first = trimmed.first, first == "=" || first == "-" else {
            return nil
        }
        guard trimmed.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first == "=" ? 1 : 2
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let level = trimmed.prefix { $0 == "#" }.count
        // Seven is not a level. Without the upper bound this emits `<h7>`, which no browser
        // knows and no stylesheet targets.
        guard (1...6).contains(level) else {
            return nil
        }
        let rest = String(trimmed.dropFirst(level))
        guard rest.isEmpty || rest.hasPrefix(" ") else {
            return nil
        }
        // A closing run of hashes is decoration, not content.
        let text = rest.trimmingCharacters(in: .whitespaces)
        return (level, String(text.reversed().drop { $0 == "#" }.reversed()).trimmingCharacters(in: .whitespaces))
    }

    private static func listMarker(_ trimmed: String) -> (isOrdered: Bool, content: String)? {
        for marker in ["-", "*", "+"] where trimmed.hasPrefix(marker + " ") {
            return (false, String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }

        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else {
            return nil
        }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") else {
            return nil
        }
        return (true, String(afterDigits.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    // MARK: 표

    private static func table(_ lines: [String], from index: inout Int) -> String? {
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), index + 1 < lines.count else {
            return nil
        }
        let alignments = delimiterAlignments(lines[index + 1].trimmingCharacters(in: .whitespaces))
        // Without a delimiter row it is a paragraph that happens to contain pipes. Treating
        // every pipe as a table turns ordinary prose into a one-cell grid.
        guard let alignments, !alignments.isEmpty else {
            return nil
        }

        let headerCells = rowCells(header)
        var body: [String] = []
        index += 2

        while index < lines.count {
            let row = lines[index].trimmingCharacters(in: .whitespaces)
            guard row.contains("|"), !row.isEmpty else {
                break
            }
            let cells = rowCells(row).enumerated().map { position, cell in
                "<td\(alignmentAttribute(alignments, at: position))>\(inline(cell))</td>"
            }
            body.append("<tr>" + cells.joined() + "</tr>")
            index += 1
        }

        let head = headerCells.enumerated().map { position, cell in
            "<th\(alignmentAttribute(alignments, at: position))>\(inline(cell))</th>"
        }
        return "<table><thead><tr>" + head.joined() + "</tr></thead><tbody>"
            + body.joined() + "</tbody></table>"
    }

    /// Splits a row on its cell dividers — the *unescaped* ones.
    ///
    /// `\|` is a literal pipe inside a cell, and it is the only way to write one, because a
    /// table row is split before any inline parsing happens: a pipe inside a code span is
    /// still a divider. Splitting on every pipe tears the code span in half and leaves the
    /// backslash showing. Found in our own design document, which writes
    /// `` `.opened(id) \| .failed(e)` `` in a table — so this is not a hypothetical.
    private static func rowCells(_ row: String) -> [String] {
        var trimmed = Substring(row)
        if trimmed.hasPrefix("|") {
            trimmed = trimmed.dropFirst()
        }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") {
            trimmed = trimmed.dropLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in trimmed {
            if isEscaped {
                // Only `\|` is consumed here. Every other backslash belongs to the inline
                // parser, which has its own escapes — eating them would silently change what
                // `\*` means depending on whether it sits in a table.
                if character == "|" {
                    current.append("|")
                } else {
                    current.append("\\")
                    current.append(character)
                }
                isEscaped = false
                continue
            }
            switch character {
            case "\\":
                isEscaped = true
            case "|":
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }

        if isEscaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func delimiterAlignments(_ row: String) -> [String?]? {
        guard row.contains("-"), row.contains("|") || row.hasPrefix(":") || row.hasPrefix("-") else {
            return nil
        }
        var alignments: [String?] = []

        for cell in rowCells(row) {
            let body = cell.trimmingCharacters(in: .whitespaces)
            let leading = body.hasPrefix(":")
            let trailing = body.hasSuffix(":")
            let dashes = body.dropFirst(leading ? 1 : 0).dropLast(trailing ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            switch (leading, trailing) {
            case (true, true): alignments.append("center")
            case (true, false): alignments.append("left")
            case (false, true): alignments.append("right")
            case (false, false): alignments.append(nil)
            }
        }

        return alignments
    }

    private static func alignmentAttribute(_ alignments: [String?], at position: Int) -> String {
        guard position < alignments.count, let alignment = alignments[position] else {
            return ""
        }
        return " style=\"text-align:\(alignment)\""
    }

    // MARK: 인라인

    private static func inline(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        var position = 0

        while position < characters.count {
            let character = characters[position]

            switch character {
            case "\\":
                // A backslash escape is the author saying "this is a character, not syntax".
                if position + 1 < characters.count, isPunctuation(characters[position + 1]) {
                    output += escaped(String(characters[position + 1]))
                    position += 2
                    continue
                }
                output += "\\"
                position += 1

            case "`":
                if let span = codeSpan(characters, at: position) {
                    output += span.html
                    position = span.end
                    continue
                }
                output += "`"
                position += 1

            case "!":
                if let link = linkLike(characters, at: position + 1), characters.count > position + 1 {
                    output += "<img src=\"\(escapedAttribute(link.url))\""
                        + " alt=\"\(escapedAttribute(link.label))\">"
                    position = link.end
                    continue
                }
                output += "!"
                position += 1

            case "[":
                if let link = linkLike(characters, at: position) {
                    output += "<a href=\"\(escapedAttribute(link.url))\">\(inline(link.label))</a>"
                    position = link.end
                    continue
                }
                output += "["
                position += 1

            case "*", "_":
                if let span = emphasis(characters, at: position, marker: character) {
                    output += span.html
                    position = span.end
                    continue
                }
                output += String(character)
                position += 1

            case "<":
                // Raw inline HTML is passed through for the same reason as a raw block; a `<`
                // that does not begin a tag is text, and text is escaped.
                if let length = rawTagLength(characters, at: position) {
                    output += String(characters[position..<(position + length)])
                    position += length
                    continue
                }
                output += "&lt;"
                position += 1

            case ">":
                output += "&gt;"
                position += 1

            case "&":
                // An entity the author already wrote stays an entity. Escaping it again shows
                // the reader `&amp;` where they wrote `&`.
                if let length = entityLength(characters, at: position) {
                    output += String(characters[position..<(position + length)])
                    position += length
                    continue
                }
                output += "&amp;"
                position += 1

            default:
                output.append(character)
                position += 1
            }
        }

        return output
    }

    private static func codeSpan(_ characters: [Character], at start: Int) -> (html: String, end: Int)? {
        var length = 0
        while start + length < characters.count, characters[start + length] == "`" {
            length += 1
        }
        let fence = Array(repeating: Character("`"), count: length)
        guard let close = firstIndex(of: fence, in: characters, from: start + length) else {
            return nil
        }

        var content = String(characters[(start + length)..<close])
        // CommonMark strips one padding space from each side, so `` ` `` can be shown.
        if content.count > 2, content.hasPrefix(" "), content.hasSuffix(" ") {
            content = String(content.dropFirst().dropLast())
        }
        // Escaped, never inlined: the point of a code span is that its content is not markup.
        return ("<code>" + escaped(content) + "</code>", close + length)
    }

    private static func emphasis(
        _ characters: [Character],
        at start: Int,
        marker: Character
    ) -> (html: String, end: Int)? {
        // Strong is tested first. With emphasis first, `**x**` matches the single-marker rule
        // and produces an empty `<em>` wrapped around a stray marker.
        if start + 1 < characters.count, characters[start + 1] == marker {
            let doubled = [marker, marker]
            if let close = firstIndex(of: doubled, in: characters, from: start + 2), close > start + 2 {
                let inner = String(characters[(start + 2)..<close])
                return ("<strong>" + inline(inner) + "</strong>", close + 2)
            }
        }

        if let close = firstIndex(of: [marker], in: characters, from: start + 1), close > start + 1 {
            let inner = String(characters[(start + 1)..<close])
            return ("<em>" + inline(inner) + "</em>", close + 1)
        }

        return nil
    }

    private static func linkLike(
        _ characters: [Character],
        at start: Int
    ) -> (label: String, url: String, end: Int)? {
        guard start < characters.count, characters[start] == "[" else {
            return nil
        }
        guard let labelEnd = firstIndex(of: ["]"], in: characters, from: start + 1) else {
            return nil
        }
        let urlStart = labelEnd + 1
        guard urlStart < characters.count, characters[urlStart] == "(" else {
            return nil
        }
        guard let urlEnd = firstIndex(of: [")"], in: characters, from: urlStart + 1) else {
            return nil
        }

        let label = String(characters[(start + 1)..<labelEnd])
        // A title (`[x](url "title")`) is dropped rather than half-parsed — showing a tooltip
        // we did not parse correctly is worse than showing none.
        let target = String(characters[(urlStart + 1)..<urlEnd])
        let url = target.split(separator: " ").first.map(String.init) ?? target
        return (label, url, urlEnd + 1)
    }

    /// The length of a raw HTML tag or comment beginning at `start`, if there is one.
    private static func rawTagLength(_ characters: [Character], at start: Int) -> Int? {
        if matches(["<", "!", "-", "-"], in: characters, at: start) {
            guard let close = firstIndex(of: ["-", "-", ">"], in: characters, from: start + 4) else {
                return nil
            }
            return close + 3 - start
        }

        var position = start + 1
        if position < characters.count, characters[position] == "/" {
            position += 1
        }
        guard position < characters.count, characters[position].isLetter else {
            return nil
        }

        // Quote-aware: a `>` inside an attribute value does not end the tag. The same lesson
        // the sanitizer's scanner learned — the first `>` is not always the tag's `>`.
        var quote: Character?
        while position < characters.count {
            let character = characters[position]
            if let open = quote {
                if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return position + 1 - start
            }
            position += 1
        }
        return nil
    }

    /// The length of a character entity beginning at `start`, if there is one.
    private static func entityLength(_ characters: [Character], at start: Int) -> Int? {
        var position = start + 1
        if position < characters.count, characters[position] == "#" {
            position += 1
        }
        let nameStart = position
        while position < characters.count, characters[position].isLetter || characters[position].isNumber {
            position += 1
        }
        guard position > nameStart, position < characters.count, characters[position] == ";" else {
            return nil
        }
        return position + 1 - start
    }

    // MARK: 이스케이프

    // 이스케이프는 `HTMLText` 하나만 쓴다 — 규칙이 두 벌이면 한쪽만 고쳐지고, 안 고쳐진
    // 쪽이 곧 아무도 안 본 경로가 된다.
    private static func escaped(_ text: String) -> String { HTMLText.escaped(text) }
    private static func escapedAttribute(_ text: String) -> String { HTMLText.escapedAttribute(text) }

    private static func isPunctuation(_ character: Character) -> Bool {
        ##"\`*_{}[]()#+-.!|<>&"'~"##.contains(character)
    }

    // MARK: 스캐닝 보조

    private static func firstIndex(
        of needle: [Character],
        in characters: [Character],
        from start: Int
    ) -> Int? {
        guard !needle.isEmpty, start >= 0 else {
            return nil
        }
        var position = start
        while position + needle.count <= characters.count {
            if matches(needle, in: characters, at: position) {
                return position
            }
            position += 1
        }
        return nil
    }

    private static func matches(_ needle: [Character], in characters: [Character], at start: Int) -> Bool {
        guard start >= 0, start + needle.count <= characters.count else {
            return false
        }
        for offset in 0..<needle.count where characters[start + offset] != needle[offset] {
            return false
        }
        return true
    }
}
