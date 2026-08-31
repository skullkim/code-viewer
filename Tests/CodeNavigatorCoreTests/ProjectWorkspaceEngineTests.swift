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

    /// AC-5 on a case-insensitive volume, which is the default on macOS.
    ///
    /// `/tmp/Foo` and `/tmp/foo` are the same directory there, so opening both must give one tab.
    /// The engine gets this right because `realpath(3)` answers with the spelling on disk — but
    /// that is a property of the resolver, not something the engine states, and nothing asserted
    /// it. A future change to plain string normalisation would break AC-5 while the suite stayed
    /// green. **A guarantee that rests on an unstated property is a coincidence, not a guarantee.**
    ///
    /// On a case-sensitive volume the two really are different projects, and two tabs is the
    /// correct answer — so the volume is asked rather than assumed.
    @Test("대소문자만 다른 경로가 한 탭으로 접힌다 — 비구분 볼륨 (AC-5)")
    func pathsDifferingOnlyInCaseFoldIntoOneTab() async throws {
        let container = TemporaryProjectFixture()
        container.makeDirectory("CaseFolded")
        let asCreated = container.rootURL.appendingPathComponent("CaseFolded")
        let lowercased = container.rootURL.appendingPathComponent("casefolded")

        // 볼륨에 직접 묻는다. 대소문자 구분 여부는 파일시스템의 성질이지 우리가 정할 수 없다.
        let volumeFoldsCase = FileManager.default.fileExists(atPath: lowercased.path)

        let workspace = makeWorkspace()
        let first = try await workspace.openProject(at: asCreated)
        let second = try await workspace.openProject(at: lowercased)

        if volumeFoldsCase {
            guard case .activatedExisting(let tab) = second else {
                Issue.record("비구분 볼륨인데 대소문자만 다른 경로로 새 탭을 만들었다 — 한 프로젝트가 두 번 열린다")
                return
            }
            #expect(tab.id == first.tab.id)
            #expect(await workspace.tabs().count == 1)
        } else {
            // 구분 볼륨에서는 정말 다른 디렉토리다. 접으면 그게 결함이다.
            #expect(await workspace.tabs().count == 2)
        }
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

/// AC-3 asks that closing a tab really releases what it held.
///
/// Memory is a trap to judge that by. The allocator keeps freed pages and reuses them, so a
/// correct close frees nothing the process footprint can show — the question is not "did it drop"
/// but "does repeating it grow". A leak compounds; reuse does not.
///
/// 🔴 **The growth figure is only meaningful in isolation, so this suite does not judge it.**
/// `phys_footprint` is process-wide, and in the shared runner a dozen other suites allocate into
/// the same number. Measured alone this reads a 5.3MB index and 0.12MB per cycle; inside a full
/// run the same code read 1.9MB and 0.98MB. **Both halves move, so the ratio moves too**, and the
/// verdict would be about how busy the machine was rather than about the workspace. `gate.sh` runs
/// this alone and judges the printed figures — the arrangement SC-8 already uses, for this reason.
///
/// What stays asserted here is what does not depend on load: the closed session is gone and its
/// symbols leave the count. That is the direct evidence that closing released something.
@Suite("탭 여닫기가 메모리를 누적하지 않는다 (AC-3)", .serialized)
struct WorkspaceMemoryReuseTests {

    @Test("같은 프로젝트를 열 번 여닫아도 footprint 가 계속 늘지 않는다")
    func repeatedOpenAndCloseDoesNotAccumulate() async throws {
        // 인덱스가 **눈에 띄게 커야** 이 검사가 무언가를 잰다. 작은 픽스처로는 인덱스를 통째로
        // 새게 만들어도 증가가 잡음에 묻힌다 — 처음에 200개로 썼다가 변이가 안 잡혀서 알았다.
        let fixture = TemporaryProjectFixture()
        for index in 0..<2_000 {
            fixture.write("src/File\(index).kt", contents: "class Service\(index) { fun run() {} }")
        }
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
        )

        // 인덱스 하나의 값은 **아직 아무것도 안 연 상태**에서 재야 한다. 닫은 뒤와 비교하면
        // 0 이 나온다 — 할당자가 페이지를 안 돌려주므로 닫은 뒤가 연 뒤보다 작지 않다.
        // 그 0 으로 임계값을 만들면 검사가 항상 실패한다(실제로 그렇게 한 번 틀렸다).
        let empty = await workspace.memoryFootprint().processFootprintBytes
        let warmUp = try await workspace.openProject(at: fixture.rootURL)
        let withOneIndexOpen = await workspace.memoryFootprint().processFootprintBytes
        let indexCostInBytes = max(withOneIndexOpen - empty, 1)

        // 첫 회차는 기준선이 아니다 — 파서·캐시 등 한 번만 치르는 비용이 섞인다.
        try await workspace.closeTab(warmUp.tab.id)
        let baseline = await workspace.memoryFootprint().processFootprintBytes

        let cycles = 10
        for _ in 0..<cycles {
            let outcome = try await workspace.openProject(at: fixture.rootURL)
            #expect(await workspace.session(for: outcome.tab.id) != nil)
            try await workspace.closeTab(outcome.tab.id)
        }
        let after = await workspace.memoryFootprint().processFootprintBytes

        // **총 증가로 판정한다. 회당이 아니다.** 회차를 늘려 가며 각각 새 프로세스에서 재 보니
        // 총 증가가 회차와 **무관하게** 일정했다:
        //
        //     10회 → 1312 KB      40회 →  848 KB
        //     20회 →  704 KB      80회 →  768 KB
        //
        // 누수라면 80회가 10MB 쪽이어야 한다. 일정하다는 것은 **한 번 치르는 정착 비용**이라는
        // 뜻이고, 그래서 "회당"으로 나누면 회차가 늘수록 작아진다(131→9KB) — 줄어드는 게
        // 좋아지는 것처럼 보이지만 실은 분모만 커진 것이다. 그 수를 판정에 쓰면 회차를 늘리는
        // 것만으로 통과시킬 수 있다.
        let totalGrowth = after - baseline
        // gate.sh 가 이 줄을 읽어 판정한다. 형식을 바꾸면 그쪽 파서와 자체 검사도 같이 고쳐라.
        print(String(
            format: "[AC-3] 인덱스 %d KB · 총 증가 %d KB (%d회)",
            indexCostInBytes / 1024, totalGrowth / 1024, cycles
        ))

        // 판정은 여기서 하지 않는다 — 위 주석 참조. gate.sh 격리 스텝이 한다.
        // 상한은 **인덱스 하나**다: 열 번을 여닫고도 인덱스 하나보다 적게 늘었다면 재사용되고
        // 있다는 뜻이고, 인덱스 하나를 넘겼다면 최소 한 벌이 남은 것이다.
        //
        // 여기서는 부하와 무관한 사실만 단언한다.
        #expect(await workspace.session(for: warmUp.tab.id) == nil)
        #expect(await workspace.memoryFootprint().openTabCount == 0)
        #expect(await workspace.memoryFootprint().indexedSymbolCount == 0)

        await workspace.shutDown()
    }

    @Test("탭을 닫으면 그 탭의 심볼이 집계에서 빠진다")
    func closingATabRemovesItsSymbolsFromTheFootprint() async throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "class Application")
        let workspace = ProjectWorkspaceEngine(
            columns: 80, rows: 24, editorExecutableOverridePath: "/nonexistent/nvim"
        )

        let outcome = try await workspace.openProject(at: fixture.rootURL)
        #expect(await workspace.memoryFootprint().indexedSymbolCount > 0)
        #expect(await workspace.memoryFootprint().openTabCount == 1)

        try await workspace.closeTab(outcome.tab.id)
        // 프로세스 footprint 와 달리 이건 즉시 떨어져야 한다 — 실제로 놓았는지를 재는 값이다.
        #expect(await workspace.memoryFootprint().indexedSymbolCount == 0)
        #expect(await workspace.memoryFootprint().openTabCount == 0)
        await workspace.shutDown()
    }
}
