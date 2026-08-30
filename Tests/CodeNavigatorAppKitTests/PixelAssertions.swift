import AppKit
import CoreGraphics
@testable import CodeNavigatorAppKit

/// Questions that can be asked of a rendered window, as pure functions over a bitmap.
///
/// They are separated from the tests that use them for one reason: a checker that has only
/// ever seen correct input has not been shown to catch anything. Keeping the questions
/// answerable about *any* bitmap lets `DesignRegressionSelfTests` hand them deliberately
/// broken images — a blank canvas, a wrong token colour, glyphs run together — and confirm
/// each one fires. Nothing in `Sources/` is touched to do it.
enum PixelAssertions {

    /// A colour distance beyond which two colours are considered different.
    ///
    /// Font smoothing and colour-space conversion move a channel by a hair; a token painted
    /// with the wrong hex moves it by far more.
    static let tokenTolerance = 0.02

    // MARK: 색

    static func colour(_ representation: NSBitmapImageRep, atX x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < representation.pixelsWide, y < representation.pixelsHigh else {
            return nil
        }
        return representation.colorAt(x: x, y: y)
    }

    /// Whether the pixel carries the token's colour, within tolerance.
    static func matches(
        _ representation: NSBitmapImageRep,
        atX x: Int,
        y: Int,
        token: CodeNavigatorAppKit.RGBColor,
        tolerance: Double = tokenTolerance
    ) -> Bool {
        guard let sampled = colour(representation, atX: x, y: y) else {
            return false
        }
        return abs(sampled.redComponent - token.red) < tolerance
            && abs(sampled.greenComponent - token.green) < tolerance
            && abs(sampled.blueComponent - token.blue) < tolerance
    }

    /// How many different colours appear, sampled on a coarse grid.
    ///
    /// One or two means the render produced a flat field: layout ran and nothing was drawn.
    static func distinctColourCount(_ representation: NSBitmapImageRep, step: Int = 9) -> Int {
        var seen: Set<Int> = []
        var x = 0
        while x < representation.pixelsWide {
            var y = 0
            while y < representation.pixelsHigh {
                if let colour = representation.colorAt(x: x, y: y) {
                    // Quantised so imperceptible smoothing differences do not read as
                    // "many colours" on an otherwise blank image.
                    let key = (Int(colour.redComponent * 32) << 16)
                        | (Int(colour.greenComponent * 32) << 8)
                        | Int(colour.blueComponent * 32)
                    seen.insert(key)
                }
                y += step
            }
            x += step
        }
        return seen.count
    }

    // MARK: 잉크

    /// Pixels in `band` that differ from the band's dominant colour — its "ink".
    ///
    /// The background is measured rather than assumed, so the same question works on a
    /// light toolbar and a dark one.
    static func inkPixelCount(_ representation: NSBitmapImageRep, band: CGRect, threshold: Double = 0.12) -> Int {
        guard let background = dominantColour(representation, band: band) else {
            return 0
        }
        var count = 0
        forEachPixel(in: band, of: representation) { colour, _, _ in
            if distance(colour, background) > threshold {
                count += 1
            }
        }
        return count
    }

    /// How many separate marks sit in `band`, left to right.
    ///
    /// A column counts as ink if any pixel in it differs from the background; a run of ink
    /// columns bounded by blank ones is one mark. This is the right question for glyph
    /// collision: `⇧⌘F` drawn correctly is three marks, and the same string with its glyphs
    /// run together is one. Width cannot tell those apart — a merged blob and three tight
    /// glyphs occupy nearly the same span.
    /// - Parameter threshold: summed per-channel distance from the background. The default
    ///   is deliberately far higher than `inkPixelCount`'s, and the two answer different
    ///   questions. Presence tolerates a faint mark; separation must not, because a glyph's
    ///   antialiasing halo bridges the gap to its neighbour and merges marks that a reader
    ///   sees as distinct. Calibrated against known text: at this value "ABC" reports three
    ///   marks and "XYZ" three, which is the property `theMetricSeparatesKnownGlyphs` pins.
    static func inkRunCount(_ representation: NSBitmapImageRep, band: CGRect, threshold: Double = 1.2) -> Int {
        guard let background = dominantColour(representation, band: band) else {
            return 0
        }

        let minX = max(0, Int(band.minX))
        let maxX = min(representation.pixelsWide, Int(band.maxX))
        let minY = max(0, Int(band.minY))
        let maxY = min(representation.pixelsHigh, Int(band.maxY))
        guard minX < maxX, minY < maxY else {
            return 0
        }

        var runs = 0
        var insideRun = false

        for x in minX..<maxX {
            var columnHasInk = false
            for y in minY..<maxY {
                guard let colour = representation.colorAt(x: x, y: y) else { continue }
                if distance(colour, background) > threshold {
                    columnHasInk = true
                    break
                }
            }

            if columnHasInk && !insideRun {
                runs += 1
            }
            insideRun = columnHasInk
        }
        return runs
    }

    // MARK: 내부

    private static func forEachPixel(
        in band: CGRect,
        of representation: NSBitmapImageRep,
        _ body: (NSColor, Int, Int) -> Void
    ) {
        let minX = max(0, Int(band.minX))
        let maxX = min(representation.pixelsWide, Int(band.maxX))
        let minY = max(0, Int(band.minY))
        let maxY = min(representation.pixelsHigh, Int(band.maxY))
        guard minX < maxX, minY < maxY else {
            return
        }

        for x in minX..<maxX {
            for y in minY..<maxY {
                if let colour = representation.colorAt(x: x, y: y) {
                    body(colour, x, y)
                }
            }
        }
    }

    /// The most common colour in the band, quantised — the surface the marks sit on.
    private static func dominantColour(_ representation: NSBitmapImageRep, band: CGRect) -> NSColor? {
        var tally: [Int: (count: Int, colour: NSColor)] = [:]
        forEachPixel(in: band, of: representation) { colour, _, _ in
            let key = (Int(colour.redComponent * 64) << 16)
                | (Int(colour.greenComponent * 64) << 8)
                | Int(colour.blueComponent * 64)
            tally[key, default: (0, colour)].count += 1
        }
        return tally.values.max { $0.count < $1.count }?.colour
    }

    private static func distance(_ first: NSColor, _ second: NSColor) -> Double {
        abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent)
    }
}
