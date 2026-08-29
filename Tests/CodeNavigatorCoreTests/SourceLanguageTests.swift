import Testing
@testable import CodeNavigatorCore

@Suite("SourceLanguage — 확장자 매핑")
struct SourceLanguageTests {

    @Test("지원 확장자가 언어로 매핑된다", arguments: [
        ("Sample.kt", SourceLanguage.kotlin),
        ("a/build.gradle.kts", SourceLanguage.kotlin),
        ("Sample.java", SourceLanguage.java),
        ("sample.ts", SourceLanguage.typescript),
        ("sample.mts", SourceLanguage.typescript),
        ("sample.cts", SourceLanguage.typescript),
        ("sample.tsx", SourceLanguage.typescript),
        ("sample.js", SourceLanguage.javascript),
        ("sample.jsx", SourceLanguage.javascript),
        ("sample.mjs", SourceLanguage.javascript),
        ("sample.cjs", SourceLanguage.javascript),
    ])
    func mapsSupportedExtensions(path: String, expected: SourceLanguage) {
        #expect(SourceLanguage(filePath: path) == expected)
    }

    @Test("미지원 확장자는 nil이다", arguments: [
        "README.md", "config.yaml", "image.png", "Makefile", "noextension", ".gitignore",
    ])
    func returnsNilForUnsupportedExtensions(path: String) {
        #expect(SourceLanguage(filePath: path) == nil)
    }

    @Test("확장자 대소문자를 가리지 않는다")
    func extensionMatchingIsCaseInsensitive() {
        #expect(SourceLanguage(filePath: "Sample.KT") == .kotlin)
        #expect(SourceLanguage(filePath: "Sample.Java") == .java)
    }

    @Test("파싱에 쓸 문법은 언어와 별개로 결정된다 — JS 계열은 TSX 문법을 쓴다")
    func selectsGrammarSeparatelyFromLanguage() {
        #expect(GrammarKind(filePath: "sample.ts") == .typescript)
        #expect(GrammarKind(filePath: "sample.tsx") == .tsx)
        #expect(GrammarKind(filePath: "sample.js") == .tsx)
        #expect(GrammarKind(filePath: "sample.jsx") == .tsx)
        #expect(GrammarKind(filePath: "sample.mjs") == .tsx)
        #expect(GrammarKind(filePath: "Sample.kt") == .kotlin)
        #expect(GrammarKind(filePath: "Sample.java") == .java)
        #expect(GrammarKind(filePath: "README.md") == nil)
    }
}
