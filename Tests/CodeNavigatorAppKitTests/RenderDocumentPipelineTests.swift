import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// 동기 전처리와 비동기 읽기를 잇는 2패스 선반입 (리더 판정 2026-08-31, 세마포어 금지).
@Suite("RenderDocumentPipeline — 읽기는 비동기로, 전처리는 동기로 (INV-6)")
struct RenderDocumentPipelineTests {

    private func fixture() throws -> (root: String, cleanUp: () -> Void) {
        let root = NSTemporaryDirectory() + "cn-pipe-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/images", withIntermediateDirectories: true)
        try Data([0x89, 0x50]).write(to: URL(fileURLWithPath: root + "/images/logo.png"))
        try Data([0x89, 0x50]).write(to: URL(fileURLWithPath: root + "/images/other.png"))
        return (root, { try? FileManager.default.removeItem(atPath: root) })
    }

    @Test("허용된 로컬 리소스를 비동기로 읽어 인라인한다")
    func allowedResourcesAreLoadedAndInlined() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: #"<img src="images/logo.png">"#,
            projectRoot: root,
            loadResource: { _ in .success(Data([0x89, 0x50])) }
        )

        #expect(document.html.contains("data:image/png;base64,"))
        #expect(document.blocked.isEmpty)
        #expect(document.unavailable.isEmpty)
    }

    @Test("같은 리소스를 두 번 참조해도 한 번만 읽는다")
    func aResourceReferencedTwiceIsLoadedOnce() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }
        let counter = Counter()

        _ = await RenderDocumentPipeline.prepare(
            html: #"<img src="images/logo.png"><img src="images/logo.png">"#,
            projectRoot: root,
            loadResource: { _ in
                counter.increment()
                return .success(Data([0x89, 0x50]))
            }
        )

        // 문서가 같은 이미지를 스무 번 쓰는 일은 흔하다. 참조마다 읽으면 2MB 문서가
        // 디스크를 스무 번 때린다.
        #expect(counter.value == 1)
    }

    @Test("참조가 없으면 아무것도 읽지 않는다")
    func aDocumentWithNoResourcesLoadsNothing() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }
        let counter = Counter()

        let document = await RenderDocumentPipeline.prepare(
            html: "<p>글만 있는 문서</p>",
            projectRoot: root,
            loadResource: { _ in
                counter.increment()
                return .success(Data())
            }
        )

        #expect(counter.value == 0)
        #expect(document.html.contains("글만 있는 문서"))
    }

    @Test("원격 참조는 읽으러 가지도 않는다")
    func remoteReferencesAreNeverLoaded() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }
        let counter = Counter()

        let document = await RenderDocumentPipeline.prepare(
            html: #"<img src="https://evil.example/x.png">"#,
            projectRoot: root,
            loadResource: { _ in
                counter.increment()
                return .success(Data())
            }
        )

        // 판정이 먼저다. 읽고 나서 차단하면 이미 파일 시스템을 만진 뒤다.
        #expect(counter.value == 0)
        #expect(document.blocked.map(\.kind) == [.remoteImage])
    }

    @Test("읽기 실패의 사유가 최종 문서까지 살아 온다")
    func aFailureReasonSurvivesToTheFinalDocument() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: #"<img src="images/logo.png">"#,
            projectRoot: root,
            loadResource: { _ in .failure(.tooLarge(byteSize: 3_000_000, limit: 2_097_152)) }
        )

        // 2패스의 목적이 이것이다 — 비동기 읽기의 사유가 동기 전처리의 결과에 실려 나온다.
        #expect(document.blocked.map(\.kind) == [.tooLarge])
    }

    @Test("여러 리소스를 각각의 사유와 함께 돌려준다")
    func eachResourceKeepsItsOwnOutcome() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: #"<img src="images/logo.png"><img src="images/other.png">"#,
            projectRoot: root,
            loadResource: { path in
                path.hasSuffix("other.png")
                    ? .failure(.tooLarge(byteSize: 3_000_000, limit: 2_097_152))
                    : .success(Data([0x89, 0x50]))
            }
        )

        // 하나가 실패했다고 나머지를 못 그리면 문서 하나에 그림 하나 잘못된 것이
        // 문서 전체를 가져간다.
        #expect(document.html.contains("data:image/png;base64,"))
        #expect(document.blocked.map(\.kind) == [.tooLarge])
    }

    /// 클로저에서 세는 도구. `await` 사이에 값을 넘겨야 해서 참조 타입이다.
    private final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
