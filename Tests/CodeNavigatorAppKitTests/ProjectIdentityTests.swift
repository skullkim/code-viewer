import Testing
import Foundation
@testable import CodeNavigatorAppKit

/// REQ-012 AC-5: reopening an open project activates its tab rather than adding a second.
///
/// The whole criterion rests on when two paths are "the same project", and that question has
/// two traps — symlinks and letter case. Both fail the same quiet way: a duplicate tab onto
/// one project, with two indexes and two edit sessions where the user asked for one.
@Suite("ProjectIdentity — 같은 프로젝트인가 (REQ-012 AC-5)")
struct ProjectIdentityTests {

    private func tab(_ path: String, name: String, caseSensitive: Bool = true) -> ProjectTabDescriptor {
        ProjectTabDescriptor(
            id: ProjectIdentity.canonical(for: path, isCaseSensitiveVolume: caseSensitive),
            rootPath: path,
            name: name
        )
    }

    private func resolve(
        _ requested: String,
        against tabs: [ProjectTabDescriptor],
        caseSensitive: Bool = true
    ) -> ProjectOpenResolution {
        ProjectIdentity.resolve(
            requestedPath: requested,
            openTabs: tabs,
            isCaseSensitiveVolume: caseSensitive
        )
    }

    // MARK: 같은 경로

    @Test("같은 경로를 다시 열면 기존 탭을 활성화한다")
    func reopeningTheSamePathActivatesTheExistingTab() {
        let open = [tab("/Users/dev/repo", name: "repo")]
        #expect(resolve("/Users/dev/repo", against: open) == .activateExisting(tabID: open[0].id))
    }

    @Test("다른 프로젝트는 새 탭을 연다")
    func aDifferentProjectOpensANewTab() {
        let open = [tab("/Users/dev/repo", name: "repo")]
        guard case .openNew = resolve("/Users/dev/other", against: open) else {
            Issue.record("다른 경로인데 기존 탭을 활성화했다")
            return
        }
    }

    @Test("탭이 하나도 없으면 언제나 새 탭이다")
    func nothingOpenAlwaysMeansANewTab() {
        guard case .openNew = resolve("/Users/dev/repo", against: []) else {
            Issue.record("열린 탭이 없는데 기존 탭을 활성화했다")
            return
        }
    }

    // MARK: 표기만 다른 같은 경로

    @Test("끝의 슬래시나 . / .. 표기는 같은 프로젝트로 본다")
    func spellingDifferencesStillMeanTheSameProject() {
        let open = [tab("/Users/dev/repo", name: "repo")]

        for spelling in ["/Users/dev/repo/", "/Users/dev/./repo", "/Users/dev/sub/../repo"] {
            #expect(
                resolve(spelling, against: open) == .activateExisting(tabID: open[0].id),
                "\(spelling) 가 새 탭을 열었다"
            )
        }
    }

    // MARK: 심링크 — 실제 파일 시스템으로 확인한다

    @Test("심링크로 가리킨 같은 폴더는 같은 프로젝트다")
    func aSymlinkToTheSameFolderIsTheSameProject() throws {
        // 목이 아니라 실제 심링크를 만든다. 이 규칙이 틀리면 나타나는 증상(탭 둘, 인덱스
        // 둘)이 조용해서, 규칙 자체를 파일 시스템에 물어봐야 의미가 있다.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tab-identity-\(UUID().uuidString)")
        let real = root.appendingPathComponent("real-project")
        let link = root.appendingPathComponent("linked-project")

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let open = [tab(real.path, name: "real-project")]
        #expect(
            resolve(link.path, against: open) == .activateExisting(tabID: open[0].id),
            "심링크 경로가 같은 폴더를 가리키는데 새 탭을 열었다"
        )
    }

    @Test("/tmp 와 /private/tmp 는 같은 곳이다")
    func theTmpAliasResolvesToOnePlace() {
        // macOS 가 같은 폴더를 두 이름으로 보고하는 대표 사례다. 이 빌드에서 트리 강조가
        // 조용히 깨졌던 원인이기도 하다(03 §3.1).
        //
        // **실재하는 경로로 물어야 한다.** `resolvingSymlinksInPath` 는 없는 경로에서는
        // 링크를 풀지 않는다 — 처음에 `/tmp/repo`(없는 폴더)로 썼더니 통과하지 못했고,
        // 그건 규칙이 아니라 픽스처의 문제였다. 실제로는 사용자가 고르거나 북마크로
        // 복원한 경로만 들어오므로 언제나 실재한다.
        let open = [tab("/tmp", name: "tmp")]
        #expect(resolve("/private/tmp", against: open) == .activateExisting(tabID: open[0].id))
    }

    // MARK: 대소문자 — 볼륨이 정한다

    @Test("대소문자를 구분하지 않는 볼륨에서는 같은 프로젝트다")
    func caseInsensitiveVolumesFoldTheCase() {
        // macOS 기본값이다. 여기서 구분해 버리면 ~/Repo 와 ~/repo 로 탭이 둘 생긴다.
        let open = [tab("/Users/dev/Repo", name: "Repo", caseSensitive: false)]
        #expect(
            resolve("/Users/dev/repo", against: open, caseSensitive: false)
                == .activateExisting(tabID: open[0].id)
        )
    }

    @Test("대소문자를 구분하는 볼륨에서는 다른 프로젝트다")
    func caseSensitiveVolumesKeepThemApart() {
        // 그런 볼륨에서 App/ 과 app/ 은 진짜 다른 폴더다. 접어 버리면 사용자가 연 것과
        // 다른 프로젝트의 파일을 보여 주게 된다 — 중복 탭보다 나쁜 실패다.
        let open = [tab("/Volumes/case/App", name: "App", caseSensitive: true)]
        guard case .openNew = resolve("/Volumes/case/app", against: open, caseSensitive: true) else {
            Issue.record("대소문자 구분 볼륨에서 다른 폴더를 같은 것으로 봤다")
            return
        }
    }

    @Test("볼륨 질의는 실제 파일 시스템에 물어본다")
    func theVolumeQuestionIsAskedOfTheFilesystem() {
        // 값 자체는 기계에 따라 다르므로 단언하지 않는다. 확인하는 것은 이 함수가
        // 트랩 없이 답을 내놓는다는 것 — 못 물으면 기본값(구분 안 함)으로 떨어진다.
        _ = ProjectIdentity.isCaseSensitiveVolume(at: NSTemporaryDirectory())
        _ = ProjectIdentity.isCaseSensitiveVolume(at: "/does/not/exist-\(UUID().uuidString)")
    }

    // MARK: 정체성 자체

    @Test("정체성은 같은 입력에 같은 값을 준다")
    func theIdentityIsStable() {
        let first = ProjectIdentity.canonical(for: "/Users/dev/repo", isCaseSensitiveVolume: true)
        let second = ProjectIdentity.canonical(for: "/Users/dev/repo/", isCaseSensitiveVolume: true)
        #expect(first == second)
        #expect(!first.isEmpty)
    }
}
