import Foundation

/// `Method.LineTable` (6, 1) — 소스 줄과 바이트코드 위치 사이의 지도.
///
/// 브레이크포인트는 "파일 12행" 이 아니라 "메서드 M 의 코드 인덱스 N" 에 걸린다. 이 지도가
/// 그 사이를 잇고, 여기서 틀리면 브레이크포인트가 엉뚱한 줄에 걸리거나 아무 데도 안 걸린다 —
/// 그리고 **아무 데도 안 걸린 것은 "아직 그 줄을 안 지났다" 와 구별되지 않는다.**
struct JDWPLineTable: Sendable {
    /// 이 메서드 바이트코드의 시작·끝. 네이티브 메서드면 둘 다 -1 이다.
    let start: Int64
    let end: Int64
    /// 코드 인덱스 → 줄 번호. JVM 이 주는 순서 그대로 둔다.
    private let entries: [(codeIndex: UInt64, line: Int32)]

    var isNative: Bool { start == -1 && end == -1 }

    var coveredLines: Set<Int> { Set(entries.map { Int($0.line) }) }

    init(payload: [UInt8]) throws {
        var reader = JDWPReader(bytes: payload)
        self.start = Int64(bitPattern: try reader.readUInt64())
        self.end = Int64(bitPattern: try reader.readUInt64())
        let count = Int(try reader.readUInt32())
        var entries: [(UInt64, Int32)] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            let codeIndex = try reader.readUInt64()
            let line = try reader.readInt32()
            entries.append((codeIndex, line))
        }
        self.entries = entries
    }

    /// Where to plant a breakpoint for `line`, or nil when the line has no executable code.
    ///
    /// **가까운 줄로 몰래 옮기지 않는다.** 주석이나 빈 줄에 걸어 달라는 요청을 다음 실행
    /// 가능한 줄로 밀어 주면, 사용자는 자기가 찍지 않은 줄에서 멈춘 화면을 본다. 그건 편의가
    /// 아니라 디버거가 거짓말을 한 것이다. 못 걸면 못 건다고 말하고, 위층이 사용자에게 알린다.
    ///
    /// 한 줄이 여러 코드 인덱스에 걸리면(루프 머리, 조건식) **가장 앞**을 고른다. 뒤쪽에 걸면
    /// 그 줄에 처음 닿을 때 안 멈춘다.
    func codeIndex(forLine line: Int) -> UInt64? {
        entries
            .filter { Int($0.line) == line }
            .map(\.codeIndex)
            .min()
    }

    /// Which source line a program counter is on — the reverse direction, for showing a stack.
    ///
    /// 정확히 일치하는 항목을 찾는 게 아니라 **그 위치를 넘지 않는 마지막 항목**을 찾는다.
    /// 한 줄은 여러 명령으로 컴파일되고, 스택의 코드 인덱스는 그 중간을 가리키는 것이 보통이다.
    /// 일치만 찾으면 대부분의 프레임이 "줄 모름" 으로 나온다.
    func line(forCodeIndex codeIndex: UInt64) -> Int? {
        entries
            .filter { $0.codeIndex <= codeIndex }
            .max { $0.codeIndex < $1.codeIndex }
            .map { Int($0.line) }
    }
}
