import CodeNavigatorContract

/// Turns the design system's colours into the palette the editor paints code with.
///
/// This is the whole of the application's side of REQ-016: the classification is Neovim's
/// (ADR-0010) and the colours are the design system's (ADR-0112), so the only thing left is
/// naming which token plays which part. Keeping that as a pure function means the mapping can be
/// checked without an editor, which matters because a crossed wire here — `type` in the `keyword`
/// slot — produces a screen that is fully coloured and quietly wrong.
enum SyntaxPaletteBuilder {

    /// The palette for one appearance.
    ///
    /// Called again when the appearance changes; the session is expected to tolerate that
    /// (REQ-016 AC-6, and `applySyntaxPalette`'s own contract says so).
    /// 디버거 표시 색. 구문 팔레트와 따로 만든다 — 바뀌는 이유가 다르다.
    static func debugPalette(for scheme: AppearanceScheme) -> EditorDebugPalette {
        EditorDebugPalette(
            // 오류 빨강(`danger`)과 **다른 색**이다. 브레이크포인트는 사용자가 의도해서
            // 놓은 것이고 고장이 아닌데, 같은 빨강이면 화면이 매번 사고처럼 보인다.
            breakpointForeground: EditorColor(DesignTokens.debugBreakpoint.value(for: scheme)),
            stoppedLineBackground: EditorColor(DesignTokens.debugStoppedLine.value(for: scheme)),
            stoppedLineForeground: EditorColor(DesignTokens.debugStoppedArrow.value(for: scheme))
        )
    }

    /// 거터의 git 변경 막대 색.
    static func gitMarkerPalette(for scheme: AppearanceScheme) -> GitMarkerPalette {
        GitMarkerPalette(
            added: EditorColor(DesignTokens.gitAdded.value(for: scheme)),
            modified: EditorColor(DesignTokens.gitModified.value(for: scheme)),
            deleted: EditorColor(DesignTokens.gitDeleted.value(for: scheme))
        )
    }

    static func palette(for scheme: AppearanceScheme) -> EditorSyntaxPalette {
        EditorSyntaxPalette(
            keyword: EditorColor(DesignTokens.syntaxKeyword.value(for: scheme)),
            type: EditorColor(DesignTokens.syntaxType.value(for: scheme)),
            function: EditorColor(DesignTokens.syntaxFunction.value(for: scheme)),
            string: EditorColor(DesignTokens.syntaxString.value(for: scheme)),
            number: EditorColor(DesignTokens.syntaxNumber.value(for: scheme)),
            comment: EditorColor(DesignTokens.syntaxComment.value(for: scheme)),
            // §4.1.1 sets keywords in bold as well as in colour. Weight is a second channel:
            // it survives the colour being hard to tell apart, which is what a red-green
            // colour-blind reader gets from a magenta-on-white keyword.
            keywordIsBold: true,
            // Plain code, named rather than left out. A group we choose *not* to colour is still
            // a group the user's colourscheme fills in, which puts a seventh colour we never
            // picked on screen — AC-6 breaks quietly. Plain has to be a chosen colour.
            normalForeground: EditorColor(DesignTokens.editorPlainForeground.value(for: scheme)),
            // Neovim's own `Normal` background is #14141B, not our #1B1B1F. Sending ours is what
            // makes the editor actually sit on the surface the rest of the window uses.
            normalBackground: EditorColor(DesignTokens.backgroundContent.value(for: scheme)),
            // Both arrive opaque from §4.1.1 and are passed straight through. An earlier version
            // reused `match` (the search hit) here on the argument that "this word is also there"
            // is a single idea; the design review measured that idea and rejected it — four of
            // six syntax colours fell below 4.5:1 on top of it, and search results can be on
            // screen at the same time as the symbol under the cursor, so one colour for both
            // leaves the two indistinguishable.
            sameSymbolBackground: EditorColor(DesignTokens.backgroundSameSymbol.value(for: scheme)),
            selectionBackground: EditorColor(DesignTokens.backgroundSelection.value(for: scheme)),
            // 거터. 프로토타입이 `text-3` 로 그리고 현재 줄만 `text-1` 로 올린다
            // (`styles.css:193·196`). 두 값이 갈려야 현재 줄이 눈에 띈다.
            annotation: EditorColor(DesignTokens.syntaxAnnotation.value(for: scheme)),
            lineNumberForeground: EditorColor(DesignTokens.textTertiary.value(for: scheme)),
            currentLineNumberForeground: EditorColor(DesignTokens.textPrimary.value(for: scheme)),
            // 편집기 주변부. 색을 안 주면 nvim 기본값이 나오는데, 그건 우리 배경을 모르고
            // 고른 색이라 대비가 맞을 이유가 없다 — 라이트 모드에서 어두운 회색 막대가
            // 남아 편집기 절반이 다른 앱처럼 보였다.
            statusLineForeground: EditorColor(DesignTokens.textSecondary.value(for: scheme)),
            statusLineBackground: EditorColor(DesignTokens.backgroundStatus.value(for: scheme)),
            endOfBufferForeground: EditorColor(DesignTokens.editorEdgeMarker.value(for: scheme)),
            nonTextForeground: EditorColor(DesignTokens.editorEdgeMarker.value(for: scheme)),
            // 편집기 배경과 **같은** 값이다. 다르면 아무것도 없는 줄에도 세로 띠가 생기고,
            // 사용자는 그것을 무언가 켜져 있는 표시로 읽는다.
            signColumnBackground: EditorColor(DesignTokens.backgroundContent.value(for: scheme))
        )
    }
}

extension EditorColor {
    /// Bridges the renderer's colour type back into the contract's.
    ///
    /// The sibling in the other direction lives beside `GridFrameBuilder`, which is where colours
    /// arrive. This one is where they leave.
    ///
    /// Rounds rather than truncates: truncating loses a step on almost every channel, and the
    /// error is invisible on screen but breaks the round trip a test uses to prove the two
    /// bridges agree.
    init(_ color: RGBColor) {
        func channel(_ value: Double) -> UInt8 {
            UInt8(min(max((value * 255).rounded(), 0), 255))
        }
        self.init(red: channel(color.red), green: channel(color.green), blue: channel(color.blue))
    }
}
