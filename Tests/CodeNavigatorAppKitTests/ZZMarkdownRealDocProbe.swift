import Testing
import Foundation
@testable import CodeNavigatorAppKit

@Suite("ZZ 임시 프로브")
struct ZZMarkdownRealDocProbe {

    @Test("남은 구문 주변 문맥")
    func leftoverContext() {
        guard let text = try? String(contentsOfFile: "_workspace/02b_design.md", encoding: .utf8) else { return }
        let html = MarkdownDocument.html(from: text)
        let characters = Array(html)

        for needle in ["**", "`"] {
            let target = Array(needle)
            var position = 0
            var shown = 0
            while position + target.count <= characters.count, shown < 6 {
                if Array(characters[position..<(position + target.count)]) == target {
                    let from = max(0, position - 60)
                    let to = min(characters.count, position + 60)
                    print("CTX [\(needle)] …\(String(characters[from..<to]))…")
                    shown += 1
                    position += target.count
                    continue
                }
                position += 1
            }
        }
    }
}
