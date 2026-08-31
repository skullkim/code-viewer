import Testing
import AppKit
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// What reaches Neovim while an input method is composing (D-13, REQ-014 2단계).
///
/// The defect: with a Korean input source the view forwarded `characters` verbatim, which
/// is a single jamo. Typing `한글` put `ㅎㅏㄴㄱㅡㄹ` in the buffer — QA measured 18 bytes
/// on disk where 6 were expected. The composed syllable only exists on the other side of
/// the input context, so the view has to go through it and forward what comes back.
@MainActor
@Suite("입력 조합 — 조합된 글자만 Neovim 에 간다 (D-13)")
struct EditorCompositionTests {

    private func makeView(onKey: @escaping (String) -> Void) -> EditorGridNSView {
        let view = EditorGridNSView()
        view.onKey = onKey
        view.editorMode = .insert
        view.inputMode = .vim
        return view
    }

    @Test("커밋된 글자가 그대로 전달된다 — 자모가 아니라 음절")
    func committedTextIsForwardedWhole() {
        // Whatever the input method commits is what gets sent. The application does not
        // decide what Korean composes to; the input method does.
        var sent: [String] = []
        let view = makeView { sent.append($0) }

        view.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(sent == ["한"])
    }

    @Test("조합 중인 글자는 보내지 않는다")
    func textStillBeingComposedIsNotSent() {
        // It is not committed: the user may still replace or cancel it. Putting it in the
        // buffer would leave characters there that were never typed.
        var sent: [String] = []
        let view = makeView { sent.append($0) }

        view.setMarkedText("ㅎ", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(sent.isEmpty)
        #expect(view.hasMarkedText())
    }

    @Test("조합이 끝나면 마크가 풀리고 커밋본만 남는다")
    func committingClearsTheComposition() {
        var sent: [String] = []
        let view = makeView { sent.append($0) }

        view.setMarkedText("ㅎ", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(sent == ["한"], "조합 중이던 자모까지 함께 가면 버퍼에 'ㅎ한' 이 남는다")
        #expect(view.hasMarkedText() == false)
    }

    @Test("빈 커밋은 아무것도 보내지 않는다")
    func anEmptyCommitSendsNothing() {
        var sent: [String] = []
        let view = makeView { sent.append($0) }

        view.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(sent.isEmpty)
    }

    @Test("마크 해제는 글자를 버리지 않고 상태만 정리한다")
    func unmarkingClearsStateWithoutSending() {
        // `unmarkText` is the input method saying it is done with the marked run. The
        // commit, when there is one, arrives separately through `insertText`.
        var sent: [String] = []
        let view = makeView { sent.append($0) }

        view.setMarkedText("ㅎ", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()

        #expect(sent.isEmpty)
        #expect(view.hasMarkedText() == false)
    }

    @Test("조합 중 표시 범위가 실제 길이를 따른다")
    func theMarkedRangeTracksWhatIsBeingComposed() {
        // The input method asks for this to place its candidate window and to replace the
        // run it owns. A wrong length makes it replace the wrong characters.
        let view = makeView { _ in }
        #expect(view.markedRange().location == NSNotFound)

        view.setMarkedText("한글", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.markedRange() == NSRange(location: 0, length: 2))
    }
}
