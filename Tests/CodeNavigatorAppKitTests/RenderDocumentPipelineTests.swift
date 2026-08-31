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

    // MARK: 문서 서식 (W-14)

    @Test("문서에 본문 서식이 실린다")
    func theDocumentCarriesItsOwnTypography() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: "<p>본문</p>", projectRoot: root, loadResource: { _ in .failure(.notFound) }
        )

        // W-14: 본문 최대 폭 720px 중앙 정렬 · 산문 14px/1.7.
        // 예전엔 SwiftUI 수식어가 이걸 걸었는데, **그 수식어가 웹뷰를 0 높이로 접었고**
        // `.html` 파일에는 애초에 안 걸렸다. 서식은 문서의 것이므로 문서가 들고 간다.
        #expect(document.html.contains("max-width: 720px"))
        #expect(document.html.contains("14px/1.7"))
    }

    @Test("코드블록이 가로로 스크롤한다 — 문서 전체가 밀리지 않는다")
    func codeBlocksScrollHorizontallyOnTheirOwn() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: "<pre><code>긴 줄</code></pre>", projectRoot: root,
            loadResource: { _ in .failure(.notFound) }
        )

        // 02b W-14 접근성: 긴 코드 한 줄이 문서 전체를 가로로 밀면 본문을 읽을 수 없다.
        #expect(document.html.contains("overflow-x: auto"))
    }

    @Test("링크가 색만으로 구별되지 않는다")
    func linksAreNotDistinguishedByColourAlone() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: "<p><a href=\"#x\">링크</a></p>", projectRoot: root,
            loadResource: { _ in .failure(.notFound) }
        )

        // §4.5 색 단독 금지. 밑줄이 없으면 색각 이상에서 링크가 본문과 같아 보인다.
        #expect(document.html.contains("text-decoration: underline"))
    }

    @Test("서식이 페치 가능한 참조를 만들지 않는다")
    func theStylesheetFetchesNothing() async throws {
        let (root, cleanUp) = try fixture()
        defer { cleanUp() }

        let document = await RenderDocumentPipeline.prepare(
            html: "<p>본문</p>", projectRoot: root, loadResource: { _ in .failure(.notFound) }
        )

        // 우리가 넣는 스타일이 폰트나 이미지를 부르면, 우리가 만든 문서가 INV-6 을 깬다.
        #expect(!document.html.contains("url("))
        #expect(document.blocked.isEmpty)
    }

    /// 클로저에서 세는 도구. `await` 사이에 값을 넘겨야 해서 참조 타입이다.
    private final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
