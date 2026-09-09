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

    /// 흔한 도구 위치. **셸에서 못 받았을 때의 안전망**이다.
    ///
    /// 셸에 묻는 방법은 기계마다 실패한다 — zsh 는 `-l -c` 에서 `.zshrc` 를 읽지 않는데
    /// 대부분 거기에 homebrew 를 넣고, fish 는 `$PATH` 가 목록이라 콜론으로 안 나오며,
    /// 프로파일이 인사말을 찍으면 그 글자가 섞인다. 사용자가 다른 컴퓨터에서 겪은
    /// `command not found` 가 이 자리다.
    ///
    /// 디스크에 실제로 있는 것만 넣는다 — 없는 폴더는 PATH 만 길게 한다.
    static let wellKnownDirectories = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",   // Apple Silicon homebrew
        "/usr/local/bin", "/usr/local/sbin",         // Intel homebrew · 직접 설치
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.sdkman/candidates/java/current/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// 이 사용자의 로그인 셸이 쓰는 PATH 에 안전망을 합친 것. 못 받아도 nil 이 아니다.
    public static func loginPath() -> String? {
        cached.value {
            composedPath(shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        }
    }

    /// 셸이 준 것 + 실제로 있는 흔한 위치. **셸이 준 것이 앞에 온다** — 사용자가 골라 둔
    /// 버전이 있으면 그것이 이겨야 한다.
    static func composedPath(shellPath: String) -> String? {
        var entries: [String] = []
        var seen: Set<String> = []

        func append(_ directory: String) {
            guard !seen.contains(directory) else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return
            }
            seen.insert(directory)
            entries.append(directory)
        }

        resolvedPath(shellPath: shellPath)?.split(separator: ":").forEach { append(String($0)) }
        wellKnownDirectories.forEach(append)

        return entries.isEmpty ? nil : entries.joined(separator: ":")
    }

    /// 셸이 뱉은 것에서 PATH 를 골라낸다.
    ///
    /// 프로파일이 인사말을 찍을 수 있으므로 **마지막 줄**을 본다. 콜론이 없으면 PATH 가
    /// 아니다 — fish 의 `$PATH` 는 목록이라 공백으로 나온다.
    static func parsePath(fromShellOutput output: String) -> String? {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = lines.last, last.contains(":"), last.contains("/") else { return nil }
        return last
    }

    static func resolvedPath(shellPath: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        // `-l` 로 `.zprofile`·`.profile` 을, `-i` 로 `.zshrc` 를 읽는다.
        //
        // 예전에는 `-i` 를 뺐다 — 대화형 프로파일이 프롬프트를 그리거나 입력을 기다리면
        // 여기서 멈추기 때문이다. 그런데 **zsh 는 `-l` 만으로는 `.zshrc` 를 안 읽고**,
        // 대부분의 사람이 거기에 homebrew 를 넣는다. 사용자가 다른 컴퓨터에서 겪은
        // `command not found` 가 그것이다.
        //
        // 멈추는 것은 표준 입력을 막고(`/dev/null`) 시간을 재서 막는다. 그래도 못 받으면
        // 흔한 위치 안전망이 받는다.
        process.arguments = ["-l", "-i", "-c", "printf %s \"$PATH\""]
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

        return parsePath(fromShellOutput: String(decoding: data, as: UTF8.self))
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

    /// 지금 쓰는 PATH. 실행이 실패했을 때 화면이 보여 준다 — "command not found" 만으로는
    /// 사용자도 우리도 무엇이 빠졌는지 알 수 없다.
    public static func describeSearchPath() -> String {
        loginPath() ?? ProcessInfo.processInfo.environment["PATH"] ?? "(없음)"
    }
}
