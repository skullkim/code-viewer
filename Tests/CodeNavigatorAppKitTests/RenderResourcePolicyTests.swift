import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// What the render surface is allowed to load (INV-6, ADR-0109).
///
/// This is the whole of "로컬 파일 접근은 열린 프로젝트 루트 안으로 제한". It is a pure function
/// on purpose: the content rule list blocks the network, and everything local goes through
/// here, so this is the one place a path can escape — and the one place worth testing hard.
@Suite("렌더 리소스 정책 — 무엇을 읽어도 되는가 (INV-6)")
struct RenderResourcePolicyTests {

    private let root = "/tmp/cn-policy-root"

    private func decide(_ reference: String, root: String? = nil) -> RenderResourceDecision {
        RenderResourcePolicy.decide(reference: reference, projectRoot: root ?? self.root)
    }

    // MARK: 원격은 전부 막는다

    @Test("원격 스킴은 전부 차단된다", arguments: [
        "http://example.com/a.png",
        "https://example.com/a.png",
        "HTTPS://EXAMPLE.COM/a.png",
        "ftp://example.com/a.png",
        "ws://example.com/socket",
        "wss://example.com/socket",
    ])
    func remoteSchemesAreBlocked(reference: String) {
        #expect(decide(reference).isBlocked, "\(reference) 가 통과하면 INV-6 첫 항목이 열린다")
    }

    @Test("스킴 없는 프로토콜 상대 참조도 원격이다")
    func protocolRelativeReferencesAreRemote() {
        // `//evil.com/x.png` inherits the page's scheme. It looks like a path and is not.
        #expect(decide("//evil.com/x.png").isBlocked)
    }

    // MARK: 루트 밖으로 나가는 경로

    @Test("`..` 로 루트를 벗어나면 차단된다")
    func parentTraversalIsBlocked() {
        #expect(decide("../../etc/passwd").isBlocked)
        #expect(decide("docs/../../../etc/passwd").isBlocked)
    }

    @Test("루트 밖 절대 경로는 차단된다")
    func absolutePathsOutsideTheRootAreBlocked() {
        #expect(decide("/etc/passwd").isBlocked)
        #expect(decide("/tmp/other-project/a.png").isBlocked)
    }

    @Test("이름이 루트로 시작하기만 하는 형제 폴더는 루트 안이 아니다")
    func aSiblingWhoseNameStartsWithTheRootIsNotInside() {
        // The classic prefix bug: "/tmp/cn-policy-root-evil" starts with the root string
        // but is a different directory. Comparing strings instead of path components lets
        // an attacker pick a folder name and walk right out.
        #expect(decide("/tmp/cn-policy-root-evil/a.png").isBlocked)
        #expect(decide("/tmp/cn-policy-rootsecrets.png").isBlocked)
    }

    @Test("경로 안의 콜론을 스킴으로 오해하지 않는다")
    func aColonInsideAPathIsNotAScheme() {
        // `images/c:logo.png` has a colon but no scheme — the part before it contains a
        // separator. Treating it as one would refuse a legitimate file.
        #expect(decide("images/c:logo.png").allowedPath == "/tmp/cn-policy-root/images/c:logo.png")
    }

    @Test("스킴처럼 생긴 단독 참조는 통과시키지 않는다")
    func aSchemeShapedReferenceIsNotTreatedAsAPath() {
        // `c:/x.png` reads as a scheme to Foundation too (measured). Refusing is the safe
        // reading: a macOS path does not begin that way.
        #expect(decide("c:/x.png").isBlocked)
        #expect(decide("javascript:alert(1)").isBlocked)
    }

    // MARK: 루트 안은 통과

    @Test("루트 안의 상대 경로는 허용된다")
    func relativePathsInsideTheRootAreAllowed() {
        #expect(decide("images/logo.png").allowedPath == "/tmp/cn-policy-root/images/logo.png")
        #expect(decide("./images/logo.png").allowedPath == "/tmp/cn-policy-root/images/logo.png")
    }

    @Test("루트 안으로 되돌아오는 `..` 는 허용된다")
    func traversalThatStaysInsideIsAllowed() {
        // Escaping is the thing forbidden, not the `..` character.
        #expect(decide("docs/../images/logo.png").allowedPath == "/tmp/cn-policy-root/images/logo.png")
    }

    @Test("루트 자신은 파일이 아니므로 허용하지 않는다")
    func theRootItselfIsNotAResource() {
        #expect(decide(".").isBlocked)
        #expect(decide("").isBlocked)
    }

    // MARK: data: 는 이미 인라인된 것

    @Test("data: URI 는 그대로 통과한다 — 이미 문서 안에 있다")
    func dataURIsPassThrough() {
        // Measured in the spike: these survive the blanket rule and carry no fetch.
        #expect(decide("data:image/png;base64,AAAA").isInlineData)
    }

    // MARK: 심링크

    @Test("루트 밖을 가리키는 심링크는 차단된다")
    func aSymlinkPointingOutsideTheRootIsBlocked() throws {
        // Measured against the filesystem, not a mock: a policy that only reads the string
        // sees a name inside the root and lets it through.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cn-policy-\(UUID().uuidString)")
        let realRoot = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let secret = outside.appendingPathComponent("secret.png")
        try Data([1, 2, 3]).write(to: secret)
        let escape = realRoot.appendingPathComponent("escape.png")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: secret)

        let decision = RenderResourcePolicy.decide(reference: "escape.png", projectRoot: realRoot.path)
        #expect(decision.isBlocked, "심링크가 루트 밖을 가리키는데 통과했다")
    }

    @Test("루트 안을 가리키는 심링크는 허용된다")
    func aSymlinkStayingInsideTheRootIsAllowed() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cn-policy-\(UUID().uuidString)")
        let realRoot = base.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: realRoot.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let target = realRoot.appendingPathComponent("images/logo.png")
        try Data([1, 2, 3]).write(to: target)
        let link = realRoot.appendingPathComponent("logo.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let decision = RenderResourcePolicy.decide(reference: "logo.png", projectRoot: realRoot.path)
        #expect(decision.isBlocked == false, "루트 안 심링크까지 막으면 정상 문서가 안 그려진다")
    }
}
