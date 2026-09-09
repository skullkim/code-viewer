import Testing
import Foundation
@testable import CodeNavigatorCore

/// 번들한 하이라이트 쿼리가 만들어 내는 **모든 캡처를 우리가 칠해야** 한다.
///
/// 안 칠한 캡처는 사용자의 colorscheme 이 칠한다. 그러면 같은 코드가 기계마다 다르게 보이고,
/// 사용자가 겪은 것이 정확히 그것이다: "하이라이트가 intellJ랑 다르게 변수명, 함수 이름,
/// 어노테이션 이런게 제대로 안돼, 컴퓨터 마다 기존의 vim 설정이 달라서 그런거 같아."
///
/// 실측(번들 nvim 0.12 + 우리 java 파서)으로 쿼리가 내는 캡처는 9종이었고, 그중
/// `@type.builtin`·`@variable.builtin`·`@operator` 셋이 매핑에 없었다.
///
/// 이 검사는 **파서를 더할 때도** 유효하다 — 새 언어의 캡처를 매핑에 안 넣으면 여기서 걸린다.
@Suite("하이라이트 캡처 빠짐없이 칠하기")
struct HighlightCaptureCoverageTests {

    /// 쿼리 파일에서 `@capture.name` 을 모은다. `@` 뒤에 이름이 오는 것만 캡처다 —
    /// `"@" @operator` 처럼 문자열 안의 `@` 는 캡처가 아니다.
    private func captures(inQueryAt path: String) throws -> Set<String> {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var found: Set<String> = []
        for line in text.split(separator: "\n") {
            // 주석 줄은 건너뛴다.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix(";") else { continue }
            var index = trimmed.startIndex
            while let at = trimmed[index...].firstIndex(of: "@") {
                let after = trimmed.index(after: at)
                guard after < trimmed.endIndex else { break }
                let name = trimmed[after...].prefix { $0.isLetter || $0 == "." || $0 == "_" }
                // 앞이 따옴표면 문자열 안의 `@` 다.
                let precededByQuote = at > trimmed.startIndex
                    && trimmed[trimmed.index(before: at)] == "\""
                if !name.isEmpty, !precededByQuote {
                    found.insert(String(name))
                }
                index = after
            }
        }
        return found
    }

    private var queryPath: String {
        // 테스트는 저장소 안에서 돈다. 번들 리소스가 아니라 원본을 본다 — 번들에 넣는 것과
        // 같은 파일이고, 넣기 전에 잡아야 의미가 있다.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CodeNavigatorCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 저장소 루트
            .appendingPathComponent("Resources/treesitter/queries/java/highlights.scm")
            .path
    }

    /// 검사기 자체 검사 — 쿼리에서 아무것도 못 읽으면 이 스위트는 통과하면서 아무것도
    /// 증명하지 않는다.
    @Test("쿼리에서 캡처를 실제로 읽는다 (positive control)")
    func readsCapturesFromTheQuery() throws {
        let found = try captures(inQueryAt: queryPath)
        #expect(found.count >= 5, "쿼리에서 읽은 캡처: \(found.sorted())")
        #expect(found.contains("attribute"), "어노테이션 캡처를 못 읽었다")
        #expect(found.contains("variable"))
    }

    @Test("쿼리가 내는 캡처를 모두 칠한다")
    func coversEveryCapture() throws {
        let declared = try captures(inQueryAt: queryPath)
        let painted = NeovimHighlightScript.paintedTreeSitterCaptures
        let missing = declared.subtracting(painted).sorted()
        #expect(
            missing.isEmpty,
            "이 캡처를 안 칠한다 — 사용자 colorscheme 이 칠하게 되고 기계마다 달라진다: \(missing)"
        )
    }

    /// 칠하기만 하고 쿼리에 없는 이름은 죽은 설정이다. 나중에 이름이 바뀐 흔적이기도 하다.
    @Test("쿼리에 없는 캡처를 칠하고 있지는 않은지 — 목록만 보고한다")
    func reportsPaintedButUndeclared() throws {
        let declared = try captures(inQueryAt: queryPath)
        let extra = NeovimHighlightScript.paintedTreeSitterCaptures.subtracting(declared).sorted()
        // 다른 언어 파서를 더할 것을 대비해 미리 칠해 두는 것은 정상이라 실패로 보지 않는다.
        // 다만 눈에 보이게 남긴다.
        print("쿼리에 없지만 칠하는 캡처(다른 파서 대비): \(extra)")
        #expect(true)
    }
}
