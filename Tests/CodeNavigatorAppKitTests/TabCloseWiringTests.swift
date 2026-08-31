import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Closing a tab with unsaved work, end to end through the model (W-13, REQ-012 AC-3).
///
/// The sheet's wording is tested elsewhere. What matters here is the decision it guards: a
/// tab whose save did not complete must not close, because closing then discards exactly
/// the files that could not be written — the loss the sheet exists to prevent, carried out
/// with the user's consent.
@MainActor
@Suite("탭 닫기 배선 — 저장이 끝나야 닫힌다 (W-13)")
struct TabCloseWiringTests {

    /// An editor that answers the save questions, so the model's decisions can be measured.
    final class SavingEditorSession: FakeEditorSession, @unchecked Sendable {
        var dirtyPaths: [String] = []
        var outcome = SaveAllOutcome(savedPaths: [], failures: [])
        var saveAllError: (any Error)?
        private(set) var saveAllCalls: [URL] = []

        override func dirtyFiles(inProjectRoot root: URL) async throws -> [String] { dirtyPaths }

        override func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome {
            saveAllCalls.append(root)
            if let saveAllError { throw saveAllError }
            return outcome
        }
    }

    private func makeModel() -> (AppModel, SavingEditorSession) {
        let editor = SavingEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, editor)
    }

    private func openTab(_ model: AppModel) async -> ProjectTabState {
        await model.openProject(at: URL(fileURLWithPath: "/tmp/alpha"))
        return model.tabs.activeTab!
    }

    @Test("더티 파일이 있으면 목록을 그대로 돌려준다")
    func dirtyFilesAreReportedForTheTab() async {
        let (model, editor) = makeModel()
        let tab = await openTab(model)
        editor.dirtyPaths = ["src/main.rs", "README.md"]

        #expect(await model.dirtyFiles(in: tab) == ["src/main.rs", "README.md"])
    }

    @Test("깨끗한 탭은 빈 목록이다 — 시트가 뜰 이유가 없다")
    func aCleanTabReportsNothing() async {
        let (model, _) = makeModel()
        let tab = await openTab(model)

        #expect(await model.dirtyFiles(in: tab).isEmpty)
    }

    @Test("저장은 그 탭의 루트 범위로 요청된다")
    func savingIsScopedToTheTabsRoot() async {
        // One Neovim process serves every tab, so a save that meant "the current project"
        // would write another tab's buffers (ADR-0008).
        let (model, editor) = makeModel()
        let tab = await openTab(model)

        _ = await model.saveAll(in: tab)

        #expect(editor.saveAllCalls.map(\.path) == ["/tmp/alpha"])
    }

    @Test("저장이 실패하면 완료로 보고하지 않는다")
    func aFailedSaveIsNotReportedAsComplete() async {
        let (model, editor) = makeModel()
        let tab = await openTab(model)
        editor.outcome = SaveAllOutcome(
            savedPaths: ["a.rs"],
            failures: [SaveFailure(path: "b.rs", reason: "권한이 없습니다")]
        )

        let outcome = await model.saveAll(in: tab)

        #expect(outcome.isComplete == false, "완료로 보고하면 호출부가 탭을 닫고 b.rs 를 버린다")
        #expect(outcome.failures.map(\.path) == ["b.rs"])
    }

    @Test("저장이 던지면 실패로 다룬다 — 조용한 성공이 아니다")
    func aThrownSaveIsAFailure() async {
        // A session whose RPC has died throws rather than answering. "We could not tell"
        // has to read as "not complete", or the caller closes the tab over work nobody
        // wrote.
        //
        // This test used to reproduce a session that did not implement saving at all. That
        // state no longer exists — the protocol requires it now — so it was rewritten
        // against the failure that can still happen.
        let (model, editor) = makeModel()
        let tab = await openTab(model)
        editor.saveAllError = NavigatorError.projectNotFound(path: "/tmp/alpha")

        let outcome = await model.saveAll(in: tab)

        #expect(outcome.isComplete == false)
        #expect(outcome.failures.isEmpty == false, "실패 사유가 없으면 시트가 무엇을 말해야 할지 모른다")
    }
}
