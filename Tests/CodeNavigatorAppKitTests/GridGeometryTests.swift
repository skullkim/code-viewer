import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// The grid's size is decided by the view's size, not the other way round.
///
/// The prototype lost its status bar because content was allowed to push the layout
/// around (design §9). The editor therefore takes whatever height it is given and works
/// out how many rows fit, then tells Neovim — it never asks for more room.
@Suite("GridGeometry — 뷰 크기에서 행·열 역산 (REQ-004 AC-2)")
struct GridGeometryTests {

    private let cell = CGSize(width: 8.0361328125, height: 16)

    @Test("행·열은 뷰 크기를 셀 크기로 나눈 내림값이다")
    func rowsAndColumnsFitInsideTheView() {
        let geometry = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        #expect(geometry.columns == 99)
        #expect(geometry.rows == 40)
    }

    @Test("부분 셀은 버린다 — 잘린 글자를 그리지 않는다")
    func partialCellsAreDropped() {
        let geometry = GridGeometry(viewSize: CGSize(width: 100, height: 100), cellSize: CGSize(width: 10, height: 30))
        #expect(geometry.columns == 10)
        #expect(geometry.rows == 3)
    }

    @Test("아주 작은 뷰에서도 최소 1행 1열은 유지된다")
    func aTinyViewStillHasOneCell() {
        // Neovim rejects a zero-sized UI, and a resize request of 0 would kill the session.
        let geometry = GridGeometry(viewSize: CGSize(width: 2, height: 2), cellSize: cell)
        #expect(geometry.columns >= 1)
        #expect(geometry.rows >= 1)
    }

    @Test("크기가 0이거나 음수여도 무너지지 않는다")
    func degenerateSizesAreSurvivable() {
        for size in [CGSize(width: 0, height: 0), CGSize(width: -10, height: -10)] {
            let geometry = GridGeometry(viewSize: size, cellSize: cell)
            #expect(geometry.columns >= 1)
            #expect(geometry.rows >= 1)
        }
    }

    @Test("셀 원점은 컬럼·행에 셀 크기를 곱한 값이다 — 텍스트 엔진에 맡기지 않는다")
    func cellOriginsAreArithmetic() {
        let geometry = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        #expect(geometry.originX(ofColumn: 0) == 0)
        #expect(geometry.originX(ofColumn: 10) == cell.width * 10)
        #expect(geometry.originX(ofColumn: 40) == cell.width * 40)
    }

    @Test("행 원점은 위에서부터 센다")
    func rowOriginsCountFromTheTop() {
        let geometry = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        // The top row's baseline area starts at the top of the view; row 1 is one cell down.
        #expect(geometry.topEdgeY(ofRow: 0, inViewHeight: 640) == 640 - cell.height)
        #expect(geometry.topEdgeY(ofRow: 1, inViewHeight: 640) == 640 - cell.height * 2)
    }

    @Test("커서 셀 사각형이 정확히 한 셀을 덮는다")
    func theCursorRectCoversExactlyOneCell() {
        let geometry = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        let rect = geometry.cellRect(row: 3, column: 7, cellWidth: 1, inViewHeight: 640)
        #expect(rect.width == cell.width)
        #expect(rect.height == cell.height)
        #expect(rect.minX == cell.width * 7)
    }

    @Test("더블폭 문자 위 커서는 두 셀을 덮는다")
    func theCursorSpansBothCellsOfAWideCharacter() {
        // Neovim reports a double-width character as occupying two cells. A cursor drawn
        // one cell wide would sit on half a glyph.
        let geometry = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        let rect = geometry.cellRect(row: 0, column: 4, cellWidth: 2, inViewHeight: 640)
        #expect(rect.width == cell.width * 2)
    }

    @Test("크기가 바뀌면 Neovim에 알릴 필요가 있는지 판단한다")
    func resizeIsOnlyReportedWhenTheGridActuallyChanges() {
        // Neovim redraws the whole grid on resize, so sending one per mouse-drag pixel
        // would be wasteful; only a change in cell counts matters.
        let before = GridGeometry(viewSize: CGSize(width: 800, height: 640), cellSize: cell)
        let sameGrid = GridGeometry(viewSize: CGSize(width: 803, height: 644), cellSize: cell)
        let biggerGrid = GridGeometry(viewSize: CGSize(width: 900, height: 640), cellSize: cell)
        #expect(!before.differsInGridSize(from: sameGrid))
        #expect(before.differsInGridSize(from: biggerGrid))
    }
}
