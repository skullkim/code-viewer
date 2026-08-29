import Testing
@testable import CodeNavigatorCore

private func matcher(_ text: String, baseDirectory: String = "") -> GitignoreMatcher {
    GitignoreMatcher(ruleSets: [GitignoreRuleSet(baseDirectory: baseDirectory, patternText: text)])
}

@Suite("GitignoreMatcher — 기본 문법")
struct GitignoreBasicSyntaxTests {

    @Test("단순 이름은 어느 깊이에서든 일치한다")
    func plainNameMatchesAtAnyDepth() {
        let ignore = matcher("secrets.txt")
        #expect(ignore.isIgnored(relativePath: "secrets.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "src/secrets.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "a/b/c/secrets.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "notsecrets.txt", isDirectory: false) == false)
    }

    @Test("빈 줄과 주석은 무시된다")
    func skipsBlankLinesAndComments() {
        let ignore = matcher("""

        # 주석이다
        build

        """)
        #expect(ignore.isIgnored(relativePath: "build", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "#", isDirectory: false) == false)
    }

    @Test("이스케이프한 #은 리터럴이다")
    func treatsEscapedHashAsLiteral() {
        let ignore = matcher("\\#literal")
        #expect(ignore.isIgnored(relativePath: "#literal", isDirectory: false))
    }

    @Test("후행 공백은 제거되지만 이스케이프한 공백은 남는다")
    func stripsTrailingWhitespaceUnlessEscaped() {
        #expect(matcher("build   ").isIgnored(relativePath: "build", isDirectory: true))
        #expect(matcher("name\\ ").isIgnored(relativePath: "name ", isDirectory: false))
    }

    @Test("별표는 슬래시를 넘지 않는다")
    func starDoesNotCrossSlash() {
        let ignore = matcher("*.log")
        #expect(ignore.isIgnored(relativePath: "app.log", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "logs/app.log", isDirectory: false))
        #expect(matcher("src/*.log").isIgnored(relativePath: "src/deep/app.log", isDirectory: false) == false)
    }

    @Test("물음표는 한 글자에만 일치하고 슬래시를 넘지 않는다")
    func questionMarkMatchesSingleCharacter() {
        let ignore = matcher("file?.txt")
        #expect(ignore.isIgnored(relativePath: "file1.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "file12.txt", isDirectory: false) == false)
    }

    @Test("문자 클래스를 지원한다")
    func supportsCharacterClasses() {
        let ignore = matcher("file[0-9].txt")
        #expect(ignore.isIgnored(relativePath: "file3.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "fileA.txt", isDirectory: false) == false)
    }
}

@Suite("GitignoreMatcher — 앵커링과 디렉토리")
struct GitignoreAnchoringTests {

    @Test("슬래시로 시작하면 루트에만 앵커된다")
    func leadingSlashAnchorsToRoot() {
        let ignore = matcher("/build")
        #expect(ignore.isIgnored(relativePath: "build", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "src/build", isDirectory: true) == false)
    }

    @Test("중간에 슬래시가 있으면 앵커된다")
    func innerSlashAnchorsPattern() {
        let ignore = matcher("src/generated")
        #expect(ignore.isIgnored(relativePath: "src/generated", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "lib/src/generated", isDirectory: true) == false)
    }

    @Test("후행 슬래시는 디렉토리에만 일치한다")
    func trailingSlashMatchesDirectoriesOnly() {
        let ignore = matcher("build/")
        #expect(ignore.isIgnored(relativePath: "build", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "build", isDirectory: false) == false)
    }

    @Test("후행 슬래시가 없으면 파일과 디렉토리 모두 일치한다")
    func withoutTrailingSlashMatchesBoth() {
        let ignore = matcher("target")
        #expect(ignore.isIgnored(relativePath: "target", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "target", isDirectory: false))
    }

    @Test("선행 이중별표는 어느 깊이에서든 일치한다")
    func leadingDoubleStarMatchesAnyDepth() {
        let ignore = matcher("**/generated")
        #expect(ignore.isIgnored(relativePath: "generated", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "a/b/generated", isDirectory: true))
    }

    @Test("후행 이중별표는 그 아래 전부에 일치한다")
    func trailingDoubleStarMatchesEverythingBelow() {
        let ignore = matcher("logs/**")
        #expect(ignore.isIgnored(relativePath: "logs/today.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "logs/a/b/deep.txt", isDirectory: false))
    }

