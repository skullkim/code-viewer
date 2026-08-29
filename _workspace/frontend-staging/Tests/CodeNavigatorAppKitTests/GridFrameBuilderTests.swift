import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Turns an `EditorGridSnapshot` into positioned cells the renderer can draw.
///
/// This is where ADR-0101's measurement lands: every column comes from
/// `EditorTextRun.startColumn` plus each character's own cell width. Nothing counts
/// characters, because a live Neovim reported "인덱스 abc" as seven Characters filling ten
/// cells.
@Suite("GridFrameBuilder — 스냅샷을 그릴 셀로 (REQ-004 AC-2)")
struct GridFrameBuilderTests {

    private let white = EditorColor(packedRGB: 0xE8E8ED)
    private let black = EditorColor(packedRGB: 0x1B1B1F)
    private let blue = EditorColor(packedRGB: 0x82AAFF)

    private func run(_ text: String, at column: Int, style: EditorTextStyle = .plain) -> EditorTextRun {
        EditorTextRun(text: text, style: style, startColumn: column, cellWidth: DisplayWidth.cells(of: text))
    }

    private func snapshot(
        _ lines: [EditorGridLine],
        cursor: EditorCursorPosition = EditorCursorPosition(row: 0, column: 0),
        columns: Int = 40,
        revision: UInt64 = 1
    ) -> EditorGridSnapshot {
        EditorGridSnapshot(
            columns: columns, rows: max(1, lines.count), lines: lines, cursor: cursor,
            mode: .normal, defaultForeground: white, defaultBackground: black, revision: revision
        )
    }

