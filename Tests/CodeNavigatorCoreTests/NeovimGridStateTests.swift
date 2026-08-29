import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Builds the wire shape Neovim actually sends, so these tests exercise parsing too.
private func cell(_ text: String, _ highlightIdentifier: Int? = nil, repeatCount: Int? = nil) -> MessagePackValue {
    var items: [MessagePackValue] = [.string(text)]
    if let highlightIdentifier {
        items.append(.unsignedInteger(UInt64(highlightIdentifier)))
    }
    if let repeatCount {
        items.append(.unsignedInteger(UInt64(repeatCount)))
    }
    return .array(items)
}

private func integers(_ values: Int...) -> [MessagePackValue] {
    values.map { .integer(Int64($0)) }
}

private func makeGrid(columns: Int = 10, rows: Int = 3) -> NeovimGridState {
    var grid = NeovimGridState()
    grid.apply(eventName: "grid_resize", arguments: integers(1, columns, rows))
    return grid
}

@Suite("NeovimGridState — 그리드 갱신")
struct NeovimGridStateTests {

    @Test("크기 변경이 반영되고 빈 칸으로 채워진다")
    func resizeFillsWithBlanks() {
        var grid = makeGrid(columns: 4, rows: 2)
        let snapshot = grid.makeSnapshot()

        #expect(snapshot.columns == 4)
        #expect(snapshot.rows == 2)
        #expect(snapshot.lines.count == 2)
        #expect(snapshot.lines[0].plainText == "    ")
    }

