import Testing
@testable import CodeNavigatorAppKit

/// A terminal grid gives every cell the same width, but not every character occupies one
/// cell. Neovim reports run boundaries and cell counts, and the renderer has to place each
/// character inside a run — which needs to know how many cells each one takes.
@Suite("DisplayWidth — 문자가 차지하는 셀 수")
struct DisplayWidthTests {

    @Test("ASCII는 한 셀이다")
    func asciiTakesOneCell() {
        for character: Character in ["a", "Z", "0", " ", "{", "~"] {
            #expect(DisplayWidth.cells(of: character) == 1, "\(character)")
        }
    }

    @Test("한글·한자·가나는 두 셀이다")
    func eastAsianCharactersTakeTwoCells() {
        for character: Character in ["한", "글", "인", "덱", "中", "文", "あ", "カ"] {
            #expect(DisplayWidth.cells(of: character) == 2, "\(character)")
        }
    }

    @Test("전각 기호도 두 셀이다")
    func fullwidthFormsTakeTwoCells() {
        for character: Character in ["＝", "！", "　"] {
            #expect(DisplayWidth.cells(of: character) == 2, "\(character)")
        }
    }

    @Test("이모지는 두 셀이다")
    func emojiTakeTwoCells() {
        for character: Character in ["👍", "🚀", "✅"] {
            #expect(DisplayWidth.cells(of: character) == 2, "\(character)")
        }
    }

    @Test("결합 문자만 있는 것은 셀을 차지하지 않는다")
    func combiningMarksTakeNoCell() {
        #expect(DisplayWidth.cells(of: "\u{0301}") == 0)
    }

    @Test("결합된 문자는 기반 문자의 폭을 따른다")
    func aComposedCharacterFollowsItsBase() {
        // "é" as e + combining acute is one grapheme occupying one cell.
        #expect(DisplayWidth.cells(of: "e\u{0301}") == 1)
        #expect(DisplayWidth.cells(of: "é") == 1)
    }

    @Test("문자열 전체의 셀 수를 센다")
    func aStringsCellsAreTheSumOfItsCharacters() {
        #expect(DisplayWidth.cells(of: "인덱스 abc") == 10)
        #expect(DisplayWidth.cells(of: "plain ascii") == 11)
        #expect(DisplayWidth.cells(of: "") == 0)
    }

    @Test("실제 Neovim이 보고한 셀 수와 일치한다")
    func matchesWhatNeovimReported() {
        // Measured against a live Neovim 0.12.5 grid_line dump on 2026-08-29:
        // "인덱스 abc" occupied ten cells while joining to seven Characters.
        #expect(DisplayWidth.cells(of: "인덱스 abc") == 10)
        #expect("인덱스 abc".count == 7)
    }
}
