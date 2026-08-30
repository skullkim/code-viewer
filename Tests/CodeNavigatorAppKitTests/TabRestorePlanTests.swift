import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// REQ-012 AC-4 (the tab list comes back) and AC-6 (a tab that cannot come back is
/// announced, not dropped).
///
/// AC-6 is the criterion worth the tests. Quietly shortening the list looks exactly like
/// the app forgetting the tab, and the user has no way to tell which happened — this build
/// already shipped one silent failure that took hours to find.
@Suite("TabRestorePlan — 재시작 복원 (REQ-012 AC-4·AC-6)")
struct TabRestorePlanTests {

    private func tab(_ name: String) -> SavedTab {
        SavedTab(identity: "/repo/\(name)", rootPath: "/repo/\(name)", displayName: name)
    }

    private func plan(
        _ saved: [SavedTab],
        active: String? = nil,
        failing: [String: TabRestoreFailure] = [:]
    ) -> TabRestorePlan {
        TabRestorePlanner.plan(
            saved: saved,
            activeIdentity: active,
            reachability: { failing[$0.displayName] }
        )
    }

    // MARK: 빈 상태

    @Test("저장된 탭이 없으면 첫 실행이고 시트도 없다")
    func nothingSavedIsAFirstRun() {
        let result = plan([])

        #expect(result.isFirstRun)
        #expect(result.showsWelcome)
        #expect(!result.showsFailureSheet)
        #expect(result.activeIndex == nil)
    }

    // MARK: 전부 성공

    @Test("전부 열리면 그대로 복원되고 시트가 없다")
    func everyReachableTabComesBack() {
        let saved = [tab("a"), tab("b"), tab("c")]
        let result = plan(saved)

        #expect(result.restored.map(\.displayName) == ["a", "b", "c"])
        #expect(result.omitted.isEmpty)
        #expect(!result.showsFailureSheet)
        #expect(!result.showsWelcome)
    }

    @Test("저장된 활성 탭이 그대로 활성으로 온다")
    func theSavedActiveTabIsRestoredActive() {
        let saved = [tab("a"), tab("b"), tab("c")]
        let result = plan(saved, active: "/repo/b")

        #expect(result.activeIndex == 1)
    }

    @Test("활성 탭 정보가 없으면 첫 탭이 활성이다")
    func noSavedActiveFallsBackToTheFirst() {
        // 탭은 있는데 활성이 없는 상태는 02b 의 어느 상태에도 없다.
        #expect(plan([tab("a"), tab("b")]).activeIndex == 0)
    }

    // MARK: 일부 실패 — AC-6

    @Test("사라진 탭은 조용히 버려지지 않고 사유와 함께 남는다")
    func aMissingTabIsReportedNotDropped() {
        let saved = [tab("a"), tab("gone"), tab("c")]
        let result = plan(saved, failing: ["gone": .notFound])

        #expect(result.restored.map(\.displayName) == ["a", "c"])
        #expect(result.omitted.map(\.tab.displayName) == ["gone"])
        #expect(result.showsFailureSheet)
    }

    @Test("사유는 마스킹하지 않는다 — 없음과 권한 없음이 다르게 적힌다")
    func theTwoFailuresAreWordedDifferently() {
        // 사용자가 할 수 있는 일이 다르다: 옮겨진 폴더는 없는 것이고, 권한 없는 폴더는
        // 거기 있다. 하나로 뭉뚱그리면 어느 쪽인지 알 수 없다(02b §7).
        let result = plan(
            [tab("gone"), tab("locked")],
            failing: ["gone": .notFound, "locked": .noPermission]
        )

        let messages = result.omitted.map(\.message)
        #expect(messages[0] == "gone — 경로를 찾을 수 없습니다: /repo/gone")
        #expect(messages[1] == "locked — 폴더에 접근할 권한이 없습니다: /repo/locked")
    }

    @Test("활성 탭이 사라졌으면 살아남은 첫 탭이 활성이 된다")
    func aLostActiveTabFallsBackToASurvivor() {
        let result = plan([tab("a"), tab("gone")], active: "/repo/gone", failing: ["gone": .notFound])

        #expect(result.activeIndex == 0)
        #expect(result.restored.map(\.displayName) == ["a"])
    }

    @Test("활성 인덱스는 언제나 복원된 목록 안을 가리킨다")
    func theActiveIndexAlwaysPointsIntoTheRestoredList() {
        // 사라진 탭 때문에 인덱스가 밀리면 활성 인덱스가 목록 밖을 가리킬 수 있다 —
        // 그 화면은 빈 창이다.
        let saved = (0..<5).map { tab("p\($0)") }
        for failingCount in 0..<5 {
            let failing = Dictionary(
                uniqueKeysWithValues: (0..<failingCount).map { ("p\($0)", TabRestoreFailure.notFound) }
            )
            let result = plan(saved, active: "/repo/p4", failing: failing)

            guard let index = result.activeIndex else {
                #expect(result.restored.isEmpty)
                continue
            }
            #expect(result.restored.indices.contains(index), "실패 \(failingCount)건에서 인덱스가 밖을 가리켰다")
        }
    }

    // MARK: 전부 실패

    @Test("전부 실패하면 웰컴 화면과 시트가 함께 나온다")
    func losingEverythingShowsWelcomeAndTheSheet() {
        let result = plan(
            [tab("a"), tab("b")],
            failing: ["a": .notFound, "b": .noPermission]
        )

        #expect(result.restored.isEmpty)
        #expect(result.activeIndex == nil)
        #expect(result.showsWelcome)
        #expect(result.showsFailureSheet)
        // 저장된 게 있었으므로 첫 실행이 아니다 — 시트가 필요한 이유다.
        #expect(!result.isFirstRun)
    }

    @Test("전부 실패와 첫 실행은 구별된다")
    func totalFailureIsNotAFirstRun() {
        // 둘 다 웰컴 화면이지만 하나는 시트가 있고 하나는 없다. 여기서 뭉개면
        // AC-6 이 사라진다 — 잃어버린 탭을 말해 줄 자리가 없어진다.
        let firstRun = plan([])
        let totalLoss = plan([tab("a")], failing: ["a": .notFound])

        #expect(firstRun.showsWelcome && totalLoss.showsWelcome)
        #expect(firstRun.isFirstRun && !totalLoss.isFirstRun)
        #expect(!firstRun.showsFailureSheet && totalLoss.showsFailureSheet)
    }

    // MARK: 순서와 개수

    @Test("복원 순서는 저장 순서를 지킨다")
    func theSavedOrderSurvives() {
        // 순서도 AC-4 가 복원한다고 한 것에 포함된다(드래그 재정렬이 저장되므로).
        let saved = [tab("z"), tab("a"), tab("m")]
        #expect(plan(saved).restored.map(\.displayName) == ["z", "a", "m"])
    }

    @Test("복원된 것과 빠진 것의 합은 언제나 저장된 수다")
    func nothingIsLostBetweenTheTwoLists() {
        // 어느 한쪽에서 조용히 사라지는 탭이 없어야 AC-6 이 성립한다.
        let saved = (0..<6).map { tab("p\($0)") }
        for failingCount in 0...6 {
            let failing = Dictionary(
                uniqueKeysWithValues: (0..<failingCount).map { ("p\($0)", TabRestoreFailure.notFound) }
            )
            let result = plan(saved, failing: failing)
            #expect(
                result.restored.count + result.omitted.count == saved.count,
                "실패 \(failingCount)건에서 탭이 사라졌다"
            )
        }
    }
}
