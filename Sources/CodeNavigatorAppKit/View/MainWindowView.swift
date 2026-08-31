import AppKit
import SwiftUI
import CodeNavigatorContract

/// The main window (design §3 W-1).
///
/// The order of the stack is the point. The status bar is placed with a fixed height and
/// the content takes what remains, so the editor is never in a position to push the status
/// bar off screen — the failure the designer hit in the prototype at 820x620 (ADR-0104).
/// The status bar is the only permanent surface for the input mode (REQ-010 AC-3) and the
/// index state (REQ-009), so losing it breaks two acceptance criteria at once.
///
/// Which panes go where is decided by `ShellComposition` rather than here, so that the
/// wiring is something a test can state. Views that compile and pass their own tests can
/// still fail to reach the user if nothing mounts them.
public struct MainWindowView: View {
    private let model: AppModel
    private let search: SearchModel

    /// Who holds the keyboard, for the whole window.
    ///
    /// Owned here rather than by any one surface, because the question only has a single
    /// answer if a single thing answers it. While each view decided for itself they
    /// disagreed, and closing the symbol-search modal left the editor unreachable.
    @State private var focus = KeyboardFocusCoordinator()

    /// The tab a close was requested for, while the confirmation is up (W-13).
    @State private var pendingClose: PendingTabClose?

    public init(model: AppModel, search: SearchModel) {
        self.model = model
        self.search = search
    }

