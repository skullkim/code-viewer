import Testing
@testable import CodeNavigatorCore

@Suite("NeovimVersion — 버전 파싱과 비교")
struct NeovimVersionTests {

    @Test("nvim --version 첫 줄에서 버전을 읽는다")
    func parsesTheVersionLine() throws {
        let version = try #require(NeovimVersion(versionOutput: "NVIM v0.12.5"))
        #expect(version.major == 0)
        #expect(version.minor == 12)
        #expect(version.patch == 5)
    }

    @Test("개발 빌드 접미사가 있어도 숫자만 읽는다 — 나이틀리를 쓰는 사람을 막지 않는다")
    func ignoresPreReleaseSuffixes() throws {
        let version = try #require(NeovimVersion(versionOutput: "NVIM v0.11.0-dev-1234+g0123abcd"))
        #expect(version.description == "0.11.0")
    }

    @Test("패치 번호가 없으면 0으로 본다")
    func defaultsMissingPatchToZero() throws {
        let version = try #require(NeovimVersion(versionOutput: "NVIM v0.9"))
        #expect(version.description == "0.9.0")
    }

    @Test("버전 숫자가 없으면 nil이다")
    func returnsNilWithoutAVersionNumber() {
        #expect(NeovimVersion(versionOutput: "command not found") == nil)
        #expect(NeovimVersion(versionOutput: "") == nil)
    }

    @Test("버전 순서가 자릿수가 아니라 숫자로 비교된다")
    func comparesNumericallyNotLexically() {
        #expect(NeovimVersion(major: 0, minor: 9, patch: 0) < NeovimVersion(major: 0, minor: 12, patch: 0))
        #expect(NeovimVersion(major: 0, minor: 8, patch: 9) < NeovimVersion(major: 0, minor: 9, patch: 0))
        #expect(NeovimVersion(major: 1, minor: 0, patch: 0) > NeovimVersion(major: 0, minor: 99, patch: 99))
    }

    @Test("최소 지원 버전은 0.9.0이다")
    func minimumSupportedVersionIsPinned() {
        #expect(NeovimVersion.minimumSupported.description == "0.9.0")
    }
}
