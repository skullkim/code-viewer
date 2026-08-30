import CoreGraphics

/// Brings a restored window frame back onto a screen the user can actually see
/// (REQ-011 AC-3).
///
/// A frame saved on one display is meaningless on another. Unplug the external monitor the
/// window was on and its coordinates now name empty space — the app launches, reports
/// success, and shows nothing. That failure is indistinguishable from a crash, which makes
/// it worse than not restoring at all.
///
/// Frames are in AppKit's coordinate space: the origin is bottom-left and y grows upward,
/// so the top of a window is `maxY`.
public enum WindowFrameFit {

    /// Design §4.4: the window may not be smaller than this.
    public static let minimumSize = CGSize(width: 720, height: 480)

    /// How much of the window has to remain on a screen for the frame to be left alone.
    ///
    /// A window is still usable when it hangs off an edge — people park them that way on
    /// purpose. What must never happen is a window with no grabbable title bar, so the test
    /// is a visible area rather than full containment.
    static let minimumVisibleSize = CGSize(width: 240, height: 80)

    /// The frame to actually open at.
    ///
    /// - Parameter visibleFrames: each screen's visible frame — the area excluding the menu
    ///   bar and Dock, which is what a window may occupy.
    public static func fit(_ frame: CGRect, intoVisibleFrames visibleFrames: [CGRect]) -> CGRect {
        guard let primary = visibleFrames.first else {
            // No screens reported at all. Nothing can be verified, so the frame is returned
            // with only its size made sane; inventing a position would be guessing.
            return CGRect(origin: frame.origin, size: constrainedSize(frame.size, within: nil))
        }

        let target = bestScreen(for: frame, among: visibleFrames) ?? primary
        let size = constrainedSize(frame.size, within: target.size)

        guard isSufficientlyVisible(CGRect(origin: frame.origin, size: size), on: visibleFrames) else {
            // Nowhere useful: start again in the middle of the best screen rather than
            // nudging a frame whose coordinates no longer mean anything.
            return centred(size: size, in: target)
        }

        return nudgedIntoView(CGRect(origin: frame.origin, size: size), on: target)
    }

    /// The screen the frame overlaps most, or nil when it overlaps none.
    private static func bestScreen(for frame: CGRect, among visibleFrames: [CGRect]) -> CGRect? {
        var best: CGRect?
        var bestArea: CGFloat = 0

        for screen in visibleFrames {
            let intersection = screen.intersection(frame)
            guard !intersection.isNull else {
                continue
            }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    private static func isSufficientlyVisible(_ frame: CGRect, on visibleFrames: [CGRect]) -> Bool {
        visibleFrames.contains { screen in
            let intersection = screen.intersection(frame)
            guard !intersection.isNull else {
                return false
            }
            return intersection.width >= minimumVisibleSize.width
                && intersection.height >= minimumVisibleSize.height
        }
    }

    /// Slides a frame just far enough to put its title bar back within reach.
    private static func nudgedIntoView(_ frame: CGRect, on screen: CGRect) -> CGRect {
        var origin = frame.origin

        origin.x = min(max(origin.x, screen.minX - frame.width + minimumVisibleSize.width),
                       screen.maxX - minimumVisibleSize.width)
        // The top edge is the one that matters: a title bar pushed above the screen cannot
        // be grabbed, and macOS will not let the user drag the window back down.
        origin.y = min(max(origin.y, screen.minY - frame.height + minimumVisibleSize.height),
                       screen.maxY - frame.height)

        return CGRect(origin: origin, size: frame.size)
    }

    private static func centred(size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// No smaller than the design minimum, no larger than the screen it will sit on.
    private static func constrainedSize(_ size: CGSize, within screenSize: CGSize?) -> CGSize {
        var width = max(size.width, minimumSize.width)
        var height = max(size.height, minimumSize.height)

        if let screenSize {
            // The minimum still wins: a screen too small for it is a case the window server
            // handles, and shrinking below it would break design §4.4 instead.
            width = max(minimumSize.width, min(width, screenSize.width))
            height = max(minimumSize.height, min(height, screenSize.height))
        }

        return CGSize(width: width, height: height)
    }
}
