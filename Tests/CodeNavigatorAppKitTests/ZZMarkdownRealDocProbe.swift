import Testing
import Foundation
@testable import CodeNavigatorAppKit

@Suite("ZZ 임시 프로브")
struct ZZMarkdownRealDocProbe {

    @Test("남은 것의 정체")
    func identify() {
        for path in ["_workspace/03c_multi_project_contract_draft.md",
                     "_workspace/CERTIFICATION.md",
                     "docs/adr/0102-key-routing.md"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let html = MarkdownDocument.html(from: text)
            let characters = Array(html)
            var position = 0
            var shown = 0
            while position + 1 < characters.count, shown < 3 {
                if characters[position] == "*" && characters[position + 1] == "*" {
                    let from = max(0, position - 70), to = min(characters.count, position + 70)
                    print("CTX \(path) …\(String(characters[from..<to]))…")
                    shown += 1
                    position += 2
                    continue
                }
                position += 1
            }
        }
    }
}
