import Testing
@testable import CodeNavigatorAppKit

/// D-8 — 포커스 링과 실제 키보드 포커스가 같은 것을 가리켜야 한다 (REQ-003).
@Suite("트리 포커스 링은 실제 포커스를 그린다 (D-8, REQ-003)")
struct FileTreeFocusMarkTests {

    @Test("트리가 키보드를 가졌고 선택된 행이면 링을 그린다")
    func theRingAppearsWhenTheTreeActuallyHasTheKeyboard() {
        #expect(FileTreeFocusMark.showsKeyboardCursor(isSelected: true, treeOwnsKeyboard: true))
    }

    @Test("🔑 키보드가 에디터에 있으면 선택돼 있어도 링을 안 그린다")
    func theRingDoesNotLieWhenTheEditorHasTheKeyboard() {
        // D-8 그 자체. 링이 떠 있는데 ↓ 가 nvim 커서를 움직였다 — 사용자는 트리를
        // 움직이려다 편집 위치를 잃는다.
        #expect(!FileTreeFocusMark.showsKeyboardCursor(isSelected: true, treeOwnsKeyboard: false))
    }

    @Test("선택되지 않은 행에는 트리가 포커스를 가져도 링이 없다")
    func unselectedRowsNeverWearTheRing() {
        #expect(!FileTreeFocusMark.showsKeyboardCursor(isSelected: false, treeOwnsKeyboard: true))
        #expect(!FileTreeFocusMark.showsKeyboardCursor(isSelected: false, treeOwnsKeyboard: false))
    }
}
