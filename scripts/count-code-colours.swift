// Counts the distinct colours inside a rectangle of a PNG.
//
// Why this exists: REQ-016 AC-1 ("keywords, strings, comments, numbers, types are different
// colours") and AC-4 (".py stays plain") are the kind of claim a person answers by looking,
// and looking is exactly where this build lost eight rounds. A screenshot plus a colour count
// turns both into a number.
//
//   count-code-colours.swift <png> <x> <y> <w> <h> [minShare]
//   count-code-colours.swift --self-test
//
// Prints one line per colour that occupies at least `minShare` of the sampled pixels
// (default 0.2%), most frequent first, then a `distinct: N` summary line. Rare colours are
// dropped on purpose: text antialiasing invents hundreds of in-between shades, and counting
// those would make every screenshot look colourful — including the plain one.
import AppKit
import Foundation

let SUCCESS_EXIT: Int32 = 0
let USAGE_EXIT: Int32 = 2
let SELF_TEST_FAILED_EXIT: Int32 = 3
let DEFAULT_MIN_SHARE = 0.002
let BYTES_PER_PIXEL = 4

func fail(_ message: String, code: Int32 = USAGE_EXIT) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(code)
}

/// One colour and how much of the sampled rectangle it covers.
struct ColourShare {
    let rgb: UInt32
    let pixels: Int
    let share: Double

    var hex: String { String(format: "#%06X", rgb) }
}

/// Reads the rectangle out of `cgImage` and returns the colours that clear `minShare`.
///
/// `pointScale` converts the caller's on-screen points into the device pixels a Retina capture
/// actually contains; passing 1 means the rectangle is already in pixels.
func colourShares(
    in cgImage: CGImage, rect: CGRect, pointScale: Double, minShare: Double
) -> [ColourShare]? {
    let px = Int(rect.origin.x * pointScale), py = Int(rect.origin.y * pointScale)
    let pw = Int(rect.width * pointScale), ph = Int(rect.height * pointScale)
    guard pw > 0, ph > 0,
          px >= 0, py >= 0, px + pw <= cgImage.width, py + ph <= cgImage.height,
          let cropped = cgImage.cropping(to: CGRect(x: px, y: py, width: pw, height: ph))
    else { return nil }

    var pixels = [UInt8](repeating: 0, count: pw * ph * BYTES_PER_PIXEL)
    guard let context = CGContext(
        data: &pixels, width: pw, height: ph, bitsPerComponent: 8,
        bytesPerRow: pw * BYTES_PER_PIXEL, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: pw, height: ph))

    var counts: [UInt32: Int] = [:]
    for index in stride(from: 0, to: pixels.count, by: BYTES_PER_PIXEL) {
        let rgb = UInt32(pixels[index]) << 16
            | UInt32(pixels[index + 1]) << 8
            | UInt32(pixels[index + 2])
        counts[rgb, default: 0] += 1
    }

    let total = Double(pw * ph)
    return counts
        .map { ColourShare(rgb: $0.key, pixels: $0.value, share: Double($0.value) / total) }
        .filter { $0.share >= minShare }
        .sorted { $0.pixels > $1.pixels }
}

// ── 자기 검사 ────────────────────────────────────────────────────────────────
// 죽은 측정기는 모든 칸을 통과로 돌려준다. 이 검사기가 하는 주장은 "색이 N 가지다" 하나이고,
// 그것이 틀리는 방식은 둘이다 — 있는 색을 못 세거나, 없는 색을 세거나. 양쪽을 다 건다.

/// Builds a bitmap whose left half is `left` and right half is `right`.
func twoColourImage(left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8), size: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: size * size * BYTES_PER_PIXEL)
    for row in 0..<size {
        for column in 0..<size {
            let colour = column < size / 2 ? left : right
            let index = (row * size + column) * BYTES_PER_PIXEL
            pixels[index] = colour.0
            pixels[index + 1] = colour.1
            pixels[index + 2] = colour.2
            pixels[index + 3] = 255
        }
    }
    guard let context = CGContext(
        data: &pixels, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * BYTES_PER_PIXEL, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    return context.makeImage()
}

