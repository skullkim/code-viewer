import CodeNavigatorContract

/// The mark drawn beside the index chip's label (design §3 W-10, third column).
///
/// Design §4.5 forbids colour as the only signal, so the chip carries a shape as well as a
/// tone — and the shape is not derivable from the tone. "갱신 중" and "전체 재스캔 중" are
/// both amber; one pulses in place and the other spins with a progress bar. A view that
/// guessed from the tone would draw them the same.
public enum IndexChipIndicator: Sendable, Hashable {
    /// A still dot: nothing is running.
    case dot
    /// A dot that pulses: work is in flight but too brief to measure.
    case pulsingDot
    /// A spinner: a measurable pass is running, and a progress bar accompanies it.
    case spinner
}

extension IndexChipIndicator {

    public static func indicator(for state: IndexState) -> IndexChipIndicator {
        switch state {
        case .notIndexed, .ready:
            return .dot
        case .updating:
            // A single file is reindexed in a moment; a progress bar would flash and be
            // gone, which reads as a glitch rather than as progress.
            return .pulsingDot
        case .indexing, .rescanning:
            return .spinner
        }
    }

    /// Whether the chip shows a progress bar. Only the states that carry counts do.
    public static func showsProgressBar(for state: IndexState) -> Bool {
        state.progress != nil
    }
}
