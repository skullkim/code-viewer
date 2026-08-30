import Testing
import AppKit
import SwiftUI
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// The gate's visual regression step (design §4, REQ-011 AC-4).
///
/// Two real defects shipped today with every test green: the editor drew **no Korean at
/// all**, and toolbar modifier symbols looked run together. Nothing in the suite could have
/// caught either, because nothing asked about pixels — the checks were about layout numbers
/// and presentation values, both of which were correct while the screen was wrong.
///
/// Deliberately **not** a golden-image diff. Exact-match pixel comparison fails on font
/// smoothing differences between machines and OS versions, and a gate that cries wolf gets
/// disabled. Every assertion here is a statement the design document makes — this surface
/// is that token, this window drops that label, this text is actually drawn — so a failure
/// names the rule it broke.
@MainActor
@Suite("디자인 회귀 게이트 — 화면이 명세대로 그려지는가")
struct DesignRegressionGateTests {

    // MARK: 렌더

    /// Renders the window offscreen at the given scale and appearance.
    ///
    /// Scale is chosen rather than inherited: offscreen backing scale is always 1, and at 1x
    /// a glyph collision is indistinguishable from rasterisation blur — which is exactly the
    /// ambiguity that left today's toolbar question open.
    private func renderWindow(
        size: CGSize,
        scale: Int = 2,
        appearance: NSAppearance.Name = .aqua,
        seed: (AppModel, FakeProjectSession, FakeEditorSession) async -> Void = { _, _, _ in }
    ) async -> NSBitmapImageRep? {
        let project = FakeProjectSession()
        let editor = FakeEditorSession()
        let model = AppModel(
            projectSession: project,
            editorSession: editor,
            workspace: RecordingWorkspace(),
            storage: InMemoryKeyValueStore(),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        model.projectRootPath = "/repo"
        await seed(model, project, editor)

        let hosting = NSHostingView(
            rootView: MainWindowView(model: model, search: SearchModel(projectSession: project))
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        // Pinned: a test machine in dark mode would otherwise fail every light-token check.
        hosting.appearance = NSAppearance(named: appearance)
        hosting.layoutSubtreeIfNeeded()

        return Self.rasterise(hosting, scale: scale)
    }

    static func rasterise(_ view: NSView, scale: Int) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width) * scale,
                pixelsHigh: Int(bounds.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else {
            return nil
        }
        // Pixel count is scaled while the logical size is not, which is what gives the
        // context its scale factor.
        representation.size = bounds.size

        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    /// A grid snapshot whose text is entirely Korean.
    private static func koreanSnapshot() -> EditorGridSnapshot {
        let lines = ["한글이 실제로 그려지는가", "두 번째 줄도 한글이다", "세 번째 줄"]
        return snapshot(lines: lines)
    }

    private static func asciiSnapshot() -> EditorGridSnapshot {
        snapshot(lines: ["import Foundation", "struct SymbolIndex {", "}"])
    }

    private static func snapshot(lines: [String]) -> EditorGridSnapshot {
        EditorGridSnapshot(
            columns: 100,
            rows: lines.count,
            lines: lines.map { text in
                EditorGridLine(runs: [
                    EditorTextRun(text: text, style: .plain, startColumn: 0, cellWidth: text.count)
                ])
            },
            cursor: EditorCursorPosition(row: 0, column: 0),
            mode: .normal,
            defaultForeground: EditorColor(packedRGB: 0x1C1C1E),
            defaultBackground: EditorColor(packedRGB: 0xFFFFFF),
            revision: 1
        )
    }

    private static let largeWindow = CGSize(width: 1600, height: 1000)
    private static let narrowWindow = CGSize(width: 1000, height: 700)

    /// The toolbar band in pixel space, at scale 2.
    private func toolbarBand(width: CGFloat, scale: CGFloat = 2) -> CGRect {
        CGRect(x: 0, y: 0, width: width * scale, height: ShellLayout.Metrics.titleBarHeight * scale)
    }

    /// The editor band — between the tree and the panel, below the toolbar.
    private func editorBand(layout: ShellLayout, size: CGSize, scale: CGFloat = 2) -> CGRect {
        CGRect(
            x: layout.treeWidth * scale,
            y: ShellLayout.Metrics.titleBarHeight * scale,
            width: layout.editorWidth * scale,
            height: (size.height - ShellLayout.Metrics.titleBarHeight - ShellLayout.Metrics.statusBarHeight) * scale
        )
    }

    // MARK: 그려지기는 하는가

    @Test("창이 빈 캔버스가 아니다")
    func theWindowIsNotABlankCanvas() async {
        guard let rendered = await renderWindow(size: Self.largeWindow) else {
            Issue.record("오프스크린 래스터화가 실패했다")
            return
        }
        let colours = PixelAssertions.distinctColourCount(rendered)
        #expect(colours > 3, "구별되는 색이 \(colours)개뿐 — 레이아웃만 되고 아무것도 안 그려졌다")
    }

    // MARK: 토큰 (§4.1)

    @Test("사이드바가 라이트 토큰 색으로 칠해진다")
    func theSidebarCarriesItsLightToken() async {
        guard let rendered = await renderWindow(size: Self.largeWindow) else {
            Issue.record("래스터화 실패")
            return
        }
        #expect(
            PixelAssertions.matches(
                rendered, atX: 120, y: rendered.pixelsHigh / 2,
                token: DesignTokens.backgroundSidebar.light
            ),
            "사이드바 픽셀이 bg-sidebar(#F2F2F4)가 아니다"
        )
    }

    @Test("다크 모드에서는 다크 토큰 색으로 칠해진다 (REQ-011 AC-4)")
    func theSidebarCarriesItsDarkToken() async {
        guard let rendered = await renderWindow(size: Self.largeWindow, appearance: .darkAqua) else {
            Issue.record("래스터화 실패")
            return
        }
        #expect(
            PixelAssertions.matches(
                rendered, atX: 120, y: rendered.pixelsHigh / 2,
                token: DesignTokens.backgroundSidebar.dark
            ),
            "다크 사이드바 픽셀이 bg-sidebar 다크값(#232327)이 아니다"
        )
    }

