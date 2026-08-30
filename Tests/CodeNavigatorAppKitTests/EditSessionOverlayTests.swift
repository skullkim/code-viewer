import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Design §3 W-8 and REQ-004 AC-1·AC-5, REQ-NF-005. The overlay covers the editor only —
/// the tree and the panels keep working, because the index is independent of Neovim, and a
/// user who thinks the whole application died will quit it.
@Suite("EditSessionOverlay — 편집 세션 오버레이 (REQ-004 AC-1·AC-5, REQ-NF-005)")
struct EditSessionOverlayTests {

    private func failure(foundVersion: String? = nil) -> EditorStartupFailure {
        EditorStartupFailure(
            kind: .notInstalled,
            reason: "Neovim을 찾을 수 없습니다",
            searchedPaths: ["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim", "/usr/bin/nvim"],
            requiredVersion: "0.9.0",
            foundVersion: foundVersion
        )
    }

    @Test("연결됨 상태에서는 오버레이가 없다")
    func aRunningSessionShowsNoOverlay() {
        #expect(EditSessionOverlay.make(for: .connected) == nil)
    }

    @Test("미기동 상태에서도 오버레이가 없다 — 아직 아무 일도 일어나지 않았다")
    func theNotStartedStateShowsNoOverlay() {
        #expect(EditSessionOverlay.make(for: .notStarted) == nil)
    }

    @Test("연결 중에는 입력이 전달되지 않음을 알린다")
    func connectingWarnsThatKeysGoNowhere() {
        let overlay = EditSessionOverlay.make(for: .connecting)
        #expect(overlay?.title == "편집 세션 연결 중…")
        #expect(overlay?.detail == "연결 전 키 입력은 전달되지 않습니다 (입력 유실 방지)")
        #expect(overlay?.primaryAction == nil, "연결 중에는 누를 것이 없다")
        #expect(overlay?.blocksKeyInput == true)
    }

    // MARK: Start-up failure (REQ-NF-005)

    @Test("Neovim이 없으면 설치 안내와 탐색 경로를 보여준다")
    func aMissingNeovimExplainsItself() {
        let overlay = EditSessionOverlay.make(for: .startupFailed(failure()))
        #expect(overlay?.title == "Neovim을 찾을 수 없습니다")
        #expect(overlay?.installCommand == "brew install neovim")
        #expect(overlay?.requiredVersionText == "필요 버전: 0.9.0 이상")
        #expect(overlay?.searchedPaths.count == 3)
    }

    @Test("버전이 낮으면 없는 것과 다른 문구를 낸다")
    func anOutdatedNeovimGetsItsOwnWording() {
        // "Install Neovim" is unhelpful advice to someone who already has it.
        let overlay = EditSessionOverlay.make(for: .startupFailed(failure(foundVersion: "0.7.2")))
        #expect(overlay?.title == "Neovim 버전이 너무 낮습니다")
        #expect(overlay?.requiredVersionText == "설치된 버전: 0.7.2 · 필요 버전: 0.9.0 이상")
    }

    @Test("기동 실패의 조치는 다시 확인이다")
    func theStartupFailureOffersARecheck() {
        // Design §11 ruling 6 removed the "continue read-only" button, so there is exactly
        // one action here.
        let overlay = EditSessionOverlay.make(for: .startupFailed(failure()))
        #expect(overlay?.primaryAction == .recheck)
        #expect(overlay?.primaryActionTitle == "다시 확인")
    }

    // MARK: Lost session (REQ-004 AC-5, SC-7)

    @Test("끊김에는 재기동 수단이 있다")
    func aLostSessionOffersARestart() {
        let overlay = EditSessionOverlay.make(for: .disconnected(reason: "프로세스가 종료되었습니다"))
        #expect(overlay?.title == "편집 세션이 끊겼습니다")
        #expect(overlay?.primaryAction == .restart)
        #expect(overlay?.primaryActionTitle == "편집 세션 재기동 ⌃⌘R")
    }

    @Test("끊겨도 내비게이션은 쓸 수 있다고 명시한다")
    func aLostSessionSaysWhatStillWorks() {
        // Otherwise the user reads a dead editor as a dead application.
        let overlay = EditSessionOverlay.make(for: .disconnected(reason: "종료"))
        #expect(overlay?.detail.contains("트리·심볼 검색·참조·전문 검색은 계속 사용할 수 있습니다") == true)
    }

    @Test("재기동이 무엇을 되돌리는지 정직하게 말한다")
    func theRestartNoticeIsHonestAboutWhatIsLost() {
        let overlay = EditSessionOverlay.make(for: .disconnected(reason: "종료"))
        #expect(overlay?.recoveryNotice == "재기동하면 파일은 디스크 내용으로 다시 열립니다")
    }

    @Test("끊김 사유를 그대로 보여준다 — 마스킹하지 않는다")
    func theReasonIsShownAsGiven() {
        let overlay = EditSessionOverlay.make(for: .disconnected(reason: "프로세스가 SIGKILL로 종료되었습니다"))
        #expect(overlay?.reasonText == "프로세스가 SIGKILL로 종료되었습니다")
    }

    // MARK: What the overlay covers

    @Test("오버레이는 에디터만 덮는다 — 트리와 패널은 정상이다")
    func theOverlayCoversTheEditorOnly() {
        for state in [EditorSessionState.connecting, .startupFailed(failure()), .disconnected(reason: "x")] {
            let overlay = EditSessionOverlay.make(for: state)
            #expect(overlay?.dimsEditorOnly == true, "\(state)")
            #expect(overlay?.blocksKeyInput == true, "\(state) — 오버레이 중 키 입력은 유실 방지를 위해 버린다")
        }
    }
}
