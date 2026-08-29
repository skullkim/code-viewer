import Testing
import CoreGraphics
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// Design §3 W-7 calls the status bar "this app's single surface for state". It carries
/// the input mode (REQ-010 AC-3) and the index state (REQ-009), and both of those are
/// acceptance criteria rather than decoration, so the table in the design is reproduced
/// here as a table of cases.
@Suite("StatusBarPresentation — 상태바 구성 (REQ-004·009·010·011, 02 §3 W-7)")
struct StatusBarPresentationTests {

    private let wideLayout = ShellLayout.resolve(windowSize: CGSize(width: 1600, height: 1000))
    private let narrowLayout = ShellLayout.resolve(windowSize: CGSize(width: 820, height: 620))

    private func status(
        path: String? = "/repo/Sources/Index/SymbolIndex.swift",
        dirty: Bool = false,
        mode: EditorMode = .normal,
        inputMode: InputMode = .vim,
        line: Int = 8,
        column: Int = 5
    ) -> EditorStatus {
        EditorStatus(
            filePath: path, isDirty: dirty, cursorLine: line, cursorColumn: column,
            mode: mode, inputMode: inputMode
        )
    }

    private func make(
        session: EditorSessionState = .connected,
        editorStatus: EditorStatus? = nil,
        index: IndexState = .ready,
        inputMode: InputMode = .vim,
        message: StatusMessage? = nil,
        layout: ShellLayout? = nil
    ) -> StatusBarPresentation {
        StatusBarPresentation.make(
            sessionState: session,
            editorStatus: editorStatus ?? status(inputMode: inputMode),
            indexState: index,
            inputMode: inputMode,
            message: message,
            projectRoot: "/repo",
            layout: layout ?? wideLayout
        )
    }

    // MARK: Input mode segment (REQ-010 AC-3)

    @Test("Vim 하위 모드가 각각 다른 칩과 색으로 표시된다")
    func vimSubModesEachGetTheirOwnChip() {
        let expected: [(EditorMode, String, StatusTone)] = [
            (.normal, "NORMAL", .success),
            (.insert, "INSERT", .accent),
            (.visual, "VISUAL", .purple),
            (.commandLine, "COMMAND", .warning),
        ]
        for (mode, label, tone) in expected {
            let bar = make(editorStatus: status(mode: mode), inputMode: .vim)
            #expect(bar.modeSegment.primaryLabel == label)
            #expect(bar.modeSegment.secondaryLabel == "Vim")
            #expect(bar.modeSegment.tone == tone)
        }
    }

    @Test("표준 모드는 하위 모드를 노출하지 않는다")
    func standardModeExposesNoSubMode() {
        // REQ-010 AC-2 says standard mode has no modes. Showing Neovim's internal mode
        // here would contradict that, and the app status bar is the single authority
        // (design §11 ruling 2).
        let bar = make(editorStatus: status(mode: .insert, inputMode: .standard), inputMode: .standard)
        #expect(bar.modeSegment.primaryLabel == "표준")
        #expect(bar.modeSegment.secondaryLabel == "맥 기본 편집")
        #expect(bar.modeSegment.tone == .accent)
    }

    @Test("세션이 끊기면 모드 세그먼트가 편집 불가로 바뀐다")
    func aLostSessionOverridesTheModeSegment() {
        let bar = make(session: .disconnected(reason: "프로세스 종료"))
        #expect(bar.modeSegment.primaryLabel == "편집 불가")
        #expect(bar.modeSegment.secondaryLabel == "세션 끊김")
        #expect(bar.modeSegment.tone == .danger)
    }

    @Test("명세에 없는 Neovim 모드도 이름을 그대로 보여준다 — 노멀로 위장하지 않는다")
    func unspecifiedModesAreShownRatherThanDisguised() {
        let bar = make(editorStatus: status(mode: .other("operator-pending")), inputMode: .vim)
        #expect(bar.modeSegment.primaryLabel == "OPERATOR-PENDING")
        #expect(bar.modeSegment.tone == .neutral, "명세에 색이 없는 모드를 노멀 초록으로 칠하면 오해를 만든다")
    }

    // MARK: Path and dirty state

    @Test("경로는 프로젝트 상대 경로로 표시된다")
    func pathIsShownRelativeToTheProject() {
        #expect(make().path == "Sources/Index/SymbolIndex.swift")
    }

    @Test("더티 버퍼는 경로 옆 표시로 드러난다")
    func aDirtyBufferIsMarked() {
        #expect(!make(editorStatus: status(dirty: false)).showsDirtyIndicator)
        #expect(make(editorStatus: status(dirty: true)).showsDirtyIndicator)
    }

    @Test("좁은 창에서는 경로가 앞쪽부터 축약된다")
    func theePathIsTruncatedInANarrowWindow() {
        let bar = make(
            editorStatus: status(path: "/repo/Sources/CodeNavigatorAppKit/Logic/ShellLayout.swift"),
            layout: narrowLayout
        )
        #expect(bar.path?.hasSuffix("ShellLayout.swift") == true)
        #expect(bar.path!.count <= bar.maximumPathCharacters)
    }