    // MARK: 반응형 (§4.4)

    @Test("좁은 창은 툴바 단축키 라벨을 뺀다")
    func theNarrowWindowDropsShortcutLabels() async {
        // §4.4: 1100 미만에서 kbd 라벨을 숨긴다. 픽셀로 물으면 툴바에 남는 잉크 덩어리
        // 수가 줄어야 한다 — 라벨 세 개가 사라지기 때문이다.
        guard let wide = await renderWindow(size: Self.largeWindow),
              let narrow = await renderWindow(size: Self.narrowWindow)
        else {
            Issue.record("래스터화 실패")
            return
        }

        let wideRuns = PixelAssertions.inkRunCount(wide, band: toolbarBand(width: Self.largeWindow.width))
        let narrowRuns = PixelAssertions.inkRunCount(narrow, band: toolbarBand(width: Self.narrowWindow.width))

        #expect(wideRuns > narrowRuns, "넓은 창 툴바 덩어리 \(wideRuns) · 좁은 창 \(narrowRuns) — 단축키 라벨이 빠지지 않았다")
    }

    // MARK: 오늘의 결함 ①  한글이 실제로 그려지는가

    @Test("에디터에 한글이 실제로 그려진다")
    func koreanIsActuallyDrawnInTheEditor() async {
        // 오늘 이 결함이 모든 테스트를 초록으로 통과했다. 기존 픽셀 테스트가 한글을
        // **위치 검증에만** 썼기 때문이다 — "어디에 있나"는 물었고 "있기는 한가"는
        // 묻지 않았다. 글리프가 없어 전부 스킵돼도 위치 단언은 통과한다.
        let layout = ShellLayout.resolve(windowSize: Self.largeWindow)
        let band = editorBand(layout: layout, size: Self.largeWindow)

        guard let withKorean = await renderWindow(size: Self.largeWindow, seed: { model, _, _ in
            model.handle(snapshot: Self.koreanSnapshot())
        }) else {
            Issue.record("래스터화 실패")
            return
        }
        guard let empty = await renderWindow(size: Self.largeWindow) else {
            Issue.record("래스터화 실패")
            return
        }

        let korean = PixelAssertions.inkPixelCount(withKorean, band: band)
        let blank = PixelAssertions.inkPixelCount(empty, band: band)

        #expect(korean > blank, "한글 스냅샷의 에디터 잉크 \(korean) ≤ 빈 에디터 \(blank) — 한글이 한 획도 안 그려졌다")
    }

