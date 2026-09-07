import Testing
import CodeNavigatorContract
@testable import CodeNavigatorAppKit

/// 편집 중인 실행 설정.
///
/// 저장 형식은 `[String: String]` 인데 표는 순서가 있어야 한다 — 사용자가 친 줄이 매 렌더마다
/// 자리를 바꾸면 두 줄짜리 표도 못 쓴다. 그 변환이 여기 있고, 변환이 틀리면 사용자가 적은
/// 환경변수가 조용히 사라진다.
@Suite("실행 설정 편집 초안")
struct RunConfigurationDraftTests {

    @Test("환경변수를 이름순으로 편다 — 열 때마다 순서가 달라지면 표를 못 읽는다")
    func laysEnvironmentOutInAStableOrder() {
        let draft = RunConfigurationDraft(
            RunConfiguration(
                name: "서버", command: "./gradlew bootRun", workingDirectory: "",
                environment: ["PORT": "8080", "APP_ENV": "dev", "ZONE": "kr"]
            )
        )
        #expect(draft.environmentRows.map(\.key) == ["APP_ENV", "PORT", "ZONE"])
        #expect(draft.environmentRows.map(\.value) == ["dev", "8080", "kr"])
    }

    @Test("되돌리면 원래 설정과 같다")
    func roundTripsBack() {
        let original = RunConfiguration(
            name: "서버", command: "./gradlew bootRun", workingDirectory: "server",
            environment: ["PORT": "8080", "APP_ENV": "dev"]
        )
        #expect(RunConfigurationDraft(original).configuration() == original)
    }

    /// 빈 줄은 사용자가 "추가" 를 누른 흔적이지 값이 아니다. 그대로 저장하면 자식 프로세스에
    /// 이름 없는 환경변수가 들어간다.
    @Test("키가 빈 줄은 버린다")
    func dropsRowsWithoutAKey() {
        var draft = RunConfigurationDraft(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:])
        )
        draft.addEnvironmentRow()
        draft.environmentRows[0].key = "  "
        draft.environmentRows[0].value = "버려질 값"
        draft.addEnvironmentRow()
        draft.environmentRows[1].key = " PORT "
        draft.environmentRows[1].value = " 8080 "

        // 키는 다듬는다 — 붙여넣기로 들어온 공백 하나 때문에 `PORT` 가 안 먹는 일을 막는다.
        // 값은 다듬지 않는다: 공백이 의미를 갖는 값(구분자, 접두 인자)이 실제로 있다.
        #expect(draft.configuration().environment == ["PORT": " 8080 "])
    }

    @Test("같은 키를 두 번 적으면 마지막 것이 이긴다")
    func lastDuplicateKeyWins() {
        var draft = RunConfigurationDraft(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:])
        )
        draft.addEnvironmentRow()
        draft.environmentRows[0].key = "PORT"
        draft.environmentRows[0].value = "8080"
        draft.addEnvironmentRow()
        draft.environmentRows[1].key = "PORT"
        draft.environmentRows[1].value = "9090"
        #expect(draft.configuration().environment == ["PORT": "9090"])
    }

    /// 이름이 곧 id 다. 둘이 같으면 고르개가 한 줄만 보여 주고, 나머지 하나는 영영 못 고른다.
    @Test("이름이 겹치면 뒤엣것에 번호를 붙인다")
    func makesDuplicateNamesUnique() {
        let drafts = [
            RunConfiguration(name: "서버", command: "a", workingDirectory: "", environment: [:]),
            RunConfiguration(name: "서버", command: "b", workingDirectory: "", environment: [:]),
            RunConfiguration(name: "서버", command: "c", workingDirectory: "", environment: [:]),
        ].map(RunConfigurationDraft.init)

        let saved = RunConfigurationDraft.configurations(from: drafts)
        #expect(saved.map(\.name) == ["서버", "서버 2", "서버 3"])
        #expect(saved.map(\.command) == ["a", "b", "c"], "이름을 고치느라 순서나 내용이 섞였다")
    }

    @Test("이름이 비면 기본 이름을 준다")
    func fillsInAnEmptyName() {
        var draft = RunConfigurationDraft(
            RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:])
        )
        draft.name = "   "
        #expect(RunConfigurationDraft.configurations(from: [draft]).map(\.name) == ["이름 없는 설정"])
    }

    /// 명령이 없는 설정은 눌러도 아무 일이 안 일어난다 — 저장 단계에서 걸러 준다.
    @Test("명령이 빈 설정은 저장하지 않는다")
    func dropsConfigurationsWithoutACommand() {
        let drafts = [
            RunConfigurationDraft(
                RunConfiguration(name: "서버", command: "run", workingDirectory: "", environment: [:])
            ),
            RunConfigurationDraft(
                RunConfiguration(name: "빈 것", command: "  ", workingDirectory: "", environment: [:])
            ),
        ]
        #expect(RunConfigurationDraft.configurations(from: drafts).map(\.name) == ["서버"])
    }

    @Test("새 설정은 바로 돌릴 수 있는 기본값으로 시작한다")
    func newDraftIsRunnable() {
        let draft = RunConfigurationDraft.newDraft(existing: [])
        #expect(draft.name.isEmpty == false)
        #expect(draft.command.isEmpty == false, "빈 명령이면 만들자마자 저장에서 버려진다")
    }

    @Test("새 설정 이름은 이미 있는 것과 겹치지 않는다")
    func newDraftAvoidsExistingNames() {
        let existing = [
            RunConfigurationDraft(
                RunConfiguration(name: "새 설정", command: "run", workingDirectory: "", environment: [:])
            )
        ]
        #expect(RunConfigurationDraft.newDraft(existing: existing).name != "새 설정")
    }
}
