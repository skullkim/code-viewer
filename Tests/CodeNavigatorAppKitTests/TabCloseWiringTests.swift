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
    final class SavingEditorSession: FakeEditorSession, EditorSaving, @unchecked Sendable {
        var dirtyPaths: [String] = []
        var outcome = SaveAllOutcome(savedPaths: [], failures: [])
        private(set) var saveAllCalls: [URL] = []

        func dirtyFiles(inProjectRoot root: URL) async throws -> [String] { dirtyPaths }

        func saveAll(inProjectRoot root: URL) async throws -> SaveAllOutcome {
            saveAllCalls.append(root)
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

    @Test("편집기가 저장에 답하지 못하면 실패로 다룬다 — 조용한 성공이 아니다")
    func anEditorThatCannotSaveIsAFailure() async {
        // `FakeEditorSession` does not implement the saving seam, which stands in for a
        // session that never started. "We could not ask" has to read as "not complete", or
        // the tab closes over work nobody wrote.
        let model = AppModel(
            editorSession: FakeEditorSession(),
            workspace: FakeWorkspace(),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let tab = await openTab(model)

        let outcome = await model.saveAll(in: tab)

        #expect(outcome.isComplete == false)
        #expect(await model.dirtyFiles(in: tab).isEmpty, "물어볼 수 없다면 잃을 것도 모르므로 시트를 띄우지 않는다")
    }
}
