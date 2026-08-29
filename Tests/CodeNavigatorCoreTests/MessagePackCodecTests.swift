import Testing

@testable import CodeNavigatorCore

/// covers: ADR-0006 (Neovim RPC 계층) — MessagePack 코덱.
/// Neovim이 실제로 보내는 전 타입을 다루고, 부분 프레임을 "미완성"으로 알려야 한다.
@Suite("MessagePackCodec")
struct MessagePackCodecTests {

    private func roundTrip(_ value: MessagePackValue) throws -> MessagePackValue {
        var decoder = MessagePackDecoder(bytes: MessagePackEncoder.encode(value))
        return try decoder.decodeValue()
    }

    // 타입별 왕복.

    @Test("nil·bool이 왕복한다")
    func nilAndBooleanRoundTrip() throws {
        #expect(try roundTrip(.nilValue) == .nilValue)
        #expect(try roundTrip(.boolean(true)) == .boolean(true))
        #expect(try roundTrip(.boolean(false)) == .boolean(false))
    }

    @Test("부호 없는 정수가 왕복한다")
    func unsignedIntegerRoundTrips() throws {
        #expect(try roundTrip(.unsignedInteger(0)) == .unsignedInteger(0))
        #expect(try roundTrip(.unsignedInteger(1_000_000)) == .unsignedInteger(1_000_000))
        #expect(try roundTrip(.unsignedInteger(UInt64.max)) == .unsignedInteger(UInt64.max))
    }

    @Test("음수 정수가 왕복한다")
    func negativeIntegerRoundTrips() throws {
        #expect(try roundTrip(.integer(-1)) == .integer(-1))
        #expect(try roundTrip(.integer(-1_000_000)) == .integer(-1_000_000))
        #expect(try roundTrip(.integer(Int64.min)) == .integer(Int64.min))
    }

    @Test("음수 아닌 정수는 부호 정보를 잃고 부호 없는 정수로 돌아온다")
    func nonNegativeIntegerDecodesAsUnsigned() throws {
        // msgpack 와이어에는 "부호 있는 양수"라는 표현이 없다. Neovim도 positive fixint로 보낸다.
        // 숫자 값은 보존되므로 호출자는 integerValue로 양쪽을 함께 읽는다.
        let decoded = try roundTrip(.integer(5))

        #expect(decoded == .unsignedInteger(5))
        #expect(decoded.integerValue == 5)
    }

    @Test("실수가 왕복한다")
    func doubleRoundTrips() throws {
        #expect(try roundTrip(.double(3.5)) == .double(3.5))
        #expect(try roundTrip(.double(-0.125)) == .double(-0.125))
    }

    @Test("문자열이 왕복한다 — 한글·이모지 포함")
    func stringRoundTripsIncludingNonAscii() throws {
        #expect(try roundTrip(.string("")) == .string(""))
        #expect(try roundTrip(.string("nvim_ui_attach")) == .string("nvim_ui_attach"))
        #expect(try roundTrip(.string("한글 값 😀")) == .string("한글 값 😀"))
    }

    @Test("이진 데이터가 왕복한다")
    func binaryRoundTrips() throws {
        #expect(try roundTrip(.binary([])) == .binary([]))
        #expect(try roundTrip(.binary([0x00, 0xff, 0x10])) == .binary([0x00, 0xff, 0x10]))
    }

    @Test("확장 타입이 왕복한다")
    func extensionRoundTrips() throws {
        let value = MessagePackValue.extended(type: 5, bytes: [1, 2, 3])

        #expect(try roundTrip(value) == value)
    }

    @Test("중첩 배열과 맵이 왕복한다")
    func nestedArrayAndMapRoundTrip() throws {
        let value = MessagePackValue.array([
            .unsignedInteger(1),
            .array([.string("grid_line"), .nilValue]),
            .map([
                MessagePackKeyValuePair(key: .string("rgb"), value: .boolean(true)),
                MessagePackKeyValuePair(key: .string("ext_linegrid"), value: .boolean(true)),
            ]),
        ])

        #expect(try roundTrip(value) == value)
    }

