import Foundation
import Observation
import CodeNavigatorContract

/// The right panel's state: reference results and full-text results (design §3 W-5, W-6).
///
/// Kept apart from `AppModel` because the two panels answer to the index alone. They keep
/// working while the edit session is down (design §2 F-9), and putting them beside the
/// editor's state would invite wiring them to it.
@MainActor
@Observable
public final class SearchModel {

    private var storedReferencePhase: ReferencePhase = .idle
    private var storedReferenceSymbolName: String?
    private var storedSelectedReferenceID: String?

    private var storedTextSearchPhase: TextSearchPhase = .idle
    private var storedLastTextSearchResult: TextSearchResult?
    private var storedTextSearchElapsedSeconds: Double?
    private var storedSelectedTextSearchItemID: String?

    /// 결과를 가져온 탭. 활성 탭과 다르면 그 결과는 이 화면의 것이 아니다.
    private var resultsTabID: ProjectTabIdentifier?

    /// 지금 보관 중인 결과가 **다른 탭**의 것인가.
    ///
    /// 탭 전환 때 지우는 대신 읽을 때 판단한다 — 지우는 쪽은 누군가 호출을 잊으면 조용히
    /// 깨지고, 실제로 잊혀 있었다(`AppModel.activateTab` 은 이 모델에 아무 말도 하지 않는다).
    /// 파생값은 잊을 수가 없다.
    private var holdsAnotherTabsResults: Bool {
        guard let resultsTabID else { return false }
        guard let active = activeTabProvider() else { return false }
        return resultsTabID != active
    }

    public var referencePhase: ReferencePhase { holdsAnotherTabsResults ? .idle : storedReferencePhase }
    public var referenceSymbolName: String? { holdsAnotherTabsResults ? nil : storedReferenceSymbolName }
    public var selectedReferenceID: String? { holdsAnotherTabsResults ? nil : storedSelectedReferenceID }

    public var textSearchPhase: TextSearchPhase { holdsAnotherTabsResults ? .idle : storedTextSearchPhase }
    public var lastTextSearchResult: TextSearchResult? { holdsAnotherTabsResults ? nil : storedLastTextSearchResult }
    public var textSearchElapsedSeconds: Double? { holdsAnotherTabsResults ? nil : storedTextSearchElapsedSeconds }
    public var selectedTextSearchItemID: String? { holdsAnotherTabsResults ? nil : storedSelectedTextSearchItemID }
    public var textSearchQuery: String = ""
    public var textSearchMode: TextSearchMode = .literal

    /// Reuses the panel view's own tab type rather than declaring a parallel one — two
    /// enums for one concept drift.
    public var selectedTab: SidePanelTab = .references

    /// The session to search, asked for each time rather than held.
    ///
    /// Search results belong to a tab (02b §1.1), so the session has to follow whichever
    /// project is in front. Capturing one at construction would search the first project
    /// opened for the rest of the run — and the results would look plausible, which is the
    /// worst way to be wrong.
    private let sessionProvider: () -> (any ProjectSession)?
    private let activeTabProvider: () -> ProjectTabIdentifier?
    private let clock: @Sendable () -> Date

    private var projectSession: any ProjectSession { sessionProvider() ?? NoProjectSession() }

    public init(
        sessionProvider: @escaping () -> (any ProjectSession)?,
        activeTabProvider: @escaping () -> ProjectTabIdentifier? = { nil },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessionProvider = sessionProvider
        self.activeTabProvider = activeTabProvider
        self.clock = clock
    }

    // MARK: References (REQ-006)

    public func showReferences(to symbolName: String) async {
        resultsTabID = activeTabProvider()
        storedReferenceSymbolName = symbolName
        selectedTab = .references
        storedSelectedReferenceID = nil
        storedReferencePhase = .searching

        do {
            storedReferencePhase = .results(try await projectSession.references(to: symbolName))
        } catch let error as NavigatorError {
            storedReferencePhase = .failed(error)
        } catch {
            storedReferencePhase = .failed(.editorRequestFailed(method: "references", reason: "\(error)"))
        }
    }

    public func selectReference(_ reference: Reference) {
        storedSelectedReferenceID = reference.id
    }

