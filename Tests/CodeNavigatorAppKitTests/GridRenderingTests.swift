import Testing
import AppKit
import CoreGraphics
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Draws real frames into an offscreen bitmap and inspects the pixels.
///
/// Every other grid test checks the arithmetic that decides where a glyph *should* go.
/// This one checks where it actually lands once CoreText has drawn it — the claim ADR-0101
/// rests on. The measurements that drove that decision were about drawing, so the
/// verification has to be about drawing too.
@MainActor
@Suite("GridRendering — 실제로 그려진 픽셀 (REQ-004 AC-2)")
struct GridRenderingTests {

    private let metrics = CellMetrics()

    private func run(
        _ text: String,
        at column: Int,
        bold: Bool = false,
        italic: Bool = false,
        underlined: Bool = false
    ) -> EditorTextRun {
        EditorTextRun(
            text: text,
            style: EditorTextStyle(
                foreground: EditorColor(packedRGB: 0xFFFFFF),
                isBold: bold,
                isItalic: italic,
                isUnderlined: underlined
            ),
            startColumn: column,
            cellWidth: DisplayWidth.cells(of: text)
        )
    }

    /// A digest of one row's pixels, for comparing two renderings of the same text.
    ///
    /// A digest rather than the array itself: comparing raw buffers produces a failure
    /// message that dumps hundreds of thousands of bytes, which is worse than no message.
    /// The digest still distinguishes any difference in what was drawn.
    private func renderDigest(_ frame: GridFrame, columns: Int) -> Int {
        var digest = 17
        for (index, byte) in pixels(frame, columns: columns).enumerated() where byte != 0 {
            digest = digest &* 31 &+ (index &* 251 &+ Int(byte))
        }
        return digest
    }

