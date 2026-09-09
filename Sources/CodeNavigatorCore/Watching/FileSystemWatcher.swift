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
    /// 상태는 **큐가 아니라 잠금으로** 지킨다.
    ///
    /// 큐로 지키려다 트랩을 받았다: `start()` 의 블록이 끝나면서 마지막 참조가 **큐 위에서**
    /// 풀리면 `deinit` 이 그 큐에서 돌고, 거기서 같은 큐에 `sync` 하면 자기를 기다린다.
    ///
    ///     __DISPATCH_WAIT_FOR_QUEUE__ ← stop() ← deinit ← closure #1 in start()
    ///
    /// 잠금은 `deinit` 이 어느 스레드에서 돌든 안전하다.
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    /// 스트림이 실제로 붙들고 있는 것. 감시자 자신이 아니라 이 상자다.
    private var box: FileSystemWatcherBox?
    /// 멈추라는 말을 들었는지. 생성이 끝나기 **전에** 멈추면, 뒤늦게 붙는 스트림이 남아
    /// 아무도 안 보는 감시자가 이벤트를 흘린다 — 닫은 탭이 계속 색인을 건드리는 모양이다.
    private var isStopped = false

    /// - Parameter rootPath: the project root. It is canonicalised here so incoming event paths
    ///   can be made relative to it.
    init(rootPath: String, onEvents: @escaping @Sendable ([FileSystemChangeEvent]) -> Void) {
        self.rootPath = Self.canonicalPath(rootPath)
        self.onEvents = onEvents
    }

    deinit {
        stop()
    }

    /// 감시를 시작한다. **부르는 스레드에서 스트림을 만들지 않는다.**
    ///
    /// `kFSEventStreamCreateFlagWatchRoot` 를 주면 FSEvents 가 `watch_all_parents` 로 **모든
    /// 상위 폴더를 `open()`** 한다. `~/Documents` 같은 곳을 여는 순간 macOS 의 동의 관문에
    /// 걸리는데, 그 대화상자는 메인 런루프가 돌아야 뜬다. 메인 스레드에서 이 함수를 부르면
    /// 우리가 그 런루프를 막고 있으므로 대화상자가 영원히 안 뜬다 — 앱이 시작하다 멈췄다.
    /// 실측한 스택이 그 자리를 정확히 가리켰다:
    ///
    ///     main-thread → FileSystemWatcher.start() → FSEventStreamCreate
    ///       → watch_all_parents → open → __open      (2270/2270 샘플)
    ///
    /// 네트워크 볼륨이나 느린 디스크에서도 같은 모양이 된다. 그래서 만드는 일 자체를
    /// 감시자의 큐로 옮긴다.
    /// 감시를 시작한다. **돌아오면 이미 감시 중이다.**
    ///
    /// 만드는 일은 감시자의 큐에서 하고 여기서는 그것을 기다린다. 기다리는 방식이 중요하다 —
    /// 메인 스레드를 **막지 않고 비운다**(`await`). 막으면 동의 관문의 대화상자가 뜰 수
    /// 없어서 서로를 기다리는 교착이 된다.
    ///
    /// 기다리지 않고 그냥 던져 두면 `start()` 직후에 생긴 파일 변경을 놓친다. 실제로
    /// 그렇게 만들었다가 테스트가 잡았다 — "돌아왔으니 감시 중" 이라는 약속은 부르는 쪽이
    /// 이미 기대고 있는 것이다.
    func start() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.createStream()
                continuation.resume()
            }
        }
    }

    /// 기다릴 수 없는 자리를 위한 것. 되도록 `start()` 를 쓴다 — 이것을 쓰면 직후의 변경을
    /// 놓칠 수 있다.
    func startWithoutWaiting() {
        queue.async { [weak self] in
            self?.createStream()
        }
    }

    private func createStream() {
        stateLock.lock()
        createdOnMainThreadForTesting = Thread.isMainThread
        let alreadyRunning = stream != nil || isStopped
        stateLock.unlock()
        guard !alreadyRunning else { return }

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

        // 만드는 사이에 멈추라는 말이 왔으면 붙이지 않고 버린다. 붙이면 아무도 안 보는
        // 감시자가 남아 이벤트를 흘린다 — 닫은 탭이 계속 색인을 건드리는 모양이다.
        stateLock.lock()
        if isStopped || stream != nil {
            stateLock.unlock()
            FSEventStreamRelease(created)
            return
        }
        stream = created
        self.box = box
        stateLock.unlock()

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    /// 테스트용 — 스트림이 실제로 붙었는지. 생성이 비동기라 "시작했다" 와 "붙었다" 가
    /// 다른 시점이 됐고, 그 차이가 이 수정의 전부다.
    var hasStreamForTesting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stream != nil
    }

    /// 테스트용 — 스트림을 **어느 스레드에서** 만들었는지.
    ///
    /// "동기냐 비동기냐" 는 `queue.sync` 접근자로는 못 잰다. 그 접근자가 큐에 실린 생성
    /// 작업을 기다려 버려서, 어느 쪽이든 "이미 만들어졌다" 로 보인다. 실제로 그렇게 재려다
    /// 틀린 판정을 받았다. 지키려는 성질은 "부르는 스레드에서 만들지 않는다" 이므로 그것을
    /// 그대로 잰다.
    ///
    /// 재는 것은 "메인 스레드였는가" 다. 지켜야 할 성질이 그것이다 — 메인 스레드가 비어
    /// 있어야 동의 관문의 대화상자가 뜬다.
    private(set) var createdOnMainThreadForTesting: Bool?

    func stop() {
        // 잠금 아래에서 **꺼내 오고 비운다.** 큐에 `sync` 하면 `deinit` 이 그 큐에서 돌 때
        // 자기를 기다리다 트랩한다 — 실제로 받았다.
        stateLock.lock()
        isStopped = true
        // **먼저 떼어 낸다.** 무효화를 먼저 하면 그 사이에 이미 큐에 실린 콜백이 아직 살아
        // 있는 감시자를 잡고 들어올 수 있고, 그 콜백이 끝나기 전에 `deinit` 이 끝나면
        // 같은 크래시다. 떼어 내는 것이 먼저여야 순서가 성립한다.
        box?.detach()
        box = nil
        let stopping = stream
        stream = nil
        stateLock.unlock()

        // 무효화는 잠금 밖에서 한다. 이 호출은 큐를 건드리므로, 잠금을 쥔 채로 하면
        // 콜백 쪽과 서로 기다릴 수 있다.
        guard let stopping else { return }
        FSEventStreamStop(stopping)
        FSEventStreamInvalidate(stopping)
        FSEventStreamRelease(stopping)
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
