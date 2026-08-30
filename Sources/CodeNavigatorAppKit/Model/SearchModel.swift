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

    public private(set) var referencePhase: ReferencePhase = .idle
    public private(set) var referenceSymbolName: String?
    public private(set) var selectedReferenceID: String?

    public private(set) var textSearchPhase: TextSearchPhase = .idle
    public private(set) var lastTextSearchResult: TextSearchResult?
    public private(set) var textSearchElapsedSeconds: Double?
    public private(set) var selectedTextSearchItemID: String?
    public var textSearchQuery: String = ""
    public var textSearchMode: TextSearchMode = .literal

    /// Reuses the panel view's own tab type rather than declaring a parallel one — two
    /// enums for one concept drift.
    public var selectedTab: SidePanelTab = .references

    private let projectSession: ProjectSession
    private let clock: @Sendable () -> Date

    public init(projectSession: ProjectSession, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.projectSession = projectSession
        self.clock = clock
    }

    // MARK: References (REQ-006)

    public func showReferences(to symbolName: String) async {
        referenceSymbolName = symbolName
        selectedTab = .references
        selectedReferenceID = nil
        referencePhase = .searching

        do {
            referencePhase = .results(try await projectSession.references(to: symbolName))
        } catch let error as NavigatorError {
            referencePhase = .failed(error)
        } catch {
            referencePhase = .failed(.editorRequestFailed(method: "references", reason: "\(error)"))
        }
    }

    public func selectReference(_ reference: Reference) {
        selectedReferenceID = reference.id
    }

    public func referencePresentation(indexState: IndexState) -> ReferencePresentation {
        ReferencePresentation.make(
            symbolName: referenceSymbolName,
            phase: referencePhase,
            indexState: indexState
        )
    }

    // MARK: Symbol search (REQ-007)

    public private(set) var symbolResults: [SymbolSearchResult] = []
    public private(set) var symbolSelectedIndex = 0
    /// When the query in flight started, for the 200ms spinner rule (design §3 W-3).
    public private(set) var symbolSearchStartedAt: Date?
    public var symbolSearchQuery = ""
    public var isShowingSymbolSearch = false

    public func runSymbolSearch() async {
        let query = symbolSearchQuery
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            symbolResults = []
            symbolSearchStartedAt = nil
            return
        }

        symbolSearchStartedAt = clock()
        let results = await projectSession.searchSymbols(matching: query)

        // A query goes out on every keystroke, so replies can arrive out of order. A late
        // reply to an old query would overwrite newer results, leaving the list disagreeing
        // with the letters the user just typed.
        guard query == symbolSearchQuery else {
            return
        }
        symbolResults = results
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
        symbolResults = []
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
            textSearchPhase = .idle
            return
        }

        selectedTextSearchItemID = nil
        textSearchPhase = .searching
        let startedAt = clock()

        do {
            let result = try await projectSession.searchText(query, mode: textSearchMode)
            // Timed here rather than in the engine: a duration measured before rendering
            // would report less than the user waited.
            textSearchElapsedSeconds = clock().timeIntervalSince(startedAt)
            lastTextSearchResult = result
            textSearchPhase = .results(result)
        } catch let error as NavigatorError {
            // The previous results stay on screen, dimmed. An invalid regular expression
            // is an error, never an empty result set (SC-6).
            textSearchPhase = .failed(error)
        } catch {
            textSearchPhase = .failed(.editorRequestFailed(method: "searchText", reason: "\(error)"))
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
        selectedTextSearchItemID = item.id
    }

    public func textSearchPresentation() -> TextSearchPresentation {
        TextSearchPresentation.make(
            phase: textSearchPhase,
            previousResult: lastTextSearchResult,
            elapsedSeconds: textSearchElapsedSeconds
        )
    }
}