    @Test("grid_line이 지정한 행·열에 글자를 쓴다")
    func gridLineWritesTextAtPosition() {
        var grid = makeGrid()
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(1), .integer(2),
            .array([cell("h"), cell("i")]),
            .boolean(false),
        ])

        let snapshot = grid.makeSnapshot()
        #expect(snapshot.lines[1].plainText == "  hi      ")
        #expect(snapshot.lines[0].plainText == "          ")
    }

    @Test("반복 횟수가 있는 셀은 그만큼 채운다")
    func repeatedCellFillsMultipleColumns() {
        var grid = makeGrid()
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([cell("-", 0, repeatCount: 5)]),
            .boolean(false),
        ])

        #expect(grid.makeSnapshot().lines[0].plainText == "-----     ")
    }

    @Test("하이라이트 아이디가 생략된 셀은 직전 셀의 것을 잇는다")
    func omittedHighlightIdentifierInheritsPrevious() {
        var grid = makeGrid()
        grid.apply(eventName: "hl_attr_define", arguments: [
            .integer(7),
            .map([MessagePackKeyValuePair(key: .string("bold"), value: .boolean(true))]),
            .map([]), .array([]),
        ])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([cell("a", 7), cell("b")]),
            .boolean(false),
        ])

        let runs = grid.makeSnapshot().lines[0].runs
        // 같은 스타일이 이어지므로 하나의 run 으로 합쳐진다.
        #expect(runs.first?.text == "ab")
        #expect(runs.first?.style.isBold == true)
    }

    @Test("grid_clear는 전체를 빈 칸으로 되돌린다")
    func gridClearResetsEverything() {
        var grid = makeGrid()
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0), .array([cell("x")]), .boolean(false),
        ])
        grid.apply(eventName: "grid_clear", arguments: [.integer(1)])

        #expect(grid.makeSnapshot().lines[0].plainText == "          ")
    }

    @Test("grid_scroll이 영역을 위로 밀어 올린다")
    func gridScrollMovesRegionUp() {
        var grid = makeGrid(columns: 3, rows: 3)
        for row in 0..<3 {
            grid.apply(eventName: "grid_line", arguments: [
                .integer(1), .integer(Int64(row)), .integer(0),
                .array([cell(String(row))]), .boolean(false),
            ])
        }
        // top=0 bottom=3 left=0 right=3 rows=1 → 한 줄 위로
        grid.apply(eventName: "grid_scroll", arguments: integers(1, 0, 3, 0, 3, 1, 0))

        let lines = grid.makeSnapshot().lines
        #expect(lines[0].plainText.hasPrefix("1"))
        #expect(lines[1].plainText.hasPrefix("2"))
    }

    @Test("grid_scroll이 영역을 아래로 내린다")
    func gridScrollMovesRegionDown() {
        var grid = makeGrid(columns: 3, rows: 3)
        for row in 0..<3 {
            grid.apply(eventName: "grid_line", arguments: [
                .integer(1), .integer(Int64(row)), .integer(0),
                .array([cell(String(row))]), .boolean(false),
            ])
        }
        grid.apply(eventName: "grid_scroll", arguments: integers(1, 0, 3, 0, 3, -1, 0))

        let lines = grid.makeSnapshot().lines
        #expect(lines[1].plainText.hasPrefix("0"))
        #expect(lines[2].plainText.hasPrefix("1"))
    }

    @Test("커서 위치가 반영된다")
    func cursorPositionIsTracked() {
        var grid = makeGrid()
        grid.apply(eventName: "grid_cursor_goto", arguments: integers(1, 2, 5))

        let cursor = grid.makeSnapshot().cursor
        #expect(cursor.row == 2)
        #expect(cursor.column == 5)
    }

    @Test("모드 변경이 반영된다")
    func modeChangeIsTracked() {
        var grid = makeGrid()
        grid.apply(eventName: "mode_change", arguments: [.string("insert"), .integer(1)])
        #expect(grid.makeSnapshot().mode == .insert)

        grid.apply(eventName: "mode_change", arguments: [.string("cmdline_normal"), .integer(2)])
        #expect(grid.makeSnapshot().mode == .commandLine)

        grid.apply(eventName: "mode_change", arguments: [.string("어떤_새_모드"), .integer(9)])
        #expect(grid.makeSnapshot().mode == .other("어떤_새_모드"))
    }

    @Test("기본 색상이 스냅샷에 실린다")
    func defaultColoursAreCarried() {
        var grid = makeGrid()
        grid.apply(eventName: "default_colors_set", arguments: integers(0xFF_00_00, 0x00_FF_00, 0, 0, 0))

        let snapshot = grid.makeSnapshot()
        #expect(snapshot.defaultForeground == EditorColor(red: 255, green: 0, blue: 0))
        #expect(snapshot.defaultBackground == EditorColor(red: 0, green: 255, blue: 0))
    }

    @Test("하이라이트 속성이 스타일로 변환된다")
    func highlightAttributesBecomeStyles() {
        var grid = makeGrid()
        grid.apply(eventName: "hl_attr_define", arguments: [
            .integer(3),
            .map([
                MessagePackKeyValuePair(key: .string("foreground"), value: .unsignedInteger(0x11_22_33)),
                MessagePackKeyValuePair(key: .string("italic"), value: .boolean(true)),
                MessagePackKeyValuePair(key: .string("underline"), value: .boolean(true)),
                MessagePackKeyValuePair(key: .string("reverse"), value: .boolean(true)),
            ]),
            .map([]), .array([]),
        ])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0), .array([cell("z", 3)]), .boolean(false),
        ])

        let style = grid.makeSnapshot().lines[0].runs.first?.style
        #expect(style?.foreground == EditorColor(red: 0x11, green: 0x22, blue: 0x33))
        #expect(style?.isItalic == true)
        #expect(style?.isUnderlined == true)
        #expect(style?.isReverseVideo == true)
    }

    @Test("스타일이 다르면 run이 나뉜다")
    func differentStylesSplitIntoSeparateRuns() {
        var grid = makeGrid()
        grid.apply(eventName: "hl_attr_define", arguments: [
            .integer(1),
            .map([MessagePackKeyValuePair(key: .string("bold"), value: .boolean(true))]),
            .map([]), .array([]),
        ])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([cell("a", 0), cell("b", 1), cell("c", 0)]),
            .boolean(false),
        ])

        let runs = grid.makeSnapshot().lines[0].runs
        #expect(runs.count >= 3)
        #expect(runs[0].text == "a")
        #expect(runs[1].text == "b")
        #expect(runs[1].style.isBold == true)
    }

    @Test("리비전은 스냅샷마다 증가한다 — 늦게 온 프레임을 버릴 수 있게")
    func revisionIncreasesPerSnapshot() {
        var grid = makeGrid()
        let first = grid.makeSnapshot().revision
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0), .array([cell("x")]), .boolean(false),
        ])
        let second = grid.makeSnapshot().revision
        #expect(second > first)
    }

    @Test("다른 그리드의 이벤트는 무시한다 — 전역 그리드만 그린다")
    func ignoresEventsForOtherGrids() {
        var grid = makeGrid()
        grid.apply(eventName: "grid_line", arguments: [
            .integer(4), .integer(0), .integer(0), .array([cell("X")]), .boolean(false),
        ])
        #expect(grid.makeSnapshot().lines[0].plainText == "          ")
    }

    @Test("모르는 이벤트와 잘못된 인자에도 죽지 않는다")
    func survivesUnknownEventsAndMalformedArguments() {
        var grid = makeGrid()
        grid.apply(eventName: "완전히_새로운_이벤트", arguments: [.integer(1)])
        grid.apply(eventName: "grid_line", arguments: [])
        grid.apply(eventName: "grid_resize", arguments: [.string("이건 숫자가 아니다")])
        grid.apply(eventName: "grid_cursor_goto", arguments: [.integer(1)])

        #expect(grid.makeSnapshot().rows == 3)
    }

    @Test("범위를 벗어난 좌표는 잘라낸다 — 크래시 금지")
    func clampsOutOfBoundsWrites() {
        var grid = makeGrid(columns: 3, rows: 2)
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(99), .integer(0), .array([cell("x")]), .boolean(false),
        ])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(2),
            .array([cell("a"), cell("b"), cell("c")]),
            .boolean(false),
        ])
        grid.apply(eventName: "grid_cursor_goto", arguments: integers(1, 99, 99))

        let snapshot = grid.makeSnapshot()
        #expect(snapshot.lines[0].plainText == "  a")
        #expect(snapshot.cursor.row < snapshot.rows)
        #expect(snapshot.cursor.column < snapshot.columns)
    }
}

