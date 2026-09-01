import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Every `NavigatorError` → `RenderResourceFailure`, walked one by one.
///
/// This suite exists because of a near miss. `pathOutsideProject` was added to `NavigatorError`
/// and fell through a `default` into `.notReadable`, which `blockedKind()` maps to `nil` — so a
/// real INV-6 rejection would have **disappeared from the block list** rather than shown up
/// wrongly. backend-senior confirmed the gap by reverting the fix: three tests broke, all
/// engine-level, and **none** covered this mapping. The regression would have passed the gate.
@Suite("렌더 리소스 실패 매핑 — 전수 (W-14 · W-15)")
struct RenderResourceFailureMappingTests {

    /// `NavigatorError` 는 결합값이 있어 `CaseIterable` 이 아니다. 그래서 표를 손으로 적고,
    /// **개수를 단언**해 손으로 적은 표가 조용히 뒤처지는 것을 막는다
    /// (`NamedKeyRoutingTableTests` 가 쓰는 것과 같은 장치).
    private static let everyError: [NavigatorError] = [
        .projectNotFound(path: "/p"),
        .projectNotReadable(path: "/p", reason: "r"),
        .noProjectOpen,
        .invalidPath("/p"),
        .pathOutsideProject("/p"),
        .fileNotFound(path: "/p"),
        .fileTooLarge(path: "/p", byteSize: 3_000_000, limit: 2_000_000),
        .fileNotReadable(path: "/p", reason: "r"),
        .fileNotDecodable(path: "/p"),
        .invalidRegularExpression(pattern: "(", reason: "r"),
        .editorNotInstalled,
        .editorUnavailable(reason: "r"),
        .editorNotRunning,
        .editorRequestFailed(method: "m", reason: "r"),
    ]

    @Test("NavigatorError 14종이 전부 표에 있다")
    func theTableCoversEveryError() {
        // 케이스가 늘면 여기서 먼저 깨진다 — 그 다음 사람이 "이 오류는 화면에서 무엇인가"를
        // 답하게 하는 것이 목적이다. 매핑 자체는 `default` 가 없어 컴파일러가 먼저 잡는다.
        #expect(Self.everyError.count == 14, "지금 \(Self.everyError.count)종")
    }

    @Test("모든 오류가 매핑된다 — 빠지는 것이 없다")
    func everyErrorMaps() {
        #expect(!Self.everyError.isEmpty)

        for error in Self.everyError {
            // 값이 무엇이든 좋다. 여기서 묻는 것은 "부를 수 있는가"다.
            _ = RenderResourceFailureMapping.failure(for: error)
        }
    }

    /// **이 테스트가 그 회귀를 잡는 것이다.** `pathOutsideProject` 가 `.notReadable` 로 떨어지면
    /// `blockedKind()` 가 nil 을 돌려주고 차단 목록에서 사라진다 — 조용하고, 사용자에게는
    /// "이미지가 그냥 없는 것"으로 보인다.
    @Test("루트 밖 거절은 invalidPath 로 간다 — notReadable 로 새지 않는다")
    func anOutsideRootRejectionStaysABlock() {
        let mapped = RenderResourceFailureMapping.failure(for: .pathOutsideProject("/etc/passwd"))

        #expect(mapped == .invalidPath, "실제: \(mapped)")
    }

    @Test("계약 오용과 INV-6 거절은 화면에서 같은 사건이다")
    func contractMisuseAndRootRejectionLookTheSame() {
        // 엔진이 둘을 가르는 것은 로그와 문장을 위해서다. 칩이 말할 것은 하나뿐이라
        // 여기서 합쳐지는 것이 맞다 — 다만 **이름을 적어서** 합친다.
        #expect(
            RenderResourceFailureMapping.failure(for: .invalidPath("/p"))
                == RenderResourceFailureMapping.failure(for: .pathOutsideProject("/p"))
        )
    }

    @Test("없음·너무 큼은 각자 제 분류를 갖는다")
    func absenceAndSizeKeepTheirOwnClassification() {
        // 크기 초과는 사용자가 고칠 수 있는 유일한 사유라 별도로 남아야 한다(리더 판정).
        #expect(RenderResourceFailureMapping.failure(for: .fileNotFound(path: "/p")) == .notFound)
        #expect(
            RenderResourceFailureMapping.failure(
                for: .fileTooLarge(path: "/p", byteSize: 3_000_000, limit: 2_000_000)
            ) == .tooLarge(byteSize: 3_000_000, limit: 2_000_000)
        )
    }

    @Test("못 읽은 것들은 이유를 싣고 나간다 — 빈 문자열로 뭉개지지 않는다")
    func unreadableCarriesItsReason() {
        // 이유가 비면 W-15 박스가 "표시할 수 없습니다"만 말하고 왜인지는 사라진다.
        let unreadable: [NavigatorError] = [
            .projectNotFound(path: "/p"),
            .fileNotReadable(path: "/p", reason: "권한 없음"),
            .fileNotDecodable(path: "/p"),
            .editorNotRunning,
        ]
        #expect(!unreadable.isEmpty)

        for error in unreadable {
            guard case .notReadable(let reason) = RenderResourceFailureMapping.failure(for: error) else {
                Issue.record("\(error) 가 notReadable 이 아니다")
                continue
            }
            #expect(!reason.isEmpty, "\(error) 의 이유가 비었다")
        }
    }
}
