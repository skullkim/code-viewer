import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// REQ-013 and design 02b §3 W-14.
///
/// Two rules carry requirements rather than styling. AC-6 forbids a blank screen: every
/// state that cannot draw a document draws a card that says why and offers a way out. And
/// the size limit refuses to render rather than rendering part — a truncated document reads
/// as "it ends here", which is a silent lie.
@Suite("RenderDocumentPresentation — 렌더 표면 상태 (REQ-013, §3 W-14)")
struct RenderDocumentPresentationTests {

    private func make(
        _ phase: RenderPhase,
        hasPrevious: Bool = false,
        elapsed: Double? = nil
    ) -> RenderDocumentPresentation {
        RenderDocumentPresentation.make(
            fileName: "README.md",
            phase: phase,
            hasPreviousDocument: hasPrevious,
            elapsedSeconds: elapsed
        )
    }

    // MARK: 읽기 전용

    @Test("읽기 전용 배지는 어느 상태에서나 헤더에 있다")
    func theReadOnlyBadgeIsAlwaysPresent() {
        // 렌더 보기 동안 에디터로 가는 키가 전달되지 않는다. 그 사실이 화면에 없으면
        // 사용자는 타이핑이 먹히지 않는 것을 고장으로 읽는다.
        let phases: [RenderPhase] = [
            .rendering, .rerendering, .rendered(source: .buffer), .empty,
            .failed(reason: "x"), .undecodable, .tooLarge(byteCount: 1),
        ]
        for phase in phases {
            #expect(make(phase).readOnlyBadge == "읽기 전용", "\(phase)")
        }
    }

    // MARK: 버퍼 우선 · 디스크 폴백

    @Test("버퍼를 그렸으면 출처 배지가 없다")
    func renderingTheBufferNeedsNoBadge() {
        // 정상 경로다. 늘 배지를 달면 아무도 안 읽게 된다.
        let screen = make(.rendered(source: .buffer))
        #expect(screen.sourceBadge == nil)
        #expect(screen.sourceTooltip == nil)
    }

    @Test("디스크로 떨어졌으면 화면이 그렇게 말한다")
    func fallingBackToDiskIsAnnounced() {
        // 조용한 폴백은 "방금 친 문단이 없는 화면"을 정상으로 보이게 한다 — 그건
        // 낡은 게 아니라 틀린 것이다.
        let screen = make(.rendered(source: .disk))
        #expect(screen.sourceBadge == "저장된 내용")
        #expect(screen.sourceTooltip?.isEmpty == false)
    }

    // MARK: 깜빡임 방지

    @Test("200ms 전에는 스피너를 그리지 않는다")
    func aFastRenderShowsNoSpinner() {
        // 02 W-3 규칙 계승. 대부분의 렌더가 몇 ms에 끝나고, 그때 스피너는 진행이
        // 아니라 결함처럼 보인다.
        #expect(make(.rendering, elapsed: 0.05).progressText == nil)
        #expect(make(.rendering, elapsed: 0.199).progressText == nil)
    }

    @Test("200ms를 넘으면 스피너와 문구가 나온다")
    func aSlowRenderExplainsItself() {
        #expect(make(.rendering, elapsed: 0.2).progressText == "문서를 렌더하는 중…")
        #expect(make(.rendering, elapsed: 3).progressText == "문서를 렌더하는 중…")
    }

    @Test("재렌더는 중앙 스피너 대신 헤더 스피너다")
    func aRerenderSpinsInTheHeader() {
        let screen = make(.rerendering, hasPrevious: true)
        #expect(screen.showsHeaderSpinner)
        #expect(screen.progressText == nil)
    }

    @Test("저장 후 재렌더는 읽던 문서를 지우지 않는다")
    func arerenderKeepsTheDocumentOnScreen() {
        // AC-5. 읽는 중에 화면이 비면 스크롤 위치도 맥락도 잃는다.
        #expect(make(.rerendering, hasPrevious: true).keepsPreviousDocument)
        #expect(make(.rerendering, hasPrevious: false).keepsPreviousDocument == false)
    }

    // MARK: 카드 (AC-6 — 빈 화면 금지)

    @Test("문서를 못 그리는 모든 상태가 카드를 낸다")
    func everyUndrawableStateExplainsItself() {
        // AC-6 의 전부다. 어느 하나가 카드 없이 지나가면 그 자리가 빈 화면이 된다.
        let phases: [RenderPhase] = [
            .empty, .failed(reason: "권한 없음"), .undecodable, .tooLarge(byteCount: 5_000_000),
        ]
        for phase in phases {
            guard let notice = make(phase).notice else {
                Issue.record("\(phase) 가 카드 없이 지나갔다")
                continue
            }
            #expect(!notice.title.isEmpty, "\(phase)")
            #expect(!notice.detail.isEmpty, "\(phase)")
            #expect(notice.actions.contains(.viewSource), "\(phase) 에 빠져나갈 길이 없다")
        }
    }

    @Test("문서를 그리는 상태에는 카드가 없다")
    func drawableStatesShowNoCard() {
        for phase in [RenderPhase.rendering, .rerendering, .rendered(source: .buffer)] {
            #expect(make(phase).notice == nil, "\(phase)")
        }
    }

    @Test("읽기 실패만 다시 시도를 제공한다")
    func onlyAFailureOffersRetry() {
        // 빈 파일이나 인코딩 불일치는 다시 시도해도 같다 — 죽은 버튼을 두지 않는다.
        #expect(make(.failed(reason: "x")).notice?.actions.contains(.retry) == true)
        #expect(make(.empty).notice?.actions.contains(.retry) == false)
        #expect(make(.undecodable).notice?.actions.contains(.retry) == false)
        #expect(make(.tooLarge(byteCount: 1)).notice?.actions.contains(.retry) == false)
    }

    // MARK: 크기 상한

    @Test("크기 초과는 상한과 실제 크기를 둘 다 말한다")
    func theSizeLimitNamesBothNumbers() {
        // "너무 큽니다"만 있으면 얼마나 줄여야 하는지 알 수 없다.
        let notice = make(.tooLarge(byteCount: 5_400_000)).notice
        #expect(notice?.detail.contains("2") == true, "상한이 안 적혔다: \(notice?.detail ?? "")")
        #expect(notice?.detail.contains("5") == true, "실제 크기가 안 적혔다: \(notice?.detail ?? "")")
    }

    @Test("크기 초과는 잘라서 보여주지 않는다")
    func anOversizedDocumentIsNotPartiallyRendered() {
        // 부분 렌더는 "문서가 여기서 끝났다"로 읽힌다 — 조용한 거짓말이다. 자를 바에는
        // 못 그린다고 말하고 소스로 보낸다.
        let screen = make(.tooLarge(byteCount: 5_400_000))
        #expect(screen.notice != nil)
        #expect(!screen.keepsPreviousDocument)
        #expect(screen.notice?.actions == [.viewSource])
    }

    @Test("상한은 2MB다")
    func theLimitIsTwoMegabytes() {
        #expect(RenderDocumentPresentation.maximumRenderableBytes == 2 * 1024 * 1024)
    }
}
