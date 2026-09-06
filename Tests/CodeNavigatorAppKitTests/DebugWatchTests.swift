import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Watch — 계속 보고 싶은 식. 멈출 때마다 다시 푼다.
@Suite("Watch 목록")
@MainActor
struct DebugWatchTests {

    @Test("식을 더하고 뺀다")
    func addsAndRemoves() async {
        let model = DebugModel()
        await model.toggleWatch("input")
        #expect(model.watches.map(\.expression) == ["input"])
        await model.toggleWatch("input")
        #expect(model.watches.isEmpty)
    }

    @Test("읽을 수 없는 식은 안 들어간다 — 그렇다고 말한다")
    func refusesNonsense() async {
        let model = DebugModel()
        await model.toggleWatch("list.size()")
        #expect(model.watches.isEmpty)
        #expect(model.lastError != nil)
    }

    /// 달리는 중에는 값이 없다. **옛 값을 남기지 않는다** — 남기면 사용자는 그것을 지금
    /// 값으로 읽고, 그 값으로 판단한다.
    @Test("재개하면 값이 비고 식은 남는다")
    func clearsValuesButKeepsExpressions() async {
        let model = DebugModel()
        await model.toggleWatch("input")
        await model.refreshWatches()
        #expect(model.watches.first?.value == nil)
        #expect(model.watches.first?.expression == "input")
    }

    @Test("빈 식은 무시한다")
    func ignoresEmptyText() async {
        let model = DebugModel()
        await model.toggleWatch("   ")
        #expect(model.watches.isEmpty)
    }
}
