import Testing
import Foundation
@testable import CodeNavigatorCore

/// 브레이크포인트는 "파일 12행" 이 아니라 "메서드 M 의 코드 인덱스 N" 에 걸린다. 그 사이를
/// 잇는 것이 `LineTable` 이고, 여기서 틀리면 브레이크포인트가 **엉뚱한 줄에 걸리거나 아무
/// 데도 안 걸린다** — 그리고 아무 데도 안 걸린 것은 "아직 그 줄을 안 지났다" 와 구별되지 않는다.
@Suite("JDWP 라인 테이블")
struct JDWPLineTableTests {

    private func payload(start: UInt64, end: UInt64, entries: [(UInt64, Int32)]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: start.bigEndian, Array.init)
        bytes += withUnsafeBytes(of: end.bigEndian, Array.init)
        bytes += withUnsafeBytes(of: UInt32(entries.count).bigEndian, Array.init)
        for (codeIndex, line) in entries {
            bytes += withUnsafeBytes(of: codeIndex.bigEndian, Array.init)
            bytes += withUnsafeBytes(of: line.bigEndian, Array.init)
        }
        return bytes
    }

    @Test("줄 번호를 코드 인덱스로 옮긴다")
    func mapsALineToACodeIndex() throws {
        let table = try JDWPLineTable(payload: payload(
            start: 0, end: 40,
            entries: [(0, 8), (6, 9), (14, 10)]
        ))
        #expect(table.codeIndex(forLine: 9) == 6)
        #expect(table.codeIndex(forLine: 10) == 14)
    }

    /// 한 줄이 여러 코드 인덱스에 걸릴 수 있다(루프 머리, 조건식). 브레이크포인트는 그 줄에
    /// **처음 닿는** 지점에 걸어야 한다 — 뒤쪽에 걸면 첫 진입에서 안 멈춘다.
    @Test("한 줄에 여러 항목이 있으면 가장 앞을 고른다")
    func choosesTheEarliestEntryForALine() throws {
        let table = try JDWPLineTable(payload: payload(
            start: 0, end: 40,
            entries: [(20, 12), (4, 12), (30, 13)]
        ))
        #expect(table.codeIndex(forLine: 12) == 4)
    }

    /// 실행 가능한 코드가 없는 줄이 있다 — 주석, 빈 줄, 선언만 있는 줄. 여기에 걸어 달라는
    /// 요청에 **가까운 줄로 옮겨 걸면 안 된다.** 사용자는 자기가 찍은 줄에서 멈추길 기대하고,
    /// 다른 줄에서 멈추면 그건 디버거가 거짓말을 한 것이다. 못 걸면 못 건다고 말한다.
    @Test("실행 코드가 없는 줄은 nil 이다 — 가까운 줄로 몰래 옮기지 않는다")
    func refusesALineWithNoCode() throws {
        let table = try JDWPLineTable(payload: payload(
            start: 0, end: 40,
            entries: [(0, 8), (6, 12)]
        ))
        #expect(table.codeIndex(forLine: 9) == nil)
        #expect(table.codeIndex(forLine: 100) == nil)
    }

    /// 네이티브 메서드는 라인 테이블이 없고, JDWP 는 그것을 start=end=-1 로 알린다.
    @Test("네이티브 메서드는 걸 수 있는 줄이 없다")
    func handlesANativeMethod() throws {
        let table = try JDWPLineTable(payload: payload(
            start: UInt64(bitPattern: -1), end: UInt64(bitPattern: -1), entries: []
        ))
        #expect(table.isNative)
        #expect(table.codeIndex(forLine: 8) == nil)
    }

    @Test("이 메서드가 덮는 줄 범위를 안다 — 어느 메서드에 걸지 고르는 데 쓴다")
    func reportsTheLinesItCovers() throws {
        let table = try JDWPLineTable(payload: payload(
            start: 0, end: 40, entries: [(0, 8), (6, 9), (14, 10)]
        ))
        #expect(table.coveredLines == Set([8, 9, 10]))
    }
}