@Suite("NeovimGridState — 더블폭 문자와 컬럼 좌표")
struct NeovimGridStateWideCharacterTests {

    /// Neovim sends a double-width glyph as one cell followed by an **empty** cell, so a run's
    /// character count and its column span differ. This is the fixture that was missing: every
    /// other offset path in the engine had a Korean case, this one did not.
    private func gridWithKoreanLine() -> NeovimGridState {
        var grid = NeovimGridState()
        // 그리드 폭을 셀 수와 정확히 맞춘다. 남는 칸이 있으면 같은 하이라이트의 빈 칸이
        // 같은 run 으로 합쳐져서(정상 동작) 이 테스트의 의도가 흐려진다.
        grid.apply(eventName: "grid_resize", arguments: [.integer(1), .integer(10), .integer(1)])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([
                cell("인"), cell(""), cell("덱"), cell(""), cell("스"), cell(""),
                cell(" "), cell("a"), cell("b"), cell("c"),
            ]),
            .boolean(false),
        ])
        return grid
    }

    @Test("한글 줄의 run은 문자 수가 아니라 실제 셀 수를 보고한다")
    func reportsCellWidthNotCharacterCount() {
        var grid = gridWithKoreanLine()
        let line = grid.makeSnapshot().lines[0]
        let run = line.runs[0]

        // '인덱스 abc' = 문자 7개(공백 포함), 점유 셀 10개. 이 차이가 이 필드의 존재 이유다.
        #expect(run.text == "인덱스 abc")
        #expect(run.text.count == 7)
        #expect(run.cellWidth == 10)
        #expect(run.startColumn == 0)
    }

    @Test("한글 뒤에 오는 run의 시작 컬럼이 셀 기준으로 정확하다")
    func reportsCorrectStartColumnAfterWideCharacters() {
        var grid = NeovimGridState()
        grid.apply(eventName: "grid_resize", arguments: [.integer(1), .integer(7), .integer(1)])
        grid.apply(eventName: "hl_attr_define", arguments: [
            .integer(5),
            .map([MessagePackKeyValuePair(key: .string("bold"), value: .boolean(true))]),
            .map([]), .array([]),
        ])
        // '인덱스'(6셀) 뒤에 다른 하이라이트로 'x' — x는 반드시 컬럼 6에서 시작해야 한다.
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([cell("인", 0), cell(""), cell("덱"), cell(""), cell("스"), cell(""), cell("x", 5)]),
            .boolean(false),
        ])

        let runs = grid.makeSnapshot().lines[0].runs
        let styledRun = try! #require(runs.first { $0.style.isBold })
        #expect(styledRun.text == "x")
        #expect(styledRun.startColumn == 6)

        // 문자 수로 컬럼을 유도했다면 3이 나온다. 그게 이 필드가 존재하는 이유다.
        #expect(runs[0].text.count == 3)
        #expect(runs[0].cellWidth == 6)
    }

    @Test("run들의 시작 컬럼과 폭이 줄 전체를 빈틈없이 덮는다")
    func runsTileTheLineWithoutGaps() {
        var grid = gridWithKoreanLine()
        let snapshot = grid.makeSnapshot()
        let runs = snapshot.lines[0].runs

        var expectedColumn = 0
        for run in runs {
            #expect(run.startColumn == expectedColumn)
            expectedColumn += run.cellWidth
        }
        #expect(expectedColumn == snapshot.columns)
    }

    @Test("커서 컬럼은 셀 좌표라 한글 뒤에서도 run 좌표와 같은 공간에 있다")
    func cursorColumnSharesTheCellCoordinateSpace() {
        var grid = gridWithKoreanLine()
        // '인덱스 ' 다음, 즉 'a' 위 — 셀 기준 7번째.
        grid.apply(eventName: "grid_cursor_goto", arguments: [.integer(1), .integer(0), .integer(7)])

        let snapshot = grid.makeSnapshot()
        #expect(snapshot.cursor.column == 7)

        // 커서가 놓인 셀을 run 좌표로 찾을 수 있어야 한다.
        let run = snapshot.lines[0].runs.first {
            snapshot.cursor.column >= $0.startColumn
                && snapshot.cursor.column < $0.startColumn + $0.cellWidth
        }
        #expect(run != nil)
    }

    @Test("ASCII 전용 줄에서는 문자 수와 셀 수가 같다")
    func asciiLineHasMatchingCharacterAndCellCounts() {
        var grid = NeovimGridState()
        grid.apply(eventName: "grid_resize", arguments: [.integer(1), .integer(5), .integer(1)])
        grid.apply(eventName: "grid_line", arguments: [
            .integer(1), .integer(0), .integer(0),
            .array([cell("h"), cell("e"), cell("l"), cell("l"), cell("o")]),
            .boolean(false),
        ])

        let run = grid.makeSnapshot().lines[0].runs[0]
        #expect(run.text.count == run.cellWidth)
        #expect(run.cellWidth == 5)
    }
}
