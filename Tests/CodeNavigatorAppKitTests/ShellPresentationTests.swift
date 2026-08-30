import Testing
import CoreGraphics
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

@Suite("심볼 종류 배지 — REQ-002 추출 종류의 UI 표면 (02 §4.1)")
struct SymbolKindBadgeTests {

    @Test("설계가 지정한 글자와 색이 종류마다 붙는다")
    func everyKindHasItsDesignedBadge() {
        let expected: [SymbolKind: (String, String)] = [
            .class: ("C", "accent-text"),
            .object: ("O", "accent-text"),
            .interface: ("I", "teal"),
            .typeAlias: ("T", "teal"),
            .enum: ("E", "purple"),
            .function: ("F", "purple"),
            .property: ("P", "warning"),
        ]

        #expect(expected.count == SymbolKind.allCases.count)
        for kind in SymbolKind.allCases {
            let badge = SymbolKindBadge.badge(for: kind)
            #expect(badge.letter == expected[kind]?.0, "\(kind) 의 글자")
            #expect(badge.token.name == expected[kind]?.1, "\(kind) 의 색 토큰")
        }
    }

    @Test("색이 겹치는 종류는 글자와 라벨로 갈린다 — 색만으로 구분하지 않는다 (§4.5)")
    func colourIsNeverTheOnlySignal() {
        let badges = SymbolKind.allCases.map(SymbolKindBadge.badge(for:))
        #expect(badges.count == 7)

        // Four colours carry seven kinds, so the colour alone cannot identify a kind.
        #expect(Set(badges.map(\.token.name)).count == 4)
        // The letter and the spoken label both can.
        #expect(Set(badges.map(\.letter)).count == 7)
        #expect(Set(badges.map(\.accessibilityLabel)).count == 7)
        #expect(badges.allSatisfy { !$0.accessibilityLabel.isEmpty })
    }

    @Test("배지 색은 배지가 놓이는 표면에서 대비 하한을 넘는다")
    func badgeColoursClearTheirFloor() {
        #expect(DesignTokens.badgeTokens.count == 4)
        #expect(DesignTokens.badgeBearingSurfaces.count >= 3)

        let badgeTokenNames = Set(SymbolKind.allCases.map { SymbolKindBadge.badge(for: $0).token.name })
        #expect(badgeTokenNames == Set(DesignTokens.badgeTokens.map(\.name)))

        for token in DesignTokens.badgeTokens {
            for surface in DesignTokens.badgeBearingSurfaces {
                for scheme in AppearanceScheme.allCases {
                    let ratio = ColorContrast.ratio(token.value(for: scheme), surface.value(for: scheme))
                    #expect(
                        ratio >= DesignTokens.minimumBadgeContrastRatio,
                        "\(token.name) on \(surface.name) (\(scheme)): \(ratio)"
                    )
                }
            }
        }
    }
}

@Suite("ToolbarPresentation — 타이틀바 (02 §3 W-1, §4.4, §11 판정 5)")
struct ToolbarPresentationTests {

    private func layout(width: CGFloat) -> ShellLayout {
        ShellLayout.resolve(windowSize: CGSize(width: width, height: 800))
    }

    private func availability(hasOpenProject: Bool, sessionState: EditorSessionState = .connected) -> MenuAvailability {
        MenuAvailability(inputMode: .vim, sessionState: sessionState, hasOpenProject: hasOpenProject)
    }

    private func status(path: String?, isDirty: Bool) -> EditorStatus {
        EditorStatus(filePath: path, isDirty: isDirty, cursorLine: 1, cursorColumn: 1, mode: .normal, inputMode: .vim)
    }

    @Test("프로젝트가 없으면 그렇게 말하고 검색·패널 버튼이 비활성이다")
    func theEmptyStateDisablesSearch() {
        let toolbar = ToolbarPresentation.make(
            projectName: nil,
            editorStatus: nil,
            availability: availability(hasOpenProject: false),
            layout: layout(width: 1600)
        )

        #expect(toolbar.projectButtonTitle == ToolbarPresentation.noProjectTitle)
        #expect(toolbar.buttons.count == 3)
        #expect(toolbar.buttons.allSatisfy { !$0.isEnabled })
    }

