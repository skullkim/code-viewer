import SwiftUI

/// Why a panel is showing a sentence instead of a list.
enum PanelMessageTone {
    /// Nothing has been asked yet, or the answer was legitimately empty.
    case quiet
    /// A request is in flight.
    case busy
    /// The request failed. Never used for "no results" — an error and an empty answer are
    /// different facts, and SC-6 exists because conflating them hides a broken query.
    case failure
}

/// The centred sentence a panel shows in place of results (design §3 W-5 · W-6, `.panel-empty`).
struct PanelMessage: View {

    let text: String
    var tone: PanelMessageTone = .quiet

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            if tone == .busy {
                MotionSafeSpinner(tone: DesignTokens.textTertiary.dynamicColor)
            }
            Text(text)
                .font(.system(size: Metrics.fontSize))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.large)
        .padding(.vertical, DesignTokens.Spacing.huge)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch tone {
        case .quiet, .busy:
            return DesignTokens.textTertiary.dynamicColor
        case .failure:
            return DesignTokens.danger.dynamicColor
        }
    }

    private enum Metrics {
        static let fontSize: CGFloat = 12
    }
}
