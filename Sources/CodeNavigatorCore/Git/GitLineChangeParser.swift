import CodeNavigatorContract
import Foundation

/// `git diff -U0` 의 헝크 머리글을 줄 표시로 옮긴다.
///
/// `-U0` 인 것이 핵심이다. 문맥 줄이 없어야 머리글의 숫자가 **바뀐 줄 그 자체**를 가리킨다.
/// 기본값(`-U3`)이면 앞뒤 세 줄이 함께 들어와서, 손대지 않은 줄에도 표시가 붙는다.
public enum GitLineChangeParser {

    /// 머리글 모양: `@@ -oldStart[,oldCount] +newStart[,newCount] @@`
    public static func parse(unifiedDiff: String) -> [GitLineChange] {
        var changes: [GitLineChange] = []

        for rawLine in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false) {
            // **줄 맨 앞의 `@@` 만 머리글이다.** 코드 본문에 `@@` 가 들어 있을 수 있고,
            // 그것까지 읽으면 있지도 않은 변경이 생긴다.
            guard rawLine.hasPrefix("@@ "), let hunk = parseHunkHeader(rawLine) else { continue }

            if hunk.newCount > 0 {
                // 옛 줄이 없었으면 통째로 새로 생긴 것, 있었으면 자리를 지킨 채 바뀐 것.
                let kind: GitLineChange.Kind = hunk.oldCount == 0 ? .added : .modified
                for offset in 0..<hunk.newCount {
                    changes.append(GitLineChange(line: hunk.newStart + offset, kind: kind))
                }
            }

            // 줄 수가 줄었으면 사라진 줄이 있다. 새 줄이 하나도 없으면 순수 삭제다.
            if hunk.oldCount > hunk.newCount {
                // 삭제 표시는 **남아 있는 줄**에 붙어야 보인다. 새 줄이 없으면 사라진 자리
                // 바로 앞에, 있으면 마지막 새 줄에 붙인다. 파일 맨 앞이면 가리킬 앞 줄이
                // 없어 1이다.
                let anchor = hunk.newCount > 0
                    ? hunk.newStart + hunk.newCount - 1
                    : max(hunk.newStart, 1)
                changes.append(GitLineChange(line: anchor, kind: .deleted))
            }
        }
        return changes
    }

    private struct Hunk {
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    private static func parseHunkHeader(_ line: Substring) -> Hunk? {
        // `@@ -3,5 +3,2 @@ 뒤쪽 문맥` — 앞의 두 조각만 필요하다.
        let parts = line.dropFirst(3).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("-"), parts[1].hasPrefix("+") else { return nil }

        guard
            let old = parseRange(parts[0].dropFirst()),
            let new = parseRange(parts[1].dropFirst())
        else {
            return nil
        }
        return Hunk(oldCount: old.count, newStart: new.start, newCount: new.count)
    }

    /// `12,3` 또는 `12`. 개수를 생략하면 1이다.
    private static func parseRange(_ text: Substring) -> (start: Int, count: Int)? {
        let pieces = text.split(separator: ",")
        guard let first = pieces.first, let start = Int(first) else { return nil }
        guard pieces.count > 1 else { return (start, 1) }
        guard let count = Int(pieces[1]) else { return nil }
        return (start, count)
    }
}
