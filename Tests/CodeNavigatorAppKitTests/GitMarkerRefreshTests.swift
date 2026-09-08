import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 변경 막대가 **언제** 다시 계산되는지.
///
/// 표시를 만들어 두고 갱신을 안 걸면, 파일을 열 때 한 번 그린 뒤로 영영 그대로다. 사용자는
/// 방금 고친 줄에 막대가 없는 것을 보고 기능이 고장났다고 읽는다.
@Suite("Git 변경 막대 갱신")
@MainActor
struct GitMarkerRefreshTests {

    private func makeModel(
        changes: [GitLineChange] = [GitLineChange(line: 2, kind: .modified)]
    ) -> (AppModel, FakeEditorSession) {
        let editor = FakeEditorSession()
        let model = AppModel(
            editorSession: editor,
            workspace: FakeWorkspace(sharedSession: FakeProjectSession()),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        model.setProjectRootForTesting("/tmp/project")
        model.gitLineChangeProvider = { _, _ in changes }
        return (model, editor)
    }

    private func status(_ path: String, isDirty: Bool = false) -> EditorStatus {
        EditorStatus(
            filePath: path, isDirty: isDirty, cursorLine: 1, cursorColumn: 1,
            mode: .normal, inputMode: .vim
        )
    }

    @Test("파일을 열면 그 파일의 변경 막대를 놓는다")
    func marksOnOpen() async {
        let (model, editor) = makeModel()
        model.handle(editorStatus: status("/tmp/project/A.java"))
        await model.refreshGitMarkers()

        #expect(editor.gitMarkers.isEmpty == false)
        #expect(editor.gitMarkers.last?.modified == [2])
        #expect(editor.gitMarkers.last?.absolutePath == "/tmp/project/A.java")
    }

    /// 저장하면 diff 가 달라진다. 다시 묻지 않으면 방금 고친 줄에 막대가 없다.
    @Test("저장하면 다시 계산한다")
    func recalculatesAfterSaving() async {
        let (model, editor) = makeModel()
        model.handle(editorStatus: status("/tmp/project/A.java", isDirty: true))
        await model.refreshGitMarkers()
        let beforeSave = editor.gitMarkers.count

        model.handle(editorStatus: status("/tmp/project/A.java", isDirty: false))
        await model.settleGitMarkersForTesting()
        #expect(editor.gitMarkers.count > beforeSave, "저장 뒤에 다시 계산하지 않았다")
    }

    /// 다른 파일로 옮기면 그 파일의 것을 놓아야 한다. 앞 파일의 줄 번호를 그대로 두면
    /// 엉뚱한 줄에 막대가 붙는다.
    @Test("파일을 바꾸면 새 파일 기준으로 놓는다")
    func followsTheActiveFile() async {
        let (model, editor) = makeModel()
        model.handle(editorStatus: status("/tmp/project/A.java"))
        await model.refreshGitMarkers()

        model.handle(editorStatus: status("/tmp/project/B.java"))
        await model.refreshGitMarkers()
        #expect(editor.gitMarkers.last?.absolutePath == "/tmp/project/B.java")
    }

    /// 열린 파일이 없으면 물을 것도 없다. 빈 경로로 git 을 부르면 저장소 전체 diff 가 온다.
    @Test("열린 파일이 없으면 git 을 부르지 않는다")
    func asksNothingWithoutAFile() async {
        let (model, editor) = makeModel()
        await model.refreshGitMarkers()
        #expect(editor.gitMarkers.isEmpty)
    }

    /// 변경이 없어도 **빈 표시를 보내야** 한다. 안 보내면 앞서 놓인 막대가 남는다 —
    /// 되돌리기로 원래대로 만들었는데 막대가 그대로인 모양이다.
    @Test("변경이 사라지면 빈 표시를 보내 지운다")
    func clearsWhenNothingDiffers() async {
        let (model, editor) = makeModel(changes: [])
        model.handle(editorStatus: status("/tmp/project/A.java"))
        await model.refreshGitMarkers()

        // 재는 것은 횟수가 아니라 **빈 결과도 보냈는가** 다. 파일이 바뀌면 모델이 스스로
        // 한 번 걸어 두므로 횟수는 그 타이밍에 따라 달라진다.
        #expect(editor.gitMarkers.isEmpty == false, "빈 결과라고 아무것도 안 보내면 옛 막대가 남는다")
        #expect(editor.gitMarkers.allSatisfy { $0.isEmpty })
    }
}
