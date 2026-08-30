import Testing
import AppKit
import SwiftUI
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Renders the window to PNG files without putting it on screen.
///
/// The design-fidelity comparison had been waiting on the screen being unlocked, which is
/// not something this build controls. But nothing about drawing a view needs a visible
/// window: `NSHostingView` lays out and `cacheDisplay(in:to:)` rasterises, both offscreen.
/// What genuinely needs an unlocked screen is narrower than it looked — live key and mouse
/// input, and the window chrome the system draws.
///
/// Writing files is a side effect, so it is opt-in: set `WRITE_DESIGN_SHOTS=1`. The
/// assertions run either way, because "the window rasterises to something non-empty at
/// every size" is worth checking on every run.
@MainActor
@Suite("DesignFidelity — 화면 없이 렌더한 스냅샷")
struct DesignFidelitySnapshotTests {

    private var outputDirectory: URL? {
        guard ProcessInfo.processInfo.environment["WRITE_DESIGN_SHOTS"] == "1" else {
            return nil
        }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("_workspace/app-shots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeModels() -> (AppModel, SearchModel, FakeProjectSession, FakeEditorSession) {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            projectSession: project,
            editorSession: editor,
            workspace: RecordingWorkspace(),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (model, SearchModel(projectSession: project), project, editor)
    }

    /// Fills the window with the same content the prototype shows, so the two can be
    /// compared as pictures rather than as "both render something".
    private func populate(
        model: AppModel,
        search: SearchModel,
        project: FakeProjectSession,
        editor: FakeEditorSession
    ) async {
        project.directoryEntries[""] = [
            DirectoryEntry(name: "Sources", path: "Sources", isDirectory: true),
            DirectoryEntry(name: "Tests", path: "Tests", isDirectory: true),
            DirectoryEntry(name: "Package.swift", path: "Package.swift", isDirectory: false),
        ]
        project.directoryEntries["Sources"] = [
            DirectoryEntry(name: "Index", path: "Sources/Index", isDirectory: true),
            DirectoryEntry(name: "App.swift", path: "Sources/App.swift", isDirectory: false),
        ]
        project.directoryEntries["Sources/Index"] = [
            DirectoryEntry(name: "SymbolIndex.swift", path: "Sources/Index/SymbolIndex.swift", isDirectory: false),
            DirectoryEntry(name: "Parser.swift", path: "Sources/Index/Parser.swift", isDirectory: false),
        ]
        project.referenceResult = ReferenceSearchResult(
            references: [
                Reference(path: "Sources/Index/SymbolIndex.swift", line: 8,
                          previewText: "    func buildIndex(files: [URL]) {", matchRanges: [MatchRange(start: 9, end: 19)],
                          isDefinition: true),
                Reference(path: "Sources/App.swift", line: 42,
                          previewText: "        index.buildIndex(files: sources)", matchRanges: [MatchRange(start: 14, end: 24)],
                          isDefinition: false),
                Reference(path: "Tests/SymbolIndexTests.swift", line: 17,
                          previewText: "        sut.buildIndex(files: fixtures)", matchRanges: [MatchRange(start: 12, end: 22)],
                          isDefinition: false),
            ],
            total: 3, truncated: false, limit: 500
        )

        model.projectRootPath = "/repo/code-navigator-mac"
        await model.fileTree.loadProject(name: "code-navigator-mac", rootPath: "/repo/code-navigator-mac")
        await model.fileTree.perform(.expand(path: "Sources"))
        await model.fileTree.perform(.expand(path: "Sources/Index"))
        await model.fileTree.perform(.select(path: "Sources/Index/SymbolIndex.swift"))

        model.handle(sessionState: .connected)
        model.handle(indexState: .ready)
        model.handle(editorStatus: EditorStatus(
            filePath: "/repo/code-navigator-mac/Sources/Index/SymbolIndex.swift",
            isDirty: true, cursorLine: 8, cursorColumn: 5, mode: .normal, inputMode: .vim
        ))
        model.handle(snapshot: codeSnapshot)
        await search.showReferences(to: "buildIndex")
    }

    /// A few lines of syntax-coloured code, standing in for what Neovim draws.
    private var codeSnapshot: EditorGridSnapshot {
        func run(_ text: String, _ column: Int, _ rgb: Int, italic: Bool = false) -> EditorTextRun {
            EditorTextRun(
                text: text,
                style: EditorTextStyle(foreground: EditorColor(packedRGB: rgb), isItalic: italic),
                startColumn: column,
                cellWidth: DisplayWidth.cells(of: text)
            )
        }
        let keyword = 0xC792EA, type = 0x57C7B8, plain = 0xE8E8ED, comment = 0x8B92A0

        return EditorGridSnapshot(
            columns: 80, rows: 6,
            lines: [
                EditorGridLine(runs: [run("import ", 0, keyword), run("Foundation", 7, type)]),
                EditorGridLine(runs: []),
                EditorGridLine(runs: [run("/// 정방향·역방향 인덱스", 0, comment, italic: true)]),
                EditorGridLine(runs: [run("struct ", 0, keyword), run("SymbolIndex", 7, type), run(" {", 18, plain)]),
                EditorGridLine(runs: [run("    func ", 0, keyword), run("buildIndex", 9, type), run("(files: [URL]) {", 19, plain)]),
                EditorGridLine(runs: [run("    }", 0, plain)]),
            ],
            cursor: EditorCursorPosition(row: 4, column: 9),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0xE8E8ED),
            defaultBackground: EditorColor(packedRGB: 0x1B1B1F),
            revision: 1
        )
    }

