import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

/// Design §3 W-4's two placement rules, as the popover actually composes them:
/// it flips above the cursor when there is no room below, and it **never covers the
/// cursor's line**. The second is the one with teeth — reading a candidate list while the
/// line it refers to is hidden defeats the popover's purpose.
///
/// `PopoverPlacementTests` covers the placement function alone. This suite covers the
/// composition the view performs: card height, fitted height, then placement. A correct
/// placement fed a wrong height still lands on the cursor.
@Suite("정의 후보 팝오버 배치 — 플립과 커서 가림 (REQ-005 AC-2, §3 W-4)")
struct DefinitionPopoverPlacementTests {

    private let cellSize = CGSize(width: 8, height: 18)

    /// The card's rectangle once the view has placed it.
    private func placedCard(
        rowCount: Int,
        cursorRow: Int,
        cursorColumn: Int = 10,
        area: CGSize
    ) -> (card: CGRect, anchor: CGRect, isFlippedAbove: Bool) {
        let anchor = PopoverPlacement.cursorAnchor(row: cursorRow, column: cursorColumn, cellSize: cellSize)
        let natural = DefinitionCandidatesView.cardHeight(rowCount: rowCount)
        let height = DefinitionCandidatesView.fittedHeight(natural: natural, anchor: anchor, area: area)
        let placement = PopoverPlacement.place(
            anchor: anchor,
            contentSize: CGSize(width: 460, height: height),
            in: area
        )
        return (
            CGRect(x: placement.origin.x, y: placement.origin.y, width: 460, height: height),
            anchor,
            placement.isFlippedAbove
        )
    }

    // MARK: 커서 앵커

    @Test("커서 셀이 행·열에서 사각형으로 환산된다")
    func theCursorCellBecomesARectangle() {
        let anchor = PopoverPlacement.cursorAnchor(row: 4, column: 12, cellSize: cellSize)

        #expect(anchor.origin.x == CGFloat(96))
        #expect(anchor.origin.y == CGFloat(72))
        #expect(anchor.size == cellSize)
    }

    @Test("첫 셀은 원점이다")
    func theFirstCellSitsAtTheOrigin() {
        #expect(PopoverPlacement.cursorAnchor(row: 0, column: 0, cellSize: cellSize).origin == .zero)
    }

    // MARK: 카드 높이

    @Test("카드 높이가 후보 수를 따라 자란다")
    func theCardGrowsWithTheCandidateCount() {
        let two = DefinitionCandidatesView.cardHeight(rowCount: 2)
        let five = DefinitionCandidatesView.cardHeight(rowCount: 5)

        #expect(five > two)
        #expect(five - two == CGFloat(3) * 30)
    }

    @Test("후보가 아주 많아도 목록 높이가 상한에서 멈춘다")
    func theListStopsGrowingAtItsCap() {
        let capped = DefinitionCandidatesView.cardHeight(rowCount: 100)
        let atCap = DefinitionCandidatesView.cardHeight(rowCount: 8)

        #expect(capped == atCap)
    }

    // MARK: 플립 (§3 W-4)

    @Test("아래에 자리가 있으면 커서 아래에 붙는다")
    func thePopoverSitsBelowWhenThereIsRoom() {
        let placed = placedCard(rowCount: 3, cursorRow: 5, area: CGSize(width: 900, height: 700))

        #expect(!placed.isFlippedAbove)
        #expect(placed.card.minY > placed.anchor.maxY)
    }

    @Test("창 아래쪽 커서에서는 위로 뒤집힌다")
    func thePopoverFlipsAboveNearTheBottom() {
        // 커서가 마지막 줄 근처면 아래에 카드가 들어갈 자리가 없다.
        let placed = placedCard(rowCount: 3, cursorRow: 36, area: CGSize(width: 900, height: 700))

        #expect(placed.isFlippedAbove)
        #expect(placed.card.maxY < placed.anchor.minY)
    }

    // MARK: 커서를 덮지 않는다 — 이 팝오버의 존재 이유

    @Test("어느 줄에 커서가 있어도 팝오버가 그 줄을 덮지 않는다")
    func thePopoverNeverCoversTheCursorLine() {
        let area = CGSize(width: 900, height: 700)

        for cursorRow in 0...38 {
            for rowCount in [2, 5, 12] {
                let placed = placedCard(rowCount: rowCount, cursorRow: cursorRow, area: area)

                #expect(
                    !placed.card.intersects(placed.anchor),
                    "행 \(cursorRow) · 후보 \(rowCount)개에서 팝오버가 커서를 덮었다"
                )
            }
        }
    }

    @Test("창이 낮아 양쪽 다 모자라면 카드가 높이를 줄여 커서를 피한다")
    func aShortWindowShrinksTheCardRatherThanCoverTheCursor() {
        // 위아래 어느 쪽도 카드 전체를 담지 못하는 크기. 자리를 양보하지 않고 높이를
        // 양보한다 — 목록은 어차피 스크롤된다.
        let area = CGSize(width: 900, height: 220)
        let placed = placedCard(rowCount: 8, cursorRow: 5, area: area)

        #expect(!placed.card.intersects(placed.anchor), "짧은 창에서 팝오버가 커서를 덮었다")
        #expect(placed.card.height < DefinitionCandidatesView.cardHeight(rowCount: 8))
    }

    @Test("줄어든 카드에서도 목록이 음수 높이가 되지 않는다")
    func aShrunkCardNeverGivesTheListANegativeHeight() {
        for cardHeight in [CGFloat(0), 10, 40, 68, 200] {
            #expect(DefinitionCandidatesView.listHeight(inCardHeight: cardHeight) >= 0, "\(cardHeight)")
        }
    }

    @Test("아무리 좁아도 카드가 한 줄짜리 아래로는 줄지 않는다")
    func theCardNeverShrinksBelowOneRow() {
        let floor = DefinitionCandidatesView.cardHeight(rowCount: 1)
        let anchor = PopoverPlacement.cursorAnchor(row: 2, column: 0, cellSize: cellSize)

        let fitted = DefinitionCandidatesView.fittedHeight(
            natural: DefinitionCandidatesView.cardHeight(rowCount: 8),
            anchor: anchor,
            area: CGSize(width: 900, height: 90)
        )
        #expect(fitted == floor)
    }
}
