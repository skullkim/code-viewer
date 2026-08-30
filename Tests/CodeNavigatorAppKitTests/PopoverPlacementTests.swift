import Testing
import CoreGraphics
@testable import CodeNavigatorAppKit

@Suite("PopoverPlacement — 커서 앵커 팝오버의 가장자리 플립 (02 §3 W-4)")
struct PopoverPlacementTests {

    private let area = CGSize(width: 900, height: 600)
    private let content = CGSize(width: 460, height: 200)

    @Test("자리가 있으면 커서 아래에 붙는다")
    func itSitsBelowTheCursorWhenThereIsRoom() {
        let anchor = CGRect(x: 120, y: 100, width: 10, height: 18)
        let placement = PopoverPlacement.place(anchor: anchor, contentSize: content, in: area)

        #expect(!placement.isFlippedAbove)
        #expect(placement.origin.y == anchor.maxY + PopoverPlacement.anchorGap)
        #expect(placement.origin.x == CGFloat(120))
    }

    @Test("아래에 자리가 없으면 위로 뒤집힌다")
    func itFlipsAboveWhenThereIsNoRoomBelow() {
        let anchor = CGRect(x: 120, y: 520, width: 10, height: 18)
        let placement = PopoverPlacement.place(anchor: anchor, contentSize: content, in: area)

        #expect(placement.isFlippedAbove)
        #expect(placement.origin.y == anchor.minY - PopoverPlacement.anchorGap - content.height)
        // Flipped means above: it must not overlap the cursor's own line.
        #expect(placement.origin.y + content.height <= anchor.minY)
    }

    @Test("어느 쪽에도 자리가 없으면 영역 안에 갇힌다")
    func itStaysInsideWhenNeitherSideFits() {
        let tallContent = CGSize(width: 460, height: 560)
        let anchor = CGRect(x: 120, y: 300, width: 10, height: 18)
        let placement = PopoverPlacement.place(anchor: anchor, contentSize: tallContent, in: area)

        #expect(placement.origin.y >= PopoverPlacement.edgeMargin)
        #expect(placement.origin.y + tallContent.height <= area.height)
    }

    @Test("오른쪽 가장자리 커서에서도 팝오버가 창 밖으로 나가지 않는다")
    func itIsPulledBackFromTheRightEdge() {
        let anchor = CGRect(x: 860, y: 100, width: 10, height: 18)
        let placement = PopoverPlacement.place(anchor: anchor, contentSize: content, in: area)

        #expect(placement.origin.x < anchor.minX)
        #expect(placement.origin.x + content.width <= area.width)
        #expect(placement.origin.x >= PopoverPlacement.edgeMargin)
    }

    @Test("영역이 팝오버보다 작아도 좌표가 음수가 되지 않는다")
    func aTinyAreaDoesNotProduceNegativeCoordinates() {
        let tiny = CGSize(width: 200, height: 120)
        let anchor = CGRect(x: 10, y: 40, width: 10, height: 18)
        let placement = PopoverPlacement.place(anchor: anchor, contentSize: content, in: tiny)

        #expect(placement.origin.x >= 0)
        #expect(placement.origin.y >= 0)
    }
}