    @Test("이름 없는 버퍼는 경로가 없다")
    func anUnnamedBufferHasNoPath() {
        #expect(make(editorStatus: status(path: nil)).path == nil)
    }

    // MARK: Centre region

    @Test("메시지가 없으면 모드별 힌트가 표시된다")
    func theHintFillsTheCentreWhenThereIsNoMessage() {
        #expect(make(inputMode: .vim).centerText == ":w 저장 · gd 정의 이동 · ⌃O 뒤로")
        #expect(make(inputMode: .standard).centerText == "⌘S 저장 · ⌘B 정의 이동 · ⌘[ 뒤로")
    }

    @Test("메시지가 힌트를 덮는다")
    func aMessageTakesPrecedenceOverTheHint() {
        let bar = make(message: StatusMessage(kind: .success, text: "✓ 저장됨 · SymbolIndex.swift"))
        #expect(bar.centerText == "✓ 저장됨 · SymbolIndex.swift")
        #expect(bar.centerRole == .success)
    }

    @Test("세션 끊김 안내는 어떤 메시지보다 우선한다")
    func theLostSessionNoticeOutranksEverything() {
        // Design §3 W-7 marks it a standing error for as long as the session is down.
        // A transient "saved" toast must not hide the fact that keys go nowhere.
        let bar = make(
            session: .disconnected(reason: "프로세스 종료"),
            message: StatusMessage(kind: .success, text: "✓ 저장됨")
        )
        #expect(bar.centerText == "⚠ 편집 세션이 끊겼습니다 — ⌃⌘R로 재기동")
        #expect(bar.centerRole == .persistentError)
    }

    @Test("좁은 창에서는 힌트가 숨지만 메시지는 계속 보인다")
    func hintsHideInANarrowWindowButMessagesDoNot() {
        #expect(make(layout: narrowLayout).centerText.isEmpty)
        let bar = make(message: StatusMessage(kind: .error, text: "✕ 정의를 찾을 수 없습니다"), layout: narrowLayout)
        #expect(bar.centerText == "✕ 정의를 찾을 수 없습니다")
        #expect(bar.centerRole == .error)
    }

    // MARK: Right-hand chips

    @Test("인덱스 칩이 §6 상태 5종을 1:1로 반영한다")
    func theIndexChipMirrorsTheStateTable() {
        let cases: [(IndexState, String, StatusTone)] = [
            (.notIndexed, "인덱스 없음", .neutral),
            (.indexing(IndexProgress(completed: 120, total: 900)), "인덱싱 중 120/900", .accent),
            (.ready, "인덱스 최신", .success),
            (.updating, "갱신 중", .warning),
            (.rescanning(IndexProgress(completed: 30, total: 500)), "전체 재스캔 중 30/500", .warning),
        ]
        for (state, label, tone) in cases {
            let chip = make(index: state).indexChip
            #expect(chip.label == label)
            #expect(chip.tone == tone)
        }
    }

    @Test("비-최신 인덱스 상태는 직전 인덱스로 응답 중임을 툴팁으로 고지한다")
    func staleIndexStatesExplainThemselves() {
        // INV-1 and design §3 W-10: queries keep working during a rebuild, and the user is
        // told the answer may be a moment behind rather than left to guess.
        #expect(make(index: .ready).indexChip.tooltip == nil)
        for state in [IndexState.updating, .indexing(IndexProgress(completed: 1, total: 2)), .rescanning(IndexProgress(completed: 1, total: 2))] {
            #expect(make(index: state).indexChip.tooltip == "직전 인덱스로 응답 중 — 결과가 잠시 이전 상태일 수 있습니다")
        }
    }

    @Test("편집 세션 칩이 §6 상태 4종을 1:1로 반영한다")
    func theSessionChipMirrorsTheStateTable() {
        let cases: [(EditorSessionState, String, StatusTone)] = [
            (.notStarted, "편집 세션 미기동", .neutral),
            (.connecting, "편집 세션 연결 중", .warning),
            (.connected, "편집 세션 연결됨", .success),
            (.disconnected(reason: "종료"), "편집 세션 끊김", .danger),
        ]
        for (state, label, tone) in cases {
            let chip = make(session: state).sessionChip
            #expect(chip.label == label)
            #expect(chip.tone == tone)
        }
    }

    @Test("커서 위치는 버퍼 좌표로 표시되고 좁은 창에서 숨는다")
    func theCursorPositionUsesBufferCoordinates() {
        #expect(make(editorStatus: status(line: 8, column: 5)).cursorText == "8:5")
        #expect(make(layout: ShellLayout.resolve(windowSize: CGSize(width: 640, height: 480))).cursorText == nil)
    }

    @Test("어떤 창 폭에서도 모드 세그먼트와 인덱스 칩은 남는다")
    func theModeAndIndexNeverDisappear() {
        for width in [1600.0, 1000, 820, 720, 640] {
            let layout = ShellLayout.resolve(windowSize: CGSize(width: width, height: 600))
            let bar = make(layout: layout)
            #expect(!bar.modeSegment.primaryLabel.isEmpty, "폭 \(width)에서 모드가 사라졌다")
            #expect(!bar.indexChip.label.isEmpty, "폭 \(width)에서 인덱스 칩이 사라졌다")
        }
    }
}