    @Test("가운데 이중별표는 0개 이상의 디렉토리에 일치한다")
    func innerDoubleStarMatchesZeroOrMoreDirectories() {
        let ignore = matcher("a/**/b")
        #expect(ignore.isIgnored(relativePath: "a/b", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "a/x/b", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "a/x/y/b", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "a/x/y/c", isDirectory: false) == false)
    }
}

@Suite("GitignoreMatcher — 부정과 우선순위")
struct GitignoreNegationTests {

    @Test("느낌표는 앞선 규칙을 되돌린다 — 마지막 일치가 이긴다")
    func negationReversesEarlierRule() {
        let ignore = matcher("""
        *.log
        !keep.log
        """)
        #expect(ignore.isIgnored(relativePath: "app.log", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "keep.log", isDirectory: false) == false)
    }

    @Test("부정 뒤에 다시 무시하면 마지막 것이 이긴다")
    func lastMatchingRuleWins() {
        let ignore = matcher("""
        *.log
        !keep.log
        keep.log
        """)
        #expect(ignore.isIgnored(relativePath: "keep.log", isDirectory: false))
    }

    @Test("이스케이프한 느낌표는 리터럴이다")
    func treatsEscapedBangAsLiteral() {
        let ignore = matcher("\\!important")
        #expect(ignore.isIgnored(relativePath: "!important", isDirectory: false))
    }

    @Test("더 깊은 .gitignore가 상위 규칙을 이긴다")
    func deeperFileOverridesShallowerOne() {
        let ignore = GitignoreMatcher(ruleSets: [
            GitignoreRuleSet(baseDirectory: "", patternText: "*.log"),
            GitignoreRuleSet(baseDirectory: "src", patternText: "!*.log"),
        ])
        #expect(ignore.isIgnored(relativePath: "app.log", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "src/app.log", isDirectory: false) == false)
    }

    @Test("하위 .gitignore 규칙은 그 디렉토리 밖에 영향을 주지 않는다")
    func nestedRulesApplyOnlyBelowTheirDirectory() {
        let ignore = GitignoreMatcher(ruleSets: [
            GitignoreRuleSet(baseDirectory: "sub", patternText: "nested.txt"),
        ])
        #expect(ignore.isIgnored(relativePath: "sub/nested.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "sub/deeper/nested.txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "other/nested.txt", isDirectory: false) == false)
        #expect(ignore.isIgnored(relativePath: "nested.txt", isDirectory: false) == false)
    }
}

@Suite("GitignoreMatcher — 실제 레포 형태")
struct GitignoreRealisticTests {

    @Test("전형적인 .gitignore가 의도대로 동작한다")
    func handlesATypicalGitignore() {
        let ignore = matcher("""
        # 빌드 산출물
        build/
        .gradle/
        *.class

        # 의존성
        node_modules/

        # 환경
        .env
        !.env.example
        """)

        #expect(ignore.isIgnored(relativePath: "build", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "app/build", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "Main.class", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "node_modules", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: ".env", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: ".env.example", isDirectory: false) == false)
        #expect(ignore.isIgnored(relativePath: "src/main/kotlin/App.kt", isDirectory: false) == false)
    }

    @Test("정규식 메타문자가 든 이름을 리터럴로 다룬다")
    func treatsRegexMetacharactersLiterally() {
        let ignore = matcher("file+name(1).txt")
        #expect(ignore.isIgnored(relativePath: "file+name(1).txt", isDirectory: false))
        #expect(ignore.isIgnored(relativePath: "fileXname1.txt", isDirectory: false) == false)
    }

    @Test("한글 파일명도 정상 처리한다")
    func handlesKoreanFileNames() {
        let ignore = matcher("문서/")
        #expect(ignore.isIgnored(relativePath: "문서", isDirectory: true))
        #expect(ignore.isIgnored(relativePath: "src/문서", isDirectory: true))
    }

    @Test("규칙이 없으면 아무것도 무시하지 않는다")
    func ignoresNothingWithoutRules() {
        let ignore = GitignoreMatcher(ruleSets: [])
        #expect(ignore.isIgnored(relativePath: "anything.kt", isDirectory: false) == false)
    }
}