func runSelfTest() -> Never {
    print("=== count-code-colours 자체 검사 ===")
    var failures = 0

    func check(_ label: String, _ passed: Bool) {
        print(passed ? "  ok: \(label)" : "  FAIL: \(label)")
        if !passed { failures += 1 }
    }

    let size = 40
    let red: (UInt8, UInt8, UInt8) = (255, 0, 0)
    let blue: (UInt8, UInt8, UInt8) = (0, 0, 255)
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    guard let twoColour = twoColourImage(left: red, right: blue, size: size),
          let oneColour = twoColourImage(left: red, right: red, size: size) else {
        print("  FAIL: 픽스처 생성 실패")
        exit(SELF_TEST_FAILED_EXIT)
    }

    // 있는 색을 세는가
    let two = colourShares(in: twoColour, rect: full, pointScale: 1, minShare: DEFAULT_MIN_SHARE)
    check("두 색 이미지를 2 로 센다 (실제: \(two?.count.description ?? "nil"))", two?.count == 2)
    check("색 값을 정확히 읽는다 (#FF0000·#0000FF)",
          Set(two?.map(\.hex) ?? []) == ["#FF0000", "#0000FF"])
    check("점유율이 반반이다", (two?.allSatisfy { abs($0.share - 0.5) < 0.01 }) == true)

    // 없는 색을 세지 않는가 — 평문(.py) 판정이 이 방향에 걸려 있다
    let one = colourShares(in: oneColour, rect: full, pointScale: 1, minShare: DEFAULT_MIN_SHARE)
    check("단색 이미지를 1 로 센다 (실제: \(one?.count.description ?? "nil"))", one?.count == 1)

    // 임계값이 실제로 걷어내는가 — 안 걷어내면 안티에일리어싱이 모든 화면을 다채롭게 만든다
    let aboveHalf = colourShares(in: twoColour, rect: full, pointScale: 1, minShare: 0.6)
    check("minShare 0.6 이면 반반 두 색을 전부 걷어낸다 (실제: \(aboveHalf?.count.description ?? "nil"))",
          aboveHalf?.count == 0)

    // 사각형이 이미지 밖이면 0 이 아니라 nil 이어야 한다 — 0 을 돌려주면 "색이 없다"로 읽힌다
    let outside = colourShares(
        in: twoColour, rect: CGRect(x: 0, y: 0, width: size * 2, height: size),
        pointScale: 1, minShare: DEFAULT_MIN_SHARE
    )
    check("범위 밖 사각형은 nil (0 이 아니다)", outside == nil)

    if failures == 0 {
        print("  → 자체 검사 통과. 0 색과 '못 잰 것'은 다른 사건이라 따로 표시한다.")
        exit(SUCCESS_EXIT)
    }
    print("  → 자체 검사 실패 \(failures)건 — 이 검사기의 결과를 근거로 쓰지 마라.")
    exit(SELF_TEST_FAILED_EXIT)
}

// ── 진입점 ───────────────────────────────────────────────────────────────────
let args = CommandLine.arguments
if args.count >= 2, args[1] == "--self-test" { runSelfTest() }

guard args.count >= 6 else {
    fail("사용법: count-code-colours.swift <png> <x> <y> <w> <h> [minShare] | --self-test")
}
guard let x = Double(args[2]), let y = Double(args[3]),
      let w = Double(args[4]), let h = Double(args[5]), w > 0, h > 0 else {
    fail("좌표는 숫자여야 하고 폭·높이는 0 보다 커야 한다")
}
let minShare = args.count >= 7 ? (Double(args[6]) ?? DEFAULT_MIN_SHARE) : DEFAULT_MIN_SHARE

guard let image = NSImage(contentsOfFile: args[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("PNG 를 읽지 못했다: \(args[1])")
}

let pointScale = Double(cgImage.width) / Double(image.size.width)
guard let shares = colourShares(
    in: cgImage, rect: CGRect(x: x, y: y, width: w, height: h),
    pointScale: pointScale, minShare: minShare
) else {
    fail("사각형이 이미지 밖이다 — 이미지 \(cgImage.width)x\(cgImage.height) px, 배율 \(pointScale)")
}

for share in shares {
    print(String(format: "%@  %6.2f%%  %d", share.hex, share.share * 100, share.pixels))
}
print("distinct: \(shares.count)")
exit(SUCCESS_EXIT)
