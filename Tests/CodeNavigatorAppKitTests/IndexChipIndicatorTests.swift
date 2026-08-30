import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Design §3 W-10 maps each of the five index states to a mark and says whether it carries
/// a progress bar. §4.5 makes that mark load-bearing rather than decorative: colour alone
/// may not distinguish a state, and two of the five states share the amber tone.
@Suite("IndexChipIndicator — 칩 표시 5상태 (REQ-009, §4.5)")
struct IndexChipIndicatorTests {

    private let progress = IndexProgress(completed: 1_284, total: 4_812)

    @Test("모든 상태가 §3 W-10 표대로 표시된다")
    func everyStateGetsItsMark() {
        // `Kind.allCases` 순회 + `default` 없는 switch. 상태가 늘면 손목록이 그것을
        // 빠뜨리는 대신 이 파일이 컴파일되지 않는다.
        for kind in IndexState.Kind.allCases {
            let state: IndexState
            let expected: IndexChipIndicator
            switch kind {
            case .notIndexed: state = .notIndexed; expected = .dot
            case .ready: state = .ready; expected = .dot
            case .updating: state = .updating; expected = .pulsingDot
            case .indexing: state = .indexing(progress); expected = .spinner
            case .rescanning: state = .rescanning(progress); expected = .spinner
            }
            #expect(IndexChipIndicator.indicator(for: state) == expected, "\(kind)")
        }
    }

    @Test("같은 앰버 두 상태가 서로 다른 표시를 갖는다")
    func theTwoAmberStatesAreDistinguishable() {
        // 갱신 중과 전체 재스캔 중은 색이 같다. 색만으로 구분하지 않는다는 §4.5의
        // 요구가 실제로 지켜지는지가 여기서 갈린다.
        #expect(IndexChipIndicator.indicator(for: .updating)
            != IndexChipIndicator.indicator(for: .rescanning(progress)))
    }

    @Test("진행률을 세는 상태만 진행 바를 켠다")
    func onlyCountingStatesShowAProgressBar() {
        #expect(IndexChipIndicator.showsProgressBar(for: .indexing(progress)))
        #expect(IndexChipIndicator.showsProgressBar(for: .rescanning(progress)))

        // 진행률을 안 가진 상태는 전수로 확인한다 — 새 상태가 조용히 진행 바를 켜거나
        // 끄는 일이 없도록.
        let withoutProgress = IndexState.allKnownCases.filter { $0.progress == nil }
        // 걸러낸 목록이 비면 아래 루프는 한 번도 돌지 않고 조용히 통과한다. `--filter`가
        // 0건을 매칭해도 초록이 뜨는 것과 같은 함정이라, 먼저 비지 않았음을 확인한다.
        #expect(!withoutProgress.isEmpty)
        for state in withoutProgress {
            #expect(!IndexChipIndicator.showsProgressBar(for: state), "\(state.kind)")
        }
    }

    @Test("스피너가 도는 상태는 항상 진행 바를 함께 가진다")
    func aSpinnerAlwaysComesWithABar() {
        // 스피너만 있고 숫자가 없으면 "얼마나 남았나"에 답하지 못한다 — W-10이 두 상태에
        // 모두 {done}/{total}을 적어 둔 이유다.
        let spinning = IndexState.allKnownCases.filter { IndexChipIndicator.indicator(for: $0) == .spinner }
        #expect(!spinning.isEmpty, "스피너 상태가 하나도 없으면 이 테스트는 아무것도 검사하지 않는다")
        for state in spinning {
            #expect(IndexChipIndicator.showsProgressBar(for: state), "\(state.kind)")
        }
    }
}
