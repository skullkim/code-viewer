import Testing
import CodeNavigatorContract

/// `allKnownCases` exists so that tests claiming to cover "every state" actually do. These tests
/// guard the guard: they check the list is complete and that each entry is distinct, so a
/// copy-paste slip cannot leave two entries of the same kind and one kind missing.
@Suite("계약 enum 전수 열거")
struct ContractCaseEnumerationTests {

    @Test("IndexState 의 모든 종류가 대표값을 갖는다")
    func indexStateListsEveryKind() {
        let listedKinds = Set(IndexState.allKnownCases.map(\.kind))
        #expect(listedKinds == Set(IndexState.Kind.allCases))
        #expect(IndexState.allKnownCases.count == IndexState.Kind.allCases.count)
    }

    @Test("EditorSessionState 의 모든 종류가 대표값을 갖는다")
    func editorSessionStateListsEveryKind() {
        let listedKinds = Set(EditorSessionState.allKnownCases.map(\.kind))
        #expect(listedKinds == Set(EditorSessionState.Kind.allCases))
        #expect(EditorSessionState.allKnownCases.count == EditorSessionState.Kind.allCases.count)
    }

    @Test("kind 가 페이로드를 무시하고 같은 상태를 같다고 본다")
    func kindIgnoresPayload() {
        let early = IndexState.indexing(IndexProgress(completed: 0, total: 100))
        let late = IndexState.indexing(IndexProgress(completed: 99, total: 100))
        #expect(early != late)
        #expect(early.kind == late.kind)

        let missing = EditorSessionState.disconnected(reason: "하나")
        let other = EditorSessionState.disconnected(reason: "둘")
        #expect(missing != other)
        #expect(missing.kind == other.kind)
    }

    @Test("진행 중 상태의 대표값은 파일 목록을 아직 만드는 중인 경계다")
    func progressRepresentativesUseTheBoundaryValue() throws {
        for state in IndexState.allKnownCases where state.progress != nil {
            let progress = try #require(state.progress)
            // total 0 은 0으로 나누기와 빈 진행바를 드러내는 값이다.
            #expect(progress.total == 0)
            #expect(progress.fractionCompleted == 0)
        }
    }

    @Test("기동 실패 대표값은 버전을 못 찾은 쪽이다 — 표시할 숫자가 없는 분기")
    func startupFailureRepresentativeHasNoFoundVersion() throws {
        let failure = try #require(
            EditorSessionState.allKnownCases.compactMap { state -> EditorStartupFailure? in
                if case .startupFailed(let failure) = state { return failure }
                return nil
            }.first
        )
        #expect(failure.foundVersion == nil)
        #expect(failure.searchedPaths.isEmpty == false)
        #expect(failure.requiredVersion.isEmpty == false)
    }

    @Test("끊김 대표값은 사유가 비어 있지 않다 — 사유를 버리는 뷰가 통과하지 못하게")
    func disconnectedRepresentativeCarriesAReason() throws {
        let reason = try #require(
            EditorSessionState.allKnownCases.compactMap { state -> String? in
                if case .disconnected(let reason) = state { return reason }
                return nil
            }.first
        )
        #expect(reason.isEmpty == false)
    }

    @Test("작업 중 여부가 모든 상태에서 정의된다")
    func isWorkingIsDefinedForEveryState() {
        let working = IndexState.allKnownCases.filter(\.isWorking).map(\.kind)
        #expect(Set(working) == [.indexing, .updating, .rescanning])
    }
}
