import CodeNavigatorContract

/// The line-number gutter, as the tests have to account for it.
///
/// The gutter arrived with REQ-016 and moved two things every mouse and grid test depends on:
/// screen columns shift right by its width, and a grid row's text now begins with a number that
/// is not in the buffer. Both were encoded as bare literals across three files, so both are here
/// instead — one place to change when `numberwidth` does.

/// Neovim's `numberwidth` default. Files past 999 lines widen it; no fixture here is that long.
let gutterColumns = 4

/// A grid line's text with the gutter dropped, for comparing against buffer content.
///
/// Drops the leading run rather than stripping digits with a pattern: a buffer line may itself
/// start with a number, and a pattern would silently eat it. The gutter is its own run, so
/// dropping one run is exact.
func codeText(of line: EditorGridLine) -> String {
    let withoutGutter = line.runs.dropFirst()
    return withoutGutter.map(\.text).joined().trimmingCharacters(in: .whitespaces)
}
