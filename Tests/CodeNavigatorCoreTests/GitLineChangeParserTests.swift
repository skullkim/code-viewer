import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// `git diff -U0` 의 헝크 머리글을 줄 표시로 옮긴다.
///
/// `-U0` 을 쓰는 이유는 문맥 줄이 없어야 헝크 머리글의 숫자가 **바뀐 줄 그 자체**를 가리키기
/// 때문이다. 기본값(-U3)이면 앞뒤 세 줄이 함께 들어와서, 안 바꾼 줄에도 표시가 붙는다.
@Suite("Git 줄 변경 파서")
struct GitLineChangeParserTests {

    private func parse(_ diff: String) -> [GitLineChange] {
        GitLineChangeParser.parse(unifiedDiff: diff)
    }

    @Test("추가된 줄은 추가로 표시한다")
    func marksAddedLines() {
        let changes = parse("""
        diff --git a/A.java b/A.java
        --- a/A.java
        +++ b/A.java
        @@ -10,0 +11,3 @@
        +one
        +two
        +three
        """)
        #expect(changes == [
            GitLineChange(line: 11, kind: .added),
            GitLineChange(line: 12, kind: .added),
            GitLineChange(line: 13, kind: .added),
        ])
    }

    @Test("고친 줄은 수정으로 표시한다")
    func marksModifiedLines() {
        let changes = parse("""
        @@ -5,2 +5,2 @@
        -old one
        -old two
        +new one
        +new two
        """)
        #expect(changes == [
            GitLineChange(line: 5, kind: .modified),
            GitLineChange(line: 6, kind: .modified),
        ])
    }

    /// 지워진 줄은 화면에 없다. 그 **자리**를 가리켜야 사용자가 어디서 사라졌는지 안다.
    @Test("지워진 줄은 사라진 자리에 표시한다")
    func marksDeletionsAtTheGap() {
        let changes = parse("""
        @@ -7,3 +6,0 @@
        -gone one
        -gone two
        -gone three
        """)
        #expect(changes == [GitLineChange(line: 6, kind: .deleted)])
    }

    /// 파일 첫 줄이 지워지면 가리킬 앞 줄이 없다. 1을 가리킨다.
    @Test("맨 앞이 지워지면 첫 줄을 가리킨다")
    func deletionAtTheTopPointsAtTheFirstLine() {
        #expect(parse("@@ -1,2 +0,0 @@\n-a\n-b") == [GitLineChange(line: 1, kind: .deleted)])
    }

    /// 줄 수가 줄어든 수정은 수정이면서 삭제이기도 하다. 둘 다 보여 준다.
    @Test("줄이 줄어든 수정은 수정과 삭제를 함께 표시한다")
    func shrinkingHunkShowsBoth() {
        let changes = parse("""
        @@ -3,5 +3,2 @@
        -a
        -b
        -c
        -d
        -e
        +x
        +y
        """)
        #expect(changes.contains(GitLineChange(line: 3, kind: .modified)))
        #expect(changes.contains(GitLineChange(line: 4, kind: .modified)))
        #expect(changes.contains(GitLineChange(line: 4, kind: .deleted)), "사라진 세 줄을 아무 데서도 안 알린다")
    }

    /// 개수를 생략하면 1이다 — `@@ -5 +5 @@`.
    @Test("개수를 생략한 머리글도 읽는다")
    func readsHeadersWithoutCounts() {
        #expect(parse("@@ -5 +5 @@\n-a\n+b") == [GitLineChange(line: 5, kind: .modified)])
    }

    @Test("헝크가 여러 개면 전부 읽는다")
    func readsEveryHunk() {
        let changes = parse("""
        @@ -1,1 +1,1 @@
        -a
        +b
        @@ -10,0 +10,1 @@
        +c
        """)
        #expect(changes == [
            GitLineChange(line: 1, kind: .modified),
            GitLineChange(line: 10, kind: .added),
        ])
    }

    /// 헝크 머리글이 아닌 줄에 `@@` 가 들어 있을 수 있다 — 코드 본문이 그렇다.
    @Test("본문에 든 @@ 를 머리글로 읽지 않는다")
    func doesNotMistakeBodyLinesForHeaders() {
        let changes = parse("""
        @@ -1,1 +1,1 @@
        -String separator = "@@ -1 +1 @@";
        +String separator = "--";
        """)
        #expect(changes == [GitLineChange(line: 1, kind: .modified)])
    }

    @Test("변경이 없으면 빈 목록이다")
    func emptyDiffIsEmpty() {
        #expect(parse("").isEmpty)
        #expect(parse("diff --git a/A b/A\n--- a/A\n+++ b/A\n").isEmpty)
    }
}