    @Test("한글이 영문과 비슷한 양의 잉크를 남긴다")
    func koreanDrawsAsMuchAsAscii() async {
        // 위 테스트는 "조금이라도 그려졌나"만 본다. 일부 글자만 폴백에 걸리는 경우를
        // 잡으려면 양을 비교해야 한다 — 한글이 영문의 몇 분의 일이면 대부분 스킵된 것이다.
        let layout = ShellLayout.resolve(windowSize: Self.largeWindow)
        let band = editorBand(layout: layout, size: Self.largeWindow)

        guard let korean = await renderWindow(size: Self.largeWindow, seed: { model, _, _ in
            model.handle(snapshot: Self.koreanSnapshot())
        }),
            let ascii = await renderWindow(size: Self.largeWindow, seed: { model, _, _ in
                model.handle(snapshot: Self.asciiSnapshot())
            })
        else {
            Issue.record("래스터화 실패")
            return
        }

        let koreanInk = PixelAssertions.inkPixelCount(korean, band: band)
        let asciiInk = PixelAssertions.inkPixelCount(ascii, band: band)

        #expect(asciiInk > 0, "영문조차 안 그려졌다 — 기준 자체가 무너졌다")
        #expect(
            Double(koreanInk) > Double(asciiInk) * 0.4,
            "한글 잉크 \(koreanInk) 가 영문 \(asciiInk) 의 40% 미만 — 상당수 글자가 스킵됐다"
        )
    }

    // MARK: 오늘의 결함 ②  수식키가 겹치지 않는가

    @Test("덩어리 세기가 아는 글자를 실제로 갈라낸다")
    func theMetricSeparatesKnownGlyphs() {
        // 검사기를 먼저 검사한다. 문턱값이 낮으면 안티에일리어싱이 글자 사이를 이어
        // 붙여 **또렷하게 떨어진 글자도 한 덩어리로 읽는다** — 그 상태의 "겹쳤다"는
        // 판정은 대상이 아니라 자를 탓하는 것이다. 실측으로 교정한 값에서 확인한다.
        for (text, expected) in [("ABC", 3), ("XYZ", 3), ("⌘P", 2)] {
            guard let rendered = Self.renderShortcutLabel(text) else {
                Issue.record("래스터화 실패: \(text)")
                continue
            }
            let runs = PixelAssertions.inkRunCount(
                rendered,
                band: CGRect(x: 0, y: 0, width: rendered.pixelsWide, height: rendered.pixelsHigh)
            )
            #expect(runs == expected, "\(text) 가 \(runs) 덩어리 — 지표가 글자를 못 가른다")
        }
    }

    @Test("수식키 기호가 서로 겹치지 않는다")
    func modifierSymbolsDoNotCollide() {
        // 옳은 지표는 폭이 아니라 **덩어리 수**다. 뭉개진 `⇧⌘F` 와 좁게 붙은 `⇧⌘F` 는
        // 차지하는 폭이 거의 같아서 폭으로는 갈리지 않는다.
        //
        // 하한은 3이다. 한때 2로 낮췄던 것은 내가 **툴바가 쓰지 않는 모노스페이스
        // 폰트**로 재고 있었기 때문이고, 그 수치는 앱의 렌더가 아니라 옛 폰트의 렌더였다.
        // 실제 폰트(`.shortcutLabel()` = 시스템)에서는 세 글리프가 따로 그려진다 —
        // 시니어가 폰트 교체로 고친 결함이 바로 그것이다. 하한을 2로 두면 게이트가
        // **자기가 잡으라고 만들어진 결함을 합격시킨다**.
        for shortcut in ["⇧⌘F", "⌥⌘0", "⌃⌘R"] {
            guard let rendered = Self.renderShortcutLabel(shortcut) else {
                Issue.record("단축키 라벨 래스터화 실패: \(shortcut)")
                continue
            }
            let runs = PixelAssertions.inkRunCount(
                rendered,
                band: CGRect(x: 0, y: 0, width: rendered.pixelsWide, height: rendered.pixelsHigh)
            )
            #expect(runs >= 3, "\(shortcut) 이 \(runs) 덩어리 — 수식키 기호가 겹쳤다")
        }
    }

    /// Draws one shortcut label on its own, in the font design §4.2 assigns it.
    ///
    /// Rendered standalone rather than located inside the toolbar: the question is whether
    /// these glyphs draw separately at this size, and a band cropped out of the window would
    /// have to be re-aimed every time the toolbar's layout shifts.
    static func renderShortcutLabel(_ text: String, scale: Int = 3) -> NSBitmapImageRep? {
        let label = Text(text)
            // The font the toolbar actually uses. Rendering the monospaced face here
            // measured a font the app no longer draws with — and reported its collision as
            // the app's, which is how a checker ends up certifying the defect it was built
            // to catch.
            .font(.shortcutLabel())
            .foregroundStyle(Color.black)
            .padding(4)
            .background(Color.white)

        let hosting = NSHostingView(rootView: label)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return rasterise(hosting, scale: scale)
    }
}
