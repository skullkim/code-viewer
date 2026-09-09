import Testing
import Foundation
@testable import CodeNavigatorCore

/// 셸 탐지가 **완전히 실패해도** homebrew 도구를 찾을 수 있어야 한다.
///
/// 사용자가 다른 컴퓨터에서 `command not found` 를 겪었다. 그 기계에서 무엇이 실패했는지
/// 우리는 볼 수 없지만, 실패해도 되게 만들 수는 있다.
@Suite("PATH 안전망 — 진짜 프로세스", .serialized)
struct PathSafetyNetLiveTests {

    /// 이 검사가 뜻을 가지려면 **그 도구가 이 기계에 있어야** 한다. 없으면 건너뛴다 —
    /// 조용히 통과시키지 않는다.
    private func brewTool() -> String? {
        for candidate in ["/opt/homebrew/bin/node", "/opt/homebrew/bin/git", "/usr/local/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    @Test("셸을 아예 못 부르는 상황에서도 도구를 찾는다")
    func findsToolsWhenTheShellProbeFails() throws {
        let tool = try #require(brewTool(), "이 기계에 homebrew 도구가 없어 검사할 수 없다")
        let name = (tool as NSString).lastPathComponent

        // 셸이 없는 것으로 친다 — 그 기계에서 무엇이 실패했든 결과는 같다.
        let path = try #require(LoginShellEnvironment.composedPath(shellPath: "/그런/셸/없음"))

        // **실제로 그 PATH 로 찾아본다.** 문자열에 들어 있다는 것만으로는 부족하다.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", "command -v \(name)"]
        process.environment = ["PATH": path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let found = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(process.terminationStatus == 0, "안전망 PATH 로 \(name) 을 못 찾았다: \(path)")
        #expect(found.isEmpty == false, "찾은 경로가 비었다")
    }

    /// positive control — GUI 앱이 받는 PATH 로는 못 찾아야 한다. 못 찾는 것이 확인돼야
    /// 위 검사가 무언가를 증명한다.
    @Test("GUI 기본 PATH 로는 못 찾는다 (positive control)")
    func theGuiPathCannotFindIt() throws {
        let tool = try #require(brewTool(), "이 기계에 homebrew 도구가 없어 검사할 수 없다")
        let name = (tool as NSString).lastPathComponent
        try #require(
            !tool.hasPrefix("/usr/bin"),
            "이 도구는 GUI PATH 에도 있어서 이 대조가 뜻이 없다"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", "command -v \(name)"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0, "\(name) 이 GUI PATH 에도 있다 — 대조가 성립 안 함")
    }
}