    @Test("프로젝트가 열리면 이름이 뜨고 버튼이 살아난다")
    func anOpenProjectEnablesTheButtons() {
        let toolbar = ToolbarPresentation.make(
            projectName: "code-navigator-mac",
            editorStatus: status(path: "/repo/Sources/Index.swift", isDirty: false),
            availability: availability(hasOpenProject: true),
            layout: layout(width: 1600)
        )

        #expect(toolbar.projectButtonTitle == "code-navigator-mac")
        #expect(toolbar.buttons.allSatisfy { $0.isEnabled })
        #expect(toolbar.buttons.map(\.command) == [.symbolSearch, .textSearch, .togglePanel])
    }

    @Test("창 제목은 편집 중인 파일 이름 + 더티 표시다")
    func theWindowTitleFollowsTheBuffer() {
        let dirty = ToolbarPresentation.make(
            projectName: "sample",
            editorStatus: status(path: "/repo/Sources/SymbolIndex.swift", isDirty: true),
            availability: availability(hasOpenProject: true),
            layout: layout(width: 1600)
        )
        #expect(dirty.windowTitle == "SymbolIndex.swift")
        #expect(dirty.showsDirtyIndicator)

        // No file open yet: the project is the next most useful thing to name.
        let noFile = ToolbarPresentation.make(
            projectName: "sample",
            editorStatus: nil,
            availability: availability(hasOpenProject: true),
            layout: layout(width: 1600)
        )
        #expect(noFile.windowTitle == "sample")
        #expect(!noFile.showsDirtyIndicator)
    }

    @Test("창이 좁아지면 단축키 라벨 → 버튼 제목 순으로 사라진다 (§4.4)")
    func narrowWindowsShedLabelsInOrder() {
        let wide = ToolbarPresentation.make(
            projectName: "sample", editorStatus: nil,
            availability: availability(hasOpenProject: true), layout: layout(width: 1600)
        )
        #expect(wide.showsShortcutLabels)
        #expect(wide.showsButtonTitles)

        let medium = ToolbarPresentation.make(
            projectName: "sample", editorStatus: nil,
            availability: availability(hasOpenProject: true), layout: layout(width: 1000)
        )
        #expect(!medium.showsShortcutLabels)
        #expect(medium.showsButtonTitles)

        let narrow = ToolbarPresentation.make(
            projectName: "sample", editorStatus: nil,
            availability: availability(hasOpenProject: true), layout: layout(width: 700)
        )
        #expect(!narrow.showsShortcutLabels)
        #expect(!narrow.showsButtonTitles)
    }

    @Test("모드 세그먼트는 어떤 폭에서도 사라지지 않는다 (§11 판정 5, REQ-010 AC-3)")
    func theModeSegmentSurvivesEveryWidth() {
        for width in [CGFloat(1600), 1280, 1000, 900, 820, 720] {
            let toolbar = ToolbarPresentation.make(
                projectName: "sample", editorStatus: nil,
                availability: availability(hasOpenProject: true), layout: layout(width: width)
            )
            #expect(toolbar.showsModeSegment, "폭 \(width)에서 모드 세그먼트가 사라졌다")
        }
    }

    @Test("버튼 활성 여부는 메뉴와 같은 판정을 쓴다 — 두 규칙이 엇갈리지 않는다")
    func theToolbarAndTheMenuAgree() {
        let availability = availability(hasOpenProject: true, sessionState: .disconnected(reason: "종료"))
        let toolbar = ToolbarPresentation.make(
            projectName: "sample", editorStatus: nil,
            availability: availability, layout: layout(width: 1600)
        )

        for button in toolbar.buttons {
            #expect(button.isEnabled == availability.isEnabled(button.command), "\(button.command)")
        }
        // A dead edit session must not disable navigation: the index outlives it.
        #expect(toolbar.buttons.allSatisfy { $0.isEnabled })
    }
}

