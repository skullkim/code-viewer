import Testing
@testable import CodeNavigatorCore

/// covers: 계약 §3.4 — `navigationRequests()` 는 replay 하지 않는다
///
/// `EventBroadcaster` 는 늦게 붙은 구독자에게 마지막 값을 돌려준다. 그리드·상태·진행률에는 그게
/// 맞다 — 늦게 붙은 뷰가 빈 화면이면 안 되니까. **사건에는 틀리다.** `gd` 를 replay 하면 나중에
/// 구독한 쪽이 사용자가 누른 적 없는 시점에 정의로 점프한다.
///
/// 같은 타입이 두 성격을 다 다루므로, 어느 쪽인지를 값이 아니라 **선언**으로 정한다.
@Suite("EventBroadcaster replay 정책")
struct EventBroadcasterReplayPolicyTests {

    @Test("기본값은 마지막 값을 되돌려준다 — 상태를 보는 구독자가 빈 채로 시작하지 않는다")
    func theDefaultReplaysTheLatestValue() async {
        var broadcaster = EventBroadcaster<Int>()
        broadcaster.send(7)

        let stream = broadcaster.subscribe(onCancel: { _ in })
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == 7)
    }

    @Test("사건 전용 브로드캐스터는 구독 이전의 값을 되돌려주지 않는다")
    func anEventsOnlyBroadcasterReplaysNothing() async {
        var broadcaster = EventBroadcaster<Int>(replayPolicy: .eventsOnly)
        broadcaster.send(7)

        let stream = broadcaster.subscribe(onCancel: { _ in })
        var iterator = stream.makeAsyncIterator()

        // 구독 후에 보낸 것만 온다.
        broadcaster.send(8)
        #expect(await iterator.next() == 8)
    }

    @Test("사건 전용이어도 구독 중에 온 값은 전부 받는다")
    func anEventsOnlyBroadcasterStillDeliversWhileSubscribed() async {
        var broadcaster = EventBroadcaster<Int>(replayPolicy: .eventsOnly)
        let stream = broadcaster.subscribe(onCancel: { _ in })
        var iterator = stream.makeAsyncIterator()

        broadcaster.send(1)
        broadcaster.send(2)
        #expect(await iterator.next() == 1)
        #expect(await iterator.next() == 2)
    }
}
