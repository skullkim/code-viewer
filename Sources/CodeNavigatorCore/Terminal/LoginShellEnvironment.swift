import Foundation

/// 로그인 셸이 쓰는 `PATH` 를 받아 온다.
///
/// Finder 로 띄운 GUI 앱은 로그인 셸의 환경을 물려받지 않는다 — `PATH` 는
/// `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이다. 그 PATH 로는 homebrew 에 깐 `npm`·`node`·
/// `gradle` 이 전부 "command not found" 가 되고, 사용자는 "실행이 안 된다" 만 본다.
///
/// 터미널에서 앱을 띄우면 셸의 PATH 를 물려받아 잘 되기 때문에 **개발 중에는 드러나지
/// 않는다.** 사용자만 겪는 결함이다.
public enum LoginShellEnvironment {

    /// 셸을 기다리는 한계. 사용자의 프로파일이 무엇을 하는지 우리는 모른다 — 네트워크를
    /// 만지는 것도 있다. 못 받으면 물려받은 환경으로 간다.
    static let timeout: TimeInterval = 3

    /// 한 번 받으면 들고 있는다. 실행할 때마다 로그인 셸을 띄우면 그만큼 느려진다.
    private static let cached = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var resolved: String??

        func value(_ compute: () -> String?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            if let resolved { return resolved }
            let value = compute()
            resolved = value
            return value
        }
    }

    /// 이 사용자의 로그인 셸이 쓰는 PATH. 못 받으면 nil.
    public static func loginPath() -> String? {
        cached.value {
            resolvedPath(shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        }
    }

    static func resolvedPath(shellPath: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        // `-l` 로 로그인 셸이 되어야 `.zprofile`·`.profile` 이 읽힌다. `-i`(대화형)는 쓰지
        // 않는다 — 대화형 프로파일은 프롬프트를 그리거나 입력을 기다릴 수 있고, 그러면
        // 여기서 멈춘다.
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        // 프로파일이 찍는 인사말이 PATH 에 섞이지 않게 한다.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        // 파이프를 읽는 동안 시간을 잰다. 프로파일이 멈추면 여기서 영원히 기다리게 된다.
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let handle = output.fileHandleForReading
        while process.isRunning, Date() < deadline {
            data.append(handle.availableData)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        data.append(handle.readDataToEndOfFile())
        process.waitUntilExit()

        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // 한 항목뿐이면 프로파일이 제대로 안 읽힌 것이다. 그런 값으로 덮어쓰면 오히려 나빠진다.
        guard path.contains(":") else { return nil }
        return path
    }

    /// 물려받은 환경의 `PATH` 만 바꾼다. 통째로 갈아 끼우면 사용자가 실행 설정에 적은 값이
    /// 사라진다.
    static func augment(_ environment: [String: String], with loginPath: String?) -> [String: String] {
        guard let loginPath else { return environment }
        var augmented = environment
        augmented["PATH"] = loginPath
        return augmented
    }

    /// 물려받은 환경에 로그인 PATH 를 얹은 것. 터미널이 이것을 쓴다.
    public static func augmentedEnvironment() -> [String: String] {
        augment(ProcessInfo.processInfo.environment, with: loginPath())
    }
}