    @Test("빈 배열과 빈 맵이 왕복한다")
    func emptyArrayAndMapRoundTrip() throws {
        #expect(try roundTrip(.array([])) == .array([]))
        #expect(try roundTrip(.map([])) == .map([]))
    }

    // 폭 경계 — 인코딩이 한 단계 넓어지는 지점.

    @Test("fixint 경계에서 인코딩 폭이 바뀐다")
    func fixedIntegerBoundariesChangeWidth() throws {
        #expect(MessagePackEncoder.encode(.unsignedInteger(127)).count == 1)
        #expect(MessagePackEncoder.encode(.unsignedInteger(128)).count == 2)
        #expect(MessagePackEncoder.encode(.integer(-32)).count == 1)
        #expect(MessagePackEncoder.encode(.integer(-33)).count == 2)

        #expect(try roundTrip(.unsignedInteger(127)) == .unsignedInteger(127))
        #expect(try roundTrip(.unsignedInteger(128)) == .unsignedInteger(128))
        #expect(try roundTrip(.integer(-32)) == .integer(-32))
        #expect(try roundTrip(.integer(-33)) == .integer(-33))
    }

    @Test("uint8·uint16·uint32 경계에서 인코딩 폭이 바뀐다")
    func unsignedIntegerWidthBoundaries() throws {
        #expect(MessagePackEncoder.encode(.unsignedInteger(255)).count == 2)
        #expect(MessagePackEncoder.encode(.unsignedInteger(256)).count == 3)
        #expect(MessagePackEncoder.encode(.unsignedInteger(65_535)).count == 3)
        #expect(MessagePackEncoder.encode(.unsignedInteger(65_536)).count == 5)
        #expect(MessagePackEncoder.encode(.unsignedInteger(4_294_967_295)).count == 5)
        #expect(MessagePackEncoder.encode(.unsignedInteger(4_294_967_296)).count == 9)

        for value in [255, 256, 65_535, 65_536, 4_294_967_295, 4_294_967_296] as [UInt64] {
            #expect(try roundTrip(.unsignedInteger(value)) == .unsignedInteger(value))
        }
    }

    @Test("int8·int16·int32 경계에서 인코딩 폭이 바뀐다")
    func signedIntegerWidthBoundaries() throws {
        for value in [-128, -129, -32_768, -32_769, -2_147_483_648, -2_147_483_649] as [Int64] {
            #expect(try roundTrip(.integer(value)) == .integer(value))
        }
    }

    @Test("fixstr·str8·str16 경계에서 문자열이 왕복한다")
    func stringWidthBoundaries() throws {
        for length in [31, 32, 255, 256] {
            let text = String(repeating: "a", count: length)
            #expect(try roundTrip(.string(text)) == .string(text))
        }
    }

    @Test("fixarray·array16 경계에서 배열이 왕복한다")
    func arrayWidthBoundaries() throws {
        for count in [15, 16, 65_535, 65_536] {
            let value = MessagePackValue.array(Array(repeating: .nilValue, count: count))
            #expect(try roundTrip(value) == value)
        }
    }

    // 부분 프레임 — 호출자가 "더 기다린다"를 판단할 수 있어야 한다.

