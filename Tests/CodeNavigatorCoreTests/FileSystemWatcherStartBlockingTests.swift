import Testing
import Foundation
@testable import CodeNavigatorCore

/// `start()` 는 **메인 스레드에서 스트림을 만들면 안 된다.**
///
/// 실측으로 확인한 교착: `kFSEventStreamCreateFlagWatchRoot` 를 주면 FSEvents 가
/// `watch_all_parents` 로 감시 루트의 **상위 폴더를 전부 `open()`** 한다. `~/Documents` 를
/// 여는 순간 macOS 동의 관문에 걸리는데, 그 대화상자는 메인 런루프가 돌아야 뜬다. 우리가
/// 메인 스레드에서 이 함수를 부르고 있었으니 영원히 안 떴다 — 앱이 시작하다 멈췄다.
///
/// ```
/// DispatchQueue_1: com.apple.main-thread
///   AppModel.restoreTabs → ProjectIndexer.openProject → FileSystemWatcher.start()
///     → FSEventStreamCreate → watch_all_parents → open → __open   ← 2270/2270 샘플
/// ```
///
/// 그렇다고 던져 두고 가면 안 된다 — `start()` 직후의 변경을 놓친다. 그래서 큐에서 만들되
/// 그것을 **기다린다**(막지 않고 비운다).
@Suite("감시자 시작이 메인 스레드를 막지 않는다", .serialized)
struct FileSystemWatcherStartBlockingTests {

    private func makeDirectory() throws -> String {
        let root = NSTemporaryDirectory() + "watch-start-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    @Test("스트림을 메인 스레드에서 만들지 않는다")
    func doesNotCreateTheStreamOnTheMainThread() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        await watcher.start()
        defer { watcher.stop() }

        #expect(
            watcher.createdOnMainThreadForTesting == false,
            "메인 스레드에서 만들었다 — 그 호출이 막히면 앱이 통째로 멈춘다"
        )
    }

    /// 돌아왔으면 이미 감시 중이어야 한다. 던져 두고 가면 직후에 생긴 변경을 놓치는데,
    /// 부르는 쪽은 이미 그 약속에 기대고 있다.
    @Test("돌아오면 이미 감시 중이다")
    func isWatchingOnceItReturns() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        await watcher.start()
        defer { watcher.stop() }
        #expect(watcher.hasStreamForTesting, "돌아왔는데 아직 안 붙었다")
    }

    /// 붙기 전에 멈춰도 안전해야 한다. 창을 열자마자 닫는 경우가 그 모양이다.
    @Test("기다리지 않고 시작한 뒤 곧바로 멈춰도 스트림이 남지 않는다")
    func stoppingRightAfterAFireAndForgetStartLeavesNothing() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let watcher = FileSystemWatcher(rootPath: root) { _ in }
        watcher.startWithoutWaiting()
        watcher.stop()

        // 뒤늦게 생성이 끝나 스트림이 되살아나면, 아무도 안 보는 감시자가 남아 이벤트를
        // 흘린다 — 닫은 탭이 계속 색인을 건드리는 모양이다.
        try await Task.sleep(for: .seconds(1))
        #expect(watcher.hasStreamForTesting == false, "멈춘 뒤에 스트림이 되살아났다")
    }
}
