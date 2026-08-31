import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// 차단된 자리에 박스가 실제로 남는지 — 전처리 통과 후의 문서로 확인한다(W-15, 리더 판정 D1).
@Suite("차단 자리표시자 — 전처리가 문서에 박스를 남긴다 (W-15)")
struct RenderBlockedBoxIntegrationTests {

    private let root = "/tmp/cn-box-fixture"

    private func sanitize(_ html: String) -> SanitizedDocument {
        RenderDocumentSanitizer.sanitize(html: html, projectRoot: root, loadFile: { _ in .failure(.notFound) })
    }

    @Test("차단된 원격 이미지 자리에 박스가 남는다")
    func aBlockedRemoteImageLeavesABox() {
        // 지금까지는 `src` 만 비웠다 — 웹뷰에서 그건 깨진 이미지 아이콘이고, 사용자는
        // "앱이 고장났다"로 읽는다. 차단은 보호이지 고장이 아니다.
        let result = sanitize("<p><img src=\"https://cdn.evil.example/x.png\" alt=\"회사 로고\"></p>")

        #expect(result.html.contains("차단되었습니다"))
        #expect(result.html.contains("cdn.evil.example"))
        #expect(result.html.contains("회사 로고"))
        // 원래 요소는 남지 않는다 — 빈 `src` 를 가진 `<img>` 가 곧 깨진 아이콘이다.
        #expect(!result.html.contains("<img"))
    }

    @Test("박스가 남아도 차단 목록은 그대로 센다")
    func theBoxDoesNotReplaceTheCount() {
        // 박스는 자리를, 칩은 개수를 말한다. 둘 다 있어야 W-15 다.
        let result = sanitize("<img src=\"https://a.example/1.png\"><img src=\"https://b.example/2.png\">")

        #expect(result.blocked.count == 2)
        #expect(result.blocked.allSatisfy { $0.kind == .remoteImage })
    }

    @Test("루트 밖 이미지는 위치를 말하는 박스를 남긴다")
    func anImageOutsideTheRootSaysSo() {
        let result = sanitize("<img src=\"/etc/passwd\">")

        #expect(result.html.contains("프로젝트 폴더 밖"))
    }

    @Test("alt 가 없으면 alt 줄 없이 박스만 남는다")
    func aBoxWithoutAltHasNoAltLine() {
        let result = sanitize("<img src=\"https://a.example/1.png\">")

        #expect(result.html.contains("차단되었습니다"))
        #expect(!result.html.contains("alt:"))
    }

    @Test("박스가 뒤따르는 패스에 훼손되지 않는다")
    func theBoxSurvivesTheRestOfThePipeline() {
        // 박스는 전처리 중간에 삽입되므로 이후 패스(속성 재작성·CSS url·CSP 주입)를 지난다.
        // 그 과정에서 스타일이나 접근성 이름이 뜯기면 박스가 글자 뭉치가 된다.
        let result = sanitize("<img src=\"https://a.example/1.png\" alt=\"로고\">")

        #expect(result.html.contains("role=\"img\""))
        #expect(result.html.contains("aria-label="))
        #expect(result.html.contains("var(--cn-"))
        #expect(result.html.contains("</span>"))
    }

    @Test("허용된 로컬 이미지는 박스가 아니라 인라인된다")
    func anAllowedLocalImageIsInlinedNotBoxed() throws {
        // 반대 방향. 박스가 너무 넓게 잡히면 정상 이미지까지 박스로 바뀌는데, 그건
        // "차단됐다"는 거짓말이 된다.
        let directory = NSTemporaryDirectory() + "cn-box-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let file = directory + "/logo.png"
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: file))

        let result = RenderDocumentSanitizer.sanitize(
            html: "<img src=\"logo.png\">",
            projectRoot: directory,
            loadFile: { FileManager.default.contents(atPath: $0).map { .success($0) } ?? .failure(.notFound) }
        )

        #expect(result.html.contains("data:image/png;base64,"))
        #expect(!result.html.contains("차단되었습니다"))
        #expect(result.blocked.isEmpty)
    }

    @Test("못 읽은 로컬 이미지는 '차단'이 아니라 '표시할 수 없음' 박스를 남긴다")
    func anUnreadableLocalImageSaysSoWithoutClaimingWeBlockedIt() throws {
        let directory = NSTemporaryDirectory() + "cn-miss-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try Data([0x89, 0x50]).write(to: URL(fileURLWithPath: directory + "/logo.png"))

        let result = RenderDocumentSanitizer.sanitize(
            html: "<img src=\"logo.png\" alt=\"로고\">",
            projectRoot: directory,
            loadFile: { _ in .failure(.notFound) }
        )

        #expect(result.html.contains("표시할 수 없습니다"))
        #expect(!result.html.contains("차단"), "안 막았는데 막았다고 말한다")
        #expect(result.blocked.isEmpty, "차단 칩에 오르면 사용자가 우리가 막았다고 읽는다")
        #expect(result.unavailable.count == 1, "그렇다고 조용히 사라지면 안 된다")
    }

    @Test("스크립트는 박스를 남기지 않는다")
    func aBlockedScriptLeavesNoBox() {
        // 스크립트는 페이지에 자리가 없었다. 박스를 그리면 문서에 없던 구멍이 생긴다.
        let result = sanitize("<p>앞</p><script src=\"https://a.example/x.js\"></script><p>뒤</p>")

        #expect(!result.html.contains("차단되었습니다"))
        #expect(result.blocked.contains { $0.kind == .script })
    }
}