    @Test("빈 버퍼는 미완성으로 판정된다")
    func emptyBufferNeedsMoreBytes() {
        var decoder = MessagePackDecoder(bytes: [])

        #expect(throws: MessagePackError.needsMoreBytes) {
            try decoder.decodeValue()
        }
    }

    @Test("잘린 문자열 프레임은 미완성으로 판정된다")
    func truncatedStringFrameNeedsMoreBytes() {
        let complete = MessagePackEncoder.encode(.string("nvim_ui_attach"))
        var decoder = MessagePackDecoder(bytes: Array(complete.dropLast()))

        #expect(throws: MessagePackError.needsMoreBytes) {
            try decoder.decodeValue()
        }
    }

    @Test("중간에서 잘린 중첩 프레임은 미완성으로 판정된다")
    func truncatedNestedFrameNeedsMoreBytes() {
        let complete = MessagePackEncoder.encode(
            .array([.unsignedInteger(0), .string("nvim_eval"), .array([.string("1 + 1")])])
        )
        var decoder = MessagePackDecoder(bytes: Array(complete.prefix(complete.count / 2)))

        #expect(throws: MessagePackError.needsMoreBytes) {
            try decoder.decodeValue()
        }
    }

    @Test("쓰이지 않는 포맷 바이트는 미완성이 아니라 손상으로 판정된다")
    func reservedFormatByteIsReportedAsCorrupt() {
        var decoder = MessagePackDecoder(bytes: [0xc1])

        #expect(throws: MessagePackError.unsupportedFormatByte(0xc1)) {
            try decoder.decodeValue()
        }
    }

    // 한 버퍼에 여러 프레임 — 파이프는 프레임 경계에서 잘려 오지 않는다.

    @Test("이어 붙은 두 프레임이 각각 디코드되고 소비 위치가 정확하다")
    func twoConcatenatedFramesDecodeInSequence() throws {
        let firstFrame = MessagePackEncoder.encode(.unsignedInteger(1))
        let secondFrame = MessagePackEncoder.encode(.string("hello"))
        var decoder = MessagePackDecoder(bytes: firstFrame + secondFrame)

        #expect(try decoder.decodeValue() == .unsignedInteger(1))
        #expect(decoder.position == firstFrame.count)

        #expect(try decoder.decodeValue() == .string("hello"))
        #expect(decoder.position == firstFrame.count + secondFrame.count)
    }

    @Test("두 번째 프레임이 아직 덜 왔으면 첫 프레임만 소비된다")
    func partialSecondFrameLeavesFirstFrameConsumed() throws {
        let firstFrame = MessagePackEncoder.encode(.unsignedInteger(1))
        let secondFrame = MessagePackEncoder.encode(.string("hello"))
        var decoder = MessagePackDecoder(bytes: firstFrame + secondFrame.dropLast(2))

        #expect(try decoder.decodeValue() == .unsignedInteger(1))
        #expect(throws: MessagePackError.needsMoreBytes) {
            try decoder.decodeValue()
        }
        // 호출자는 이 위치까지를 버리고 나머지를 다음 읽기와 이어 붙인다.
        #expect(decoder.position == firstFrame.count)
    }

    @Test("지정한 위치부터 디코드할 수 있다")
    func decodingStartsAtGivenPosition() throws {
        let firstFrame = MessagePackEncoder.encode(.unsignedInteger(1))
        let secondFrame = MessagePackEncoder.encode(.string("hello"))
        var decoder = MessagePackDecoder(bytes: firstFrame + secondFrame, startingAt: firstFrame.count)

        #expect(try decoder.decodeValue() == .string("hello"))
    }

    // 접근자 — RPC 파싱이 매번 switch를 쓰지 않도록.

    @Test("접근자가 정수·문자열·배열·맵을 꺼낸다")
    func accessorsReadCommonTypes() {
        #expect(MessagePackValue.unsignedInteger(7).integerValue == 7)
        #expect(MessagePackValue.integer(-7).integerValue == -7)
        #expect(MessagePackValue.string("x").integerValue == nil)
        #expect(MessagePackValue.string("x").stringValue == "x")
        #expect(MessagePackValue.array([.nilValue]).arrayValue?.count == 1)
        #expect(MessagePackValue.map([]).mapValue?.isEmpty == true)
        #expect(MessagePackValue.boolean(true).booleanValue == true)
    }
}
