import Testing
import AppKit
import SwiftUI
@testable import CodeNavigatorAppKit

/// Whether shortcut labels draw each modifier symbol as a separate glyph.
///
/// They did not. The monospaced system font has no glyphs for ⌘ ⇧ ⌥ ⌃, so they came from a
/// fallback face whose advances did not match the monospace cell, and two modifiers in a
/// row drew on top of one another. At 11pt `⇧⌘F` was a single unbroken mass of ink.
///
/// An earlier version of this suite measured the label's total ink *width* and concluded
/// there was no defect. That metric cannot see this bug: the span from the first drawn
/// pixel to the last is the same whether the glyphs inside it are distinct or crushed
/// together. What separates the two is **gaps** — so that is what is measured here.
@MainActor
@Suite("ShortcutLabelRendering — 단축키 기호가 겹치지 않는가 (REQ-011 AC-2)")
struct ShortcutLabelRenderingTests {

    /// How many gap-separated clusters of ink the text draws.
    ///
    /// One glyph per cluster when the label renders correctly. Overlapping glyphs merge
    /// into fewer clusters, which is exactly the defect.
    private func inkClusterCount(_ text: String, font: Font = .shortcutLabel()) -> Int {
        let columns = inkColumns(text, font: font)
        var clusters = 0
        var previousHadInk = false
        for hasInk in columns {
            if hasInk && !previousHadInk {
                clusters += 1
            }
            previousHadInk = hasInk
        }
        return clusters
    }

    /// Per-pixel-column: does this column contain any ink?
    private func inkColumns(_ text: String, font: Font) -> [Bool] {
        let hosting = NSHostingView(rootView:
            Text(text)
                .font(font)
                .foregroundStyle(Color.white)
                .fixedSize()
                .padding(4)
                .background(Color.black)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: DesignTokens.Typography.shortcutSize * 4)
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("비트맵을 만들지 못했다")
            return []
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        return (0..<representation.pixelsWide).map { x in
            for y in 0..<representation.pixelsHigh {
                guard let colour = representation.colorAt(x: x, y: y) else { continue }
                if colour.redComponent > 0.25 || colour.greenComponent > 0.25 || colour.blueComponent > 0.25 {
                    return true
                }
            }
            return false
        }
    }

    @Test("수식키 두 개가 연달아 와도 글리프가 따로 그려진다")
    func consecutiveModifiersDrawAsSeparateGlyphs() {
        // The defect in one assertion: ⇧⌘F drew as one merged blob under the monospaced
        // font, and as three under the system font.
        for label in ["⇧⌘F", "⌥⌘0", "⌃⌘V", "⇧⌘B"] {
            #expect(
                inkClusterCount(label) >= 3,
                "\(label)이 \(inkClusterCount(label))덩어리로 그려졌다 — 수식키 기호가 겹쳤다"
            )
        }
    }

    @Test("수식키 하나짜리도 분리된다")
    func aSingleModifierAlsoSeparates() {
        #expect(inkClusterCount("⌘P") >= 2)
        #expect(inkClusterCount("⌘O") >= 2)
    }

    @Test("모노스페이스로 그리면 실제로 겹친다 — 폰트 선택이 원인이라는 근거")
    func theMonospacedFaceIsWhatMergedThem() {
        // Pins the diagnosis, not just the fix. If a future change reaches for `.monospaced`
        // again for key notation, this records exactly why that is wrong.
        let merged = inkClusterCount("⇧⌘F", font: .system(size: DesignTokens.Typography.shortcutSize, design: .monospaced))
        let separated = inkClusterCount("⇧⌘F", font: .shortcutLabel())
        #expect(merged < separated, "모노스페이스와 시스템 폰트의 렌더가 같다 — 진단 근거가 사라졌다")
    }

    @Test("툴바가 쓰는 모든 단축키가 기호 수만큼 분리된다")
    func everyToolbarShortcutSeparates() {
        // Walks the real presentation rather than a hand-written list, so a shortcut added
        // to the toolbar is covered without anyone remembering to add it here.
        let toolbar = ToolbarPresentation.make(
            projectName: "repo",
            editorStatus: nil,
            availability: MenuAvailability(inputMode: .vim, sessionState: .connected, hasOpenProject: true),
            layout: ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
        )
        #expect(!toolbar.buttons.isEmpty)

        for button in toolbar.buttons where !button.shortcutLabel.isEmpty {
            #expect(
                inkClusterCount(button.shortcutLabel) >= button.shortcutLabel.count,
                "\(button.title)의 \(button.shortcutLabel)이 글자 수보다 적은 덩어리로 그려졌다"
            )
        }
    }

    @Test("수식키 기호가 폰트에 실제로 있다")
    func theModifierSymbolsExistInTheFont() {
        // The Hangul defect was exactly this — a glyph the font did not have, skipped in
        // silence. Checking directly rules it out for these symbols rather than inferring it.
        let metrics = CellMetrics(pointSize: DesignTokens.Typography.shortcutSize)
        let cache = GlyphCache()
        for symbol: Character in ["⌘", "⇧", "⌥", "⌃"] {
            #expect(
                cache.resolve(symbol, style: .plain, metrics: metrics) != nil,
                "\(symbol) 글리프를 찾지 못했다"
            )
        }
    }
}
