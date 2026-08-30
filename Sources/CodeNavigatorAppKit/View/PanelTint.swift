import SwiftUI

/// Translucent tints the reference and full-text panels draw on (design §4.1).
///
/// Kept here rather than on `DesignTokens` because that type belongs to the shell owner and
/// the badge work is adding tints of its own; two definitions of `warning-dim` landing at
/// once would collide. Promote these when that settles — the values are §4.1's, not new ones.
enum PanelTint {

    /// `warning-dim` — behind the limit bar and the "인덱싱 중" banner.
    ///
    /// Light is `warning-solid` at 18%, dark the same hex at 16%; §4.1 gives `warning-solid`
    /// the same value in both appearances, so only the opacity differs.
    static let warning = TranslucentColorToken(
        name: "panel-warning-dim",
        light: DesignTokens.warningSolid.light,
        lightOpacity: 0.18,
        dark: DesignTokens.warningSolid.dark,
        darkOpacity: 0.16
    )
}
