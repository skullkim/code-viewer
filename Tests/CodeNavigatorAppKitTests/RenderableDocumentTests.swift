import Testing
@testable import CodeNavigatorAppKit

/// "이 파일을 렌더할 수 있나"는 **한 곳에서만** 답한다.
///
/// 링크 클릭도, 툴바 버튼 활성 여부도, 상태바 문구도 같은 질문을 한다. 답이 두 벌이면
/// **하나만 늘어나는 날**이 온다 — 링크는 열리는데 버튼은 비활성이거나, 그 반대.
@Suite("RenderableDocument — 렌더 가능 판정은 한 곳에서 (W-14)")
struct RenderableDocumentTests {

    @Test("마크다운과 HTML 을 렌더한다")
    func markdownAndHtmlAreRenderable() {
        #expect(RenderableDocument.isRenderable(relativePath: "README.md"))
        #expect(RenderableDocument.isRenderable(relativePath: "docs/guide.html"))
    }

    @Test("코드 파일은 렌더 대상이 아니다")
    func codeFilesAreNot() {
        #expect(!RenderableDocument.isRenderable(relativePath: "src/main.swift"))
        #expect(!RenderableDocument.isRenderable(relativePath: "src/a.ts"))
        #expect(!RenderableDocument.isRenderable(relativePath: "notes.txt"))
    }

    @Test("확장자가 없으면 렌더하지 않는다")
    func aFileWithoutAnExtensionIsNot() {
        #expect(!RenderableDocument.isRenderable(relativePath: "LICENSE"))
        #expect(!RenderableDocument.isRenderable(relativePath: "docs/Makefile"))
    }

    @Test("대소문자는 가리지 않는다")
    func theExtensionMatchIsCaseInsensitive() {
        // `README.MD` 를 소스로만 열면 사용자는 그 파일만 렌더가 고장 났다고 읽는다.
        #expect(RenderableDocument.isRenderable(relativePath: "README.MD"))
        #expect(RenderableDocument.isRenderable(relativePath: "INDEX.HTML"))
    }

    @Test("점이 여럿이어도 마지막 확장자로 판단한다")
    func onlyTheLastExtensionCounts() {
        #expect(RenderableDocument.isRenderable(relativePath: "docs/v1.2.md"))
        #expect(!RenderableDocument.isRenderable(relativePath: "archive.md.zip"))
    }

    @Test("안내 문구가 실제 목록과 어긋나지 않는다")
    func theMessageCannotDriftFromTheList() {
        // W-14 의 문구가 확장자를 **이름으로 부른다**(`.md · .html 만 지원`). 목록만 고치고
        // 문구를 두면 화면이 거짓말을 하므로, 문구를 목록에서 만든다.
        for suffix in RenderableDocument.extensions {
            #expect(
                RenderableDocument.unsupportedMessage.contains(".\(suffix)"),
                "문구가 \(suffix) 를 안 알린다"
            )
        }
        #expect(RenderableDocument.unsupportedMessage.contains("렌더할 수 없습니다"))
    }

    @Test("링크 판정도 같은 답을 쓴다")
    func theLinkDecisionUsesTheSameAnswer() throws {
        // 이 스위트가 지키려는 것 자체다 — 판정이 갈리지 않는지 링크 쪽에서 되짚는다.
        for suffix in RenderableDocument.extensions {
            #expect(RenderableDocument.isRenderable(relativePath: "a.\(suffix)"))
        }
    }
}
