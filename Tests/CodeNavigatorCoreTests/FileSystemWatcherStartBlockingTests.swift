import Testing
import Foundation
@testable import CodeNavigatorCore

/// `start()` 는 부르는 스레드를 막으면 안 된다.
///
/// 실측으로 확인한 교착: `kFSEventStreamCreateFlagWatchRoot` 를 주면 FSEvents 가
/// `watch_all_parents` 로 **모든 상위 폴더를 `open()`** 한다. `~/Documents` 를 여는 순간
/// TCC 동의 관문에 걸리는데, 그 대화상자는 메인 런루프가 돌아야 뜬다. 우리가 메인 스레드에서
/// 이 함수를 부르고 있었으니 영원히 안 뜬다 — 앱이 시작하다 멈췄다.
///
/// ```
/// DispatchQueue_1: com.apple.main-thread
///   AppModel.restoreTabs → ProjectIndexer.openProject → FileSystemWatcher.start()
///     → FSEventStreamCreate → watch_all_parents → open → __open   ← 2270/2270 샘플
/// ```
///
/// 권한이 관여하지만 원인은 우리 코드다. I/O 를 메인 스레드에서 하고 있었다.
@Suite("감시자 시작이 부르는 쪽을 막지 않는다", .serialized)
struct FileSystemWatcherStartBlockingTests {

    private func makeDirectory() throws -> String {
        let root = NSTemporaryDirectory() + "watch-start-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    /// 스트림 생성이 **부르는 스레드 밖에서** 일어나는지. 여기서 만들면, 그 만드는 일이
    /// 무엇에 걸리든(동의 관문·네트워크 볼륨·느린 디스크) 그대로 창이 멈춘다.
    ///
    /// "스트림이 아직 없다" 로는 못 잰다 — 그걸 읽는 접근자가 큐를 기다려 버려서 어느
    /// 쪽이든 "이미 만들어졌다" 로 보인다. 실제로 그렇게 재려다 틀린 판정을 받았다.
    @Test("스트림을 부르는 스레드에서 만들지 않는다")
    func doesNotCreateTheStreamOnTheCallingThread() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let callingThread = ObjectIdentifier(Thread.current)
        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        watcher.start()
        defer { watcher.stop() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, watcher.creationThreadForTesting == nil {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let creationThread = watcher.creationThreadForTesting
        #expect(creationThread != nil, "스트림 생성이 아예 안 돌았다")
        #expect(
            creationThread != callingThread,
            "부르는 스레드에서 만들었다 — 그 호출이 막히면 앱이 통째로 멈춘다"
        )
    }

    /// 비동기로 옮겼다고 감시가 늦어지면 안 된다. 곧 실제로 붙어야 한다.
    @Test("곧 스트림이 붙는다")
    func attachesShortlyAfterwards() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        watcher.start()
        defer { watcher.stop() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !watcher.hasStreamForTesting {
            Thread.sleep(forTimeInterval: 0.02)
        }
        #expect(watcher.hasStreamForTesting, "5초 안에 스트림이 안 붙었다")
    }

    /// 붙기 전에 바로 내려도 안전해야 한다. 창을 열자마자 닫는 경우가 그 모양이다.
    @Test("붙기 전에 멈춰도 스트림이 남지 않는다")
    func stoppingBeforeTheStreamAttachesLeavesNothing() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        watcher.start()
        watcher.stop()

        // 뒤늦게 생성이 끝나 스트림이 되살아나면, 아무도 안 보는 감시자가 남아 이벤트를
        // 흘린다 — 닫은 탭이 계속 색인을 건드리는 모양이다.
        Thread.sleep(forTimeInterval: 1.0)
        #expect(watcher.hasStreamForTesting == false, "멈춘 뒤에 스트림이 되살아났다")
    }
}
