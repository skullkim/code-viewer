import Testing
import Foundation
import CoreGraphics
@testable import CodeNavigatorAppKit

@MainActor
@Suite("ShellPreferences — 분할 비율·영역 표시 복원 (REQ-011 AC-3)")
struct ShellPreferencesTests {

    @Test("처음 실행하면 설계 기본값이고 두 영역이 다 보인다")
    func theFirstRunLooksLikeTheWireframe() {
        let preferences = ShellPreferences(storage: InMemoryKeyValueStore())

        #expect(preferences.treeWidth == ShellLayout.Metrics.treeDefaultWidth)
        #expect(preferences.panelWidth == ShellLayout.Metrics.panelDefaultWidth)
        #expect(preferences.isTreeVisible)
        #expect(preferences.isPanelVisible)
    }

    @Test("드래그한 폭과 숨긴 영역이 재시작 후 돌아온다")
    func draggedWidthsSurviveARestart() {
        let storage = InMemoryKeyValueStore()

        let first = ShellPreferences(storage: storage)
        first.setTreeWidth(300)
        first.setPanelWidth(420)
        first.isPanelVisible = false

        let second = ShellPreferences(storage: storage)
        #expect(second.treeWidth == CGFloat(300))
        #expect(second.panelWidth == CGFloat(420))
        #expect(second.isTreeVisible)
        #expect(!second.isPanelVisible)
    }

    @Test("한계를 벗어난 드래그는 저장 시점에 이미 잘린다")
    func anOutOfRangeDragIsClampedBeforeItIsStored() {
        let storage = InMemoryKeyValueStore()

        let first = ShellPreferences(storage: storage)
        first.setTreeWidth(5_000)
        first.setPanelWidth(1)

        #expect(first.treeWidth == ShellLayout.Metrics.treeMaximumWidth)
        #expect(first.panelWidth == ShellLayout.Metrics.panelMinimumWidth)

        let second = ShellPreferences(storage: storage)
        #expect(second.treeWidth == ShellLayout.Metrics.treeMaximumWidth)
        #expect(second.panelWidth == ShellLayout.Metrics.panelMinimumWidth)
    }

    @Test("손상된 저장값은 앱을 못 그리게 만들지 않는다")
    func damagedStoredValuesFallBackToTheDefaults() {
        let storage = InMemoryKeyValueStore()
        storage.setData("바나나".data(using: .utf8), forKey: ShellPreferences.treeWidthKey)
        storage.setData(Data([0xFF, 0xFE]), forKey: ShellPreferences.panelWidthKey)

        let preferences = ShellPreferences(storage: storage)
        #expect(preferences.treeWidth == ShellLayout.Metrics.treeDefaultWidth)
        #expect(preferences.panelWidth == ShellLayout.Metrics.panelDefaultWidth)
    }

    @Test("직접 써넣은 극단값도 읽을 때 잘린다 — 저장물은 코드보다 오래 산다")
    func aHandWrittenExtremeIsClampedOnRead() {
        let storage = InMemoryKeyValueStore()
        storage.setData("99999".data(using: .utf8), forKey: ShellPreferences.treeWidthKey)
        storage.setData("-40".data(using: .utf8), forKey: ShellPreferences.panelWidthKey)

        let preferences = ShellPreferences(storage: storage)
        #expect(preferences.treeWidth == ShellLayout.Metrics.treeMaximumWidth)
        #expect(preferences.panelWidth == ShellLayout.Metrics.panelMinimumWidth)
    }
}
