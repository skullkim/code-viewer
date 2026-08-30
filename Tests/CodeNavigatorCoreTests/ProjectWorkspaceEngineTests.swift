import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Several projects open at once (REQ-012).
@Suite("다중 프로젝트 워크스페이스", .serialized)
struct ProjectWorkspaceEngineTests {

    /// Without a usable editor the projects still open, which is the point of W-8 — and it keeps
    /// these checks about the workspace rather than about Neovim's start-up.
    private func makeWorkspace() -> ProjectWorkspaceEngine {
        ProjectWorkspaceEngine(columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim")
    }

    private func makeProject(_ name: String, symbol: String) -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/\(name).kt", contents: "class \(symbol)")
        return fixture
    }

    @Test("두 프로젝트가 동시에 열리고 둘 다 검색된다 (AC-1)")
    func twoProjectsStayOpenTogether() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let beta = makeProject("Beta", symbol: "BetaService")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        #expect(await workspace.tabs().count == 2)
        // 첫 번째가 두 번째를 여는 것으로 대체되지 않았다는 것이 핵심이다.
        let firstSession = await workspace.session(for: first.tab.id)
        let secondSession = await workspace.session(for: second.tab.id)
        #expect(await firstSession?.definitions(named: "AlphaService").isEmpty == false)
        #expect(await secondSession?.definitions(named: "BetaService").isEmpty == false)
        await workspace.shutDown()
    }

    /// INV-5. The isolation is structural: each tab answers from its own engine, which holds no
    /// reference to another's index — not a rule anyone has to remember.
    @Test("한 탭의 검색이 다른 탭의 심볼을 보지 못한다 (INV-5)")
    func aTabNeverSeesAnotherProjectsSymbols() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let beta = makeProject("Beta", symbol: "BetaService")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        let firstSession = await workspace.session(for: first.tab.id)
        let secondSession = await workspace.session(for: second.tab.id)
        #expect(await firstSession?.definitions(named: "BetaService").isEmpty == true)
        #expect(await secondSession?.definitions(named: "AlphaService").isEmpty == true)
        await workspace.shutDown()
    }

    @Test("이미 열린 프로젝트를 다시 열면 새 탭을 만들지 않고 활성화한다 (AC-5)")
    func reopeningAnOpenProjectActivatesItInstead() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let beta = makeProject("Beta", symbol: "BetaService")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        _ = try await workspace.openProject(at: beta.rootURL)
        let again = try await workspace.openProject(at: alpha.rootURL)

        guard case .activatedExisting(let tab) = again else {
            Issue.record("이미 열린 프로젝트인데 \(again) 을 돌려줬다")
            return
        }
        #expect(tab.id == first.tab.id)
        #expect(await workspace.tabs().count == 2)
        #expect(await workspace.activeTab()?.id == first.tab.id)
        await workspace.shutDown()
    }

    /// The same directory spelled two ways is one project. Without canonicalisation the workspace
    /// would open a second tab for it and the two would disagree about which is which.
    @Test("같은 디렉토리를 다르게 적어도 한 프로젝트다 — 심링크 경로")
    func twoSpellingsOfOneDirectoryAreOneProject() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let workspace = makeWorkspace()

        _ = try await workspace.openProject(at: alpha.rootURL)
        // /var 과 /private/var 은 같은 곳이다.
        let unresolved = URL(fileURLWithPath: "/var" + alpha.rootURL.path.replacingOccurrences(
            of: "/private/var", with: ""
        ))
        let again = try await workspace.openProject(at: unresolved.path.hasPrefix("/var/") ? unresolved : alpha.rootURL)

        guard case .activatedExisting = again else {
            Issue.record("같은 디렉토리인데 새 탭을 만들었다 — 탭 \(await workspace.tabs().count)개")
            return
        }
        #expect(await workspace.tabs().count == 1)
        await workspace.shutDown()
    }

    @Test("탭을 닫으면 그 프로젝트의 인덱스가 해제된다 (AC-3)")
    func closingATabReleasesItsIndex() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let beta = makeProject("Beta", symbol: "BetaService")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)
        try await workspace.closeTab(first.tab.id)

        #expect(await workspace.session(for: first.tab.id) == nil, "닫힌 탭의 세션이 남았다")
        #expect(await workspace.tabs().map(\.id) == [second.tab.id])
        // 남은 탭은 멀쩡해야 한다 — 닫기가 이웃을 건드리면 그게 더 나쁘다.
        #expect(await workspace.session(for: second.tab.id)?.definitions(named: "BetaService").isEmpty == false)
        await workspace.shutDown()
    }

    @Test("이름이 겹치는 탭에만 구분자가 붙고, 겹침이 사라지면 없어진다")
    func onlyCollidingNamesGetADisambiguator() async throws {
        let container = TemporaryProjectFixture()
        container.makeDirectory("one/shared")
        container.makeDirectory("two/shared")
        let first = container.rootURL.appendingPathComponent("one/shared")
        let second = container.rootURL.appendingPathComponent("two/shared")
        let solo = makeProject("Solo", symbol: "SoloService")
        let workspace = makeWorkspace()

        let firstTab = try await workspace.openProject(at: first)
        _ = try await workspace.openProject(at: second)
        _ = try await workspace.openProject(at: solo.rootURL)

        let tabs = await workspace.tabs()
        let shared = tabs.filter { $0.displayName == "shared" }
        #expect(shared.count == 2)
        #expect(shared.allSatisfy { $0.disambiguator != nil }, "겹치는데 구분자가 없다")
        #expect(tabs.first { $0.displayName == solo.rootURL.lastPathComponent }?.disambiguator == nil,
                "안 겹치는 탭에 구분자가 붙었다")

        // 겹침이 사라지면 구분자도 사라져야 한다 — 남아 있으면 없는 충돌을 말하는 셈이다.
        try await workspace.closeTab(firstTab.tab.id)
        let remaining = await workspace.tabs().first { $0.displayName == "shared" }
        #expect(remaining?.disambiguator == nil, "충돌이 사라졌는데 구분자가 남았다")
        await workspace.shutDown()
    }

    @Test("복원은 못 연 것을 조용히 버리지 않고 사유와 함께 돌려준다 (AC-4·AC-6)")
    func restoringNamesWhatItCouldNotOpen() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let gone = URL(fileURLWithPath: "/nonexistent/project-\(UUID().uuidString)")
        let workspace = makeWorkspace()

        let outcome = await workspace.restoreTabs(from: [alpha.rootURL, gone])

        #expect(outcome.restored.count == 1)
        #expect(outcome.missing.count == 1)
        #expect(outcome.missing.first?.reason == .notFound)
        #expect(outcome.missing.first?.rootPath == gone)
        await workspace.shutDown()
    }

    @Test("순서 바꾸기는 열린 탭의 순열만 받아들인다")
    func reorderingOnlyAcceptsAPermutationOfWhatIsOpen() async throws {
        let alpha = makeProject("Alpha", symbol: "AlphaService")
        let beta = makeProject("Beta", symbol: "BetaService")
        let workspace = makeWorkspace()

        let first = try await workspace.openProject(at: alpha.rootURL)
        let second = try await workspace.openProject(at: beta.rootURL)

        await workspace.reorderTabs([second.tab.id, first.tab.id])
        #expect(await workspace.tabs().map(\.id) == [second.tab.id, first.tab.id])

        // 모르는 식별자가 섞여도 열린 탭이 사라지면 안 된다 — 바에서만 없어지고 프로젝트는
        // 계속 인덱싱되는 유령 탭이 된다.
        await workspace.reorderTabs([ProjectTabIdentifier()])
        #expect(await workspace.tabs().count == 2)
        await workspace.shutDown()
    }
}
