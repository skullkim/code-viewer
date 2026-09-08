import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// 참조 목록에 **정의가 반드시 들어 있어야** 한다.
///
/// 사용자가 겪은 것: "검색 결과에 정의가 없어." 목록은 본문 훑기로 만들어지고, 정의 표시는
/// 훑어서 걸린 줄이 마침 정의 자리일 때만 붙는다. 그래서 훑기가 그 줄을 못 잡거나 수신자
/// 타입 좁히기가 떨궈 내면 정의가 통째로 사라진다 — 그런데 색인은 그 정의를 알고 있다.
///
/// IntelliJ 의 Find Usages 가 선언을 맨 위에 따로 보여 주는 것과 같은 이유다: 사용처를
/// 보려는 사람이 가장 먼저 찾는 것이 선언이다.
@Suite("참조 목록에 정의가 들어간다")
struct ReferenceDefinitionInclusionTests {

    private func makeProject(_ files: [String: String]) throws -> (root: URL, paths: [String]) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory() + "refdef-\(UUID().uuidString)")
        for (relativePath, contents) in files {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        return (root, Array(files.keys))
    }

    /// 정의가 있는 줄을 본문 훑기가 못 잡는 경우. 색인만이 그 자리를 안다.
    @Test("훑기가 못 잡은 정의도 목록에 들어간다")
    func includesADefinitionTheScanMissed() async throws {
        // 호출부에만 `getName` 이 글자로 있고, 정의는 다른 이름의 줄에 있다고 색인이 말한다.
        let (root, paths) = try makeProject([
            "Member.java": "package a;\nclass Member {\n    String field;\n}\n",
            "Caller.java": "package a;\nclass Caller {\n    void go(Member m) { m.getName(); }\n}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let index = SymbolIndex()
        await index.replaceFile(
            "Member.java",
            with: [SymbolDefinition(
                name: "getName", kind: .function, path: "Member.java", line: 3,
                signature: "String getName()"
            )]
        )

        let result = await ReferenceSearcher().search(
            symbolName: "getName", filePaths: paths, rootPath: root, symbolIndex: index
        )
        let definitions = result.references.filter(\.isDefinition)
        #expect(definitions.count == 1, "색인이 아는 정의가 목록에 없다")
        #expect(definitions.first?.path == "Member.java")
        #expect(definitions.first?.line == 3)
    }

    /// 정의가 맨 위에 온다. 아래에 섞여 있으면 스크롤해서 찾아야 한다.
    @Test("정의가 목록 맨 위에 온다")
    func definitionsComeFirst() async throws {
        let (root, paths) = try makeProject([
            "Member.java": "package a;\nclass Member {\n    String getName() { return name; }\n}\n",
            "Caller.java": "package a;\nclass Caller {\n    void go(Member m) { m.getName(); }\n}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let index = SymbolIndex()
        await index.replaceFile(
            "Member.java",
            with: [SymbolDefinition(
                name: "getName", kind: .function, path: "Member.java", line: 3,
                signature: "String getName()"
            )]
        )

        let result = await ReferenceSearcher().search(
            symbolName: "getName", filePaths: paths.sorted(), rootPath: root, symbolIndex: index
        )
        #expect(result.references.first?.isDefinition == true, "정의가 맨 위가 아니다")
    }

    /// 훑기가 이미 잡은 정의를 색인이 또 넣으면 같은 줄이 두 번 나온다.
    @Test("같은 정의를 두 번 넣지 않는다")
    func doesNotDuplicateADefinitionTheScanFound() async throws {
        let (root, paths) = try makeProject([
            "Member.java": "package a;\nclass Member {\n    String getName() { return name; }\n}\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let index = SymbolIndex()
        await index.replaceFile(
            "Member.java",
            with: [SymbolDefinition(
                name: "getName", kind: .function, path: "Member.java", line: 3,
                signature: "String getName()"
            )]
        )

        let result = await ReferenceSearcher().search(
            symbolName: "getName", filePaths: paths, rootPath: root, symbolIndex: index
        )
        let atLine3 = result.references.filter { $0.path == "Member.java" && $0.line == 3 }
        #expect(atLine3.count == 1, "같은 줄이 두 번 나왔다")
        #expect(atLine3.first?.isDefinition == true)
    }

    /// 수신자 타입으로 좁힌 검색에서도 정의는 남아야 한다. 좁히기는 **사용처**를 줄이는
    /// 것이지 선언을 지우는 것이 아니다.
    @Test("좁혀도 그 타입의 정의는 남는다")
    func narrowingKeepsTheDefinitionOfThatType() async throws {
        let (root, paths) = try makeProject([
            "Member.java": "package a;\nclass Member {\n    String getName() { return name; }\n}\n",
            "Coupon.java": "package a;\nclass Coupon {\n    String getName() { return code; }\n}\n",
            "Caller.java": "package a;\nclass Caller {\n    void go(Member m) { m.getName(); }\n}\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let index = SymbolIndex()
        await index.replaceFile("Member.java", with: [SymbolDefinition(
            name: "getName", kind: .function, path: "Member.java", line: 3, signature: "String getName()"
        )])
        await index.replaceFile("Coupon.java", with: [SymbolDefinition(
            name: "getName", kind: .function, path: "Coupon.java", line: 3, signature: "String getName()"
        )])

        let result = await ReferenceSearcher().search(
            symbolName: "getName", filePaths: paths.sorted(), rootPath: root, symbolIndex: index,
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        let definitionPaths = result.references.filter(\.isDefinition).map(\.path)
        #expect(definitionPaths.contains("Member.java"), "좁히기가 그 타입의 정의를 지웠다")
    }

    @Test("정의가 없는 이름이면 아무것도 지어내지 않는다")
    func inventsNoDefinition() async throws {
        let (root, paths) = try makeProject([
            "Caller.java": "package a;\nclass Caller {\n    void go() { helper(); }\n}\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await ReferenceSearcher().search(
            symbolName: "helper", filePaths: paths, rootPath: root, symbolIndex: SymbolIndex()
        )
        #expect(result.references.allSatisfy { !$0.isDefinition })
    }
}
