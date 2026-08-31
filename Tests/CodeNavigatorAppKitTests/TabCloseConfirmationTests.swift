import Testing
@testable import CodeNavigatorAppKit

/// The sheet that stands between a dirty tab and closing it (W-13, REQ-012 AC-3).
///
/// It exists because Neovim itself refuses to discard a modified buffer (`E37`). An
/// application that closes the tab anyway would be making a different promise than the
/// editor it delegates all editing to — and the two defects this build already closed
/// (⌘S not saving, `gv` deleting the wrong range) were both silent data loss.
@Suite("탭 닫기 확인 — 저장 안 한 변경을 조용히 버리지 않는다 (W-13)")
struct TabCloseConfirmationTests {

    private func sheet(
        project: String = "code-navigator",
        files: [String],
        state: TabCloseConfirmation.SaveState = .idle
    ) -> TabCloseConfirmation? {
        TabCloseConfirmation.make(projectName: project, dirtyFiles: files, saveState: state)
    }

    @Test("깨끗한 탭은 시트 없이 닫힌다")
    func aCleanTabClosesWithoutAsking() {
        // Friction where there is nothing to lose trains people to dismiss the sheet
        // without reading it — and then it fails the one time it matters.
        #expect(sheet(files: []) == nil)
    }

    @Test("더티 1건이면 파일 한 줄")
    func oneDirtyFileIsOneRow() {
        guard let sheet = sheet(files: ["src/main.rs"]) else {
            Issue.record("더티 탭인데 시트가 없다")
            return
        }
        #expect(sheet.title == "'code-navigator' 탭에 저장하지 않은 변경이 있습니다")
        #expect(sheet.body == "저장하지 않고 닫으면 다음 파일의 변경 사항이 사라집니다.")
        #expect(sheet.fileRows == ["src/main.rs"])
        #expect(sheet.overflowNote == nil)
    }

    @Test("5건까지는 전부 보여 준다")
    func fiveFilesAreAllShown() {
        let files = (1...5).map { "src/file\($0).rs" }
        #expect(sheet(files: files)?.fileRows.count == 5)
        #expect(sheet(files: files)?.overflowNote == nil)
    }

    @Test("5건을 넘으면 5줄 + 외 n건")
    func moreThanFiveFilesAreSummarised() {
        // The count has to be the *remainder*, not the total — "외 8건" when three are
        // listed above would tell the user there are eleven.
        let files = (1...8).map { "src/file\($0).rs" }
        let sheet = sheet(files: files)
        #expect(sheet?.fileRows.count == 5)
        #expect(sheet?.overflowNote == "외 3건")
    }

    @Test("버튼 셋이 있고 기본은 저장 후 닫기")
    func theDefaultButtonSaves() {
        // The safe action is the default: Enter must not be the one that discards work.
        guard let sheet = sheet(files: ["a.rs"]) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.buttons.map(\.action) == [.cancel, .closeWithoutSaving, .saveAndClose])
        #expect(sheet.defaultAction == .saveAndClose)
        #expect(sheet.cancelAction == .cancel)
    }

    @Test("저장 중에는 모든 버튼이 비활성이고 스피너가 돈다")
    func everyButtonIsDisabledWhileSaving() {
        // Including cancel: the save is already in flight and Neovim owns the write, so a
        // cancel here would only lie about what it stopped.
        guard let sheet = sheet(files: ["a.rs"], state: .saving) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.buttons.allSatisfy { $0.isEnabled == false })
        #expect(sheet.showsSpinner)
        #expect(sheet.failureNote == nil)
    }

    @Test("저장에 실패하면 시트가 남고 이유를 말한다")
    func aFailedSaveKeepsTheSheetOpen() {
        // Closing after a failed save is exactly the data loss the sheet exists to prevent.
        guard let sheet = sheet(files: ["a.rs"], state: .failed) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.failureNote == "⚠ 일부 파일을 저장하지 못했습니다 — 소스 보기에서 확인하세요")
        #expect(sheet.showsSpinner == false)
        #expect(sheet.buttons.allSatisfy { $0.isEnabled }, "실패 후에는 사용자가 다시 고를 수 있어야 한다")
    }

    @Test("프로젝트 이름이 제목에 그대로 들어간다")
    func theProjectNameAppearsInTheTitle() {
        // Which tab is being closed is the whole question when several are open.
        #expect(sheet(project: "shop", files: ["a.rs"])?.title.contains("'shop'") == true)
    }
}
