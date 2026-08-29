import Testing
@testable import CodeNavigatorAppKit

/// The reference panel and the full-text panel both show results grouped by file
/// (design §2 F-4 step 3, F-6 step 2). The engine returns a flat list sorted by path and
/// line; turning that into groups is the view's job, so it is done once here.
@Suite("FileGrouping — 결과를 파일별로 묶기 (REQ-006, REQ-008)")
struct FileGroupingTests {

    private struct Hit: Equatable {
        let path: String
        let line: Int
    }

    @Test("같은 파일의 항목이 하나의 그룹으로 묶인다")
    func hitsInOneFileFormOneGroup() {
        let groups = FileGrouping.group(
            [Hit(path: "a.swift", line: 3), Hit(path: "a.swift", line: 9)],
            by: \.path
        )
        #expect(groups.count == 1)
        #expect(groups[0].path == "a.swift")
        #expect(groups[0].items == [Hit(path: "a.swift", line: 3), Hit(path: "a.swift", line: 9)])
    }

    @Test("그룹 순서는 처음 나타난 순서를 따른다")
    func groupsKeepFirstAppearanceOrder() {
        // The engine already sorted by path and line; re-sorting here would only risk
        // disagreeing with it.
        let groups = FileGrouping.group(
            [Hit(path: "b.swift", line: 1), Hit(path: "a.swift", line: 1), Hit(path: "b.swift", line: 7)],
            by: \.path
        )
        #expect(groups.map(\.path) == ["b.swift", "a.swift"])
        #expect(groups[0].items.map(\.line) == [1, 7])
    }

    @Test("빈 입력은 빈 그룹 목록이다")
    func emptyInputProducesNoGroups() {
        #expect(FileGrouping.group([Hit](), by: \.path).isEmpty)
    }

    @Test("그룹은 항목 수를 알려준다")
    func groupsReportTheirCount() {
        let groups = FileGrouping.group(
            [Hit(path: "a.swift", line: 1), Hit(path: "a.swift", line: 2), Hit(path: "b.swift", line: 1)],
            by: \.path
        )
        #expect(groups.map(\.count) == [2, 1])
    }
}