    /// Lays the window out at a size and rasterises it. Returns the PNG data.
    private func render(
        model: AppModel,
        search: SearchModel,
        size: CGSize,
        named name: String
    ) -> Data? {
        let hosting = NSHostingView(rootView: MainWindowView(model: model, search: search))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("\(name): 비트맵 표현을 만들지 못했다")
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        guard let png = representation.representation(using: .png, properties: [:]) else {
            Issue.record("\(name): PNG 인코딩에 실패했다")
            return nil
        }

        if let directory = outputDirectory {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }

    /// How many distinct colours the rasterised window contains.
    ///
    /// A window that laid out but drew nothing still produces a valid PNG — of one flat
    /// colour. Counting distinct colours separates "rasterised" from "rasterised something".
    private func distinctColourCount(_ png: Data) -> Int {
        guard let image = NSBitmapImageRep(data: png) else { return 0 }
        var colours: Set<UInt32> = []
        let width = image.pixelsWide
        let height = image.pixelsHigh
        // Sampled on a grid: every pixel of a large window is far more work than this needs.
        for y in stride(from: 0, to: height, by: max(1, height / 60)) {
            for x in stride(from: 0, to: width, by: max(1, width / 60)) {
                guard let colour = image.colorAt(x: x, y: y) else { continue }
                let packed = UInt32(colour.redComponent * 255) << 16
                    | UInt32(colour.greenComponent * 255) << 8
                    | UInt32(colour.blueComponent * 255)
                colours.insert(packed)
            }
        }
        return colours.count
    }

    @Test(
        "프로젝트가 열린 창이 화면 없이 래스터화된다",
        arguments: [
            ("large-1600x1000", CGSize(width: 1600, height: 1000)),
            ("small-1000x700", CGSize(width: 1000, height: 700)),
            ("narrow-820x620", CGSize(width: 820, height: 620)),
        ]
    )
    func theProjectWindowRasterises(name: String, size: CGSize) async {
        let (model, search, project, editor) = makeModels()
        await populate(model: model, search: search, project: project, editor: editor)

        guard let png = render(model: model, search: search, size: size, named: "main-\(name)") else {
            return
        }
        #expect(png.count > 1_000, "PNG가 너무 작다 — 아무것도 그리지 않았을 수 있다")
        #expect(
            distinctColourCount(png) >= 3,
            "창이 단색이다 — 레이아웃은 됐지만 아무것도 그려지지 않았다"
        )
    }

    @Test("프로젝트 열기 화면도 래스터화된다")
    func theWelcomeScreenRasterises() {
        let (model, search, _, _) = makeModels()
        guard let png = render(
            model: model, search: search,
            size: CGSize(width: 1000, height: 700), named: "welcome-1000x700"
        ) else {
            return
        }
        #expect(distinctColourCount(png) >= 3)
    }

    @Test("편집 세션 끊김 화면도 래스터화된다")
    func theLostSessionScreenRasterises() {
        let (model, search, _, _) = makeModels()
        model.projectRootPath = "/repo"
        model.handle(sessionState: .disconnected(reason: "프로세스가 종료되었습니다"))
        guard let png = render(
            model: model, search: search,
            size: CGSize(width: 1000, height: 700), named: "session-lost-1000x700"
        ) else {
            return
        }
        #expect(distinctColourCount(png) >= 3)
    }

    @Test("라이트와 다크가 서로 다르게 렌더된다 (REQ-011 AC-4)")
    func theTwoAppearancesDiffer() async {
        // The appearance is read from the environment at draw time, so this also proves the
        // rasterisation path honours it rather than baking one theme in.
        let (model, search, project, editor) = makeModels()
        await populate(model: model, search: search, project: project, editor: editor)

        let previous = NSApp?.appearance
        defer { NSApp?.appearance = previous }

        var renders: [String: Data] = [:]
        for name in ["light", "dark"] {
            NSApp?.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
            if let png = render(
                model: model, search: search,
                size: CGSize(width: 1000, height: 700), named: "main-1000x700-\(name)"
            ) {
                renders[name] = png
            }
        }

        guard let light = renders["light"], let dark = renders["dark"] else {
            return
        }
        #expect(light != dark, "라이트와 다크가 같은 픽셀을 낸다 — 테마가 렌더에 반영되지 않았다")
    }
}