@Suite("DefinitionCandidatePresentation — 정의 후보 팝오버 (REQ-005 AC-2, 02 §3 W-4)")
struct DefinitionCandidatePresentationTests {

    private func definition(_ name: String, kind: SymbolKind = .function, path: String, line: Int, signature: String) -> SymbolDefinition {
        SymbolDefinition(name: name, kind: kind, path: path, line: line, signature: signature)
    }

    @Test("헤더가 이름과 건수를 말한다")
    func theHeaderNamesTheSymbolAndTheCount() {
        let presentation = DefinitionCandidatePresentation.make(symbolName: "parse", definitions: [
            definition("parse", path: "Index/Parser.swift", line: 41, signature: "func parse(_ url: URL)"),
            definition("parse", path: "Util/ArgParse.swift", line: 12, signature: "func parse(args:)"),
            definition("parse", path: "Index/SwiftParser.swift", line: 37, signature: "func parse(_ text: String)"),
        ])

        #expect(presentation.symbolName == "parse")
        #expect(presentation.headerDetail == "정의 3건 — 이동할 위치를 선택하세요")
        #expect(presentation.rows.count == 3)
    }

    @Test("행은 배지·시그니처·파일:라인을 담는다")
    func eachRowCarriesItsBadgeSignatureAndLocation() throws {
        let presentation = DefinitionCandidatePresentation.make(symbolName: "Parser", definitions: [
            definition("Parser", kind: .class, path: "Index/Parser.swift", line: 41, signature: "final class Parser"),
        ])

        let row = try #require(presentation.rows.first)
        #expect(row.badge.letter == "C")
        #expect(row.signature == "final class Parser")
        #expect(row.location == "Index/Parser.swift:41")
    }

    @Test("여러 줄 시그니처는 한 줄로 접힌다 — 행 높이가 고정이다 (PD 실측 결함 2)")
    func aMultiLineSignatureIsFoldedOntoOneLine() throws {
        let presentation = DefinitionCandidatePresentation.make(symbolName: "make", definitions: [
            definition("make", path: "A.swift", line: 3, signature: "  func make(\n    first: Int,\n\tsecond: String\n  )  "),
        ])

        let signature = try #require(presentation.rows.first?.signature)
        #expect(!signature.contains("\n"))
        #expect(!signature.contains("\t"))
        #expect(!signature.hasPrefix(" "))
        #expect(!signature.hasSuffix(" "))
        // Collapsed, not merely stripped: the words must not run together.
        #expect(signature == "func make( first: Int, second: String )")
    }

    @Test("후보 순서는 엔진이 준 순서 그대로다")
    func theEngineOrderIsPreserved() {
        let definitions = [
            definition("parse", path: "Z.swift", line: 9, signature: "func parse() // z"),
            definition("parse", path: "A.swift", line: 1, signature: "func parse() // a"),
            definition("parse", path: "M.swift", line: 5, signature: "func parse() // m"),
        ]
        let presentation = DefinitionCandidatePresentation.make(symbolName: "parse", definitions: definitions)

        // Neither the given order's reverse nor a sort by path: the fixture is arranged so
        // that "sorted it anyway" and "reversed it" both fail.
        #expect(presentation.rows.map(\.location) == ["Z.swift:9", "A.swift:1", "M.swift:5"])
    }

    @Test("푸터가 참조 보기 경로를 안내한다")
    func theFooterOffersReferences() {
        let presentation = DefinitionCandidatePresentation.make(symbolName: "parse", definitions: [
            definition("parse", path: "A.swift", line: 1, signature: "func parse()"),
            definition("parse", path: "B.swift", line: 2, signature: "func parse()"),
        ])

        #expect(presentation.footerText == DefinitionCandidatePresentation.referencesFooter)
        #expect(presentation.footerText.contains("⇧⌘B"))
        #expect(presentation.keyHintText == DefinitionCandidatePresentation.keyHint)
    }
}
