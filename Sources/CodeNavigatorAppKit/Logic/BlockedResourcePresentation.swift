import Foundation

/// One thing the sandbox refused, as recorded while rendering.
public struct BlockedResource: Sendable, Hashable {
    public let kind: BlockedResourceKind
    /// The host, the offending path, or `(인라인)` — what the popover shows beside the count.
    public let detail: String

    public init(kind: BlockedResourceKind, detail: String) {
        self.kind = kind
        self.detail = detail
    }
}

/// One row of the popover.
public struct BlockedResourceRow: Sendable, Hashable, Identifiable {
    public let kind: BlockedResourceKind
    public let label: String
    public let count: Int
    /// A single source, or `{첫 곳} 외 {n}곳` when several.
    public let detail: String

    public var id: String { kind.rawValue }
}

/// The sandbox chip and its popover (design 02b §3 W-15).
///
/// The chip is shown even with nothing blocked. That is the point of the design note: a
/// silent block becomes "why is this image missing", and the user concludes the app is
/// broken. Saying "this document may not look like the original" at all times costs one
/// chip; saying nothing costs the user's trust in what they are looking at.
public struct BlockedResourcePresentation: Sendable {
    public let chipLabel: String
    public let blockedCount: Int
    public let rows: [BlockedResourceRow]
    /// Shown in place of rows when nothing was blocked.
    public let emptyText: String?
    public let policyText: String
}

extension BlockedResourcePresentation {

    static let quietChipLabel = "🛡 샌드박스"
    static let emptyMessage = "차단된 항목이 없습니다"
    static let policyMessage = """
        렌더 보기는 네트워크 요청을 하지 않고 스크립트를 실행하지 않습니다.
        이 차단은 해제할 수 없습니다 — 원본 그대로 보려면 브라우저에서 파일을 여세요.
        """

    public static func make(blocked: [BlockedResource]) -> BlockedResourcePresentation {
        BlockedResourcePresentation(
            chipLabel: blocked.isEmpty
                ? quietChipLabel
                : "🛡 차단됨 \(GroupedNumberText.string(blocked.count))",
            blockedCount: blocked.count,
            rows: rows(for: blocked),
            emptyText: blocked.isEmpty ? emptyMessage : nil,
            policyText: policyMessage
        )
    }

    /// One row per kind, in the order W-15 lists them.
    ///
    /// Aggregated rather than listed: forty blocked resources are forty lines nobody reads,
    /// and the design caps the popover at the six kinds for that reason.
    static func rows(for blocked: [BlockedResource]) -> [BlockedResourceRow] {
        BlockedResourceKind.allCases.compactMap { kind in
            let matching = blocked.filter { $0.kind == kind }
            guard !matching.isEmpty else {
                return nil
            }
            return BlockedResourceRow(
                kind: kind,
                label: kind.label,
                count: matching.count,
                detail: detail(for: matching)
            )
        }
    }

    private static func detail(for blocked: [BlockedResource]) -> String {
        // Distinct sources, first-seen order — the order they appear in the document is
        // more use than an alphabetical one when hunting for what went missing.
        var seen: Set<String> = []
        var sources: [String] = []
        for resource in blocked where !seen.contains(resource.detail) {
            seen.insert(resource.detail)
            sources.append(resource.detail)
        }

        guard let first = sources.first else {
            return ""
        }
        guard sources.count > 1 else {
            return first
        }
        return "\(first) 외 \(GroupedNumberText.string(sources.count - 1))곳"
    }
}