    @Test("ASCII 런은 시작 컬럼부터 한 칸씩 놓인다")
    func asciiRunsAdvanceOneColumnPerCharacter() {
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("let", at: 0)])]))
        #expect(frame.cells.map(\.column) == [0, 1, 2])
        #expect(frame.cells.map(\.character) == ["l", "e", "t"])
        #expect(frame.cells.allSatisfy { $0.row == 0 })
    }

    @Test("런은 자기 시작 컬럼에서 시작한다 — 앞 런의 문자 수를 세지 않는다")
    func runsStartAtTheirDeclaredColumn() {
        let frame = GridFrameBuilder.build(from: snapshot([
            EditorGridLine(runs: [run("ab", at: 0), run("cd", at: 12)])
        ]))
        #expect(frame.cells.map(\.column) == [0, 1, 12, 13])
    }

    @Test("더블폭 문자는 두 컬럼을 전진시킨다")
    func wideCharactersAdvanceTwoColumns() {
        // The measurement that forced the contract change: seven Characters, ten cells.
        let frame = GridFrameBuilder.build(from: snapshot([
            EditorGridLine(runs: [run("인덱스 abc", at: 0)])
        ]))
        // Every cell is reported, blanks included; dropping what has nothing to draw is
        // the batcher's job, one layer down. The columns are what matter here: the space
        // lands at 6 because three double-width syllables consumed six cells, not three.
        #expect(frame.cells.map(\.column) == [0, 2, 4, 6, 7, 8, 9])
        #expect(frame.cells.map(\.character) == ["인", "덱", "스", " ", "a", "b", "c"])
    }

    @Test("더블폭 문자 뒤의 런도 자기 컬럼에 정확히 놓인다")
    func aRunAfterWideCharactersIsStillCorrect() {
        let frame = GridFrameBuilder.build(from: snapshot([
            EditorGridLine(runs: [run("한글", at: 0), run("x", at: 4)])
        ]))
        #expect(frame.cells.map(\.column) == [0, 2, 4])
    }

    @Test("여러 행이 각자의 행 번호를 갖는다")
    func rowsAreNumberedInOrder() {
        let frame = GridFrameBuilder.build(from: snapshot([
            EditorGridLine(runs: [run("a", at: 0)]),
            EditorGridLine(runs: [run("b", at: 0)]),
            EditorGridLine(runs: [run("c", at: 0)]),
        ]))
        #expect(frame.cells.map(\.row) == [0, 1, 2])
    }

    // MARK: Colour

    @Test("스타일에 전경색이 없으면 그리드 기본색을 쓴다")
    func runsWithoutAForegroundUseTheGridDefault() {
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a", at: 0)])]))
        #expect(frame.cells[0].foreground == RGBColor(hex: "#E8E8ED"))
    }

    @Test("스타일의 전경색이 우선한다")
    func anExplicitForegroundWins() {
        let styled = EditorTextStyle(foreground: blue)
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a", at: 0, style: styled)])]))
        #expect(frame.cells[0].foreground == RGBColor(hex: "#82AAFF"))
    }

    @Test("굵기가 셀에 전달된다")
    func boldnessReachesTheCell() {
        let bold = EditorTextStyle(isBold: true)
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a", at: 0, style: bold)])]))
        #expect(frame.cells[0].isBold)
    }

    @Test("반전 표시는 전경색과 배경색을 맞바꾼다")
    func reverseVideoSwapsTheColours() {
        // Neovim uses reverse video for selections and search matches. Ignoring the flag
        // would render selected text invisible against its own highlight.
        let reversed = EditorTextStyle(foreground: blue, background: white, isReverseVideo: true)
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a", at: 0, style: reversed)])]))
        #expect(frame.cells[0].foreground == RGBColor(hex: "#E8E8ED"))
        #expect(frame.backgroundRuns.first?.color == RGBColor(hex: "#82AAFF"))
    }

    @Test("기본 배경과 같은 런은 배경을 그리지 않는다")
    func runsOnTheDefaultBackgroundDrawNoRectangle() {
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("abc", at: 0)])]))
        #expect(frame.backgroundRuns.isEmpty, "전체 배경은 한 번에 칠하므로 셀마다 다시 칠하지 않는다")
    }

    @Test("배경이 다른 런은 사각형을 만든다")
    func runsWithTheirOwnBackgroundProduceARectangle() {
        let highlighted = EditorTextStyle(background: blue)
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("ab", at: 3, style: highlighted)])]))
        #expect(frame.backgroundRuns.count == 1)
        #expect(frame.backgroundRuns[0].startColumn == 3)
        #expect(frame.backgroundRuns[0].cellWidth == 2)
    }

    // MARK: Cursor

    @Test("커서는 스냅샷이 준 셀 좌표에 놓인다")
    func theCursorSitsWhereTheSnapshotSaid() {
        let frame = GridFrameBuilder.build(from: snapshot(
            [EditorGridLine(runs: [run("abcdef", at: 0)])],
            cursor: EditorCursorPosition(row: 0, column: 3)
        ))
        #expect(frame.cursor.row == 0)
        #expect(frame.cursor.column == 3)
        #expect(frame.cursor.cellWidth == 1)
    }

    @Test("더블폭 문자 위의 커서는 두 셀을 덮는다")
    func theCursorOnAWideCharacterCoversTwoCells() {
        // Otherwise the cursor sits on half a Hangul syllable.
        let frame = GridFrameBuilder.build(from: snapshot(
            [EditorGridLine(runs: [run("한글", at: 0)])],
            cursor: EditorCursorPosition(row: 0, column: 2)
        ))
        #expect(frame.cursor.cellWidth == 2)
    }

    @Test("내용이 없는 자리의 커서는 한 셀이다")
    func theCursorPastTheEndOfALineIsOneCell() {
        let frame = GridFrameBuilder.build(from: snapshot(
            [EditorGridLine(runs: [run("ab", at: 0)])],
            cursor: EditorCursorPosition(row: 0, column: 30)
        ))
        #expect(frame.cursor.cellWidth == 1)
    }

    @Test("행 범위를 벗어난 커서도 무너지지 않는다")
    func anOutOfRangeCursorIsSurvivable() {
        let frame = GridFrameBuilder.build(from: snapshot(
            [EditorGridLine(runs: [run("ab", at: 0)])],
            cursor: EditorCursorPosition(row: 99, column: 0)
        ))
        #expect(frame.cursor.cellWidth == 1)
    }

    // MARK: Frame identity

    @Test("리비전이 그대로 전달된다 — 늦게 온 프레임을 버릴 수 있어야 한다")
    func theRevisionIsCarriedThrough() {
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a", at: 0)])], revision: 42))
        #expect(frame.revision == 42)
    }

    @Test("공백 셀은 여기서 유지되고 배치 단계에서 걸러진다")
    func blanksAreKeptHereAndDroppedWhenBatching() {
        // Two layers, one responsibility each: this one gets the columns right, the
        // batcher decides what is worth a draw call.
        let frame = GridFrameBuilder.build(from: snapshot([EditorGridLine(runs: [run("a b", at: 0)])]))
        #expect(frame.cells.count == 3)
        #expect(GlyphBatcher.batches(for: frame.cells).flatMap(\.cells).count == 2)
    }

    @Test("빈 스냅샷도 무너지지 않는다")
    func anEmptySnapshotIsSurvivable() {
        let frame = GridFrameBuilder.build(from: snapshot([]))
        #expect(frame.cells.isEmpty)
        #expect(frame.backgroundRuns.isEmpty)
    }
}
