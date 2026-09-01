import Testing
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// covers: REQ-015 AC-6 (사용자의 `~/.config/nvim` 매핑을 덮어쓰지 않는다), INV-7
///
/// 이 판정은 **셋 중 하나**다. 하나의 불리언("매핑이 있는가")으로 뭉개면 Neovim 자신의 기본
/// 매핑이 사용자 설정으로 읽혀 우리가 심지 못하거나(REQ-015 AC-1·2 가 죽는다), 반대로 사용자
/// 매핑이 빈 자리로 읽혀 우리가 덮어쓴다(AC-6 이 죽는다). 두 실패 방향이 다 있다.
@Suite("내비게이션 키 매핑 판정 (REQ-015 AC-6)")
struct NavigationKeyMappingClassifierTests {

    private let editorRuntimePath = "/opt/homebrew/Cellar/neovim/0.12.5/share/nvim/runtime"

    @Test("매핑이 없으면 임자가 없다")
    func anAbsentMappingHasNoOwner() {
        let report = NeovimKeyMappingReport(isPresent: false, scriptIdentifier: 0, scriptPath: nil)
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath) == .nobody
        )
    }

    @Test("스크립트 식별자가 양수가 아니면 Neovim 자신의 기본이다")
    func aNonPositiveScriptIdentifierMeansAnEditorDefault() {
        // 실측: Neovim 0.12.5 의 기본 `grr`·`gc` 는 sid=-8 이고 스크립트가 없다.
        let report = NeovimKeyMappingReport(isPresent: true, scriptIdentifier: -8, scriptPath: nil)
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath)
                == .editorDefault
        )
    }

    @Test("Neovim 런타임 안의 스크립트가 심은 것은 사용자 것이 아니다")
    func aMappingFromTheEditorRuntimeIsNotTheUsers() {
        let report = NeovimKeyMappingReport(
            isPresent: true,
            scriptIdentifier: 12,
            scriptPath: editorRuntimePath + "/plugin/something.vim"
        )
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath)
                == .editorDefault
        )
    }

    @Test("런타임 밖 스크립트가 심은 것은 사용자 것이고, 어느 파일인지 남는다")
    func aMappingFromOutsideTheRuntimeBelongsToTheUser() {
        let configuration = "/Users/someone/.config/nvim/init.lua"
        let report = NeovimKeyMappingReport(
            isPresent: true, scriptIdentifier: 3, scriptPath: configuration
        )
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath)
                == .user(scriptPath: configuration)
        )
    }

    /// 실측에서 이 경로로 틀렸다 — `stdpath('config')` 는 `/var/…` 를, `getscriptinfo` 는
    /// `/private/var/…` 를 줬다. 접두 비교가 실패해 **사용자 매핑이 사용자 것으로 안 읽혔고**,
    /// 그 방향의 실패는 곧 덮어쓰기다. 그래서 판정 기준을 "설정 안인가"가 아니라
    /// "런타임 밖인가"로 두고, 경로는 심링크가 풀린 채로 들어온다.
    @Test("런타임 경로가 심링크로 다르게 표기돼도 런타임 것으로 읽힌다")
    func runtimePathsAreComparedAfterSymbolicLinksAreResolved() {
        let report = NeovimKeyMappingReport(
            isPresent: true,
            scriptIdentifier: 12,
            scriptPath: "/private/opt/runtime/plugin/x.vim"
        )
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: "/private/opt/runtime")
                == .editorDefault
        )
    }

    @Test("런타임 경로를 모를 때 사용자 매핑을 기본으로 오인하지 않는다")
    func anUnknownRuntimePathDoesNotMisreadAUserMapping() {
        // 빈 문자열은 "모든 경로의 접두"다. 그대로 비교하면 사용자 스크립트가 전부
        // 런타임 것으로 읽히고, AC-6 이 조용히 꺼진다.
        let configuration = "/Users/someone/.config/nvim/init.lua"
        let report = NeovimKeyMappingReport(
            isPresent: true, scriptIdentifier: 3, scriptPath: configuration
        )
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: "")
                == .user(scriptPath: configuration)
        )
    }

    @Test("스크립트 식별자는 양수인데 경로를 못 얻으면 사용자 것으로 단정하지 않는다")
    func aPositiveIdentifierWithoutAPathIsNotClaimedForTheUser() {
        // "경로를 모른다"와 "런타임 밖이다"는 다른 사실이다. 모르는 것을 사용자 것으로 읽으면
        // 우리가 심지 못해 gd/gr 이 조용히 없는 기능이 된다.
        let report = NeovimKeyMappingReport(isPresent: true, scriptIdentifier: 7, scriptPath: nil)
        #expect(
            NeovimKeyMappingClassifier.owner(of: report, editorRuntimePath: editorRuntimePath)
                == .editorDefault
        )
    }

    // MARK: - 임자 → 우리가 하는 일

    @Test("임자에 따라 심을지 말지와 남길 판정이 정해진다")
    func theOwnerDecidesWhetherWeInstallAndWhatWeRecord() {
        #expect(NeovimKeyMappingClassifier.resolution(for: .nobody) == .installed)
        #expect(NeovimKeyMappingClassifier.resolution(for: .editorDefault) == .replacedEditorDefault)
        #expect(
            NeovimKeyMappingClassifier.resolution(for: .user(scriptPath: "/x/init.lua"))
                == .deferredToUserMapping
        )

        #expect(NeovimKeyMappingClassifier.shouldInstall(for: .nobody))
        #expect(NeovimKeyMappingClassifier.shouldInstall(for: .editorDefault))
        #expect(!NeovimKeyMappingClassifier.shouldInstall(for: .user(scriptPath: "/x/init.lua")))
    }

    @Test("사용자 매핑일 때만 어느 파일이 이겼는지 남는다")
    func onlyADeferredDecisionCarriesTheUsersScriptPath() {
        #expect(NeovimKeyMappingClassifier.userScriptPath(for: .nobody) == nil)
        #expect(NeovimKeyMappingClassifier.userScriptPath(for: .editorDefault) == nil)
        #expect(
            NeovimKeyMappingClassifier.userScriptPath(for: .user(scriptPath: "/x/init.lua"))
                == "/x/init.lua"
        )
    }

    @Test("임자 세 종류가 전부 열거된다")
    func everyKindOfOwnerIsListed() {
        // catch-all 로 새 종류가 조용히 흘러들지 않게, 목록을 수로 고정한다.
        let owners: [NeovimKeyMappingOwner] = [.nobody, .editorDefault, .user(scriptPath: "/x")]
        #expect(Set(owners.map(\.kind)) == Set(NeovimKeyMappingOwner.Kind.allCases))
        #expect(NeovimKeyMappingOwner.Kind.allCases.count == 3)
    }
}
