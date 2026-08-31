import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// 루트 안의 **없는 파일**은 "밖에 있다" 가 아니다 (D-렌더 4차, QA 라이브).
///
/// QA 가 본 것: 프로젝트 **안**의 `missing.png` 가 *"프로젝트 폴더 밖의 파일은 표시하지
/// 않습니다"* 로 안내됐고, 헤더 칩은 실제 차단 2건인데 **3** 이라고 셌다.
///
/// 손해가 두 겹이다. 사용자는 **자기 프로젝트 안의 파일을 밖에 있다고** 듣고, **보안
/// 신호가 부풀려진다** — 샌드박스 칩이 거짓말하면 진짜 차단도 못 믿는다.
@Suite("없는 리소스 — 루트 밖과 다른 사건이다 (INV-6)")
struct RenderMissingResourceTests {

    private func withFixture(_ body: (String) throws -> Void) throws {
        let root = NSTemporaryDirectory() + "cn-missing-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/images", withIntermediateDirectories: true)
        try Data([0x89, 0x50]).write(to: URL(fileURLWithPath: root + "/images/real.png"))
        defer { try? FileManager.default.removeItem(atPath: root) }
        try body(root)
    }

    private func sanitize(_ html: String, root: String) -> SanitizedDocument {
        RenderDocumentSanitizer.sanitize(
            html: html, projectRoot: root,
            loadFile: { FileManager.default.contents(atPath: $0).map { .success($0) } ?? .failure(.notFound) }
        )
    }

    @Test("루트 안의 없는 파일을 '밖에 있다' 고 하지 않는다")
    func aMissingFileInsideTheRootIsNotCalledOutside() throws {
        try withFixture { root in
            let result = sanitize("<img src=\"images/missing.png\">", root: root)

            #expect(!result.html.contains("프로젝트 폴더 밖"), "자기 프로젝트 안의 파일을 밖이라고 말한다")
            #expect(result.html.contains("표시할 수 없습니다"), "못 읽었다고 말해야 한다")
        }
    }

    @Test("없는 파일은 차단 칩에 올라가지 않는다")
    func aMissingFileIsNotCountedAsBlocked() throws {
        // 우리가 막은 게 아니다. 차단 목록에 섞이면 **보안 신호가 부풀려지고**,
        // 부풀려진 신호는 진짜 차단까지 못 믿게 만든다.
        try withFixture { root in
            let result = sanitize("<img src=\"images/missing.png\">", root: root)

            #expect(result.blocked.isEmpty, "안 막았는데 차단으로 셌다")
            #expect(result.unavailable.count == 1)
        }
    }

    @Test("실제 차단만 칩에 센다 — QA 가 본 그 문서")
    func onlyRealBlocksReachTheChip() throws {
        // QA 픽스처와 같은 조합: 원격 1 + 루트 밖 1 + 루트 안 없는 파일 1.
        try withFixture { root in
            let result = sanitize("""
            <img src="https://evil.example/remote.png">
            <img src="../outside.png">
            <img src="images/missing.png">
            """, root: root)

            #expect(result.blocked.count == 2, "차단 2건이어야 하는데 \(result.blocked.count)")
            #expect(result.unavailable.count == 1)
            let panel = BlockedResourcePresentation.make(blocked: result.blocked)
            #expect(panel.chipLabel.contains("2"), "칩이 \(panel.chipLabel)")
        }
    }

    @Test("루트 밖은 여전히 루트 밖이라고 말한다")
    func aFileOutsideTheRootStillSaysSo() throws {
        // 가르면서 반대쪽을 잃으면 안 된다.
        try withFixture { root in
            let result = sanitize("<img src=\"../outside.png\">", root: root)

            #expect(result.html.contains("프로젝트 폴더 밖"))
            #expect(result.blocked.map(\.kind) == [.outsideProjectRoot])
        }
    }

    @Test("루트 밖 파일의 존재 여부는 여전히 새지 않는다")
    func existenceOutsideTheRootIsStillNotRevealed() throws {
        // **가르면서 신탁을 열면 안 된다.** 오늘 내비게이션에서 닫은 것과 같은 자리다 —
        // 문서가 루트 밖 경로를 참조해 문구 차이로 존재를 읽어 내면, 차단 고지가
        // 파일 시스템 탐색기가 된다.
        try withFixture { root in
            let existing = sanitize("<img src=\"/etc/passwd\">", root: root)
            let absent = sanitize("<img src=\"/etc/cn-absent-\(UUID().uuidString)\">", root: root)

            #expect(existing.blocked.map(\.kind) == absent.blocked.map(\.kind))
            #expect(existing.unavailable.count == absent.unavailable.count)
        }
    }
}