    public func referencePresentation(indexState: IndexState) -> ReferencePresentation {
        ReferencePresentation.make(
            symbolName: referenceSymbolName,
            phase: referencePhase,
            indexState: indexState
        )
    }

    // MARK: Symbol search (REQ-007)

    private var storedSymbolResults: [SymbolSearchResult] = []
    public var symbolResults: [SymbolSearchResult] { holdsAnotherTabsResults ? [] : storedSymbolResults }
    public private(set) var symbolSelectedIndex = 0
    /// When the query in flight started, for the 200ms spinner rule (design §3 W-3).
    public private(set) var symbolSearchStartedAt: Date?
    public var symbolSearchQuery = ""
    public var isShowingSymbolSearch = false

    public func runSymbolSearch() async {
        let query = symbolSearchQuery
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            storedSymbolResults = []
            symbolSearchStartedAt = nil
            return
        }

        resultsTabID = activeTabProvider()
        symbolSearchStartedAt = clock()
        let results = await projectSession.searchSymbols(matching: query)

        // A query goes out on every keystroke, so replies can arrive out of order. A late
        // reply to an old query would overwrite newer results, leaving the list disagreeing
        // with the letters the user just typed.
        guard query == symbolSearchQuery else {
            return
        }
        storedSymbolResults = results
        symbolSelectedIndex = 0
        symbolSearchStartedAt = nil
    }

    public func moveSymbolSelection(_ direction: SelectionDirection) {
        symbolSelectedIndex = SymbolSearchPresentation.nextIndex(
            from: symbolSelectedIndex,
            resultCount: min(symbolResults.count, SymbolSearchPresentation.maximumResults),
            direction: direction
        )
    }

    public func selectSymbol(at index: Int) {
        symbolSelectedIndex = index
    }

    public func dismissSymbolSearch() {
        isShowingSymbolSearch = false
        symbolSearchQuery = ""
        storedSymbolResults = []
        symbolSearchStartedAt = nil
    }

    public func symbolPresentation(indexState: IndexState, now: Date) -> SymbolSearchPresentation {
        SymbolSearchPresentation.make(
            query: symbolSearchQuery,
            results: symbolResults,
            indexState: indexState,
            selectedIndex: symbolSelectedIndex,
            isLoading: SpinnerDelay.showsSpinner(startedAt: symbolSearchStartedAt, now: now)
        )
    }

    // MARK: Full-text search (REQ-008)

    public func runTextSearch() async {
        let query = textSearchQuery
        guard !query.isEmpty else {
            storedTextSearchPhase = .idle
            return
        }

        resultsTabID = activeTabProvider()
        storedSelectedTextSearchItemID = nil
        storedTextSearchPhase = .searching
        let startedAt = clock()

        do {
            let result = try await projectSession.searchText(query, mode: textSearchMode)
            // Timed here rather than in the engine: a duration measured before rendering
            // would report less than the user waited.
            storedTextSearchElapsedSeconds = clock().timeIntervalSince(startedAt)
            storedLastTextSearchResult = result
            storedTextSearchPhase = .results(result)
        } catch let error as NavigatorError {
            // The previous results stay on screen, dimmed. An invalid regular expression
            // is an error, never an empty result set (SC-6).
            storedTextSearchPhase = .failed(error)
        } catch {
            storedTextSearchPhase = .failed(.editorRequestFailed(method: "searchText", reason: "\(error)"))
        }
    }

    /// Looks a result up by the identifier the panel reports.
    ///
    /// The panel sends an id rather than the item itself because a SwiftUI list selects by
    /// identity; resolving it here keeps the lookup next to the results it searches.
    public func textSearchItem(withID id: String) -> TextSearchItem? {
        textSearchPresentation().items.first { $0.id == id }
    }

    public func selectTextSearchItem(_ item: TextSearchItem) {
        storedSelectedTextSearchItemID = item.id
    }

    public func textSearchPresentation() -> TextSearchPresentation {
        TextSearchPresentation.make(
            phase: textSearchPhase,
            previousResult: lastTextSearchResult,
            elapsedSeconds: textSearchElapsedSeconds
        )
    }
}
