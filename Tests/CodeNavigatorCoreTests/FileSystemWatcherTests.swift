import Testing
import Foundation
@testable import CodeNavigatorCore

/// Exercises the real FSEvents stream. These are timing-bound by nature, so each wait polls for a
/// condition instead of sleeping a fixed amount.
@Suite("FileSystemWatcher — 실제 FSEvents", .serialized)
final class FileSystemWatcherTests {

    private final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [FileSystemChangeEvent] = []

        func add(_ newEvents: [FileSystemChangeEvent]) {
            lock.lock()
            defer { lock.unlock() }
            events.append(contentsOf: newEvents)
        }

        var collected: [FileSystemChangeEvent] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }

        /// Waits until the collected events satisfy a condition, or gives up.
        func waitFor(
            timeout: TimeInterval = 5,
            _ condition: ([FileSystemChangeEvent]) -> Bool
        ) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition(collected) { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return condition(collected)
        }
    }

    @Test("파일 생성·수정·삭제가 상대 경로로 보고된다")
    func reportsCreateModifyAndDelete() throws {
        let fixture = TemporaryProjectFixture()
        let collector = EventCollector()
        let watcher = FileSystemWatcher(rootPath: fixture.rootURL.path) { collector.add($0) }
        watcher.start()
        defer { watcher.stop() }

        fixture.write("src/App.kt", contents: "class App")
        #expect(collector.waitFor { events in
            events.contains { $0.relativePath == "src/App.kt" && $0.kind == .changed }
        })

        fixture.remove("src/App.kt")
        #expect(collector.waitFor { events in
            events.contains { $0.relativePath == "src/App.kt" && $0.kind == .removed }
        })
    }

    @Test("에디터식 원자적 저장도 변경으로 보고된다 — rename 이라고 놓치지 않는다")
    func reportsAtomicSavesAsChanges() throws {
        let fixture = TemporaryProjectFixture()
        fixture.write("src/App.kt", contents: "original")
        let collector = EventCollector()
        let watcher = FileSystemWatcher(rootPath: fixture.rootURL.path) { collector.add($0) }
        watcher.start()
        defer { watcher.stop() }

        // 임시 파일에 쓰고 원본 위로 rename — Neovim·대부분의 에디터가 하는 저장 방식.
        let temporary = fixture.rootURL.appendingPathComponent("src/App.kt.tmp")
        let target = fixture.rootURL.appendingPathComponent("src/App.kt")
        try "updated".write(to: temporary, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)

        #expect(collector.waitFor { events in
            events.contains { $0.relativePath == "src/App.kt" && $0.kind == .changed }
        })
    }

    @Test("스트림 시작 후 만들어진 디렉토리 안의 파일도 감지된다")
    func detectsFilesInDirectoriesCreatedAfterStart() throws {
        let fixture = TemporaryProjectFixture()
        let collector = EventCollector()
        let watcher = FileSystemWatcher(rootPath: fixture.rootURL.path) { collector.add($0) }
        watcher.start()
        defer { watcher.stop() }

        fixture.write("brand/new/Deep.kt", contents: "class Deep")
        #expect(collector.waitFor { events in
            events.contains { $0.relativePath == "brand/new/Deep.kt" }
        })
    }

    @Test("대량 변경에서도 죽지 않고 이벤트를 흘려보낸다")
    func survivesBulkChanges() throws {
        let fixture = TemporaryProjectFixture()
        let collector = EventCollector()
        let watcher = FileSystemWatcher(rootPath: fixture.rootURL.path) { collector.add($0) }
        watcher.start()
        defer { watcher.stop() }

        for index in 0..<200 {
            fixture.write("bulk/File\(index).kt", contents: "class File\(index)")
        }

        #expect(collector.waitFor(timeout: 10) { $0.count >= 100 })
    }

    @Test("감시 루트 밖의 경로는 보고하지 않는다")
    func ignoresPathsOutsideTheRoot() throws {
        let fixture = TemporaryProjectFixture()
        let outside = TemporaryProjectFixture()
        let collector = EventCollector()
        let watcher = FileSystemWatcher(rootPath: fixture.rootURL.path) { collector.add($0) }
        watcher.start()
        defer { watcher.stop() }

        outside.write("Elsewhere.kt", contents: "class Elsewhere")
        fixture.write("Inside.kt", contents: "class Inside")

        #expect(collector.waitFor { events in
            events.contains { $0.relativePath == "Inside.kt" }
        })
        #expect(collector.collected.allSatisfy { $0.relativePath != "Elsewhere.kt" })
    }
}
