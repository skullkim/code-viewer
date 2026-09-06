import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// `member.getId()` used to list every `getId` in the project. Measured on a 463-file repository:
/// 670 hits over 15 unrelated receiver types, of which 331 were the `Member` in front of the user.
///
/// These are the rules that narrowing has to obey — above all the one about not being sure.
@Suite("참조 좁히기 — 수신자 타입으로")
struct ReferenceNarrowingTests {

    private func fixture(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("narrowing-\(UUID().uuidString)")
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func search(
        _ files: [String: String],
        symbol: String,
        origin: ReferenceQueryOrigin?
    ) async throws -> ReferenceSearchResult {
        let root = try fixture(files)
        defer { try? FileManager.default.removeItem(at: root) }
        return await ReferenceSearcher().search(
            symbolName: symbol,
            filePaths: files.keys.sorted(),
            rootPath: root,
            symbolIndex: SymbolIndex(),
            origin: origin
        )
    }

    private static let files: [String: String] = [
        "Caller.java": """
        class Caller {
            void run(Member member) {
                use(member.getId());
            }
        }
        """,
        "Other.java": """
        class Other {
            void run(Organization organization) {
                use(organization.getId());
            }
        }
        """,
        "Unknown.java": """
        class Unknown {
            void run() {
                use(mystery.getId());
            }
        }
        """,
    ]

    @Test("커서가 선 타입과 다른 수신자는 목록에서 빠진다")
    func dropsHitsOnOtherTypes() async throws {
        let result = try await search(
            Self.files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        let paths = result.references.map(\.path)
        #expect(paths.contains("Caller.java"))
        #expect(!paths.contains("Other.java"), "Organization.getId 는 Member.getId 가 아니다")
    }

    /// 이게 이 기능에서 가장 중요한 규칙이다. 판정을 못 한 히트를 버리면 **진짜 참조가 조용히
    /// 사라지고**, 사용자는 무엇이 없어졌는지 알 방법이 없다. 노이즈 한 줄이 훨씬 싸다.
    @Test("타입을 못 알아낸 히트는 남긴다 — 확신 없이 버리지 않는다")
    func keepsHitsItCannotJudge() async throws {
        let result = try await search(
            Self.files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        #expect(result.references.map(\.path).contains("Unknown.java"))
    }

    @Test("무엇을 어떻게 좁혔는지 결과에 적는다")
    func reportsWhatItDid() async throws {
        let result = try await search(
            Self.files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        let narrowing = try #require(result.narrowing)
        #expect(narrowing.receiverType == "Member")
        #expect(narrowing.discarded == 1)
        #expect(narrowing.unresolved == 1)
    }

    @Test("커서 위치가 없으면 예전 그대로 — 전부 보여준다")
    func behavesAsBeforeWithoutAnOrigin() async throws {
        let result = try await search(Self.files, symbol: "getId", origin: nil)
        #expect(result.references.count == 3)
        #expect(result.narrowing == nil)
    }

    @Test("커서 자리에서 타입을 못 알아내면 좁히지 않는다")
    func doesNotNarrowWhenTheCursorTypeIsUnknown() async throws {
        let result = try await search(
            Self.files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Unknown.java", line: 3)
        )
        #expect(result.references.count == 3)
        #expect(result.narrowing == nil)
    }

    /// Java 가 아닌 파일은 이 해석기가 다룰 수 없다. 판정 못 하는 것은 남긴다는 같은 규칙이다.
    @Test("Java 가 아닌 파일의 히트는 건드리지 않는다")
    func leavesNonJavaFilesAlone() async throws {
        var files = Self.files
        files["notes.md"] = "getId() 는 아이디를 준다"
        let result = try await search(
            files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        #expect(result.references.map(\.path).contains("notes.md"))
    }

    @Test("좁힌 뒤에도 total 은 실제로 보여 주는 수와 맞는다")
    func totalMatchesWhatIsShown() async throws {
        let result = try await search(
            Self.files,
            symbol: "getId",
            origin: ReferenceQueryOrigin(path: "Caller.java", line: 3)
        )
        #expect(result.total == result.references.count)
    }
}
