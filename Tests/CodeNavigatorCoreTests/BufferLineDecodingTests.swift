import Testing
import Foundation
import CodeNavigatorContract
@testable import CodeNavigatorCore

/// Decoding buffer lines, where three different situations used to produce the same value.
///
/// `arrayValue?.compactMap(\.stringValue) ?? []` collapsed them:
/// an empty buffer, a buffer whose lines could not be decoded, and a reply that was not an array
/// at all — all `[]`. The first is normal and the other two are failures, and the render view
/// says "이 파일에는 내용이 없습니다" for all three. That sentence is true for one of them.
///
/// Neovim sends msgpack `str` today (measured: fixstr, str8 and str16, valid and invalid UTF-8 —
/// every case came back `.string`). But `bin` is a legitimate thing for it to send, and a decoder
/// that silently drops what it cannot read turns a future protocol detail into a blank page.
@Suite("버퍼 줄 디코딩 — 빈 것과 못 읽은 것을 가른다")
struct BufferLineDecodingTests {

    @Test("문자열로 온 줄을 읽는다")
    func readsLinesSentAsStrings() {
        let value = MessagePackValue.array([.string("first"), .string("second")])
        #expect(value.textArrayValue == ["first", "second"])
    }

    @Test("bin 으로 온 줄도 읽는다 — msgpack 이 허용하는 형태다")
    func readsLinesSentAsBinary() {
        let value = MessagePackValue.array([
            .binary(Array("first".utf8)),
            .binary(Array("두 번째".utf8)),
        ])
        #expect(value.textArrayValue == ["first", "두 번째"])
    }

    @Test("섞여 와도 읽는다")
    func readsAMixture() {
        let value = MessagePackValue.array([.string("a"), .binary(Array("b".utf8))])
        #expect(value.textArrayValue == ["a", "b"])
    }

    @Test("빈 버퍼는 빈 배열이다 — 실패가 아니다")
    func anEmptyBufferIsAnEmptyArray() {
        #expect(MessagePackValue.array([]).textArrayValue == [])
    }

    /// The distinction the old code could not make.
    @Test("한 줄이라도 못 읽으면 nil 이다 — 빈 배열과 다르다")
    func anUndecodableLineIsNotAnEmptyBuffer() {
        // 유효하지 않은 UTF-8 바이트열.
        let value = MessagePackValue.array([.string("fine"), .binary([0xFF, 0xFE])])
        #expect(value.textArrayValue == nil, "못 읽은 줄을 조용히 빠뜨렸다")
    }

    @Test("배열이 아니면 nil 이다 — 빈 배열과 다르다")
    func aNonArrayIsNotAnEmptyBuffer() {
        #expect(MessagePackValue.string("not an array").textArrayValue == nil)
        #expect(MessagePackValue.integer(3).textArrayValue == nil)
    }

    @Test("빠뜨리지 않는다 — 원소 수가 유지된다")
    func nothingIsDroppedSilently() {
        let value = MessagePackValue.array([.string("a"), .string(""), .string("c")])
        #expect(value.textArrayValue?.count == 3, "빈 줄이 사라졌다")
    }
}
