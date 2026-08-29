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

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
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

/// The C callback. It must have no captures to be convertible to a C function pointer, so the
/// watcher travels through the stream's info pointer instead.
private let fileSystemWatcherCallback: FSEventStreamCallback = {
    _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in

    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

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
