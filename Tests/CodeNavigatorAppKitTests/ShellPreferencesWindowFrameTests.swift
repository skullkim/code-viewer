import Testing
import Foundation
import CoreGraphics
@testable import CodeNavigatorAppKit

/// REQ-011 AC-3: the window reopens where it was.
///
/// The pairing that matters is save-then-launch-elsewhere. Storing the frame is trivial;
/// what earns a test is that a frame stored on one display cannot open the window somewhere
/// invisible on another — and that a damaged preference reads as "no frame" instead of as a
/// window at NaN.
@MainActor
@Suite("ShellPreferences 창 프레임 — 저장과 복원 (REQ-011 AC-3)")
struct ShellPreferencesWindowFrameTests {

    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1055)

    private func makePreferences() -> (ShellPreferences, InMemoryKeyValueStore) {
        let storage = InMemoryKeyValueStore()
        return (ShellPreferences(storage: storage), storage)
    }

    @Test("첫 실행에는 저장된 프레임이 없다")
    func aFirstRunHasNoStoredFrame() {
        // nil이라야 호출부가 "기본 크기로 가운데"를 고를 수 있다. 0으로 채운 사각형을
        // 돌려주면 그 구분이 사라진다.
        let (preferences, _) = makePreferences()
        #expect(preferences.windowFrame(forVisibleFrames: [mainScreen]) == nil)
    }

    @Test("저장한 프레임이 다음 실행에 돌아온다")
    func aSavedFrameComesBack() {
        let (preferences, storage) = makePreferences()
        // 화면(높이 1055) 안에 완전히 들어가는 프레임이라야 "그대로 돌아온다"만 검증된다.
        let frame = CGRect(x: 240, y: 100, width: 1400, height: 900)

        preferences.setWindowFrame(frame)

        // 새 인스턴스로 읽는다 — 재시작을 흉내 내는 것이 요점이다.
        let restored = ShellPreferences(storage: storage)
        #expect(restored.windowFrame(forVisibleFrames: [mainScreen]) == frame)
    }

    @Test("사라진 모니터에 저장된 프레임은 보이는 화면으로 돌아온다")
    func aFrameFromADetachedMonitorIsBroughtBack() {
        let (preferences, storage) = makePreferences()
        preferences.setWindowFrame(CGRect(x: 3000, y: 200, width: 1280, height: 800))

        let restored = ShellPreferences(storage: storage)
        let frame = restored.windowFrame(forVisibleFrames: [mainScreen])

        #expect(frame != nil)
        #expect(mainScreen.intersection(frame ?? .zero).isNull == false)
    }

    @Test("저장은 화면에 맞추지 않고 원본 그대로 한다")
    func savingKeepsTheFrameUnfitted() {
        // 어떤 화면이 붙어 있는지는 실행 시점의 사실이다. 저장 때 잘라 버리면 외장
        // 모니터를 다시 꽂았을 때 원래 자리로 못 돌아간다.
        let (preferences, storage) = makePreferences()
        let offScreen = CGRect(x: 3000, y: 200, width: 1280, height: 800)

        preferences.setWindowFrame(offScreen)

        let secondScreen = CGRect(x: 1920, y: 0, width: 1440, height: 1055)
        let restored = ShellPreferences(storage: storage)
        #expect(restored.windowFrame(forVisibleFrames: [mainScreen, secondScreen]) == offScreen)
    }

    @Test("손상된 프레임 데이터는 저장 없음으로 읽힌다")
    func damagedFrameDataReadsAsAbsent() {
        let (_, storage) = makePreferences()

        for damaged in ["", "1,2,3", "a,b,c,d", "1,2,3,4,5", "nan,2,3,4"] {
            storage.setData(damaged.data(using: .utf8), forKey: ShellPreferences.windowFrameKey)
            let preferences = ShellPreferences(storage: storage)

            #expect(
                preferences.windowFrame(forVisibleFrames: [mainScreen]) == nil,
                "손상 입력 \"\(damaged)\"가 프레임으로 읽혔다"
            )
        }
    }

    @Test("창 프레임 저장이 다른 복원 값을 건드리지 않는다")
    func savingTheFrameLeavesTheOtherValuesAlone() {
        // 넷이 한 저장소를 공유하므로, 하나를 쓰면서 다른 키를 밟지 않는지 확인한다.
        let (preferences, storage) = makePreferences()
        preferences.setTreeWidth(300)
        preferences.setPanelWidth(380)
        preferences.isTreeVisible = false

        preferences.setWindowFrame(CGRect(x: 10, y: 20, width: 1300, height: 820))

        let restored = ShellPreferences(storage: storage)
        #expect(restored.treeWidth == CGFloat(300))
        #expect(restored.panelWidth == CGFloat(380))
        #expect(restored.isTreeVisible == false)
        #expect(restored.isPanelVisible == true)
    }
}
