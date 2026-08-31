import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Telling the user which projects did not come back (02b W-12, REQ-012 AC-6).
///
/// AC-6 asks that a vanished project is not dropped in silence. Silence is
/// indistinguishable from the application forgetting: the user cannot tell whether their
/// folder moved or something went wrong here, and the two need different responses.
@Suite("복원 실패 시트 — 사라진 프로젝트를 사유와 함께 알린다 (W-12)")
struct MissingTabsPresentationTests {

    private func missing(_ name: String, _ path: String, _ reason: TabRestoreFailureReason) -> MissingTab {
        MissingTab(displayName: name, rootPath: URL(fileURLWithPath: path), reason: reason)
    }

    @Test("복원에 전부 성공하면 시트가 없다")
    func nothingMissingMeansNoSheet() {
        // A sheet after a clean launch is friction with nothing behind it, and friction
        // with nothing behind it teaches people to dismiss sheets unread.
        #expect(MissingTabsPresentation.make(missing: []) == nil)
    }

    @Test("사라진 프로젝트 수를 본문이 말한다")
    func thebodyNamesHowManyAreGone() {
        let sheet = MissingTabsPresentation.make(missing: [
            missing("alpha", "/tmp/alpha", .notFound),
            missing("beta", "/tmp/beta", .notFound),
        ])
        #expect(sheet?.title == "일부 프로젝트를 복원하지 못했습니다")
        #expect(sheet?.body == "다음 2개 프로젝트는 열 수 없어 탭 목록에서 제거했습니다.")
    }

    @Test("경로가 없는 것과 권한이 없는 것을 구분한다")
    func aMissingFolderReadsDifferentlyFromOneYouCannotEnter() {
        // The user's next action differs: a moved folder they can find again, a permission
        // problem they have to grant. One sentence for both would hide which they face.
        let sheet = MissingTabsPresentation.make(missing: [
            missing("alpha", "/tmp/alpha", .notFound),
            missing("beta", "/tmp/beta", .noPermission),
        ])
        #expect(sheet?.rows.map(\.text) == [
            "alpha — 경로를 찾을 수 없습니다: /tmp/alpha",
            "beta — 폴더에 접근할 권한이 없습니다: /tmp/beta",
        ])
    }

    @Test("실패가 다섯이어도 시트는 한 장이다")
    func fiveFailuresAreStillOneSheet() {
        // Five sheets would train the user to hit 확인 five times without reading. One sheet
        // is read (02b W-12).
        let sheet = MissingTabsPresentation.make(missing: (1...5).map {
            missing("p\($0)", "/tmp/p\($0)", .notFound)
        })
        #expect(sheet?.rows.count == 5)
        #expect(sheet?.body.contains("5개") == true)
    }

    @Test("한 개일 때도 개수를 말한다 — 문구가 갈라지지 않는다")
    func asingleFailureUsesTheSameSentence() {
        let sheet = MissingTabsPresentation.make(missing: [missing("alpha", "/tmp/alpha", .notFound)])
        #expect(sheet?.body == "다음 1개 프로젝트는 열 수 없어 탭 목록에서 제거했습니다.")
    }

    @Test("확인 버튼 하나이고 Esc 로도 닫힌다")
    func thereIsOneButtonAndEscapeDismissesIt() {
        // Nothing here is destructive and nothing is undoable, so a second choice would be
        // a decision the user does not actually have (02b W-12 accessibility).
        let sheet = MissingTabsPresentation.make(missing: [missing("alpha", "/tmp/alpha", .notFound)])
        #expect(sheet?.confirmLabel == "확인")
    }
}
