import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

private func definition(
    _ name: String,
    _ kind: SymbolKind = .class,
    path: String,
    line: Int
) -> SymbolDefinition {
    SymbolDefinition(name: name, kind: kind, path: path, line: line, signature: "\(kind.rawValue) \(name)")
}

@Suite("SymbolIndex — 조회")
struct SymbolIndexLookupTests {

    @Test("이름으로 정의를 찾는다")
    func findsDefinitionsByName() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("SymbolIndex", path: "src/a.kt", line: 7)])

        let found = await index.definitions(named: "SymbolIndex")
        #expect(found.count == 1)
        #expect(found.first?.line == 7)
    }

    @Test("없는 이름은 빈 배열이다 — nil이 아니다")
    func returnsEmptyArrayForUnknownName() async {
        let index = SymbolIndex()
        #expect(await index.definitions(named: "Nothing").isEmpty)
    }

    @Test("동명 정의가 여러 곳에 있으면 전부 돌려주고 경로·라인 순으로 정렬한다")
    func returnsAllSameNamedDefinitionsSorted() async {
        let index = SymbolIndex()
        await index.replaceFile("src/b.kt", with: [
            definition("parse", .function, path: "src/b.kt", line: 41),
            definition("parse", .function, path: "src/b.kt", line: 30),
        ])
        await index.replaceFile("src/a.kt", with: [definition("parse", .function, path: "src/a.kt", line: 7)])

        let found = await index.definitions(named: "parse")
        #expect(found.map { "\($0.path):\($0.line)" } == ["src/a.kt:7", "src/b.kt:30", "src/b.kt:41"])
    }

    @Test("정의 위치 여부를 정확한 (이름·경로·라인) 삼중으로 판정한다")
    func matchesDefinitionSiteExactly() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("Widget", path: "src/a.kt", line: 12)])

        #expect(await index.hasDefinition(named: "Widget", atPath: "src/a.kt", line: 12))
        #expect(await index.hasDefinition(named: "Widget", atPath: "src/a.kt", line: 13) == false)
        #expect(await index.hasDefinition(named: "Widget", atPath: "src/b.kt", line: 12) == false)
        #expect(await index.hasDefinition(named: "Other", atPath: "src/a.kt", line: 12) == false)
    }

    @Test("전체 정의 열거와 개수가 일치한다")
    func enumeratesEveryDefinition() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [
            definition("A", path: "src/a.kt", line: 1),
            definition("B", path: "src/a.kt", line: 2),
        ])
        await index.replaceFile("src/b.kt", with: [definition("C", path: "src/b.kt", line: 1)])

        #expect(await index.allDefinitions().count == 3)
        #expect(await index.symbolCount() == 3)
        #expect(await index.fileCount() == 2)
    }
}

@Suite("SymbolIndex — 갱신과 유령 제거 (INV-1)")
struct SymbolIndexMutationTests {

    @Test("같은 파일을 다시 넣으면 옛 심볼이 남지 않는다")
    func replacingAFileDropsItsOldSymbols() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("OldName", path: "src/a.kt", line: 3)])
        await index.replaceFile("src/a.kt", with: [definition("NewName", path: "src/a.kt", line: 9)])

        #expect(await index.definitions(named: "OldName").isEmpty)
        #expect(await index.definitions(named: "NewName").count == 1)
        #expect(await index.fileCount() == 1)
    }

    @Test("같은 이름이라도 라인이 바뀌면 옛 라인은 사라진다")
    func replacingAFileDropsStaleLines() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("Widget", path: "src/a.kt", line: 3)])
        await index.replaceFile("src/a.kt", with: [definition("Widget", path: "src/a.kt", line: 40)])

        let found = await index.definitions(named: "Widget")
        #expect(found.map(\.line) == [40])
    }

    @Test("한 파일 교체가 다른 파일의 동명 심볼을 건드리지 않는다")
    func replacingOneFileLeavesOtherFilesAlone() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("shared", .function, path: "src/a.kt", line: 1)])
        await index.replaceFile("src/b.kt", with: [definition("shared", .function, path: "src/b.kt", line: 2)])
        await index.replaceFile("src/a.kt", with: [definition("renamed", .function, path: "src/a.kt", line: 1)])

        let found = await index.definitions(named: "shared")
        #expect(found.map(\.path) == ["src/b.kt"])
    }

    @Test("파일을 지우면 그 파일의 심볼이 양쪽 맵에서 사라진다")
    func removingAFileClearsBothDirections() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("Gone", path: "src/a.kt", line: 1)])
        await index.removeFile("src/a.kt")

        #expect(await index.definitions(named: "Gone").isEmpty)
        #expect(await index.fileCount() == 0)
        #expect(await index.symbolCount() == 0)
    }

    @Test("한 번도 없던 파일을 지워도 아무 일도 일어나지 않는다")
    func removingAnUnknownFileIsHarmless() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("Kept", path: "src/a.kt", line: 1)])
        await index.removeFile("src/never-existed.kt")

        #expect(await index.definitions(named: "Kept").count == 1)
    }

    @Test("이름 변경(삭제 후 새 경로 추가) 뒤 옛 경로 잔재가 없다")
    func renameLeavesNoTraceOfTheOldPath() async {
        let index = SymbolIndex()
        await index.replaceFile("src/old.kt", with: [definition("Widget", path: "src/old.kt", line: 5)])
        await index.removeFile("src/old.kt")
        await index.replaceFile("src/new.kt", with: [definition("Widget", path: "src/new.kt", line: 5)])

        let found = await index.definitions(named: "Widget")
        #expect(found.map(\.path) == ["src/new.kt"])
    }

    @Test("스캔셋에 없는 파일을 일괄 제거한다 — 전체 재스캔 후 유령 0")
    func removesFilesMissingFromTheScanSet() async {
        let index = SymbolIndex()
        await index.replaceFile("src/kept.kt", with: [definition("Kept", path: "src/kept.kt", line: 1)])
        await index.replaceFile("src/vanished.kt", with: [definition("Vanished", path: "src/vanished.kt", line: 1)])

        await index.removeFiles(notIn: ["src/kept.kt"])

        #expect(await index.definitions(named: "Vanished").isEmpty)
        #expect(await index.definitions(named: "Kept").count == 1)
        #expect(await index.fileCount() == 1)
    }

    @Test("인덱싱 순서가 결과를 바꾸지 않는다")
    func indexingOrderDoesNotAffectResults() async {
        let first = SymbolIndex()
        await first.replaceFile("src/a.kt", with: [definition("shared", .function, path: "src/a.kt", line: 1)])
        await first.replaceFile("src/b.kt", with: [definition("shared", .function, path: "src/b.kt", line: 2)])

        let second = SymbolIndex()
        await second.replaceFile("src/b.kt", with: [definition("shared", .function, path: "src/b.kt", line: 2)])
        await second.replaceFile("src/a.kt", with: [definition("shared", .function, path: "src/a.kt", line: 1)])

        #expect(await first.definitions(named: "shared") == second.definitions(named: "shared"))
        #expect(await first.symbolCount() == second.symbolCount())
    }

    @Test("clear는 전부 비운다")
    func clearEmptiesEverything() async {
        let index = SymbolIndex()
        await index.replaceFile("src/a.kt", with: [definition("A", path: "src/a.kt", line: 1)])
        await index.clear()

        #expect(await index.symbolCount() == 0)
        #expect(await index.fileCount() == 0)
        #expect(await index.definitions(named: "A").isEmpty)
    }
}
