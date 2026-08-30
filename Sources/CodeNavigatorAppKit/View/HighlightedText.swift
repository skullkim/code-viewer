import SwiftUI

/// A preview line with its search hits marked (design §3 W-3 · W-5 · W-6).
///
/// The runs are assembled into one `AttributedString` rather than a row of `Text` views on
/// purpose. Panel previews are single-line and have to end in an ellipsis when they do not
/// fit; a stack of separate views truncates each run on its own, so a long line loses the
/// wrong part and stops looking like the source it came from.
struct HighlightedText: View {

    let segments: [HighlightSegment]
    var font: Font = .system(size: DesignTokens.Typography.previewSize, design: .monospaced)
    var baseColor: ColorToken = DesignTokens.textSecondary

    var body: some View {
        Text(Self.attributedString(segments: segments, baseColor: baseColor))
            .font(font)
    }

    /// Matched runs get the `match` tint behind them and step up to `text-1`, the way the
    /// prototype's `mark` rule does — the highlight is meant to pull the eye to the hit,
    /// and tinting the background without lifting the text does the opposite.
    static func attributedString(segments: [HighlightSegment], baseColor: ColorToken) -> AttributedString {
        var result = AttributedString()

        for segment in segments {
            var run = AttributedString(segment.text)
            if segment.isMatch {
                run.backgroundColor = DesignTokens.match.dynamicColor
                run.foregroundColor = DesignTokens.textPrimary.dynamicColor
            } else {
                run.foregroundColor = baseColor.dynamicColor
            }
            result.append(run)
        }

        return result
    }
}
