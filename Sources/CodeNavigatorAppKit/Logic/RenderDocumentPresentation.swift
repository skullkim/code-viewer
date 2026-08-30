import Foundation

/// Where the rendered text came from (REQ-013, leader ruling 2026-08-30).
///
/// Buffer first, disk as fallback: the usual reason to open a preview is to see how what
/// you just typed looks, and rendering the disk copy would show a document missing the
/// paragraph you are looking for — not "slightly stale" but wrong.
///
/// The fallback is never silent. If the edit session died and the render quietly dropped to
/// disk, the user is looking at a wrong screen with no way to know it, which is the same
/// failure in the other direction.
public enum RenderSource: Sendable, Hashable {
    case buffer
    case disk

    /// The badge shown in the render header. Nil for the ordinary case — a notice that
    /// appears always is a notice nobody reads.
    public var badge: String? {
        switch self {
        case .buffer: return nil
        case .disk: return "저장된 내용"
        }
    }

    public var tooltip: String? {
        switch self {
        case .buffer: return nil
        case .disk: return "편집 중인 내용이 아니라 디스크에 저장된 내용을 표시하고 있습니다"
        }
    }
}

/// What the render surface is doing (design 02b §3 W-14).
public enum RenderPhase: Sendable, Hashable {
    /// First render of this file.
    case rendering
    /// A re-render after a save. The previous document stays on screen (AC-5).
    case rerendering
    case rendered(source: RenderSource)
    case empty
    case failed(reason: String)
    case undecodable
    case tooLarge(byteCount: Int)
}

/// A card shown in place of the document when there is nothing to draw.
public struct RenderNoticeCard: Sendable, Hashable {
    public let glyph: String
    public let title: String
    public let detail: String
    /// Buttons, in order. `[소스 보기]` is always among them — every dead end has a way out.
    public let actions: [RenderNoticeAction]
}

public enum RenderNoticeAction: String, Sendable, Hashable {
    case viewSource
    case retry

    public var title: String {
        switch self {
        case .viewSource: return "소스 보기 ⇧⌘V"
        case .retry: return "다시 시도"
        }
    }
}

/// Everything the render surface draws except the document itself (design 02b §3 W-14).
public struct RenderDocumentPresentation: Sendable, Hashable {
    public let fileName: String
    public let readOnlyBadge: String
    public let sourceBadge: String?
    public let sourceTooltip: String?
    public let toggleTitle: String
    /// Shown centred, and only once the wait is long enough to be worth mentioning.
    public let progressText: String?
    /// Shown in the header while a re-render runs, leaving the old document in place.
    public let showsHeaderSpinner: Bool
    /// Nil when the document itself is drawn.
    public let notice: RenderNoticeCard?
    /// True while the previous render stays on screen underneath (AC-5).
    public let keepsPreviousDocument: Bool
}

extension RenderDocumentPresentation {

    static let readOnlyText = "읽기 전용"
    static let toggleText = "소스 보기 ⇧⌘V"
    static let renderingText = "문서를 렌더하는 중…"

    /// Design 02b §3 W-14: 2MB.
    public static let maximumRenderableBytes = 2 * 1024 * 1024

    public static func make(
        fileName: String,
        phase: RenderPhase,
        hasPreviousDocument: Bool,
        elapsedSeconds: Double?
    ) -> RenderDocumentPresentation {
        let source = renderSource(for: phase)

        return RenderDocumentPresentation(
            fileName: fileName,
            readOnlyBadge: readOnlyText,
            sourceBadge: source?.badge,
            sourceTooltip: source?.tooltip,
            toggleTitle: toggleText,
            progressText: progressText(for: phase, elapsedSeconds: elapsedSeconds),
            showsHeaderSpinner: phase == .rerendering,
            notice: notice(for: phase),
            // A save should not blank the document being read (AC-5).
            keepsPreviousDocument: phase == .rerendering && hasPreviousDocument
        )
    }

    private static func renderSource(for phase: RenderPhase) -> RenderSource? {
        guard case .rendered(let source) = phase else {
            return nil
        }
        return source
    }

    /// The spinner appears only once the render has run past the flicker threshold.
    ///
    /// Same rule as the symbol search modal: most renders finish in a few milliseconds, and
    /// a spinner for those is a flash that reads as a glitch rather than as progress.
    private static func progressText(for phase: RenderPhase, elapsedSeconds: Double?) -> String? {
        guard phase == .rendering else {
            return nil
        }
        let startedAt = Date(timeIntervalSince1970: 0)
        let now = startedAt.addingTimeInterval(elapsedSeconds ?? 0)
        return SpinnerDelay.showsSpinner(startedAt: startedAt, now: now) ? renderingText : nil
    }

    private static func notice(for phase: RenderPhase) -> RenderNoticeCard? {
        switch phase {
        case .rendering, .rerendering, .rendered:
            return nil

        case .empty:
            return RenderNoticeCard(
                glyph: "📄",
                title: "빈 문서입니다",
                detail: "이 파일에는 내용이 없습니다.",
                actions: [.viewSource]
            )

        case .failed(let reason):
            return RenderNoticeCard(
                glyph: "⚠️",
                title: "문서를 읽을 수 없습니다",
                detail: reason,
                actions: [.viewSource, .retry]
            )

        case .undecodable:
            return RenderNoticeCard(
                glyph: "⚠️",
                title: "이 파일의 문자 인코딩을 해석할 수 없습니다",
                detail: "UTF-8 텍스트가 아닙니다.",
                actions: [.viewSource]
            )

        case .tooLarge(let byteCount):
            return RenderNoticeCard(
                glyph: "⚠️",
                title: "문서가 너무 큽니다",
                // The actual size is named. "Too large" without a number leaves the user
                // guessing whether trimming the file would help.
                detail: "렌더 상한은 \(ByteSizeText.string(fromByteCount: maximumRenderableBytes))입니다 "
                    + "(이 파일 \(ByteSizeText.string(fromByteCount: byteCount))).",
                // Deliberately no "render anyway": a partial render reads as "the document
                // ends here", which is a silent lie. Better to say it cannot be drawn.
                actions: [.viewSource]
            )
        }
    }
}