    public var body: some View {
        @Bindable var search = search

        GeometryReader { proxy in
            let tabBar = ProjectTabBarPresentation.make(
                tabs: model.tabs.descriptors(),
                activeTabID: model.tabs.activeTabID?.rawValue.uuidString,
                barWidth: proxy.size.width
            )
            // Widths the user dragged to and panes they hid are both restored on launch
            // (REQ-011 AC-3). Hiding gives the space back to the editor, and a neighbour
            // that was squeezed by the hidden pane reclaims its preferred width.
            let shell = ShellVisibilityLayout.resolve(
                windowSize: proxy.size,
                preferredTreeWidth: model.shell.treeWidth,
                preferredPanelWidth: model.shell.panelWidth,
                isTreeVisible: model.shell.isTreeVisible,
                isPanelVisible: model.shell.isPanelVisible
            )
            let layout = shell.layout
            let availability = model.menuAvailability

            VStack(spacing: 0) {
                ToolbarView(
                    toolbar: ToolbarPresentation.make(
                        projectName: model.fileTree.projectName,
                        editorStatus: model.editorStatus,
                        availability: availability,
                        layout: layout,
                        renderView: model.renderViewState
                    ),
                    inputMode: model.inputMode,
                    isModeSwitchEnabled: availability.isEnabled(.toggleInputMode),
                    onCommand: { command in Task { await perform(command) } },
                    onSelectInputMode: { mode in Task { await model.setInputMode(mode) } }
                )
                .frame(height: layout.titleBarHeight)

                Divider()

                // A fixed chrome row, never a share of the remainder (ADR-0108). The editor
                // once grew into the status bar and pushed it off screen; a third fixed row
                // is a third chance to repeat that, so the height comes from the layout and
                // the bar is never asked how tall it would like to be.
                //
                // Shown whenever a project is open, including with a single tab (§12 ruling
                // 1): the toolbar's project popup was removed, so hiding the bar would
                // leave the open project's name nowhere on screen.
                if tabBar.isVisible {
                    ProjectTabBarView(
                        bar: tabBar,
                        onAction: { action in Task { await performTabAction(action) } }
                    )
                    // No `Divider()` here: the bar draws its own bottom hairline. Adding one
                    // stacked a second separator under the first and made the band taller
                    // than the constant every layout calculation uses (QA measured 38 for a
                    // 32pt bar).
                    .frame(height: layout.tabBarHeight)
                }

                panes(shell: shell, windowWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                StatusBarView(
                    layout: layout,
                    presentation: model.statusBar(for: layout),
                    indexState: model.indexState,
                    indexDetails: IndexDetailsPresentation.make(
                        indexState: model.indexState,
                        statistics: model.indexStatistics,
                        now: Date(),
                        calendar: .current
                    )
                )
                .frame(height: layout.statusBarHeight)
            }
            .background(DesignTokens.backgroundWindow.dynamicColor)
            .sheet(isPresented: Binding(
                get: { MissingTabsPresentation.make(missing: model.missingTabs) != nil },
                set: { shown in if !shown { model.dismissMissingTabs() } }
            )) {
                if let presentation = MissingTabsPresentation.make(missing: model.missingTabs) {
                    MissingTabsSheetView(presentation: presentation) {
                        model.dismissMissingTabs()
                    }
                }
            }
            .sheet(item: $pendingClose) { pending in
                TabCloseConfirmationView(
                    confirmation: TabCloseConfirmation.make(
                        projectName: model.tabs.tabs.first { $0.id == pending.tabID }?.name ?? "",
                        dirtyFiles: pending.dirtyFiles,
                        saveState: pending.saveState
                    ) ?? TabCloseConfirmation.make(projectName: "", dirtyFiles: [""])!,
                    onAction: { action in Task { await performCloseAction(action) } }
                )
            }
            .overlay {
                if search.isShowingSymbolSearch {
                    SymbolSearchModalView(
                        presentation: search.symbolPresentation(indexState: model.indexState, now: Date()),
                        query: search.symbolSearchQuery,
                        onAction: { action in Task { await perform(action) } }
                    )
                    .onAppear { focus.surfaceDidOpen(.symbolSearchField) }
                    // Returns the keyboard to whoever had it. Without this the modal
                    // borrows and never gives back, and ⌘P — the core flow — ends the
                    // session's ability to type.
                    .onDisappear { focus.surfaceDidClose(.symbolSearchField) }
                }
            }
        }
    }

    // MARK: Panes

    @ViewBuilder
    private func panes(shell: ShellVisibilityLayout, windowWidth: CGFloat) -> some View {
        let layout = shell.layout
        let mounted = ShellComposition.panes(
            hasOpenProject: model.projectRootPath != nil,
            layout: layout,
            isTreeVisible: shell.isTreeMounted,
            isPanelVisible: shell.isPanelMounted
        )

        if mounted == [.projectOpen] {
            projectOpenPane
        } else {
            HStack(spacing: 0) {
                if mounted.contains(.fileTree),
                   ShellComposition.placement(of: .fileTree, layout: layout) == .column {
                    fileTreePane
                        .frame(width: layout.treeWidth)
                    ShellSplitter(width: layout.treeWidth, direction: .trailing) { proposed in
                        // Clamped against the window, not just the design limits: without
                        // this the divider lags the pointer and stores a width that was
                        // never rendered, which reopens at a split the user never chose.
                        model.shell.setTreeWidth(ShellSplitDrag.treeWidth(
                            draggedTo: proposed,
                            windowWidth: windowWidth,
                            panelWidth: layout.panelWidth,
                            panelPlacement: layout.panelPlacement
                        ))
                    }
                }

                editorPane
                    .frame(maxWidth: .infinity)

                if mounted.contains(.referencePanel),
                   ShellComposition.placement(of: .referencePanel, layout: layout) == .column {
                    ShellSplitter(width: layout.panelWidth, direction: .leading) { proposed in
                        model.shell.setPanelWidth(ShellSplitDrag.panelWidth(
                            draggedTo: proposed,
                            windowWidth: windowWidth,
                            treeWidth: layout.treeWidth,
                            treePlacement: layout.treePlacement
                        ))
                    }
                    referencePane
                        .frame(width: layout.panelWidth)
                }
            }
            .overlay(alignment: .topTrailing) {
                // Below 900pt the panel floats over the editor instead of taking a column
                // (§4.4), so it costs the editor no width.
                if mounted.contains(.referencePanel),
                   ShellComposition.placement(of: .referencePanel, layout: layout) == .overlay {
                    referencePane
                        .frame(width: layout.panelWidth)
                        .shadow(radius: 12)
                }
            }
        }
    }

    private var projectOpenPane: some View {
        ProjectOpenView(
            screen: ProjectOpenPresentation.make(
                recentProjects: model.recentProjects.projects(),
                phase: projectOpenPhase,
                now: Date(),
                calendar: .current,
                homeDirectory: NSHomeDirectory()
            ),
            onAction: { action in Task { await perform(action) } }
        )
    }

    private var fileTreePane: some View {
        FileTreeView(
            tree: model.fileTree.presentation,
            ownsKeyboard: focus.owner == .fileTree,
            onClaimKeyboard: { focus.userFocused(.fileTree) },
            onAction: { action in Task { await model.fileTree.perform(action) } }
        )
    }

    private var editorPane: some View {
        ZStack {
            EditorGridView(
                frame: model.gridFrame,
                isInputBlocked: model.isEditorInputBlocked,
                editorMode: model.editorStatus?.mode ?? .normal,
                inputMode: model.inputMode,
                ownsKeyboard: focus.owner == .editor,
                onKey: { notation in Task { await model.sendKeys(notation) } },
                onMouse: { event in Task { await model.sendMouse(event) } },
                onGridSizeChange: { columns, rows in
                    Task { await model.resizeGrid(columns: columns, rows: rows) }
                },
                onClaimKeyboard: { focus.userFocused(.editor) }
            )

            // 02b 237행: **에디터 위에 얹는다.** Neovim 그리드는 크기가 바뀌지 않고 가려질
            // 뿐이다 — 사용자 문장이 "렌더링 기능**도** 넣어줘"였고, 그건 더하기이지
            // 대체가 아니다. 소스로 돌아가면 커서·undo·더티가 그대로 있다.
            if model.renderViewState.isShowingRender,
               let path = model.editorStatus?.filePath,
               let root = model.projectRootPath {
                RenderSurface(
                    screen: RenderDocumentPresentation.make(
                        fileName: PathDisplay.fileName(path),
                        phase: model.render.phase,
                        hasPreviousDocument: !model.render.html.isEmpty,
                        elapsedSeconds: nil
                    ),
                    blocked: BlockedResourcePresentation.make(blocked: model.render.blocked),
                    html: model.render.html,
                    // 활성 탭에서 추론하지 않는다 — 모델이 문서를 읽을 때 쓴 그 경로를
                    // 그대로 넘긴다. `gt` 로 탭이 옮겨가면 추론은 맞아 보이는 방식으로 틀린다.
                    documentRelativePath: model.render.documentRelativePath ?? path,
                    projectRoot: model.render.projectRoot ?? root,
                    onAction: { action in
                        switch action {
                        case .showSource: model.toggleRenderView()
                        case .retry: model.render.show(path: path, root: root, tab: model.tabs.activeTabID ?? ProjectTabIdentifier())
                        }
                    },
                    onNavigation: { navigation in
                        Task { await follow(navigation) }
                    }
                )
            }

            // The overlay covers the editor and nothing else: the index outlives the edit
            // session, so the tree and the panels stay usable and at full brightness
            // (design §3 W-8).
            if let overlay = model.editSessionOverlay {
                EditSessionOverlayView(overlay: overlay) { action in
                    Task { await perform(action) }
                }
            }

            if let candidates = model.definitionCandidates, let name = candidates.first?.name {
                DefinitionCandidatesView(
                    presentation: DefinitionCandidatePresentation.make(symbolName: name, definitions: candidates),
                    onSelect: { definition in Task { await model.openDefinition(definition) } },
                    onShowReferences: { Task { await search.showReferences(to: name) } },
                    onDismiss: { model.dismissDefinitionCandidates() }
                )
            }
        }
    }

    private var referencePane: some View {
        @Bindable var search = search

        return SidePanelView(
            selectedTab: $search.selectedTab,
            referenceContent: {
                ReferencePanelView(
                    panel: search.referencePresentation(indexState: model.indexState),
                    selectedReferenceID: search.selectedReferenceID,
                    onSelect: { reference in
                        search.selectReference(reference)
                        Task { await model.openLocation(path: reference.path, line: reference.line) }
                    }
                )
            },
            searchContent: {
                TextSearchPanelView(
                    panel: search.textSearchPresentation(),
                    query: search.textSearchQuery,
                    mode: search.textSearchMode,
                    selectedItemID: search.selectedTextSearchItemID,
                    // The field bound `.focused` and nothing ever set it, so it never took
                    // the keyboard and REQ-008 had no way in from the UI at all.
                    hasKeyboard: focus.owner == .textSearchField,
                    onAction: { action in Task { await perform(action) } },
                    onClaimKeyboard: { focus.userFocused(.textSearchField) }
                )
                // The panel had no open path at all, so its field could never be told it
                // had the keyboard: typing there went to the editor and REQ-008 had no
                // route from the UI. The modal had `.onAppear` and the panel did not —
                // twice over, once in the views and once in the coordinator.
                .onAppear { focus.surfaceDidOpen(.textSearchField) }
                .onDisappear { focus.surfaceDidClose(.textSearchField) }
            }
        )
    }

    // MARK: 탭

    /// Routes what the tab bar asks for (REQ-012 AC-1·AC-3·AC-5).
    ///
    /// Closing is a request rather than an instruction: a tab with unsaved work has to go
    /// through the confirmation sheet first (W-13). Until that sheet exists, a close is
    /// carried out directly — and that is a gap worth seeing rather than hiding, because
    /// the alternative is a close button that silently does nothing.
    /// 렌더된 문서 안의 링크를 따라간다 (REQ-013, INV-6).
    ///
    /// 판정은 `RenderNavigationPolicy` 가 이미 끝냈다. 여기서는 그 결정을 수행만 한다 —
    /// 규칙을 여기서 다시 물으면 정책이 두 벌이 되고, **약한 쪽이 실제 경계가 된다.**
    private func follow(_ navigation: RenderNavigation) async {
        switch navigation {
        case .scrollToFragment:
            // 웹뷰 안에서 끝난다. 문서를 다시 읽지 않는다 — 읽으면 스크롤이 처음으로 간다.
            break

        case .openInTab(let relativePath, _):
            // 라인 번호는 소스에만 있는 개념이라 링크는 파일만 연다(02b F-14 5).
            // `asRendered` 는 여기서 안 본다 — 새 파일을 렌더로 열지 소스로 열지는
            // `RenderViewSelection` 이 이미 아는 것이고, 두 곳이 답하면 갈린다.
            await model.openFile(atRelativePath: relativePath, line: nil)

        case .openInBrowser(let url):
            // 원격 내용은 앱 안에서 절대 그리지 않는다(INV-6). 브라우저로 넘긴다.
            guard let target = URL(string: url) else { return }
            NSWorkspace.shared.open(target)

        case .refuse(let refusal):
            model.show(StatusMessage(kind: .error, text: refusal.statusMessage))
        }
    }

    private func performTabAction(_ action: ProjectTabBarAction) async {
        switch action {
        case .activate(let tabID):
            // The bar speaks in string identities; the engine's are UUIDs. Resolved through
            // the open tabs rather than reconstructed, so a stale row cannot name a tab that
            // was closed and reopened.
            guard let tab = model.tabs.tabs.first(where: { $0.id.rawValue.uuidString == tabID }) else { return }
            await model.activateTab(tab.id)
        case .requestClose(let tabID):
            guard let tab = model.tabs.tabs.first(where: { $0.id.rawValue.uuidString == tabID }) else { return }
            // A clean tab closes with no friction. Asking where there is nothing to lose is
            // how people learn to dismiss the sheet unread, and then it fails the one time
            // it matters (W-13).
            let dirty = await model.dirtyFiles(in: tab)
            guard !dirty.isEmpty else {
                await model.closeTab(tab.id)
                return
            }
            pendingClose = PendingTabClose(tabID: tab.id, dirtyFiles: dirty, saveState: .idle)
        case .openProject:
            await MenuCommandRouter.perform(.openProject, model: model, search: search)
        }
    }

    /// Carries out what the user chose in the close sheet (W-13).
    ///
    /// `저장 후 닫기` waits for the save and only closes if it completed. Closing on a
    /// partial save would discard exactly the files that could not be written — the loss
    /// the sheet exists to prevent, performed with the user's consent.
    private func performCloseAction(_ action: TabCloseConfirmation.Action) async {
        guard let pending = pendingClose,
              let tab = model.tabs.tabs.first(where: { $0.id == pending.tabID })
        else {
            pendingClose = nil
            return
        }

        switch action {
        case .cancel:
            pendingClose = nil

        case .closeWithoutSaving:
            pendingClose = nil
            await model.closeTab(tab.id)

        case .saveAndClose:
            pendingClose = pending.saving()
            let outcome = await model.saveAll(in: tab)
            if outcome.isComplete {
                pendingClose = nil
                await model.closeTab(tab.id)
            } else {
                // The sheet stays, now naming what was written and what was refused.
                pendingClose = pending.failed(outcome)
            }
        }
    }

    // MARK: Commands

    private var projectOpenPhase: ProjectOpenPhase {
        if model.isOpeningProject {
            return .opening
        }
        guard let error = model.projectOpenError else {
            return .idle
        }
        return .failed(error as? NavigatorError ?? .invalidPath("\(error)"))
    }

    /// Routed through `MenuCommandRouter` so a toolbar button and its menu row cannot
    /// come to mean different things.
    private func perform(_ command: MenuCommand) async {
        await MenuCommandRouter.perform(command, model: model, search: search)
    }

    private func perform(_ action: EditSessionOverlayAction) async {
        switch action {
        case .restart, .recheck:
            await model.restartEditSession()
        }
    }

    private func perform(_ action: ProjectOpenAction) async {
        switch action {
        case .openProject:
            await MenuCommandRouter.perform(.openProject, model: model, search: search)
        case .openRecentProject(let path):
            await model.openProject(at: URL(fileURLWithPath: path))
        case .dismissFailure:
            model.dismissProjectOpenError()
        }
    }

    private func perform(_ action: SymbolSearchAction) async {
        switch action {
        case .queryChanged(let query):
            search.symbolSearchQuery = query
            await search.runSymbolSearch()
        case .moveSelection(let direction):
            search.moveSymbolSelection(direction)
        case .select(let index):
            search.selectSymbol(at: index)
        case .activate(let index):
            search.selectSymbol(at: index)
            guard let hit = search.symbolPresentation(indexState: model.indexState, now: Date()).selectedResult else {
                return
            }
            search.dismissSymbolSearch()
            await model.openLocation(path: hit.definition.path, line: hit.definition.line)
        case .dismiss:
            search.dismissSymbolSearch()
        }
    }

    private func perform(_ action: TextSearchAction) async {
        switch action {
        case .submit:
            await search.runTextSearch()
        case .queryChanged(let query):
            search.textSearchQuery = query
        case .modeChanged(let mode):
            search.textSearchMode = mode
            // Switching between literal and regular expression re-runs the search, so the
            // toggle shows its effect rather than waiting for another Enter.
            await search.runTextSearch()
        case .select(let itemID):
            guard let item = search.textSearchItem(withID: itemID) else { return }
            search.selectTextSearchItem(item)
            await model.openLocation(path: item.path, line: item.line)
        }
    }
}
