import Testing
import Foundation
@testable import CodeNavigatorCore

/// 게이트가 잡은 크래시. `swift test` 가 SIGSEGV 로 죽었고 스택은 이랬다:
///
/// ```
/// FSEvents root_dir_event_callback → fileSystemWatcherCallback → 0x0
/// ```
///
/// 스트림이 감시자를 **약하게** 들고 있었다. `deinit` 이 스트림을 무효화해도 큐에 이미 실린
/// 콜백은 그 뒤에 실행될 수 있고, 그때 해제된 객체를 되살리면 주소 0 으로 뛴다.
///
/// 테스트만의 문제가 아니다 — 앱에서 탭을 닫는 순간이 정확히 같은 모양이다. 다만 앱에서는
/// 크래시 리포트가 사용자 손에 있고 우리는 못 본다.
@Suite("파일 감시자 해제")
struct FileSystemWatcherTeardownTests {

    @Test("떼어 낸 상자는 콜백에 아무것도 주지 않는다")
    func aDetachedBoxHandsNothingBack() {
        let watcher = FileSystemWatcher(rootPath: NSTemporaryDirectory()) { _ in }
        let box = FileSystemWatcherBox(watcher: watcher)

        #expect(box.watcher != nil)
        box.detach()
        // 이게 크래시를 막는 한 줄이다. 콜백은 여기서 nil 을 받고 조용히 돌아간다.
        #expect(box.watcher == nil)
    }

    /// 떼어 내는 일과 읽는 일이 다른 스레드에서 동시에 일어난다 — 콜백은 FSEvents 큐에서,
    /// 해제는 그 객체를 마지막으로 놓는 스레드에서. 잠금 없이 두면 그 사이가 크래시 창이다.
    @Test("여러 스레드가 동시에 읽고 떼어 내도 무너지지 않는다")
    func survivesConcurrentDetachAndRead() async {
        for _ in 0..<200 {
            let watcher = FileSystemWatcher(rootPath: NSTemporaryDirectory()) { _ in }
            let box = FileSystemWatcherBox(watcher: watcher)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask { _ = box.watcher }
                }
                group.addTask { box.detach() }
            }
            #expect(box.watcher == nil)
        }
    }

    /// 감시자를 만들고 버리는 동안 실제 파일이 바뀐다. 예전 구조에서는 이 조합이 크래시였다.
    @Test("감시 중에 버려도 살아남는다")
    func survivesBeingDroppedWhileWatching() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-teardown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for round in 0..<12 {
            var watcher: FileSystemWatcher? = FileSystemWatcher(rootPath: root.path) { _ in }
            watcher?.start()
            // 이벤트를 만들고 **기다리지 않고** 버린다. 콜백이 날아오는 중에 해제되는 것이
            // 재현하려는 그 순간이다.
            try "round \(round)".write(
                to: root.appendingPathComponent("file-\(round).txt"), atomically: true, encoding: .utf8
            )
            watcher = nil
        }
        // 여기까지 오면 통과다 — 크래시는 단언이 아니라 프로세스 종료로 드러난다.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(Bool(true))
    }
}
