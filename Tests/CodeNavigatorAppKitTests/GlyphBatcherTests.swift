import Testing
@testable import CodeNavigatorAppKit

/// ADR-0101 chose per-cell glyph drawing because it is the only approach whose column
/// positions are exact. Batching is what makes it also the fastest: cells sharing a font
/// and colour go to the graphics context in one call. This suite pins the grouping.
@Suite("GlyphBatcher — 같은 폰트·색 글리프를 한 배치로 (REQ-004 AC-2)")
struct GlyphBatcherTests {

    private let white = RGBColor(hex: "#E8E8ED")!
    private let blue = RGBColor(hex: "#82AAFF")!

    private func cell(_ character: Character, column: Int, row: Int = 0, colour: RGBColor? = nil, bold: Bool = false) -> PositionedCell {
        PositionedCell(character: character, row: row, column: column, foreground: colour ?? white, isBold: bold)
    }

    @Test("같은 색·굵기의 셀이 한 배치로 묶인다")
    func cellsSharingAStyleShareABatch() {
        let batches = GlyphBatcher.batches(for: [cell("a", column: 0), cell("b", column: 1), cell("c", column: 2)])
        #expect(batches.count == 1)
        #expect(batches[0].cells.map(\.character) == ["a", "b", "c"])
    }

    @Test("색이 다르면 배치가 갈린다")
    func differentColoursSplitTheBatch() {
        let batches = GlyphBatcher.batches(for: [
            cell("a", column: 0, colour: white),
            cell("b", column: 1, colour: blue),
            cell("c", column: 2, colour: white),
        ])
        #expect(batches.count == 2)
        #expect(batches.first { $0.foreground == white }?.cells.map(\.character) == ["a", "c"])
        #expect(batches.first { $0.foreground == blue }?.cells.map(\.character) == ["b"])
    }

    @Test("굵기가 다르면 폰트가 달라 배치가 갈린다")
    func boldnessSplitsTheBatch() {
        let batches = GlyphBatcher.batches(for: [
            cell("a", column: 0, bold: false),
            cell("b", column: 1, bold: true),
        ])
        #expect(batches.count == 2)
    }

    @Test("공백은 그릴 글리프가 없으므로 배치에서 빠진다")
    func blanksAreNotDrawn() {
        // A space contributes nothing but would still cost a glyph slot in every batch.
        // On a mostly-indented code file that is most of the grid.
        let batches = GlyphBatcher.batches(for: [
            cell(" ", column: 0), cell(" ", column: 1), cell("x", column: 2),
        ])
        #expect(batches.count == 1)
        #expect(batches[0].cells.map(\.character) == ["x"])
    }

    @Test("공백뿐인 행은 배치를 만들지 않는다")
    func anAllBlankRowProducesNothing() {
        #expect(GlyphBatcher.batches(for: [cell(" ", column: 0), cell(" ", column: 1)]).isEmpty)
    }

    @Test("빈 입력은 빈 배치 목록이다")
    func emptyInputProducesNoBatches() {
        #expect(GlyphBatcher.batches(for: []).isEmpty)
    }

    @Test("배치 순서가 결정적이다 — 같은 입력은 같은 순서를 낸다")
    func batchOrderIsDeterministic() {
        // Grouping through a dictionary would give a different draw order each run, which
        // makes a rendering difference impossible to reproduce. Order follows first
        // appearance instead.
        let cells = [
            cell("a", column: 0, colour: blue),
            cell("b", column: 1, colour: white),
            cell("c", column: 2, colour: blue),
        ]
        for _ in 0..<20 {
            let batches = GlyphBatcher.batches(for: cells)
            #expect(batches.map(\.foreground) == [blue, white])
        }
    }

    @Test("배치 안에서 셀 순서가 보존된다")
    func cellOrderSurvivesBatching() {
        let cells = (0..<10).map { cell(Character(UnicodeScalar(97 + $0)!), column: $0) }
        let batches = GlyphBatcher.batches(for: cells)
        #expect(batches[0].cells.map(\.column) == Array(0..<10))
    }

    @Test("행이 달라도 같은 스타일이면 한 배치로 묶인다 — 드로우 콜을 줄이는 게 목적이다")
    func batchingCrossesRows() {
        let batches = GlyphBatcher.batches(for: [
            cell("a", column: 0, row: 0),
            cell("b", column: 0, row: 1),
            cell("c", column: 0, row: 2),
        ])
        #expect(batches.count == 1)
        #expect(batches[0].cells.count == 3)
    }
}