    /// The raw pixels of one row.
    private func pixels(_ frame: GridFrame, columns: Int) -> [UInt8] {
        let size = CGSize(width: CGFloat(columns) * metrics.size.width, height: metrics.size.height)
        let scale = 2.0
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width * scale), height: Int(size.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else {
            Issue.record("비트맵 컨텍스트를 만들지 못했다")
            return []
        }
        context.scaleBy(x: scale, y: scale)
        GridRenderer().draw(frame, in: context, viewSize: size, metrics: metrics)

        guard let data = context.data else {
            Issue.record("비트맵 데이터를 읽지 못했다")
            return []
        }
        let byteCount = context.bytesPerRow * context.height
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: byteCount), count: byteCount))
    }

    /// The cursor defaults to a column outside the rendered area. It paints a filled block,
    /// which would mark every cell it covers as inked and hide exactly what these tests look
    /// for; the two cursor tests place it deliberately.
    private func frame(_ runs: [EditorTextRun], columns: Int = 20, cursorColumn: Int = 999) -> GridFrame {
        GridFrameBuilder.build(from: EditorGridSnapshot(
            columns: columns, rows: 1,
            lines: [EditorGridLine(runs: runs)],
            cursor: EditorCursorPosition(row: 0, column: cursorColumn),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0xFFFFFF),
            defaultBackground: EditorColor(packedRGB: 0x000000),
            revision: 1
        ))
    }

    /// Renders one row and reports, per cell, whether anything was drawn in it.
    ///
    /// The cursor is excluded by rendering without it: its filled block would mark every
    /// cell it covers as inked and hide exactly what this test is looking for.
    private func inkedCells(_ frame: GridFrame, columns: Int) -> [Bool] {
        let size = CGSize(
            width: CGFloat(columns) * metrics.size.width,
            height: metrics.size.height
        )
        let scale = 2.0
        // Nothing here is force-unwrapped. A trap in a helper takes down the whole test
        // process, and Swift Testing runs suites in parallel — so one nil would fail
        // unrelated tests and hide its own cause. Recording an issue keeps the blame local.
        guard size.width > 0, size.height > 0 else {
            Issue.record("셀 크기가 0이다 — 폰트 메트릭을 읽지 못했다 (\(metrics.size))")
            return []
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            Issue.record("sRGB 색 공간을 만들지 못했다")
            return []
        }
        guard let context = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            Issue.record("비트맵 컨텍스트를 만들지 못했다 (\(size), scale \(scale))")
            return []
        }
        context.scaleBy(x: scale, y: scale)

        GridRenderer().draw(frame, in: context, viewSize: size, metrics: metrics)

        guard let data = context.data else {
            Issue.record("비트맵 데이터를 읽지 못했다")
            return []
        }
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * context.height)

        return (0..<columns).map { column in
            let startX = Int(CGFloat(column) * metrics.size.width * scale)
            let endX = min(Int(CGFloat(column + 1) * metrics.size.width * scale), context.width)
            for y in 0..<context.height {
                for x in startX..<endX {
                    let offset = y * bytesPerRow + x * 4
                    // Anything brighter than the black default background is ink.
                    if pixels[offset + 1] > 40 || pixels[offset + 2] > 40 || pixels[offset + 3] > 40 {
                        return true
                    }
                }
            }
            return false
        }
    }

    @Test("글리프가 자기 컬럼 안에만 그려진다")
    func glyphsLandInTheirOwnColumn() {
        let inked = inkedCells(frame([run("A", at: 3)]), columns: 8)
        #expect(inked == [false, false, false, true, false, false, false, false])
    }

    @Test("런의 시작 컬럼이 실제 그려지는 위치를 정한다")
    func theRunsStartColumnDecidesWhereItIsDrawn() {
        let inked = inkedCells(frame([run("AB", at: 5)]), columns: 10)
        #expect(inked == [false, false, false, false, false, true, true, false, false, false])
    }

    @Test("공백은 잉크를 남기지 않는다")
    func blanksLeaveNoInk() {
        let inked = inkedCells(frame([run("A B", at: 0)]), columns: 5)
        #expect(inked == [true, false, true, false, false])
    }

    // MARK: The claim ADR-0101 rests on

    @Test("런 안에서 한글 뒤의 ASCII가 두 칸 뒤에 그려진다")
    func asciiAfterHangulAdvancesTwoCellsWithinARun() {
        // The contract gives each run its start column, so a run's first character can
        // never be misplaced. The risk lives *inside* a run, after a wide character — so
        // that is what this measures, in pixels.
        //
        // "한A" is three cells: 한 covers 0-1, A sits at 2. Counting characters would put
        // A at 1, leaving cell 2 blank. The two cases are distinguishable by cell 2 alone.
        let inked = inkedCells(frame([run("한A", at: 0)]), columns: 6)
        #expect(inked[2], "컬럼 2가 비었다 — 한글을 한 칸으로 세고 A를 컬럼 1에 그린 것이다")
        #expect(!inked[3], "A가 한 칸을 넘겼다")
    }

    @Test("런 안에서 드리프트가 누적되지 않는다")
    func driftDoesNotAccumulateWithinARun() {
        // One wrong advance is a half cell; ten are five cells. A line of Korean comments —
        // which this repository is full of — makes it obvious.
        // "가나다라X" is nine cells: four syllables cover 0-7, X sits at 8.
        let inked = inkedCells(frame([run("가나다라X", at: 0)], columns: 12), columns: 12)
        #expect(inked[8], "컬럼 8이 비었다 — 네 음절 뒤에서 컬럼이 밀렸다")
        #expect(!inked[9])
    }

    @Test("런 안에서 이모지 뒤의 문자도 두 칸 뒤에 온다")
    func charactersAfterAnEmojiAdvanceTwoCells() {
        // "👍A": the emoji covers 0-1, A sits at 2.
        let inked = inkedCells(frame([run("👍A", at: 0)]), columns: 6)
        #expect(inked[2], "이모지를 한 칸으로 세고 A를 컬럼 1에 그린 것이다")
        #expect(!inked[3])
    }

    // MARK: Characters the primary font cannot draw

    @Test("한글이 실제로 그려진다 — 자리만 차지하는 게 아니라")
    func hangulIsActuallyDrawn() {
        // The monospaced system font contains no Hangul: every Korean character resolved to
        // glyph 0 and was skipped, so Korean comments rendered as blank space. The earlier
        // tests here missed it because they asserted *where* the following character landed,
        // never that the Korean itself drew anything. This repository's own comments are
        // Korean, and this is a tool for reading code.
        let inked = inkedCells(frame([run("한글", at: 0)]), columns: 6)
        #expect(inked[0], "한글 첫 글자가 그려지지 않았다 — 폰트 폴백이 없다")
        #expect(inked[2], "한글 둘째 글자가 그려지지 않았다")
    }

    @Test("한자·가나도 그려진다")
    func otherEastAsianScriptsAreDrawn() {
        #expect(inkedCells(frame([run("中", at: 0)]), columns: 4)[0])
        #expect(inkedCells(frame([run("あ", at: 0)]), columns: 4)[0])
    }

    @Test("이모지도 그려진다")
    func emojiAreDrawn() {
        #expect(inkedCells(frame([run("👍", at: 0)]), columns: 4)[0])
    }

    @Test("폴백 글자와 ASCII가 한 줄에 섞여도 둘 다 그려진다")
    func fallbackAndPrimaryFontsCoexistOnOneLine() {
        // They are drawn in separate calls because one font cannot draw both, so this checks
        // that splitting the run did not drop either half.
        let inked = inkedCells(frame([run("A한B", at: 0)]), columns: 6)
        #expect(inked[0], "ASCII 앞글자가 사라졌다")
        #expect(inked[1], "한글이 사라졌다")
        #expect(inked[3], "ASCII 뒷글자가 사라졌다")
    }

    // MARK: Style traits (REQ-004 AC-2 · AC-3)

    @Test("이탤릭이 실제로 다르게 그려진다")
    func italicTextIsDrawnDifferently() {
        // The engine parses italic out of Neovim's highlight attributes, but nothing was
        // carrying it past the frame builder — a user's italic comments rendered upright.
        // Comparing pixels is the only way to tell "the flag is set" from "it changed the
        // drawing".
        let upright = renderDigest(frame([run("abc", at: 0)]), columns: 6)
        let italic = renderDigest(frame([run("abc", at: 0, italic: true)]), columns: 6)

        #expect(upright != italic, "이탤릭이 평문과 같은 픽셀을 낸다 — 스타일이 렌더까지 도달하지 않았다")
    }

    @Test("밑줄이 실제로 그려진다")
    func underlinedTextIsDrawnDifferently() {
        let plain = renderDigest(frame([run("abc", at: 0)]), columns: 6)
        let underlined = renderDigest(frame([run("abc", at: 0, underlined: true)]), columns: 6)

        #expect(plain != underlined, "밑줄이 평문과 같은 픽셀을 낸다 — 진단·검색 강조가 사라진다")
    }

    @Test("밑줄은 글자가 없는 칸에도 그려진다")
    func theUnderlineCoversItsOwnCell() {
        // An underline marks an extent — a diagnostic range, a search match. A space inside
        // that range still belongs to it.
        let inked = inkedCells(frame([run("a b", at: 0, underlined: true)]), columns: 5)
        #expect(inked[1], "밑줄 구간 안의 공백 칸이 비었다")
    }

    @Test("굵기·이탤릭·밑줄이 서로 다른 렌더를 낸다")
    func eachTraitProducesItsOwnRendering() {
        // Three traits collapsing into one would be invisible in a "the flag survived"
        // test: all three would still be true. Only the pixels separate them.
        let names = ["평문", "굵게", "이탤릭", "밑줄"]
        let variants = [
            renderDigest(frame([run("abc", at: 0)]), columns: 6),
            renderDigest(frame([run("abc", at: 0, bold: true)]), columns: 6),
            renderDigest(frame([run("abc", at: 0, italic: true)]), columns: 6),
            renderDigest(frame([run("abc", at: 0, underlined: true)]), columns: 6),
        ]
        for (index, first) in variants.enumerated() {
            for (otherIndex, second) in variants.enumerated() where otherIndex > index {
                #expect(first != second, "\(names[index])와 \(names[otherIndex])의 렌더가 같다")
            }
        }
    }

    // MARK: Cursor

    @Test("커서가 자기 셀을 칠한다")
    func theCursorPaintsItsOwnCell() {
        let inked = inkedCells(frame([run("ab", at: 0)], columns: 6, cursorColumn: 4), columns: 6)
        #expect(inked[4], "빈 자리의 커서가 그려지지 않았다")
    }

    @Test("더블폭 문자 위 커서가 두 셀을 칠한다")
    func theCursorOnAWideCharacterPaintsBothCells() {
        // A cursor one cell wide would sit on half a syllable.
        let inked = inkedCells(frame([run("한", at: 0)], columns: 6, cursorColumn: 0), columns: 6)
        #expect(inked[0])
        #expect(inked[1], "커서가 더블폭 문자의 뒤쪽 칸을 덮지 않았다")
    }

    @Test("빈 프레임은 배경만 남긴다")
    func anEmptyFrameDrawsNothingButBackground() {
        let empty = GridFrameBuilder.build(from: EditorGridSnapshot(
            columns: 6, rows: 1, lines: [EditorGridLine(runs: [])],
            cursor: EditorCursorPosition(row: 0, column: 99),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0xFFFFFF),
            defaultBackground: EditorColor(packedRGB: 0x000000),
            revision: 1
        ))
        #expect(inkedCells(empty, columns: 6).allSatisfy { !$0 })
    }
}
