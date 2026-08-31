import Testing
import CodeNavigatorContract
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

    @Test("5개를 넘으면 5줄 + 외 n개")
    func moreThanFiveFilesAreSummarised() {
        // The count has to be the *remainder*, not the total — "외 8개" when three are
        // listed above would tell the user there are eleven.
        //
        // 단위는 `개`다. 같은 시트의 저장 실패 문구가 파일을 `2개 중 1개`로 세는데 여기만
        // `외 3건`이면 한 시트 안에서 같은 것이 두 단위로 세어진다 — 사용자는 `건`과 `개`가
        // 같은 것을 가리키는지 확인할 방법이 없다.
        let files = (1...8).map { "src/file\($0).rs" }
        let sheet = sheet(files: files)
        #expect(sheet?.fileRows.count == 5)
        #expect(sheet?.overflowNote == "외 3개")
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
        let outcome = SaveAllOutcome(savedPaths: [], failures: [SaveFailure(path: "a.rs", reason: "권한이 없습니다")])
        guard let sheet = sheet(files: ["a.rs"], state: .failed(outcome)) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.failureNote == "⚠ 파일을 저장하지 못했습니다 — 소스 보기에서 확인하세요")
        #expect(sheet.showsSpinner == false)
        #expect(sheet.buttons.allSatisfy { $0.isEnabled }, "실패 후에는 사용자가 다시 고를 수 있어야 한다")
    }

    // MARK: 부분 저장 실패

    @Test("일부만 저장됐으면 몇 개인지 말한다 — 뭉개지 않는다")
    func aPartialSaveSaysHowMuchWasSaved() {
        // "저장 실패" alone tells the user their work is at risk without telling them how
        // much. Three dirty files where two were written is a different situation from
        // three where none were, and the difference decides what they do next.
        let outcome = SaveAllOutcome(
            savedPaths: ["a.rs", "b.rs"],
            failures: [SaveFailure(path: "c.rs", reason: "권한이 없습니다")]
        )
        guard let sheet = sheet(files: ["a.rs", "b.rs", "c.rs"], state: .failed(outcome)) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.failureNote?.contains("3개 중 2개") == true, "무엇이 저장됐는지가 문구에 없다")
        #expect(sheet.failedRows == ["c.rs"], "실패한 파일이 어느 것인지 드러나야 한다")
    }

    @Test("전부 실패하면 저장된 개수를 말하지 않는다")
    func aTotalFailureDoesNotClaimPartialSuccess() {
        let outcome = SaveAllOutcome(
            savedPaths: [],
            failures: [
                SaveFailure(path: "a.rs", reason: "권한이 없습니다"),
                SaveFailure(path: "b.rs", reason: "권한이 없습니다"),
            ]
        )
        guard let sheet = sheet(files: ["a.rs", "b.rs"], state: .failed(outcome)) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.failureNote?.contains("2개 중 0개") == false)
        #expect(sheet.failedRows == ["a.rs", "b.rs"])
    }

    @Test("부분 실패에서도 시트는 열려 있고 버튼이 산다")
    func thePartialFailureSheetStaysOpenAndActionable() {
        // Closing here would discard exactly the files that failed to save.
        let outcome = SaveAllOutcome(savedPaths: ["a.rs"], failures: [SaveFailure(path: "b.rs", reason: "읽기 전용")])
        guard let sheet = sheet(files: ["a.rs", "b.rs"], state: .failed(outcome)) else {
            Issue.record("시트가 없다")
            return
        }
        #expect(sheet.buttons.allSatisfy { $0.isEnabled })
        #expect(sheet.showsSpinner == false)
    }

    @Test("실패 사유가 파일마다 그대로 실린다")
    func eachFailureCarriesItsOwnReason() {
        // Two files can fail for different reasons, and "저장하지 못했습니다" would hide
        // that one is read-only while the other is missing a directory.
        let outcome = SaveAllOutcome(savedPaths: [], failures: [
            SaveFailure(path: "a.rs", reason: "권한이 없습니다"),
            SaveFailure(path: "b.rs", reason: "폴더가 없습니다"),
        ])
        let sheet = sheet(files: ["a.rs", "b.rs"], state: .failed(outcome))
        #expect(sheet?.failureReasons == ["a.rs": "권한이 없습니다", "b.rs": "폴더가 없습니다"])
    }

    @Test("프로젝트 이름이 제목에 그대로 들어간다")
    func theProjectNameAppearsInTheTitle() {
        // Which tab is being closed is the whole question when several are open.
        #expect(sheet(project: "shop", files: ["a.rs"])?.title.contains("'shop'") == true)
    }
}
