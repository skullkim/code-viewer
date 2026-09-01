import Testing
@testable import CodeNavigatorCore

/// covers: REQ-016 AC-4 (지원하지 않는 언어는 강조 없이 평문), SC-13
///
/// 실측: Neovim 은 파이썬·고 같은 언어도 자기 구문 파일로 **칠한다.** 그러므로 AC-4 는 가만히
/// 두면 얻어지는 상태가 아니라 우리가 만들어야 하는 상태다.
@Suite("구문 강조 허용목록 (REQ-016 AC-4)")
struct SyntaxAllowListTests {

    @Test("지원 언어의 파일타입은 강조를 허용한다")
    func supportedFileTypesAreHighlighted() {
        for fileType in ["java", "kotlin", "typescript", "typescriptreact", "javascript", "javascriptreact"] {
            #expect(
                NeovimSyntaxAllowList.allowsHighlighting(fileType: fileType),
                "\(fileType) 이 허용목록에 없다"
            )
        }
    }

    @Test("지원하지 않는 언어의 파일타입은 강조를 허용하지 않는다")
    func unsupportedFileTypesAreNotHighlighted() {
        // 요구사항이 예로 든 둘(.py·.go)과, Neovim 이 실제로 칠하는 것들.
        for fileType in ["python", "go", "rust", "c", "markdown", "lua", "vim", "sh"] {
            #expect(
                !NeovimSyntaxAllowList.allowsHighlighting(fileType: fileType),
                "\(fileType) 이 허용목록에 있다 — 지원하지 않는 언어가 칠해진다"
            )
        }
    }

    /// "파일타입이 없다"와 "모르는 파일타입이다"는 다른 사실이지만, 강조에 대해서는 같은 답이다.
    /// 그 같음을 우연이 아니라 명시로 둔다 — 빈 문자열이 접두 비교나 사전 조회에서 조용히
    /// 통과하는 값이라서다.
    @Test("파일타입이 비어 있으면 강조하지 않는다")
    func anEmptyFileTypeIsNotHighlighted() {
        #expect(!NeovimSyntaxAllowList.allowsHighlighting(fileType: ""))
    }

    @Test("허용목록의 모든 파일타입이 우리가 아는 언어로 해석된다")
    func everyAllowedFileTypeResolvesToAKnownLanguage() {
        for fileType in NeovimSyntaxAllowList.highlightedFileTypes {
            #expect(
                NeovimSyntaxAllowList.supportedLanguage(forFileType: fileType) != nil,
                "\(fileType) 이 허용됐는데 어떤 언어인지 모른다"
            )
        }
    }

    /// 지원 언어가 늘어날 때 허용목록을 같이 안 고치면 여기서 깨진다. 같은 사실(무엇을
    /// 지원하는가)이 두 곳에 살면 한쪽만 고쳐지고, 그 결과는 "인덱스는 아는데 색은 없는" 언어다.
    @Test("SourceLanguage 의 모든 언어가 적어도 하나의 파일타입을 갖는다")
    func everySupportedLanguageHasAtLeastOneFileType() {
        let covered = Set(
            NeovimSyntaxAllowList.highlightedFileTypes
                .compactMap { NeovimSyntaxAllowList.supportedLanguage(forFileType: $0) }
        )
        #expect(covered == Set(SourceLanguage.allCases))
    }
}
