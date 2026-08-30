import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// REQ-009 and REQ-002 AC-4. The criterion that has nowhere else to live is AC-4: the
/// indexer skips a file it cannot parse instead of stopping, and this popover is the only
/// screen that says so. If the skip count is missing here, the requirement is met by the
/// engine and invisible to the user.
@Suite("IndexDetailsPresentation — 인덱스 상세 팝오버 (REQ-009 · REQ-002 AC-4)")
struct IndexDetailsPresentationTests {

    private let calendar = Calendar(identifier: .gregorian)

    /// 2026-08-29 14:30, fixed so "오늘"/"어제" cannot depend on when the suite runs.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 14, minute: 30))!
    }

    private func date(month: Int, day: Int, hour: Int = 9, minute: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func statistics(
        files: Int = 1_284,
        symbols: Int = 18_402,
        skipped: Int = 0,
        lastUpdatedAt: Date? = nil
    ) -> IndexStatistics {
        IndexStatistics(
            fileCount: files,
            symbolCount: symbols,
            skippedCount: skipped,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    private func make(
        state: IndexState = .ready,
        statistics: IndexStatistics? = nil
    ) -> IndexDetailsPresentation {
        IndexDetailsPresentation.make(
            indexState: state,
            statistics: statistics ?? self.statistics(),
            now: now,
            calendar: calendar
        )
    }

    private func value(_ label: String, in details: IndexDetailsPresentation) -> String? {
        details.rows.first { $0.label == label }?.value
    }

    // MARK: 스킵 건수 (REQ-002 AC-4)

    @Test("스킵된 파일 수가 표시된다")
    func theSkippedFileCountIsShown() {
        let details = make(statistics: statistics(skipped: 3))

        #expect(value("스킵", in: details) == "3건")
        #expect(details.skippedNotice == "파싱 실패 — 로그에 기록됨")
    }

    @Test("스킵이 있으면 경고 색으로 구분된다")
    func aNonZeroSkipCountIsMarked() {
        let details = make(statistics: statistics(skipped: 3))
        #expect(details.rows.first { $0.label == "스킵" }?.isWarning == true)
    }

    @Test("스킵이 0건이어도 행은 남고, 사유 문구만 사라진다")
    func aZeroSkipCountStillShowsTheRow() {
        // 0을 숨기면 "스킵 없음"과 "스킵 표시를 깜빡함"을 구별할 수 없다. 사용자가
        // 심볼이 안 나온다고 느낄 때 확인하러 오는 곳이 여기다.
        let details = make(statistics: statistics(skipped: 0))

        #expect(value("스킵", in: details) == "0건")
        #expect(details.rows.first { $0.label == "스킵" }?.isWarning == false)
        #expect(details.skippedNotice == nil)
    }

    @Test("큰 수는 천 단위로 끊어 읽는다")
    func largeCountsAreGrouped() {
        // 02 §7의 표기가 "1,284/4,812"다.
        let details = make(statistics: statistics(files: 1_284, symbols: 18_402, skipped: 1_000))

        #expect(value("파일", in: details) == "1,284개")
        #expect(value("심볼", in: details) == "18,402개")
        #expect(value("스킵", in: details) == "1,000건")
    }

    // MARK: 마지막 갱신 시각

    @Test("오늘 갱신됐으면 시각까지 보여준다")
    func todaysUpdateShowsTheTime() {
        let details = make(statistics: statistics(lastUpdatedAt: date(month: 8, day: 29, hour: 9, minute: 12)))
        #expect(value("마지막 갱신", in: details) == "오늘 09:12")
    }

    @Test("어제 갱신은 '어제'로 적는다")
    func yesterdaysUpdateSaysYesterday() {
        let details = make(statistics: statistics(lastUpdatedAt: date(month: 8, day: 28)))
        #expect(value("마지막 갱신", in: details) == "어제")
    }

    @Test("더 오래된 갱신은 날짜로 적는다")
    func olderUpdatesShowTheDate() {
        let details = make(statistics: statistics(lastUpdatedAt: date(month: 8, day: 26)))
        #expect(value("마지막 갱신", in: details) == "8월 26일")
    }

    @Test("해가 바뀐 갱신에는 연도가 붙는다")
    func lastYearsUpdateCarriesTheYear() {
        let details = make(statistics: statistics(lastUpdatedAt: date(month: 8, day: 26, year: 2025)))
        #expect(value("마지막 갱신", in: details) == "2025년 8월 26일")
    }

    @Test("한 번도 갱신되지 않았으면 그렇게 말한다")
    func aNeverUpdatedIndexSaysSo() {
        // `lastUpdatedAt`은 첫 인덱싱이 끝나기 전까지 nil이다. 시각을 지어내면
        // 인덱스가 이미 돌았다는 뜻이 된다.
        let details = make(statistics: statistics(lastUpdatedAt: nil))
        #expect(value("마지막 갱신", in: details) == "아직 없음")
    }

    @Test("통계가 아직 없으면 숫자를 지어내지 않는다")
    func absentStatisticsProduceNoFigures() {
        let details = IndexDetailsPresentation.make(
            indexState: .notIndexed,
            statistics: nil,
            now: now,
            calendar: calendar
        )

        #expect(details.rows.map(\.label) == ["마지막 갱신"])
        #expect(value("마지막 갱신", in: details) == "아직 없음")
    }

    // MARK: 상태 (§6 전이표 1:1)

    @Test("모든 상태의 제목이 §3 W-10 표와 같다")
    func everyStateHasItsLabel() {
        let progress = IndexProgress(completed: 1_284, total: 4_812)

        // `Kind.allCases`를 순회하고 `default`가 없다. 상태가 하나 늘면 손목록이 조용히
        // 그것을 빠뜨리는 대신 이 switch가 컴파일되지 않는다.
        for kind in IndexState.Kind.allCases {
            let state: IndexState
            let expected: String
            switch kind {
            case .notIndexed: state = .notIndexed; expected = "인덱스 없음"
            case .indexing: state = .indexing(progress); expected = "인덱싱 중 1,284/4,812"
            case .ready: state = .ready; expected = "인덱스 최신"
            case .updating: state = .updating; expected = "갱신 중"
            case .rescanning: state = .rescanning(progress); expected = "전체 재스캔 중 1,284/4,812"
            }
            #expect(make(state: state).title == expected, "\(kind)")
        }
    }

    @Test("최신이 아닌 모든 상태에 낡음 고지가 붙는다")
    func everyNonReadyStateWarnsAboutStaleness() {
        // INV-1: 재빌드 중에도 직전 인덱스가 답한다. 그 사실을 감추면 사용자는 낡은
        // 결과를 현재 상태로 읽는다.
        // 손으로 적은 목록은 다음에 추가되는 상태를 빠뜨린다 — 그러면 새 상태만
        // 낡음 고지 없이 초록으로 지나간다. 계약이 주는 전수 목록을 순회한다.
        let notReady = IndexState.allKnownCases.filter { $0.kind != .ready }
        // 걸러낸 목록이 비면 루프가 안 돌고 조용히 통과한다.
        #expect(!notReady.isEmpty)
        for state in notReady {
            #expect(make(state: state).staleNotice != nil, "\(state.kind)")
        }
        #expect(make(state: .ready).staleNotice == nil)
    }

    @Test("진행률이 있는 상태만 진행 바를 켠다")
    func onlyProgressStatesCarryProgress() {
        let progress = IndexProgress(completed: 3, total: 9)

        #expect(make(state: .indexing(progress)).progress == progress)
        #expect(make(state: .rescanning(progress)).progress == progress)

        // 단일 파일 갱신은 순간이라 진행 바가 의미 없다 (02 §3 W-10). 나머지 상태는
        // 전수로 훑어 "진행률을 안 가진 상태가 진행 바를 켜지 않는지"를 확인한다.
        let withoutProgress = IndexState.allKnownCases.filter { $0.progress == nil }
        #expect(!withoutProgress.isEmpty)
        for state in withoutProgress {
            #expect(make(state: state).progress == nil, "\(state.kind)")
        }
    }

    // MARK: 자릿수 구분 (§7 표기) — 매 진행률 틱마다 도는 경로다

    @Test("천 단위 구분이 경계마다 정확하다")
    func groupingIsCorrectAtEveryBoundary() {
        let expected: [(Int, String)] = [
            (0, "0"), (7, "7"), (99, "99"), (999, "999"),
            (1_000, "1,000"), (1_284, "1,284"), (18_402, "18,402"),
            (100_000, "100,000"), (999_999, "999,999"),
            (1_000_000, "1,000,000"), (1_234_567, "1,234,567"),
        ]

        for (value, text) in expected {
            #expect(IndexDetailsPresentation.grouped(value) == text, "\(value)")
        }
    }

    @Test("음수와 극단값에서도 무너지지 않는다")
    func groupingSurvivesTheEdges() {
        // 카운트가 음수일 일은 없지만, 여기서 트랩이 나면 상태바가 통째로 죽는다.
        #expect(IndexDetailsPresentation.grouped(-1_284) == "-1,284")
        #expect(IndexDetailsPresentation.grouped(Int.min).hasPrefix("-"))
        #expect(!IndexDetailsPresentation.grouped(Int.max).isEmpty)
    }

    // MARK: kind — 페이로드가 바뀌어도 그대로여야 하는 것

    @Test("진행률 숫자만 바뀌면 낡음 고지는 그대로다")
    func onlyTheNumbersChangeAsProgressAdvances() {
        // `kind`가 같으면 상태의 정체가 같다는 뜻이다. 고지·경고처럼 정체에만 달린
        // 것들이 진행률을 따라 깜빡이면 안 된다.
        let early = make(state: .indexing(IndexProgress(completed: 1, total: 4_812)))
        let late = make(state: .indexing(IndexProgress(completed: 4_811, total: 4_812)))

        #expect(early.staleNotice == late.staleNotice)
        #expect(early.skippedNotice == late.skippedNotice)
        #expect(early.title != late.title, "제목은 진행률을 보여 주므로 달라야 한다")
    }
}
