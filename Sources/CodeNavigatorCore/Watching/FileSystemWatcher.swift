import CoreServices
import Foundation

/// Watches a project tree for changes with FSEvents.
///
/// FSEvents watches recursively and picks up directories created after the stream starts, so no
/// re-registration is needed as the project grows. It needs no entitlements.
///
/// Two measured details shape this code (ADR-0005):
/// - The C callback cannot capture context, so the watcher is passed through the stream's info
///   pointer. It also must not live in `main.swift`, where Swift 6 would make it main-actor
///   isolated and refuse to convert it to a C function pointer.
/// - FSEvents reports fully symlink-resolved paths (`/tmp` arrives as `/private/tmp`), while
///   `URL.resolvingSymlinksInPath()` deliberately leaves those prefixes alone. Comparing against
///   the unresolved root makes every path fail to match, silently. `realpath` is the fix.
final class FileSystemWatcher: @unchecked Sendable {
    /// Matches the debounce window: FSEvents coalesces within its own latency window, and a
    /// measured single-change notification arrives in about 12ms with `NoDefer` set.
    static let eventLatencySeconds = 0.1

    private let rootPath: String
    private let onEvents: @Sendable ([FileSystemChangeEvent]) -> Void
    private let queue = DispatchQueue(label: "code-navigator.file-watcher")
    private var stream: FSEventStreamRef?
    /// 스트림이 실제로 붙들고 있는 것. 감시자 자신이 아니라 이 상자다.
    private var box: FileSystemWatcherBox?

    /// - Parameter rootPath: the project root. It is canonicalised here so incoming event paths
    ///   can be made relative to it.
    init(rootPath: String, onEvents: @escaping @Sendable ([FileSystemChangeEvent]) -> Void) {
        self.rootPath = Self.canonicalPath(rootPath)
        self.onEvents = onEvents
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        // **스트림에 감시자를 직접 주지 않는다.** 예전에는 `passUnretained(self)` 였고,
        // 게이트가 그 대가를 SIGSEGV 로 청구했다:
        //
        //     FSEvents root_dir_event_callback → fileSystemWatcherCallback → 0x0
        //
        // `deinit` 이 스트림을 무효화해도 큐에 **이미 실린** 콜백은 그 뒤에 실행될 수 있고,
        // 그때 해제된 객체를 되살리면 주소 0 으로 뛴다. 앱에서는 탭을 닫는 순간이 정확히
        // 같은 모양인데, 그 크래시 리포트는 사용자 손에 있고 우리는 못 본다.
        //
        // 그래서 스트림은 상자를 **강하게** 붙들고(retain/release 를 준다), 상자는 감시자를
        // 잠금 아래 놓아 준다. 해제할 때 상자를 떼어 내면 뒤늦은 콜백은 nil 을 받고 돌아간다.
        // 상자가 스트림에 붙들리는 것은 순환이 아니다 — 감시자는 상자를 소유하지만 상자는
        // 감시자를 소유하지 않는다.
        let box = FileSystemWatcherBox(watcher: self)
        self.box = box

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(Unmanaged<FileSystemWatcherBox>.fromOpaque(pointer).retain().toOpaque())
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<FileSystemWatcherBox>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
                // Without this the stream goes quiet with no signal if the root is moved away.
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileSystemWatcherCallback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.eventLatencySeconds,
            flags
        ) else {
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        // **먼저 떼어 낸다.** 무효화를 먼저 하면 그 사이에 이미 큐에 실린 콜백이 아직 살아
        // 있는 감시자를 잡고 들어올 수 있고, 그 콜백이 끝나기 전에 `deinit` 이 끝나면
        // 같은 크래시다. 떼어 내는 것이 먼저여야 순서가 성립한다.
        box?.detach()
        box = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Called from the C callback with one batch of events.
    fileprivate func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        var events: [FileSystemChangeEvent] = []
        events.reserveCapacity(paths.count)

        for (index, path) in paths.enumerated() {
            let eventFlags = FileSystemEventFlags(rawValue: flags[index])

            if eventFlags.requiresFullRescan || eventFlags.rootChanged {
                events.append(.init(relativePath: nil, kind: .changed, requiresFullRescan: true))
                continue
            }
            // Directory events carry no per-file information we can use; the files inside them
            // arrive as their own events.
            guard eventFlags.isFile, let relativePath = relativePath(for: path) else {
                continue
            }
            let exists = FileManager.default.fileExists(atPath: path)
            events.append(
                .init(
                    relativePath: relativePath,
                    kind: eventFlags.changeKind(pathExists: exists),
                    requiresFullRescan: false
                )
            )
        }

        guard !events.isEmpty else { return }
        onEvents(events)
    }

    private func relativePath(for absolutePath: String) -> String? {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard absolutePath.hasPrefix(prefix) else { return nil }
        return String(absolutePath.dropFirst(prefix.count))
    }

    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

/// One change the watcher observed, already made relative to the project root.
struct FileSystemChangeEvent: Equatable {
    /// `nil` when the event is not about one file — a drop signal or a root change.
    let relativePath: String?
    let kind: FileChangeKind
    let requiresFullRescan: Bool
}

/// What the stream actually holds.
///
/// 감시자와 스트림 사이에 한 겹을 둔다. 스트림은 이 상자를 강하게 붙들고, 상자는 감시자를
/// 잠금 아래 놓아 준다 — 해제할 때 떼어 내면 뒤늦게 도착한 콜백이 nil 을 받고 조용히 돌아간다.
///
/// 상자가 감시자를 **소유하지 않는** 것이 요점이다. 소유하면 스트림 → 상자 → 감시자로
/// 순환이 되고, `deinit` 이 영영 안 불려서 스트림이 남는다.
final class FileSystemWatcherBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storedWatcher: FileSystemWatcher?

    init(watcher: FileSystemWatcher) {
        self.storedWatcher = watcher
    }

    var watcher: FileSystemWatcher? {
        lock.lock()
        defer { lock.unlock() }
        return storedWatcher
    }

    func detach() {
        lock.lock()
        storedWatcher = nil
        lock.unlock()
    }
}

/// The C callback. It must have no captures to be convertible to a C function pointer, so the
/// box travels through the stream's info pointer instead.
private let fileSystemWatcherCallback: FSEventStreamCallback = {
    _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in

    guard let clientCallBackInfo else { return }
    let box = Unmanaged<FileSystemWatcherBox>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    // 이미 떼어 낸 상자다 — 감시자가 사라진 뒤에 도착한 이벤트다. 조용히 돌아간다.
    guard let watcher = box.watcher else { return }

    // kFSEventStreamCreateFlagUseCFTypes was set, so this is a CFArray of CFString.
    let pathsArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    guard let paths = pathsArray as? [String] else { return }

    var flags: [FSEventStreamEventFlags] = []
    flags.reserveCapacity(numEvents)
    for index in 0..<numEvents {
        flags.append(eventFlags[index])
    }

    watcher.handle(paths: paths, flags: flags)
}
