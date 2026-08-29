import SwiftUI

/// A busy indicator that stops moving when the system asks it to.
///
/// Design §4.5: with "동작 줄이기" enabled, spinners and pulses become static icons. A
/// spinner is the shell's most common animation — the index chip, the search modal, the
/// tree — so honouring the setting once here is the difference between honouring it and
/// meaning to.
struct MotionSafeSpinner: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The token colour the static form is drawn in. The animated form uses the system
    /// spinner, which already matches the appearance.
    let tone: Color
    var size: CGFloat = 11

    var body: some View {
        if reduceMotion {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: size))
                .foregroundStyle(tone)
        } else {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(size / 16)
                .frame(width: size + 3, height: size + 3)
        }
    }
}
