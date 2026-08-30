import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// Design §3 W-3 asks for the spinner only after 200ms. The rule exists to prevent a
/// flash, so the cases that matter are the ones just under and just over the line — a
/// threshold that is off by one direction shows the flicker it was written to remove.
@Suite("SpinnerDelay — 깜빡임 방지 200ms (REQ-007)")
struct SpinnerDelayTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func showsSpinner(afterMilliseconds elapsed: Double) -> Bool {
        SpinnerDelay.showsSpinner(startedAt: start, now: start.addingTimeInterval(elapsed / 1_000))
    }

    @Test("검색이 돌고 있지 않으면 스피너가 없다")
    func noSearchMeansNoSpinner() {
        #expect(!SpinnerDelay.showsSpinner(startedAt: nil, now: start))
    }

    @Test("막 시작한 검색에는 스피너가 없다")
    func aJustStartedSearchShowsNothing() {
        #expect(!showsSpinner(afterMilliseconds: 0))
    }

    @Test("199ms까지는 스피너가 없다")
    func justUnderTheThresholdStaysQuiet() {
        // 대부분의 심볼 검색이 여기서 끝난다. 이 경계가 무너지면 화면이 매 타이핑마다
        // 깜빡인다.
        #expect(!showsSpinner(afterMilliseconds: 199))
    }

    @Test("정확히 200ms부터 스피너가 보인다")
    func theThresholdItselfShowsTheSpinner() {
        #expect(showsSpinner(afterMilliseconds: 200))
    }

    @Test("더 오래 걸리면 계속 보인다")
    func aSlowSearchKeepsTheSpinner() {
        #expect(showsSpinner(afterMilliseconds: 1_500))
    }

    @Test("시계가 거꾸로 가도 스피너가 켜지지 않는다")
    func aBackwardsClockDoesNotSummonASpinner() {
        // 시스템 시각 보정으로 now < startedAt 이 될 수 있다. 음수 간격을 크기로만
        // 비교하면 멈춘 화면에 스피너가 뜬다.
        #expect(!SpinnerDelay.showsSpinner(startedAt: start, now: start.addingTimeInterval(-5)))
    }

    @Test("문턱값이 디자인 문서의 200ms다")
    func theThresholdMatchesTheDocument() {
        #expect(SpinnerDelay.threshold == 0.2)
    }
}
